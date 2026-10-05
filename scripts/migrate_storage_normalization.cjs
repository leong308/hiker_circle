'use strict';
// D2–D4 guarded migration. Dry-run by default; --apply requires --plan.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const {firebaseAccessToken, firestoreFields, projectId} = require('./seed_malaysia_trails');
const {latestFcmTokensForUser, canonicalUsername, historicalForecastProjection} = require('../functions/storage_normalization');
const root = path.resolve(__dirname, '..');
const documentRoot = `projects/${projectId}/databases/(default)/documents`;
const apiRoot = `https://firestore.googleapis.com/v1/${documentRoot}`;
function decode(value) {
  if (value.mapValue) return decodeFields(value.mapValue.fields || {});
  if (value.arrayValue) return (value.arrayValue.values || []).map(decode);
  if ('integerValue' in value) return Number(value.integerValue);
  return Object.values(value)[0];
}
function decodeFields(fields) {return Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, decode(v)]));}
function documentUrl(name) {
  if (!name.startsWith(documentRoot + '/')) throw new Error('Unexpected document project.');
  return apiRoot + '/' + name.slice(documentRoot.length + 1).split('/').map(encodeURIComponent).join('/');
}
async function api(token, url, options = {}, missing = false) {
  const response = await fetch(url, {...options, headers: {Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json'}, signal: AbortSignal.timeout(30000)});
  if (response.status === 404 && missing) return null;
  if (!response.ok) {const error = new Error(`Migration request failed (HTTP ${response.status}).`);
    error.status = response.status; throw error;}
  return response.json();
}
async function list(token, collection) {
  const docs = [];
  let next = '';
  do {
    const url = new URL(`${apiRoot}/${collection}`);
    url.searchParams.set('pageSize', '300');
    if (next) url.searchParams.set('pageToken', next);
    const response = await api(token, url);
    docs.push(...response.documents || []);
    next = response.nextPageToken || '';
  } while (next);
  return docs;
}
function userPatch(document) {
  const data = decodeFields(document.fields || {});
  const fields = {};
  const mask = [];
  const currentApp = [data.boundAppInstanceId, data.lastSignedInAppInstanceId,
    data.currentAppId, data.activeFcmAppInstanceId].find(v => typeof v === 'string' && v.trim());
  const tokens = latestFcmTokensForUser(data);
  if (currentApp && tokens.length === 1) {
    const byApp = data.fcmTokenByAppId && typeof data.fcmTokenByAppId === 'object'
      && !Array.isArray(data.fcmTokenByAppId) ? data.fcmTokenByAppId : {};
    const aliases = ['fcmTokens', 'activeFcmToken', 'lastFcmToken'].filter(k => Object.hasOwn(data, k));
    if (aliases.length || data.fcmTokenSchemaVersion !== 2 || byApp[currentApp] !== tokens[0]) {
      Object.assign(fields, firestoreFields({fcmTokenByAppId: {...byApp, [currentApp]: tokens[0]}, fcmTokenSchemaVersion: 2}));
      mask.push('fcmTokenByAppId', 'fcmTokenSchemaVersion', ...aliases);
    }
  }
  const username = canonicalUsername(data);
  if (username && data.profile?.username !== username) {
    fields.profile = {mapValue: {fields: {username: {stringValue: username}}}};
    mask.push('profile.username');
  }
  if (username && data.username !== username) {
    fields.username = {stringValue: username}; mask.push('username');
  }
  return mask.length ? {kind: 'user', document, fields, mask} : null;
}
function historicalPatch(document, nowIso) {
  const data = decodeFields(document.fields || {});
  if (data.status !== 'completed' || !historicalForecastProjection(data.trail).changed) return null;
  const rawWeather = document.fields.trail.mapValue.fields.weather;
  const summary = structuredClone(rawWeather);
  delete summary.mapValue.fields.hourlyForecast;
  delete summary.mapValue.fields.dailyForecast;
  const forecast = summary.mapValue.fields.forecastData?.mapValue?.fields;
  if (forecast) {delete forecast.hourly; delete forecast.daily;}
  const archiveName = document.name + '/snapshotArchives/trailForecast';
  return {kind: 'history', document, fields: {
    trail: {mapValue: {fields: {weather: summary}}},
    trailSnapshotVersion: {integerValue: '2'},
    trailForecastArchivePath: {stringValue: archiveName.slice(documentRoot.length + 1)},
  }, mask: ['trail.weather', 'trailSnapshotVersion', 'trailForecastArchivePath'], archive: {
    name: archiveName, fields: {schemaVersion: {integerValue: '1'}, weather: rawWeather,
      archivedAtLocal: {stringValue: nowIso}},
  }};
}
function maintenancePatch(document, collection) {
  const data = decodeFields(document.fields || {});
  if (typeof data.isDeleted === 'boolean') return null;
  return {kind: 'maintenance', collection, document,
    fields: {isDeleted: {booleanValue: data.expired === true || Boolean(data.deletedAt || data.deletedAtLocal)}},
    mask: ['isDeleted']};
}
async function buildPlan(token) {
  const nowIso = new Date().toISOString();
  const items = [];
  const inventory = {};
  for (const collection of ['users', 'hikeSessions', 'upcomingHikes', 'groupChats']) {
    const documents = await list(token, collection);
    inventory[collection] = documents.length;
    for (const document of documents) {
      const item = collection === 'users' ? userPatch(document)
        : collection === 'hikeSessions' ? historicalPatch(document, nowIso)
          : maintenancePatch(document, collection);
      if (!item) continue;
      if (item.archive && await api(token, documentUrl(item.archive.name), {}, true)) {
        throw new Error('An existing forecast archive needs reconciliation; refusing to overwrite it.');
      }
      items.push(item);
    }
  }
  return {projectId, scope: 'D2-D4', generatedAt: nowIso, inventory, items};
}
function validItem(item) {
  const relative = item.document.name.slice(documentRoot.length + 1);
  if (!item.document.name.startsWith(documentRoot + '/') || relative.split('/').length !== 2) return false;
  if (item.kind === 'user') return relative.startsWith('users/') && item.mask.every(k =>
    ['fcmTokenByAppId', 'fcmTokenSchemaVersion', 'fcmTokens', 'activeFcmToken', 'lastFcmToken', 'profile.username', 'username'].includes(k));
  if (item.kind === 'history') return relative.startsWith('hikeSessions/')
    && item.archive?.name === item.document.name + '/snapshotArchives/trailForecast'
    && item.mask.every(k => ['trail.weather', 'trailSnapshotVersion', 'trailForecastArchivePath'].includes(k));
  return item.kind === 'maintenance' && ['upcomingHikes', 'groupChats'].includes(relative.split('/')[0])
    && item.mask.length === 1 && item.mask[0] === 'isDeleted';
}
function summary(plan) {
  const counts = {user: 0, history: 0, maintenance: 0};
  for (const item of plan.items) counts[item.kind]++;
  return {projectId, inventory: plan.inventory, changes: counts, deletesDocuments: false,
    snapshotBytesMoved: plan.items.filter(i => i.kind === 'history').reduce((n, i) =>
      n + Buffer.byteLength(JSON.stringify(i.archive.fields.weather)) -
      Buffer.byteLength(JSON.stringify(i.fields.trail.mapValue.fields.weather)), 0)};
}
async function apply(token, plan, planFile) {
  const generatedAt = Date.parse(plan.generatedAt);
  if (plan.projectId !== 'hiker-circle' || plan.scope !== 'D2-D4' ||
    !Number.isFinite(generatedAt) || generatedAt > Date.now() ||
    Date.now() - generatedAt > 3600000 || !Array.isArray(plan.items) ||
    plan.items.some(i => !i.document?.updateTime || !validItem(i))) {
    throw new Error('Invalid or stale inspected migration plan.');
  }
  const backup = path.join(root, 'tmp', 'storage-normalization-backup-' + new Date().toISOString().replace(/[:.]/g, '-'));
  fs.mkdirSync(backup, {recursive: true});
  const manifest = {...plan, sha256: crypto.createHash('sha256').update(fs.readFileSync(planFile)).digest('hex')};
  fs.writeFileSync(path.join(backup, 'manifest.json'), JSON.stringify(manifest, null, 2), {flag: 'wx'});
  const results = [];
  console.log(`Private migration backup: ${backup}`);
  for (const item of plan.items) {
    const current = await api(token, documentUrl(item.document.name), {}, true);
    let status = 'changed-preserved';
    if (current?.updateTime === item.document.updateTime) {
      const writes = [];
      if (item.archive) writes.push({update: item.archive, currentDocument: {exists: false}});
      writes.push({update: {name: current.name, fields: item.fields},
        updateMask: {fieldPaths: item.mask}, currentDocument: {updateTime: current.updateTime}});
      await api(token, `${apiRoot}:commit`, {method: 'POST', body: JSON.stringify({writes})});
      status = 'migrated';
    }
    results.push({name: item.document.name, kind: item.kind, status});
    fs.writeFileSync(path.join(backup, 'results.json'), JSON.stringify(results, null, 2));
  }
  console.log(JSON.stringify({migrated: results.filter(r => r.status === 'migrated').length,
    changedPreserved: results.filter(r => r.status !== 'migrated').length, backup}, null, 2));
}
async function main() {
  if (projectId !== 'hiker-circle') throw new Error('Unexpected project.');
  const args = process.argv.slice(2);
  const argument = flag => path.resolve(root, args[args.indexOf(flag) + 1]);
  const token = await firebaseAccessToken();
  if (args.includes('--apply')) {
    if (!args.includes('--plan')) throw new Error('--apply requires an inspected --plan file.');
    const file = argument('--plan');
    await apply(token, JSON.parse(fs.readFileSync(file)), file);
  } else {
    const plan = await buildPlan(token);
    console.log(JSON.stringify(summary(plan), null, 2));
    if (args.includes('--plan-out')) fs.writeFileSync(argument('--plan-out'), JSON.stringify(plan, null, 2), {flag: 'wx'});
  }
}
module.exports = {userPatch, historicalPatch, maintenancePatch, validItem, summary};
if (require.main === module) main().catch(error => {console.error(error.message, error.cause?.code || ''); process.exitCode = 1;});

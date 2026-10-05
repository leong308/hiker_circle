'use strict';

// Explicitly scoped B1–B9 maintenance. Never touches Storage or bound factors.
// Dry run: --plan-out tmp/firebase-review-b-plan.json
// Apply only an inspected plan: --apply --plan tmp/firebase-review-b-plan.json
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const {firebaseAccessToken, projectId} = require('./seed_malaysia_trails');
const root = path.resolve(__dirname, '..');
const documentRoot = `projects/${projectId}/databases/(default)/documents`;
const firestoreRoot = `https://firestore.googleapis.com/v1/${documentRoot}`;
const hostingRoot = `https://firebasehosting.googleapis.com/v1beta1/sites/${projectId}`;
const hour = 3600000;
const day = 24 * hour;
const rateCollections = [
  'activeHikeStartRateLimits', 'buddyRequestRateLimits', 'directChatActionRateLimits',
  'hikeCompletionRateLimits', 'hikeSessionRecoveryRateLimits', 'sosMessageRateLimits',
  'teamHikeActionRateLimits', 'upcomingHikeJoinRequestRateLimits', 'upcomingHikeRateLimits',
];
const ids = {greenApiLoginChallenges: 'B1', passwordResetChallenges: 'B2',
  passwordResetSessions: 'B3', passwordResetPasskeyChallenges: 'B4',
  live_location_shares: 'B5', fcmOutbox: 'B6',
  ...Object.fromEntries(rateCollections.map(c => [c, 'B7']))};

function decode(value) {
  if (value.mapValue) return fields({fields: value.mapValue.fields});
  if (value.arrayValue) return (value.arrayValue.values || []).map(decode);
  if ('integerValue' in value) return Number(value.integerValue);
  return Object.values(value)[0];
}
function fields(document) {
  return Object.fromEntries(Object.entries(document.fields || {}).map(([k, v]) => [k, decode(v)]));
}
function millis(value) {
  if (typeof value === 'number') return value;
  if (typeof value === 'string' && /^\d{12,}$/.test(value)) return Number(value);
  return typeof value === 'string' ? Date.parse(value) : NaN;
}
function eligible(collection, data, now) {
  if (['B1', 'B2', 'B3', 'B4'].includes(ids[collection])) {
    // Retain even consumed records while their validity window is still open.
    return millis(data.expiresAtMillis) < now - hour;
  }
  if (ids[collection] === 'B5') {
    return millis(data.expiresAt || data.expiresAtLocal) < now - hour;
  }
  if (ids[collection] === 'B7') return millis(data.windowStartedAtMillis) < now - 25 * hour;
  if (ids[collection] === 'B6') {
    if (!['sent', 'partial', 'failed', 'no_token'].includes(data.status)) return false;
    const processed = millis(data.processedAt || data.processedAtLocal);
    const updated = millis(data.updatedAt || data.updatedAtLocal);
    if (!(processed < now - 30 * day)) return false;
    if (Number.isFinite(updated) && updated >= now - 30 * day) return false;
    // Team-ready documents have a second, independent WhatsApp delivery task.
    if (data.type === 'team_hike_ready') {
      if (!['sent', 'failed'].includes(data.teamReadinessWhatsAppStatus)) return false;
      if (!(millis(data.teamReadinessWhatsAppProcessedAt ||
        data.teamReadinessWhatsAppProcessedAtLocal) < now - 30 * day)) return false;
    }
    return true;
  }
  return false;
}
function relative(document) {
  const prefix = `${documentRoot}/`;
  if (!document.name.startsWith(prefix)) throw new Error('Unexpected project/document target.');
  return document.name.slice(prefix.length);
}
function validTarget(candidate) {
  const segments = relative(candidate.document).split('/');
  if (candidate.id === 'B8') return segments.length === 4 && segments[0] === 'upcomingHikes'
    && segments[2] === 'reminderPreferences';
  return segments.length === 2 && ids[segments[0]] === candidate.id;
}
function documentUrl(name) {
  return `https://firestore.googleapis.com/v1/${documentRoot}/` +
    relative({name}).split('/').map(encodeURIComponent).join('/');
}
async function api(token, url, options = {}, allowMissing = false) {
  const response = await fetch(url, {...options, signal: AbortSignal.timeout(30000),
    headers: {Authorization: `Bearer ${token}`, 'Content-Type': 'application/json'}});
  if (response.status === 404 && allowMissing) return null;
  if (!response.ok) {
    const error = new Error(`Firebase maintenance request failed (HTTP ${response.status}).`);
    error.status = response.status;
    throw error;
  }
  const text = await response.text();
  return text ? JSON.parse(text) : {};
}
async function list(token, url, key, pageSize = 100) {
  const result = [];
  let next = '';
  do {
    const u = new URL(url);
    u.searchParams.set('pageSize', String(pageSize));
    if (next) u.searchParams.set('pageToken', next);
    const page = await api(token, u);
    result.push(...page[key] || []);
    next = page.nextPageToken || '';
  } while (next);
  return result;
}
async function hostingState(token) {
  const channels = await list(token, `${hostingRoot}/channels`, 'channels');
  const protectedVersions = new Set(channels.map(c => c.release?.version?.name).filter(Boolean));
  const versions = await list(token, `${hostingRoot}/versions`, 'versions');
  // Preserve the newest two non-active finalized versions as rollback choices.
  const rollback = versions.filter(v => v.status === 'FINALIZED' && !protectedVersions.has(v.name))
    .sort((a, b) => millis(b.createTime) - millis(a.createTime)).slice(0, 2);
  rollback.forEach(v => protectedVersions.add(v.name));
  return {channels, versions, protectedVersions: [...protectedVersions]};
}
function oldHosting(version, state, now) {
  return version.status === 'FINALIZED' && !state.protectedVersions.includes(version.name)
    && millis(version.createTime) < now - 30 * day;
}
function hostingUrl(name) {
  if (!/^(?:projects\/hiker-circle\/)?sites\/hiker-circle\/versions\/[A-Za-z0-9_-]+$/.test(name)) {
    throw new Error('Unexpected Hosting deletion target.');
  }
  return `https://firebasehosting.googleapis.com/v1beta1/${name}`;
}
async function plan(token) {
  const now = Date.now();
  const firestore = [];
  const inventory = {};
  for (const [collection, id] of Object.entries(ids)) {
    const documents = await list(token, `${firestoreRoot}/${collection}`, 'documents', 300);
    inventory[collection] = documents.length;
    for (const document of documents) {
      if (eligible(collection, fields(document), now)) firestore.push({id, collection, document});
    }
  }
  const rows = await api(token, `${firestoreRoot}:runQuery`, {method: 'POST', body: JSON.stringify({
    structuredQuery: {from: [{collectionId: 'reminderPreferences', allDescendants: true}]},
  })});
  for (const row of rows) {
    if (!row.document) continue;
    const candidate = {id: 'B8', document: row.document};
    if (!validTarget(candidate)) continue;
    const parent = `${documentRoot}/${relative(row.document).split('/').slice(0, 2).join('/')}`;
    if (!await api(token, documentUrl(parent), {}, true)) firestore.push({...candidate, parent});
  }
  const state = await hostingState(token);
  const hosting = state.versions.filter(v => oldHosting(v, state, now))
    .map(version => ({id: 'B9', version}));
  return {scope: 'B1-B9', projectId, generatedAt: new Date().toISOString(),
    inventory, firestore, hosting, hostingState: state};
}
function summary(plan) {
  const counts = Object.fromEntries(Array.from({length: 9}, (_, i) => [`B${i + 1}`, 0]));
  for (const item of [...plan.firestore, ...plan.hosting]) counts[item.id]++;
  return {scope: plan.scope, projectId, counts, firestoreDocuments: plan.firestore.length,
    hostingVersions: plan.hosting.length, storageObjects: 0,
    hostingVersionBytes: plan.hosting.reduce((n, i) => n + Number(i.version.versionBytes || 0), 0),
    protectedHostingVersions: plan.hostingState.protectedVersions.length};
}
function save(file, data) {
  fs.mkdirSync(path.dirname(file), {recursive: true});
  fs.writeFileSync(file, JSON.stringify(data, null, 2), {flag: 'wx'});
}
async function removeDocument(token, candidate, now) {
  if (!validTarget(candidate)) throw new Error('Refusing a document outside B1–B8.');
  const current = await api(token, documentUrl(candidate.document.name), {}, true);
  if (!current) return 'already_missing';
  if (current.updateTime !== candidate.document.updateTime) return 'changed_preserved';
  if (candidate.id !== 'B8' && !eligible(candidate.collection, fields(current), now)) {
    return 'ineligible_preserved';
  }
  const descendants = await api(token, `${documentUrl(current.name)}:listCollectionIds`, {
    method: 'POST', body: JSON.stringify({pageSize: 1}),
  });
  if (descendants.collectionIds?.length) return 'descendants_preserved';
  let transaction;
  try {
    if (candidate.id === 'B8') {
      if (candidate.parent !== `${documentRoot}/${relative(current).split('/').slice(0, 2).join('/')}`) {
        throw new Error('Unexpected reminder parent.');
      }
      ({transaction} = await api(token, `${firestoreRoot}:beginTransaction`, {
        method: 'POST', body: JSON.stringify({options: {readWrite: {}}}),
      }));
      const rows = await api(token, `${firestoreRoot}:batchGet`, {method: 'POST',
        body: JSON.stringify({documents: [candidate.parent, current.name], transaction})});
      if (rows.some(r => r.found?.name === candidate.parent)) return 'parent_restored_preserved';
      if (!rows.some(r => r.missing === candidate.parent)) throw new Error('Parent absence unverified.');
      if (!rows.some(r => r.found?.name === current.name && r.found.updateTime === current.updateTime)) {
        return 'changed_preserved';
      }
    }
    await api(token, `${firestoreRoot}:commit`, {method: 'POST', body: JSON.stringify({
      writes: [{delete: current.name, currentDocument: {updateTime: current.updateTime}}],
      ...(transaction ? {transaction} : {}),
    })});
    transaction = null;
    return 'deleted';
  } catch (error) {
    if ([409, 412].includes(error.status)) return 'concurrent_change_preserved';
    throw error;
  } finally {
    if (transaction) await api(token, `${firestoreRoot}:rollback`, {method: 'POST',
      body: JSON.stringify({transaction})}).catch(() => {});
  }
}
async function applyPlan(token, inspectedPlan, planFile) {
  if (inspectedPlan.scope !== 'B1-B9' || inspectedPlan.projectId !== 'hiker-circle') {
    throw new Error('Unexpected plan scope/project.');
  }
  if (Date.now() - millis(inspectedPlan.generatedAt) > hour) throw new Error('Plan is stale; run a new dry run.');
  for (const item of inspectedPlan.firestore) {
    if (!validTarget(item) || !item.document.updateTime) throw new Error('Invalid document plan.');
  }
  for (const item of inspectedPlan.hosting) hostingUrl(item.version.name);
  const backup = path.join(root, 'tmp', `firebase-review-b-backup-${new Date().toISOString().replace(/[:.]/g, '-')}`);
  const manifest = {...inspectedPlan, inspectedPlanSha256: crypto.createHash('sha256')
    .update(fs.readFileSync(planFile)).digest('hex'), hostingBackupKind: 'metadata-and-file-manifests-only'};
  // Hosting metadata and file hashes are not a byte-for-byte site archive.
  for (const item of manifest.hosting) {
    item.version = await api(token, hostingUrl(item.version.name));
    item.files = await list(token, `${hostingUrl(item.version.name)}/files`, 'files', 1000);
  }
  save(path.join(backup, 'manifest.json'), manifest);
  const checked = JSON.parse(fs.readFileSync(path.join(backup, 'manifest.json'), 'utf8'));
  if (checked.firestore.length !== manifest.firestore.length || checked.hosting.length !== manifest.hosting.length) {
    throw new Error('Backup verification failed.');
  }
  console.log(`Private backup: ${backup}`);
  const result = {scope: 'B1-B9', projectId, startedAt: new Date().toISOString(), firestore: [], hosting: []};
  const journal = path.join(backup, 'results.json');
  fs.writeFileSync(journal, JSON.stringify(result, null, 2));
  for (const item of manifest.firestore) {
    const status = await removeDocument(token, item, Date.now());
    result.firestore.push({id: item.id, name: item.document.name, status});
    fs.writeFileSync(journal, JSON.stringify(result, null, 2));
  }
  for (const item of manifest.hosting) {
    // Re-read all channels before each deletion so a newly promoted version is kept.
    const state = await hostingState(token);
    const current = state.versions.find(v => v.name === item.version.name);
    let status = 'already_missing';
    if (current && current.status !== 'DELETED') {
      status = 'protected_preserved';
      if (oldHosting(current, state, Date.now())) {
        await api(token, hostingUrl(current.name), {method: 'DELETE'});
        status = 'deleted';
      }
    }
    result.hosting.push({id: 'B9', name: item.version.name, status});
    fs.writeFileSync(journal, JSON.stringify(result, null, 2));
  }
  result.completedAt = new Date().toISOString();
  fs.writeFileSync(journal, JSON.stringify(result, null, 2));
  const deleted = {firestoreDocuments: result.firestore.filter(i => i.status === 'deleted').length,
    hostingVersions: result.hosting.filter(i => i.status === 'deleted').length};
  const byId = Object.fromEntries(Array.from({length: 9}, (_, i) => [`B${i + 1}`, 0]));
  [...result.firestore, ...result.hosting].filter(i => i.status === 'deleted').forEach(i => byId[i.id]++);
  console.log(JSON.stringify({deleted, byId, backup}, null, 2));
}
async function main() {
  if (projectId !== 'hiker-circle') throw new Error('Unexpected project.');
  const args = process.argv.slice(2);
  const arg = name => args[args.indexOf(name) + 1];
  const token = await firebaseAccessToken();
  if (args.includes('--apply')) {
    if (!args.includes('--plan')) throw new Error('Apply requires an inspected --plan file.');
    const planFile = path.resolve(root, arg('--plan'));
    await applyPlan(token, JSON.parse(fs.readFileSync(planFile, 'utf8')), planFile);
  } else {
    const inspectedPlan = await plan(token);
    console.log(JSON.stringify(summary(inspectedPlan), null, 2));
    if (args.includes('--plan-out')) {
      const file = path.resolve(root, arg('--plan-out'));
      save(file, inspectedPlan);
      console.log(`Private plan: ${file}`);
    }
  }
}
module.exports = {eligible, oldHosting, summary, validTarget, decode, millis, removeDocument};
if (require.main === module) main().catch(error => {
  console.error(error.message, error.cause?.code || '');
  process.exitCode = 1;
});

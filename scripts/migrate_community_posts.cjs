'use strict';

// Read-only by default. --apply creates a full private backup before a single
// atomic, update-time-guarded replacement and then verifies every written field.
// Existing media and full private hike captures are never deleted or rewritten.
const fs = require('node:fs');
const path = require('node:path');
const { isDeepStrictEqual } = require('node:util');
const { firebaseAccessToken, projectId } = require('./seed_malaysia_trails');
const { routePreview, validId } = require('../functions/community_posts');
const { contentHash, VERSION } = require('../functions/community_moderation');
const documentRoot = `projects/${projectId}/databases/(default)/documents`;
const base = `https://firestore.googleapis.com/v1/${documentRoot}`;
const POST_FIELDS = new Set(['postId','authorId','authorPhoneNumber','authorName','authorHandle','authorPhotoURL','authorAchievementPoints',
  'authorLevel','authorLevelName','authorLevelBadge','postType','trailId','trailName','sessionId','routeCaptureId','thumbnailType','caption','imageUrls',
  'distanceKm','durationMinutes','checkIns','manualPins','routePointCount','routePreviewPoints','routeStart','routeEnd','routeBounds','summaryReport',
  'highestAltitudeMeters','visibility','likeCount','commentCount','createdAt','createdAtLocal','updatedAt','updatedAtLocal',
  'moderationStatus','moderationReason','moderatedByAdminId','moderatedByAdminPhoneNumber','moderatedAt','moderatedAtLocal']);
const COMMENT_FIELDS = new Set(['commentId','postId','authorId','authorPhoneNumber','authorName','authorHandle','authorPhotoURL',
  'authorAchievementPoints','authorLevel','authorLevelName','authorLevelBadge','body','createdAt','createdAtLocal','updatedAt','updatedAtLocal']);
function decode(value) {
  if (value.mapValue) return decodeFields(value.mapValue.fields);
  if (value.arrayValue) return (value.arrayValue.values || []).map(decode);
  if ('timestampValue' in value) return new Date(value.timestampValue);
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('nullValue' in value) return null;
  return Object.values(value)[0];
}
function decodeFields(fields = {}) { return Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, decode(value)])); }
function encode(value) {
  if (value == null) return {nullValue: null};
  if (value instanceof Date) return {timestampValue: value.toISOString()};
  if (Array.isArray(value)) return {arrayValue: {values: value.map(encode)}};
  if (typeof value === 'string') return {stringValue: value};
  if (typeof value === 'boolean') return {booleanValue: value};
  if (typeof value === 'number' && Number.isFinite(value)) return Number.isSafeInteger(value) ? {integerValue: String(value)} : {doubleValue: value};
  if (typeof value === 'object') return {mapValue: {fields: encodeFields(value)}};
  throw new Error('An unsupported field requires review; no source records were removed.');
}
function encodeFields(value) { return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, encode(item)])); }
function requireCondition(value, message) { if (!value) throw new Error(message); }
function unknownFields(raw, allowed) { requireCondition(Object.keys(raw).every(key => allowed.has(key)), 'An unrecognized community field requires review; no records were changed.'); }
function date(raw, name, fallback) {
  const value = raw[name] instanceof Date ? raw[name] : new Date(raw[`${name}Local`] || fallback || '');
  requireCondition(Number.isFinite(value.getTime()), 'A community timestamp requires review; no records were changed.');
  return value;
}
function author(raw) {
  requireCondition(typeof raw.authorId === 'string' && raw.authorId.length > 0 && raw.authorId === raw.authorPhoneNumber,
    'A community author identity requires review; no records were changed.');
  return {name: String(raw.authorName || 'Hiker'), ...(raw.authorPhotoURL ? {photoURL: raw.authorPhotoURL} : {})};
}
function number(raw, key) {
  const value = raw[key] ?? 0;
  requireCondition(typeof value === 'number' && Number.isFinite(value) && value >= 0, 'A community statistic requires review; no records were changed.');
  return value;
}
function storageImage(url, uid) {
  const parsed = new URL(url);
  const match = /^\/v0\/b\/([^/]+)\/o\/(.+)$/.exec(parsed.pathname);
  requireCondition(parsed.protocol === 'https:' && parsed.hostname === 'firebasestorage.googleapis.com' && match,
    'A photo URL requires review before migration; the photo has been retained.');
  const objectPath = decodeURIComponent(match[2]);
  requireCondition(objectPath.startsWith(`community_hikes/${uid}/`) || objectPath.startsWith(`community_posts/${uid}/`),
    'A photo owner requires review before migration; the photo has been retained.');
  return {path: objectPath, url};
}
function canonicalPost(raw, session, capture, commentCount) {
  unknownFields(raw, POST_FIELDS);
  requireCondition(typeof raw.caption === 'string' && raw.caption.length <= 5000 && ['public','hidden','removed'].includes(raw.visibility),
    'A community post requires review; no records were changed.');
  const createdAt = date(raw, 'createdAt');
  const images = (raw.imageUrls || []).map(url => storageImage(url, raw.authorId));
  requireCondition(images.length <= 6, 'A community photo count requires review; no records were changed.');
  const result = {authorId: raw.authorId, author: author(raw), kind: raw.sessionId ? 'hike' : 'note', caption: raw.caption, images,
    visibility: raw.visibility, likeCount: number(raw, 'likeCount'), commentCount, createdAt, updatedAt: date(raw, 'updatedAt', createdAt)};
  if (raw.trailId || raw.trailName) result.trail = {id: String(raw.trailId || ''), name: String(raw.trailName || session?.trail?.name || 'Trail')};
  if (raw.sessionId) {
    requireCondition(session && capture && session.userId === raw.authorId && session.userPhoneNumber === raw.authorPhoneNumber
      && capture.userId === raw.authorId && capture.userPhoneNumber === raw.authorPhoneNumber && capture.sessionId === raw.sessionId,
    'A private hike source requires review before removing repeated post fields.');
    requireCondition(['active','completed'].includes(session.status), 'A shared hike lifecycle requires review before migration.');
    // Every route coordinate being removed remains available in its full,
    // owner-authorized source. The public preview alone is deliberately bounded.
    const full = new Set((capture.routePoints || []).map(point => `${point.latitude},${point.longitude}`));
    requireCondition((raw.routePreviewPoints || []).every(point => full.has(`${point.latitude},${point.longitude}`)),
      'A post route is missing from its private capture; no route data was removed.');
    requireCondition(!raw.summaryReport || isDeepStrictEqual(raw.summaryReport, capture.summaryReport)
      || isDeepStrictEqual(raw.summaryReport, session.summaryReport),
    'A detailed hike summary differs from both private sources; no summary data was removed.');
    result.hike = {sessionId: raw.sessionId, state: session.status, distanceKm: number(raw, 'distanceKm'),
      durationMinutes: number(raw, 'durationMinutes'), checkIns: number(raw, 'checkIns'), manualPins: number(raw, 'manualPins'),
      routePointCount: number(raw, 'routePointCount'), routePreview: routePreview(raw.routePreviewPoints || capture.routePoints)};
    if (Number.isFinite(raw.highestAltitudeMeters)) result.hike.highestAltitudeMeters = raw.highestAltitudeMeters;
  }
  if (raw.moderationStatus || raw.moderationReason || raw.moderatedByAdminId || raw.moderatedAt || raw.moderatedAtLocal) {
    result.moderation = {status: raw.moderationStatus || (raw.visibility === 'public' ? 'approved' : raw.visibility),
      reason: String(raw.moderationReason || ''), adminId: String(raw.moderatedByAdminId || ''), at: date(raw, 'moderatedAt', result.updatedAt)};
  }
  return result;
}
function canonicalComment(raw) {
  unknownFields(raw, COMMENT_FIELDS);
  requireCondition(typeof raw.body === 'string' && raw.body.trim() && raw.body.length <= 2000, 'A community comment requires review before migration.');
  const createdAt = date(raw, 'createdAt');
  return {authorId: raw.authorId, author: author(raw), body: raw.body, createdAt, updatedAt: date(raw, 'updatedAt', createdAt)};
}
async function api(token, url, options = {}) {
  const response = await fetch(url, {...options, headers: {Authorization: `Bearer ${token}`, 'Content-Type': 'application/json'}, signal: AbortSignal.timeout(60000)});
  if (!response.ok) { const error = new Error(`Community migration request failed (HTTP ${response.status}); no source records were deleted.`); error.status = response.status; throw error; }
  return response.json();
}
async function list(token, collection) {
  const documents = []; let next = '';
  do {
    const url = new URL(`${base}/${collection}`); url.searchParams.set('pageSize', '300');
    if (next) url.searchParams.set('pageToken', next);
    const page = await api(token, url); documents.push(...page.documents || []); next = page.nextPageToken || '';
  } while (next);
  return documents;
}
async function get(token, relative) {
  try { return await api(token, `${base}/${relative}`); }
  catch (error) { if (error.status === 404) return null; throw error; }
}
function documentWithData(original, value) {
  const fields = encodeFields(value);
  for (const name of ['createdAt','updatedAt']) if (original.fields?.[name]?.timestampValue) fields[name] = original.fields[name];
  return {name: original.name, fields};
}
async function assertRetiredCountersDeleted(token, request = api) {
  // Existing production triggers ran in Singapore; current source defaults
  // also permit US deployments. Fence both regions before any cutover write.
  for (const region of ['asia-southeast1','us-central1']) {
    for (const name of ['incrementCommunityCommentCount','decrementCommunityCommentCount']) {
      let exists = true;
      try { await request(token, `https://cloudfunctions.googleapis.com/v2/projects/${projectId}/locations/${region}/functions/${name}`); }
      catch (error) { if (error.status !== 404) throw error; exists = false; }
      requireCondition(!exists, `Delete the retired comment counter functions in ${region} before cutover; no records were changed.`);
    }
  }
}
async function main() {
  const apply = process.argv.includes('--apply'), token = await firebaseAccessToken();
  const functionsDirectory = path.resolve(__dirname, '../functions');
  requireCondition(!fs.readdirSync(functionsDirectory).filter(name => name.endsWith('.js'))
    .some(name => fs.readFileSync(path.join(functionsDirectory, name), 'utf8').includes('communityCounterEventReceipts')),
  'The retired counter ledger still has a runtime consumer; no records were changed.');
  const [posts, checks, reviews, receipts, captures] = await Promise.all(['communityPosts','communityModerationChecks','communityModerationReviews',
    'communityCounterEventReceipts','hikeRouteCaptures'].map(name => list(token, name)));
  const sourceDocuments = [...posts, ...checks, ...reviews, ...receipts], replacements = [], guards = new Map(), canonical = new Map();
  let comments = 0, images = 0, routePoints = 0;
  for (const original of posts) {
    const raw = decodeFields(original.fields), postId = original.name.split('/').at(-1);
    requireCondition(validId(postId), 'A post path requires review before migration.');
    const children = await list(token, `communityPosts/${encodeURIComponent(postId)}/comments`);
    sourceDocuments.push(...children); comments += children.length;
    if (raw.kind && raw.author && raw.images) {
      canonical.set(`communityPosts/${postId}`, raw);
      if (validId(raw.hike?.sessionId)) {
        const capture = await get(token, `hikeRouteCaptures/${encodeURIComponent(raw.hike.sessionId)}`);
        if (capture) { sourceDocuments.push(capture); guards.set(capture.name, capture); }
      }
      continue;
    }
    let sessionDocument, captureDocument;
    if (raw.sessionId) {
      requireCondition(validId(raw.sessionId), 'A hike reference requires review before migration.');
      [sessionDocument, captureDocument] = await Promise.all(['hikeSessions','hikeRouteCaptures'].map(name => get(token, `${name}/${encodeURIComponent(raw.sessionId)}`)));
      for (const doc of [sessionDocument, captureDocument].filter(Boolean)) { sourceDocuments.push(doc); guards.set(doc.name, doc); }
    }
    const converted = canonicalPost(raw, sessionDocument && decodeFields(sessionDocument.fields), captureDocument && decodeFields(captureDocument.fields), children.length);
    const convertedDocument = documentWithData(original, converted);
    replacements.push({original, replacement: convertedDocument}); canonical.set(`communityPosts/${postId}`, converted);
    images += converted.images.length; routePoints += converted.hike?.routePreview.length || 0;
    for (const child of children) {
      const childValue = canonicalComment(decodeFields(child.fields));
      replacements.push({original: child, replacement: documentWithData(child, childValue)});
      canonical.set(child.name.slice(documentRoot.length + 1), childValue);
    }
  }
  // Existing human decisions remain attached to the same text/author/path.
  // Re-hashing avoids losing pending flags or reopening dismissed decisions.
  for (const original of [...checks, ...reviews]) {
    const raw = decodeFields(original.fields), content = canonical.get(raw.sourcePath);
    if (!content) continue;
    const replacement = {name: original.name, fields: {...original.fields,
      fingerprint: {stringValue: contentHash(raw.sourcePath, content)}, policyVersion: {integerValue: String(VERSION)}}};
    if (!isDeepStrictEqual(original.fields, replacement.fields)) replacements.push({original, replacement});
  }
  // Old/deleted community posts can leave this reverse alias on a capture.
  // Preserve the complete private record and remove only that unused field.
  for (const capture of captures) if (capture.fields?.communityPostId && !guards.has(capture.name)) {
    sourceDocuments.push(capture); guards.set(capture.name, capture);
  }
  const privateSourcesVerified = guards.size;
  let captureAliasesRemoved = 0;
  for (const [name, original] of guards) {
    if (!name.startsWith(`${documentRoot}/hikeRouteCaptures/`) || !original.fields?.communityPostId) continue;
    const fields = {...original.fields}; delete fields.communityPostId;
    replacements.push({original, replacement: {name, fields}});
    // The replacement itself carries the same update-time guard.
    guards.delete(name); captureAliasesRemoved++;
  }
  const summary = {projectId, apply, posts: posts.length, comments, photosPreserved: images, previewPoints: routePoints,
    replacements: replacements.length, privateSourcesVerified, captureAliasesRemoved, retiredCounterReceiptsArchived: receipts.length,
    sourceDocumentsRetainedInBackup: sourceDocuments.length};
  console.log(JSON.stringify(summary));
  if (!apply || !replacements.length && !receipts.length) return;
  await assertRetiredCountersDeleted(token);
  requireCondition(replacements.length + guards.size + receipts.length <= 450, 'This dataset needs a staged migration; no records were changed.');
  const backupDirectory = path.resolve(__dirname, '../tmp/community-migration', new Date().toISOString().replace(/[:.]/g, '-'));
  fs.mkdirSync(backupDirectory, {recursive: true});
  fs.writeFileSync(path.join(backupDirectory, 'backup.json'), JSON.stringify({projectId, sourceDocuments}, null, 2), {flag: 'wx'});
  fs.writeFileSync(path.join(backupDirectory, 'plan.json'), JSON.stringify({summary, replacements, retiredCounterReceipts: receipts}, null, 2), {flag: 'wx'});
  const writes = [
    ...replacements.map(plan => ({update: plan.replacement, currentDocument: {updateTime: plan.original.updateTime}})),
    ...[...guards.values()].map(doc => ({verify: doc.name, currentDocument: {updateTime: doc.updateTime}})),
    ...receipts.map(doc => ({delete: doc.name, currentDocument: {updateTime: doc.updateTime}})),
  ];
  await api(token, `${base}:commit`, {method: 'POST', body: JSON.stringify({writes})});
  for (const plan of replacements) {
    const actual = await api(token, `https://firestore.googleapis.com/v1/${plan.original.name}`);
    requireCondition(isDeepStrictEqual(decodeFields(actual.fields), decodeFields(plan.replacement.fields)),
      'Read-back verification failed; the full original records remain in the backup.');
  }
  for (const receipt of receipts) requireCondition(await get(token, receipt.name.slice(documentRoot.length + 1)) === null,
    'A retired counter receipt was recreated; the full original records remain in the backup.');
  fs.writeFileSync(path.join(backupDirectory, 'result.json'), JSON.stringify({...summary, verified: true}, null, 2), {flag: 'wx'});
  console.log('Community migration verified. Private backup: ' + path.relative(path.resolve(__dirname, '..'), backupDirectory));
}
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = {decodeFields, encodeFields, storageImage, canonicalPost, canonicalComment, assertRetiredCountersDeleted};

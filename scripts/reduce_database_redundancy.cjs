'use strict';

// Remove only eight unused hikeRouteCaptures fields. The route, pins, summary,
// owner, IDs, and dates remain byte-for-byte equivalent Firestore values.
// Dry run is the default; --apply saves a private backup before an atomic commit.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const {firebaseAccessToken, projectId} = require('./seed_malaysia_trails');
const ROOT = path.resolve(__dirname, '..');
const DOCUMENT_ROOT = `projects/${projectId}/databases/(default)/documents`;
const API = `https://firestore.googleapis.com/v1/${DOCUMENT_ROOT}`;
const OBSOLETE_CAPTURE_FIELDS = Object.freeze([
  'routeStart', 'routeEnd', 'routeBounds', 'captureType',
  'anonymousRecommendationEligible', 'storedRoutePointCount',
  'storedManualPinCount', 'manualPinsDownsampled',
]);

// Restrict every write to a known collection and an explicit field allowlist.
function capturePatch(document) {
  assert.ok(document.name.startsWith(`${DOCUMENT_ROOT}/hikeRouteCaptures/`));
  assert.equal(document.name.slice(DOCUMENT_ROOT.length + 1).split('/').length, 2);
  const fields = document.fields || {};
  const removed = OBSOLETE_CAPTURE_FIELDS.filter(field => Object.hasOwn(fields, field));
  if (!removed.length) return null;
  assert.ok(document.updateTime, 'A document version is required.');
  return {
    update: {name: document.name, fields: {}},
    updateMask: {fieldPaths: removed},
    currentDocument: {updateTime: document.updateTime},
  };
}

function retainedFields(document) {
  return Object.fromEntries(Object.entries(document.fields || {})
    .filter(([field]) => !OBSOLETE_CAPTURE_FIELDS.includes(field)));
}

// API errors intentionally omit response bodies, which may contain user values.
async function request(token, url, options = {}) {
  const response = await fetch(url, {...options,
    headers: {Authorization: `Bearer ${token}`, 'Content-Type': 'application/json'},
    signal: AbortSignal.timeout(30000)});
  if (!response.ok) throw new Error(`Database review request failed (HTTP ${response.status}).`);
  return response.json();
}
async function listCaptures(token) {
  const documents = []; let next = '';
  do {
    const url = new URL(`${API}/hikeRouteCaptures`);
    url.searchParams.set('pageSize', '300');
    if (next) url.searchParams.set('pageToken', next);
    const response = await request(token, url);
    documents.push(...response.documents || []); next = response.nextPageToken || '';
  } while (next);
  return documents;
}
function schemaSummary(documents) {
  return {
    documents: documents.length,
    topLevelFields: [...new Set(documents.flatMap(doc => Object.keys(doc.fields || {})))].sort(),
    obsoleteFieldOccurrences: documents.reduce((total, doc) => total +
      OBSOLETE_CAPTURE_FIELDS.filter(field => Object.hasOwn(doc.fields || {}, field)).length, 0),
  };
}

async function main() {
  assert.equal(projectId, 'hiker-circle', 'Unexpected Firebase project.');
  const apply = process.argv.includes('--apply');
  const token = await firebaseAccessToken();
  const before = await listCaptures(token);
  const writes = before.map(capturePatch).filter(Boolean);
  assert.ok(writes.length <= 500, 'Review larger changes before splitting atomic commits.');
  const summary = {projectId, apply, before: schemaSummary(before), documentsToPatch: writes.length,
    removedFields: OBSOLETE_CAPTURE_FIELDS};
  if (apply && writes.length) {
    const folder = path.join(ROOT, 'tmp', 'database-review-2026-10-18',
      'capture-backup-' + new Date().toISOString().replace(/[:.]/g, '-'));
    fs.mkdirSync(folder, {recursive: true});
    const backup = JSON.stringify({projectId, documents: before}, null, 2);
    fs.writeFileSync(path.join(folder, 'backup.json'), backup, {flag: 'wx'});
    fs.writeFileSync(path.join(folder, 'plan.json'), JSON.stringify({writes}, null, 2), {flag: 'wx'});
    summary.backupSha256 = createHash('sha256').update(backup).digest('hex');
    // A concurrent edit rejects the complete commit; no partial cutover is used.
    await request(token, `${API}:commit`, {method: 'POST', body: JSON.stringify({writes})});
    const after = await listCaptures(token);
    const byName = new Map(after.map(document => [document.name, document]));
    assert.equal(after.length, before.length, 'The capture count changed during verification.');
    for (const original of before) {
      const current = byName.get(original.name);
      assert.ok(current, 'An original capture is missing.');
      assert.deepEqual(current.fields, retainedFields(original), 'A retained capture field changed.');
    }
    summary.after = schemaSummary(after);
    assert.equal(summary.after.obsoleteFieldOccurrences, 0);
    summary.retainedFieldsVerified = before.length;
    fs.writeFileSync(path.join(folder, 'result.json'), JSON.stringify(summary, null, 2));
  }
  // Public verification metadata contains counts and field names, never records.
  if (apply) {
    const out = path.join(ROOT, 'output', 'database-review'); fs.mkdirSync(out, {recursive: true});
    fs.writeFileSync(path.join(out, 'capture-reduction-verification.json'),
      JSON.stringify({...summary, verifiedAt: new Date().toISOString()}, null, 2));
  }
  console.log(JSON.stringify(summary, null, 2));
}
if (require.main === module) main().catch(error => {
  console.error(error.message); process.exitCode = 1;
});
module.exports = {OBSOLETE_CAPTURE_FIELDS, DOCUMENT_ROOT, capturePatch, retainedFields, schemaSummary};

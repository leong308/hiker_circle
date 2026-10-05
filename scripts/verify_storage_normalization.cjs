'use strict';
// Read-only verification of the exact D migration targets and preserved fields.
const fs = require('node:fs');
const path = require('node:path');
const {isDeepStrictEqual} = require('node:util');
const {firebaseAccessToken, projectId} = require('./seed_malaysia_trails');
const {validItem} = require('./migrate_storage_normalization.cjs');
const documentRoot = `projects/${projectId}/databases/(default)/documents`;
async function read(token, name) {
  if (!name.startsWith(documentRoot + '/')) throw new Error('Unexpected project.');
  const encodedPath = name.slice(documentRoot.length + 1).split('/').map(encodeURIComponent).join('/');
  const response = await fetch(`https://firestore.googleapis.com/v1/${documentRoot}/${encodedPath}`, {
    headers: {Authorization: `Bearer ${token}`}, signal: AbortSignal.timeout(30000),
  });
  if (!response.ok) throw new Error(`Verification read failed (HTTP ${response.status}).`);
  return response.json();
}
function fieldAt(fields, fieldPath) {
  const parts = fieldPath.split('.');
  for (const key of parts.slice(0, -1)) fields = fields?.[key]?.mapValue?.fields;
  return fields?.[parts.at(-1)];
}
function without(fields, masks) {
  const result = structuredClone(fields);
  for (const mask of masks) {
    let parent = result;
    const parts = mask.split('.');
    for (const key of parts.slice(0, -1)) parent = parent?.[key]?.mapValue?.fields;
    if (parent) delete parent[parts.at(-1)];
  }
  return result;
}
async function main() {
  const folder = path.resolve(process.argv[2] || '');
  const plan = JSON.parse(fs.readFileSync(path.join(folder, 'manifest.json')));
  const results = JSON.parse(fs.readFileSync(path.join(folder, 'results.json')));
  if (projectId !== 'hiker-circle' || plan.projectId !== projectId || plan.scope !== 'D2-D4') {
    throw new Error('Unexpected backup scope.');
  }
  const token = await firebaseAccessToken();
  const counts = {verified: 0, archives: 0, concurrentlyChanged: 0};
  for (const result of results) {
    if (result.status !== 'migrated') continue;
    const item = plan.items.find(i => i.document.name === result.name);
    if (!item || !validItem(item)) throw new Error('Invalid backup target.');
    const current = await read(token, result.name);
    if (!isDeepStrictEqual(without(current.fields, item.mask), without(item.document.fields, item.mask))) {
      counts.concurrentlyChanged++;
      throw new Error('Unexpected or concurrent change outside the inspected field mask; review private backup.');
    }
    for (const mask of item.mask) {
      if (!isDeepStrictEqual(fieldAt(current.fields, mask), fieldAt(item.fields, mask))) {
        throw new Error('Migrated field differs from inspected projection.');
      }
    }
    if (item.archive) {
      const archive = await read(token, item.archive.name);
      if (!isDeepStrictEqual(archive.fields, item.archive.fields)) {
        throw new Error('Archive differs from exact original forecast.');
      }
      counts.archives++;
    }
    counts.verified++;
  }
  console.log(JSON.stringify(counts, null, 2));
}
if (require.main === module) main().catch(error => {console.error(error.message); process.exitCode = 1;});
module.exports = {fieldAt, without};

/* eslint-disable no-console */
'use strict';
// One atomic commit per trail: move the complete subtree and repair references.
// Dry-run by default. Firestore types, route vertices and media paths are preserved.
const fs = require('fs');
const { isDeepStrictEqual } = require('util');
const { firebaseAccessToken, firestoreRequest, firestoreRoot,
  firestoreDocumentRoot } = require('./seed_malaysia_trails');
const renames = {
  trail_bukit_bendera_1781715992541600: 'malaysia-penang-hill-heritage-trail',
  trail_bukit_gasing_loop_1782225621903565: 'malaysia-bukit-gasing-loop',
  trail_bukit_jambul_trail_1782232587060378: 'malaysia-bukit-jambul-trail',
  trail_near_teluk_kumbar_1781870736276385: 'malaysia-near-teluk-kumbar',
};
function replacePath(value, oldId, newId) {
  return value.split('/').map(segment => segment === oldId ? newId : segment).join('/');
}
function documentUrl(name) {
  return `https://firestore.googleapis.com/v1/${name.split('/').map(encodeURIComponent).join('/')}`;
}
function transform(value, oldId, newId, field = '') {
  if (Array.isArray(value)) return value.map(v => transform(v, oldId, newId, field));
  if (!value || typeof value !== 'object') return value;
  if ('stringValue' in value || 'referenceValue' in value) {
    const type = 'stringValue' in value ? 'stringValue' : 'referenceValue';
    let text = value[type];
    if (text === oldId) text = newId;
    else if (type === 'referenceValue' || field === 'geometryDocument') {
      text = replacePath(text, oldId, newId);
    } else if (field === 'downloadedMapId' && text.endsWith(`_${oldId}`)) {
      text = text.slice(0, -oldId.length) + newId;
    }
    return { ...value, [type]: text };
  }
  if (value.mapValue) return { ...value, mapValue: { ...value.mapValue,
    ...(value.mapValue.fields ? {fields:transformFields(value.mapValue.fields, oldId, newId)} : {}) } };
  if (value.arrayValue) return { ...value, arrayValue: { ...value.arrayValue,
    ...(value.arrayValue.values ? {values:value.arrayValue.values.map(v => transform(v, oldId, newId, field))} : {}) } };
  return value;
}
function transformFields(fields, oldId, newId) {
  return Object.fromEntries(Object.entries(fields).map(([key,value]) =>
    [key === oldId ? newId : key, transform(value, oldId, newId, key)]));
}
function planRename(documents, oldId, newId) {
  const oldRoot = `${firestoreDocumentRoot}/trails/${oldId}`;
  const newRoot = `${firestoreDocumentRoot}/trails/${newId}`;
  const hasOld = documents.some(d => d.name === oldRoot);
  const hasNew = documents.some(d => d.name === newRoot);
  if (!hasOld && !hasNew) throw Error(`Trail missing: ${oldId}`);
  if (hasOld && hasNew) throw Error(`Destination already exists: ${newId}`);
  const changes = [];
  for (const doc of documents) {
    let name = doc.name;
    if (name === oldRoot || name.startsWith(`${oldRoot}/`)) name = newRoot + name.slice(oldRoot.length);
    if (name.startsWith(`${firestoreDocumentRoot}/downloadedMaps/`) && name.endsWith(`_${oldId}`)) {
      name = name.slice(0, -oldId.length) + newId;
    }
    const fields = transformFields(doc.fields || {}, oldId, newId);
    const changedKeys = [...new Set([...Object.keys(doc.fields || {}), ...Object.keys(fields)])]
      .filter(key => !isDeepStrictEqual(doc.fields?.[key], fields[key]));
    if (name === doc.name && !changedKeys.length) continue;
    if (name !== doc.name && documents.some(d => d.name === name)) throw Error(`Destination collision: ${name}`);
    changes.push({ before:doc, after:{name,fields}, changedKeys });
  }
  const writes = changes.flatMap(({before,after,changedKeys}) => before.name !== after.name ? [
    {update:after,currentDocument:{exists:false}},
    {delete:before.name,currentDocument:{updateTime:before.updateTime}},
  ] : [{update:{name:after.name,fields:Object.fromEntries(changedKeys.filter(k => k in after.fields).map(k => [k,after.fields[k]]))},
    updateMask:{fieldPaths:changedKeys.map(k => '`' + k.replace(/\\/g,'\\\\').replace(/`/g,'\\`') + '`')},
    currentDocument:{updateTime:before.updateTime}}]);
  if (writes.length > 500 || Buffer.byteLength(JSON.stringify({writes})) > 9000000) {
    throw Error(`Atomic migration exceeds commit budget: ${oldId}`);
  }
  return {oldId,newId,changes,writes};
}
async function collectionIds(token, parent = firestoreDocumentRoot) {
  const ids = []; let pageToken;
  do {
    const result = await firestoreRequest(token, `https://firestore.googleapis.com/v1/${parent}:listCollectionIds`,
      {method:'POST',body:JSON.stringify({pageSize:1000,...(pageToken?{pageToken}:{})})});
    ids.push(...(result.collectionIds || [])); pageToken = result.nextPageToken;
  } while (pageToken);
  return ids;
}
async function descendants(token, parent, result) {
  for (const id of await collectionIds(token,parent)) {
    let pageToken;
    do {
      const url = new URL(`https://firestore.googleapis.com/v1/${parent}/${id}`);
      url.searchParams.set('pageSize','300'); url.searchParams.set('showMissing','true');
      if (pageToken) url.searchParams.set('pageToken',pageToken);
      const response = await firestoreRequest(token,url);
      for (const doc of response.documents || []) {
        if (doc.updateTime) result.set(doc.name,doc);
        await descendants(token,doc.name,result);
      }
      pageToken = response.nextPageToken;
    } while (pageToken);
  }
}
async function inventory(token) {
  const groups = [...new Set([...(await collectionIds(token)),
    'authFactors','comments','messages','ratings','reminderPreferences','reports','routeGeometry','routeSources'])];
  const documents = new Map(); let cursor = 0;
  await Promise.all(Array.from({length:4}, async () => {
    while (cursor < groups.length) {
      const collectionId = groups[cursor++];
      const rows = await firestoreRequest(token,firestoreRoot+':runQuery',{method:'POST',
        body:JSON.stringify({structuredQuery:{from:[{collectionId,allDescendants:true}]}})});
      for (const row of rows) if (row.document) documents.set(row.document.name,row.document);
    }
  }));
  // Discover every descendant of both source and destination, including unknown
  // subcollections and descendants of missing documents.
  for (const id of [...Object.keys(renames),...Object.values(renames)]) {
    await descendants(token,`${firestoreDocumentRoot}/trails/${id}`,documents);
  }
  return [...documents.values()];
}
async function main() {
  const token = await firebaseAccessToken();
  let documents = await inventory(token);
  const initial = Object.entries(renames).map(([oldId,newId]) => planRename(documents,oldId,newId));
  console.log(`Audited ${documents.length} documents.`);
  for (const p of initial) console.log(`${p.oldId} -> ${p.newId}: ${p.changes.length} records, ${p.writes.length} atomic writes`);
  if (!process.argv.includes('--apply')) return;
  const directory = `output/trail-id-migration/${new Date().toISOString().replace(/[:.]/g,'-')}`;
  fs.mkdirSync(directory,{recursive:true,mode:0o700});
  const affected = [...new Map(initial.flatMap(p => p.changes.map(c => [c.before.name,c.before]))).values()];
  fs.writeFileSync(`${directory}/backup.json`,JSON.stringify(affected),{mode:0o600});
  for (const [oldId,newId] of Object.entries(renames)) {
    const plan = planRename(documents,oldId,newId);
    if (!plan.writes.length) continue;
    await firestoreRequest(token,firestoreRoot+':commit',{method:'POST',body:JSON.stringify({writes:plan.writes})});
    // Read back the exact typed fields, including all geometry vertices.
    let cursor = 0;
    const verified = [];
    await Promise.all(Array.from({length:4}, async () => {
      while (cursor < plan.changes.length) {
        const change = plan.changes[cursor++];
        const actual = await firestoreRequest(token,documentUrl(change.after.name));
        if (!isDeepStrictEqual(actual.fields,change.after.fields)) throw Error(`Read-back mismatch: ${change.after.name}`);
        verified.push(actual);
      }
    }));
    const changedNames = new Set(plan.changes.map(c => c.before.name));
    documents = [...documents.filter(d => !changedNames.has(d.name)),...verified];
    console.log(`Verified ${newId}: ${plan.changes.length} records.`);
  }
  const final = await inventory(token);
  for (const [oldId,newId] of Object.entries(renames)) {
    if (planRename(final,oldId,newId).writes.length) throw Error(`Stale references remain: ${oldId}`);
    if (final.some(d => d.name === `${firestoreDocumentRoot}/trails/${oldId}` ||
      d.name.startsWith(`${firestoreDocumentRoot}/trails/${oldId}/`))) throw Error('Old subtree remains.');
  }
  fs.writeFileSync(`${directory}/report.json`,JSON.stringify({renames,verified:true,
    updatedRecords:affected.length,trailCount:final.filter(d => d.name.split('/documents/')[1].split('/').length === 2 &&
      d.name.includes('/documents/trails/')).length},null,2));
  console.log('Verified all four IDs, subcollections and application references.');
}
if (require.main === module) main().catch(e => {console.error(e.message);process.exitCode=1;});
module.exports = {renames,transformFields,planRename,inventory,documentUrl};

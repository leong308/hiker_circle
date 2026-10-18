'use strict';
// Refresh only the changed schema from live Firestore; never write user values.
const fs = require('node:fs');
const path = require('node:path');
const { firebaseAccessToken, firestoreRequest, projectId } = require('./seed_malaysia_trails');
const root = path.resolve(__dirname, '..');
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
async function list(token, collection) {
  const docs = []; let next = '';
  do {
    const url = new URL(`${base}/${collection}`); url.searchParams.set('pageSize', '300');
    if (next) url.searchParams.set('pageToken', next);
    const result = await firestoreRequest(token, url);
    docs.push(...result.documents || []); next = result.nextPageToken || '';
  } while (next);
  return docs;
}
function collect(node, value) {
  const type = Object.keys(value)[0].replace(/Value$/, '');
  node.types ||= [];
  if (!node.types.includes(type)) node.types.push(type);
  if (type === 'map') {
    node.fields ||= {};
    for (const [key, child] of Object.entries(value.mapValue.fields || {})) collect(node.fields[key] ||= {}, child);
  }
  if (type === 'array') {
    node.items ||= {};
    for (const child of value.arrayValue.values || []) collect(node.items, child);
  }
}
async function main() {
  const token = await firebaseAccessToken();
  const [chunks, sessions, obsolete] = await Promise.all(['footprints', 'hikeSessions', 'localLocationPoints'].map(name => list(token, name)));
  if (obsolete.length) throw new Error('Old location documents remain; migration is incomplete.');
  const byName = new Map(chunks.map(doc => [doc.name, doc]));
  let samples = 0;
  const seenChunks = new Set();
  for (const session of sessions) {
    if (!session.fields.footprint?.arrayValue) throw new Error('A hike has no footprint list.');
    const times = new Set();
    for (const reference of session.fields.footprint.arrayValue.values || []) {
      const chunk = byName.get(reference.referenceValue);
      if (!chunk || seenChunks.has(chunk.name)) throw new Error('Missing or multiply linked footprint document.');
      seenChunks.add(chunk.name);
      if (chunk.fields.sessionId.stringValue !== session.name.split('/').at(-1)) throw new Error('Foreign footprint document.');
      const points = chunk.fields.samples.arrayValue.values || [];
      if (!points.length || points.length > 50) throw new Error('Invalid chunk size.');
      for (const point of points) {
        const time = point.mapValue.fields.recordedAtMillis.integerValue;
        if (times.has(time)) throw new Error('Duplicate sample identity.');
        times.add(time); samples++;
      }
    }
  }
  if (seenChunks.size !== chunks.length) throw new Error('An unlinked footprint document remains.');
  const sourceFile = path.join(root, 'output/firestore/hikercircle-firestore-schema.json');
  const source = JSON.parse(fs.readFileSync(sourceFile, 'utf8'));
  delete source.schemas['localLocationPoints/{documentId}'];
  source.relationships = source.relationships.filter(edge => !JSON.stringify(edge).includes('localLocationPoints') && edge.child !== 'footprints/{documentId}');
  const fields = {};
  for (const doc of chunks) for (const [key, value] of Object.entries(doc.fields)) collect(fields[key] ||= {}, value);
  for (const field of Object.values(fields)) field.evidence = ['Live migration verification', 'functions/footprint_batch.js'];
  fields.samples.note = 'Up to 50 compact GPS samples per document. Nested properties intentionally remain inside this single array row.';
  fields.sessionId.note = 'Backreference to the owning hike; access control derives ownership from hikeSessions.';
  const schemaPath = 'footprints/{documentId}';
  source.schemas[schemaPath] = { path: schemaPath, documentsObserved: chunks.length, fields,
    family: 'Hike tracking', scope: 'Root collection',
    description: 'Private GPS footprint chunks. Each hikeSessions.footprint list contains DocumentReference values to its chunks; each chunk stores at most 50 samples.' };
  source.schemas['hikeSessions/{sessionId}'].fields.footprint = { types: ['array'], items: { types: ['reference'] }, present: sessions.length,
    evidence: ['Live migration verification', 'functions/footprint_batch.js'],
    note: 'List of references to footprints documents. One hike owns zero or more chunks; each chunk belongs to one hike.' };
  source.relationships.push({ parent: 'hikeSessions/{sessionId}', parentField: 'footprint', child: schemaPath, childField: '__documentPath',
    cardinality: '1:M', kind: 'reference', note: 'The parent array contains Firestore DocumentReference values to its chunks. Each chunk also stores sessionId as the query/ownership backreference. Firestore does not enforce this association as a SQL FK.' });
  source.firestoreIndexConfiguration = JSON.parse(fs.readFileSync(path.join(root, 'firestore.indexes.json'), 'utf8'));
  source.footprintMigrationVerifiedAt = new Date().toISOString();
  fs.writeFileSync(sourceFile, JSON.stringify(source, null, 2));
  const report = { verifiedAt: source.footprintMigrationVerifiedAt, sessions: sessions.length,
    footprintDocuments: chunks.length, samples, maximumSamplesPerDocument: Math.max(0, ...chunks.map(doc => (doc.fields.samples.arrayValue.values || []).length)), obsoleteLocationDocuments: 0,
    validation: 'Every chunk is linked once to its owning hike; every sample timestamp is unique within its hike; all chunks contain 1–50 samples.' };
  fs.writeFileSync(path.join(root, 'output/firestore/footprint-migration-verification.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report));
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });

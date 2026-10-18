'use strict';

// Dry run by default. --apply backs up all inputs, verifies replacement chunks,
// then removes only old samples whose exact contents have been preserved.
const fs = require('node:fs');
const path = require('node:path');
const { firebaseAccessToken, firestoreFields, projectId } = require('./seed_malaysia_trails');
const { parseFootprintBatch, footprintId, documentBytes, DOCUMENT_BUDGET } = require('../functions/footprint_batch');
const documentRoot = `projects/${projectId}/databases/(default)/documents`;
const base = `https://firestore.googleapis.com/v1/${documentRoot}`;
class MigrationError extends Error { constructor(code, message) { super(message); this.code = code; } }
function decode(value) {
  if (value.mapValue) return fields(value.mapValue.fields);
  if (value.arrayValue) return (value.arrayValue.values || []).map(decode);
  if ('integerValue' in value) return Number(value.integerValue);
  if ('referenceValue' in value) return { firestore: true, path: value.referenceValue.slice(documentRoot.length + 1) };
  return Object.values(value)[0];
}
function fields(raw = {}) { return Object.fromEntries(Object.entries(raw).map(([key, value]) => [key, decode(value)])); }
async function api(token, url, options = {}) {
  const response = await fetch(url, { ...options, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(60000) });
  if (!response.ok) throw new Error(`Footprint migration request failed (HTTP ${response.status}).`);
  return response.json();
}
async function list(token, collection) {
  const documents = [];
  let next = '';
  do {
    const url = new URL(`${base}/${collection}`);
    url.searchParams.set('pageSize', '300');
    if (next) url.searchParams.set('pageToken', next);
    const result = await api(token, url);
    documents.push(...result.documents || []);
    next = result.nextPageToken || '';
  } while (next);
  return documents;
}
function compact(raw) {
  return parseFootprintBatch([{
    recordedAtMillis: raw.recordedAtMillis ?? Date.parse(raw.recordedAtLocal),
    fixCapturedAtMillis: raw.fixCapturedAtMillis ?? raw.recordedAtMillis ?? Date.parse(raw.recordedAtLocal),
    latitude: raw.latitude, longitude: raw.longitude,
    accuracyMeters: raw.accuracyMeters ?? raw.accuracy,
    altitudeMeters: raw.altitudeMeters ?? raw.altitude,
    batteryLevel: raw.batteryLevel, pointType: raw.pointType,
  }], MigrationError)[0];
}
function equivalent(left, right) {
  const canonical = value => Array.isArray(value) ? value.map(canonical)
    : value && typeof value === 'object' ? Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b)).map(([key, item]) => [key, canonical(item)])) : value;
  return JSON.stringify(canonical(left)) === JSON.stringify(canonical(right));
}
async function main() {
  const apply = process.argv.includes('--apply');
  const token = await firebaseAccessToken();
  const [sessions, oldPoints, existingChunks] = await Promise.all(['hikeSessions', 'localLocationPoints', 'footprints'].map(name => list(token, name)));
  const chunksByName = new Map(existingChunks.map(doc => [doc.name, doc]));
  const groups = new Map(sessions.map(doc => [doc.name.split('/').at(-1), { document: doc, old: [] }]));
  let orphans = 0;
  for (const document of oldPoints) {
    const raw = fields(document.fields);
    const group = groups.get(raw.sessionId);
    if (!group) { orphans++; continue; }
    const hike = fields(group.document.fields);
    if (raw.userId && raw.userId !== hike.userId || raw.userPhoneNumber && raw.userPhoneNumber !== hike.userPhoneNumber) {
      throw new Error('An old location owner conflicts with its hike; no data was removed.');
    }
    group.old.push({ document, sample: compact(raw) });
  }
  const plans = [];
  let sampleCount = 0, chunkCount = 0;
  for (const [sessionId, group] of groups) {
    const hike = fields(group.document.fields);
    const originalReferences = group.document.fields?.footprint?.arrayValue?.values || [];
    const samples = new Map();
    const previousChunks = [];
    for (const reference of originalReferences) {
      const document = chunksByName.get(reference.referenceValue);
      if (!document || fields(document.fields).sessionId !== sessionId) throw new Error('Invalid existing footprint link.');
      previousChunks.push(document);
      for (const sample of fields(document.fields).samples) samples.set(sample.recordedAtMillis, sample);
    }
    for (const { sample } of group.old) {
      if (samples.has(sample.recordedAtMillis) && !equivalent(samples.get(sample.recordedAtMillis), sample)) {
        throw new Error('Conflicting samples share a timestamp; review is required before removal.');
      }
      samples.set(sample.recordedAtMillis, sample);
    }
    const ordered = [...samples.values()].sort((a, b) => a.recordedAtMillis - b.recordedAtMillis);
    const chunks = [];
    for (let offset = 0; offset < ordered.length; offset += 50) {
      const points = ordered.slice(offset, offset + 50);
      const name = `${documentRoot}/footprints/${footprintId(sessionId, chunks.length)}`;
      const data = { sessionId, samples: points, firstRecordedAtMillis: points[0].recordedAtMillis, lastRecordedAtMillis: points.at(-1).recordedAtMillis };
      if (documentBytes(name.slice(documentRoot.length + 1), data) > DOCUMENT_BUDGET) throw new Error('Chunk exceeds document budget.');
      chunks.push({ name, fields: firestoreFields(data) });
    }
    const footprint = { arrayValue: { values: chunks.map(doc => ({ referenceValue: doc.name })) } };
    const decodedReferences = chunks.map(doc => ({ firestore: true, path: doc.name.slice(documentRoot.length + 1) }));
    if (documentBytes(`hikeSessions/${sessionId}`, { ...hike, footprint: decodedReferences }) > DOCUMENT_BUDGET) throw new Error('Parent exceeds document budget.');
    if (group.old.length || !group.document.fields?.footprint) plans.push({ ...group, previousChunks, chunks, footprint });
    sampleCount += ordered.length;
    chunkCount += chunks.length;
  }
  const summary = { projectId, apply, sessions: sessions.length, oldDocuments: oldPoints.length, orphanDocumentsRetained: orphans, uniqueSamples: sampleCount, footprintDocuments: chunkCount, parentUpdates: plans.length };
  console.log(JSON.stringify(summary));
  if (!apply) return;
  const backupDirectory = path.resolve(__dirname, '../tmp/footprint-migration', new Date().toISOString().replace(/[:.]/g, '-'));
  fs.mkdirSync(backupDirectory, { recursive: true });
  fs.writeFileSync(path.join(backupDirectory, 'backup.json'), JSON.stringify({ projectId, sessions, oldPoints, existingChunks }, null, 2));
  let migrated = 0;
  for (const plan of plans) {
    const oldByName = new Map(plan.previousChunks.map(doc => [doc.name, doc]));
    const writes = plan.chunks.map(doc => ({ update: doc, currentDocument: oldByName.has(doc.name)
      ? { updateTime: oldByName.get(doc.name).updateTime } : { exists: false } }));
    writes.push({ update: { name: plan.document.name, fields: { footprint: plan.footprint } }, updateMask: { fieldPaths: ['footprint'] }, currentDocument: { updateTime: plan.document.updateTime } });
    if (writes.length > 450) throw new Error('This hike requires a staged migration; old data was retained.');
    await api(token, `${base}:commit`, { method: 'POST', body: JSON.stringify({ writes }) });
    // Read back every committed replacement before deleting any source sample.
    const stored = new Map();
    for (const chunk of plan.chunks) {
      const actual = await api(token, `https://firestore.googleapis.com/v1/${chunk.name}`);
      if (!equivalent(fields(actual.fields), fields(chunk.fields))) throw new Error('Chunk verification failed; old data retained.');
      for (const sample of fields(actual.fields).samples) stored.set(sample.recordedAtMillis, sample);
    }
    for (const old of plan.old) if (!equivalent(stored.get(old.sample.recordedAtMillis) || {}, old.sample)) throw new Error('Sample verification failed; old data retained.');
    for (let offset = 0; offset < plan.old.length; offset += 200) {
      await api(token, `${base}:commit`, { method: 'POST', body: JSON.stringify({ writes: plan.old.slice(offset, offset + 200).map(old => ({ delete: old.document.name, currentDocument: { updateTime: old.document.updateTime } })) }) });
    }
    migrated++;
    if (migrated % 10 === 0) console.log(`Verified ${migrated}/${plans.length} hike migrations.`);
  }
  fs.writeFileSync(path.join(backupDirectory, 'result.json'), JSON.stringify(summary, null, 2));
  console.log('Migration verified. Backup: ' + path.relative(path.resolve(__dirname, '..'), backupDirectory));
}
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = { compact, equivalent };

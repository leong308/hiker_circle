'use strict';

// Refresh local schema metadata only. This script never sends Firebase writes.
// --apply merges verified capture reductions and undeployed security definitions.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const {OBSOLETE_CAPTURE_FIELDS} = require('./reduce_database_redundancy.cjs');
const {relationshipId, relationIndex} = require('./refresh_community_diagrams.cjs');
const ROOT = path.resolve(__dirname, '..');
const read = file => JSON.parse(fs.readFileSync(path.join(ROOT, file), 'utf8'));
const CAPTURE = 'hikeRouteCaptures/{documentId}';

function endpointExists(schemas, context, field) {
  const [schemaPath, ...parts] = context.split('::');
  let node = schemas[schemaPath];
  if (!node) return false;
  if (!parts.length && ['__documentPath', '__documentId', '__ownerId'].includes(field)) return true;
  for (const part of parts) {node = node.fields?.[part]; if (!node) return false; node = node.items || node;}
  return !!node.fields?.[field];
}

// Keep observed live fields unless their removal was explicitly verified.
function refreshInventory(original, security, verification, now = new Date().toISOString()) {
  assert.equal(verification.projectId, 'hiker-circle');
  assert.equal(verification.after.obsoleteFieldOccurrences, 0);
  assert.equal(verification.retainedFieldsVerified, verification.before.documents);
  assert.deepEqual([...verification.removedFields].sort(), [...OBSOLETE_CAPTURE_FIELDS].sort());
  assert.equal(security.sourceStatus, 'SOURCE-DEFINED NOT DEPLOYED');
  const next = structuredClone(original);
  const capture = next.schemas[CAPTURE]; assert.ok(capture);
  for (const field of OBSOLETE_CAPTURE_FIELDS) delete capture.fields[field];
  capture.documentsObserved = verification.after.documents;
  capture.description = 'Private full route capture. Eight unread derived fields were removed with a guarded backup; routePoints, manualPins, summaryReport, counters, owners, IDs and dates were preserved.';
  capture.evidence = [...new Set([...(capture.evidence || []), 'scripts/reduce_database_redundancy.cjs',
    'output/database-review/capture-reduction-verification.json'])];
  for (const [schemaPath, schema] of Object.entries(security.schemas)) next.schemas[schemaPath] = structuredClone(schema);
  for (const [schemaPath, additions] of Object.entries(security.existingFieldAdditions)) {
    assert.ok(next.schemas[schemaPath], 'An existing security schema is missing.');
    for (const [field, definition] of Object.entries(additions))
      next.schemas[schemaPath].fields[field] = {...structuredClone(definition),
        note: [definition.note, 'SOURCE-DEFINED NOT DEPLOYED: current security source; no live presence is claimed.'].filter(Boolean).join(' ')};
  }
  for (const change of security.existingFieldMeaningChanges) {
    const definition = next.schemas[change.path]?.fields[change.field];
    if (definition && !definition.note?.includes(change.change))
      definition.note = [definition.note, change.change + ' SOURCE-DEFINED NOT DEPLOYED.'].filter(Boolean).join(' ');
  }
  const ids = new Set(next.relationships.map(relationshipId));
  for (const edge of security.relationships) {
    if (!ids.has(relationshipId(edge))) {next.relationships.push(structuredClone(edge)); ids.add(relationshipId(edge));}
  }
  for (const edge of next.relationships) {
    assert.ok(endpointExists(next.schemas, edge.parent, edge.parentField), 'Missing relationship parent.');
    assert.ok(endpointExists(next.schemas, edge.child, edge.childField), 'Missing relationship child.');
  }
  next.title = 'HikerCircle | Firebase Cloud Firestore | Main layer';
  next.generatedAt = now;
  next.databaseReductionVerifiedAt = verification.verifiedAt;
  next.securitySourceDefinitions = {status: security.sourceStatus, generatedAt: security.generatedAt,
    paths: Object.keys(security.schemas), note: 'These definitions describe current source. Deployment/configuration from the separate security task remains pending.'};
  next.firestoreIndexConfiguration = read('firestore.indexes.json');
  next.sources = [...new Set([...next.sources, '18 October 2026 behavior-preserving database audit',
    'Undeployed security source definitions (explicitly labeled)', 'output/database-review/capture-reduction-verification.json'])];
  return next;
}

function main() {
  const next = refreshInventory(read('output/firestore/hikercircle-firestore-schema.json'),
    read('output/firestore/security-source-schema.json'), read('output/database-review/capture-reduction-verification.json'));
  const index = relationIndex(read('output/firestore/relationship-index.json'),
    read('output/dbdiagram/firestore/relationship-catalogue.json'), next.relationships);
  if (process.argv.includes('--apply')) {
    fs.writeFileSync(path.join(ROOT, 'output/firestore/hikercircle-firestore-schema.json'), JSON.stringify(next, null, 2));
    fs.writeFileSync(path.join(ROOT, 'output/firestore/relationship-index.json'), JSON.stringify(index, null, 2));
  }
  console.log(JSON.stringify({metadataApplied: process.argv.includes('--apply'), firebaseWrites: 0,
    documentShapes: Object.keys(next.schemas).length, storedTopLevelFields: Object.values(next.schemas)
      .reduce((sum, schema) => sum + Object.keys(schema.fields).length, 0),
    relationships: next.relationships.length, sourceOnlySecurityShapes: next.securitySourceDefinitions.paths.length,
    schemaSha256: createHash('sha256').update(JSON.stringify(next)).digest('hex')}, null, 2));
}
if (require.main === module) main();
module.exports = {CAPTURE, endpointExists, refreshInventory};

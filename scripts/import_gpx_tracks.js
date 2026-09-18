/* eslint-disable no-console */
'use strict';
// Convert GPX tracks to native route coordinates using the existing schema.
// Usage: node scripts/import_gpx_tracks.js manifest.json [--apply]
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { isDeepStrictEqual } = require('util');
function decodeField(v) {
  if (v.mapValue) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k,x]) => [k,decodeField(x)]));
  if (v.arrayValue) return (v.arrayValue.values || []).map(decodeField);
  if (v.integerValue !== undefined) return Number(v.integerValue);
  if (v.doubleValue !== undefined) return Number(v.doubleValue);
  if (v.booleanValue !== undefined) return v.booleanValue;
  if (v.nullValue !== undefined) return null;
  return v.stringValue;
}
const { prepareTrack, sha256, checkpointsHash } = require('./lib/imported_route_geometry');
const { existingTrails, firebaseAccessToken, firestoreFields, firestoreRequest,
  projectId, fromFirestoreValue } = require('./seed_malaysia_trails');

async function main() {
  const manifestPath = process.argv[2];
  if (!manifestPath || manifestPath.startsWith('--')) throw new Error('Provide a JSON import manifest.');
  const entries = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  if (!Array.isArray(entries) || !entries.length) throw new Error('Manifest must contain imports.');
  const token = await firebaseAccessToken();
  const documents = await existingTrails(token);
  const plans = [];
  const seen = new Set();
  for (const entry of entries) {
    if (seen.has(entry.trailId)) throw new Error('Duplicate target trail.');
    seen.add(entry.trailId);
    if (!Number.isInteger(entry.durationMinutes) || entry.durationMinutes <= 0 ||
        !['out-and-back', 'loop', 'point-to-point'].includes(entry.routeShape) ||
        typeof entry.trackName !== 'string') {
      throw new Error('Each import needs durationMinutes, routeShape, and trackName.');
    }
    const document = documents.find(d => d.name.split('/').pop() === entry.trailId);
    if (!document) throw new Error(`Trail not found: ${entry.trailId}`);
    const sourcePath = path.resolve(path.dirname(manifestPath), entry.sourceFile);
    const track = JSON.parse(execFileSync('python3',
      [path.join(__dirname, 'lib/read_gpx_track.py'), sourcePath], {maxBuffer: 32 * 1024 * 1024}));
    if (track.name !== entry.trackName) throw new Error(`Track title mismatch: ${track.name}`);
    const prepared = prepareTrack(track);
    if ((entry.routeShape !== 'point-to-point') !== prepared.closed) throw new Error('Track shape mismatch.');
    const f = document.fields;
    const origin = {lat: fromFirestoreValue(f.latitude), lon: fromFirestoreValue(f.longitude)};
    const { haversine } = require('./lib/trail_route_geometry');
    if (Math.min(...prepared.points.map(p => haversine(p, origin))) > 3000) {
      throw new Error('Export does not pass near the existing trail. Check the route match.');
    }
    const now = new Date().toISOString();
    const revisionId = `${sha256(prepared.polyline).slice(0, 24)}-${Date.now()}`;
    const revisionName = `${document.name}/routeGeometry/${revisionId}`;
    const metadata = {
      schemaVersion: 1, geometrySha256: sha256(prepared.polyline),
      geometryDocument: revisionName, pointCount: prepared.points.length,
      polylinePrecision: 5, updatedAt: now,
    };
    const updates = {
      routeEncodedPolyline: prepared.polyline,
      checkpoints: prepared.checkpoints,
      routeCheckpointsHash: checkpointsHash(prepared.checkpoints),
      latitude: prepared.points[0].lat, longitude: prepared.points[0].lon,
      distanceKm: prepared.distanceMeters / 1000,
      estimatedDurationMinutes: entry.durationMinutes,
      ...(prepared.elevationGainMeters !== undefined ? {
        elevationGainMeters: prepared.elevationGainMeters,
        minElevationMeters: prepared.minElevationMeters,
        maxElevationMeters: prepared.maxElevationMeters,
      } : {}),
      dataSource: 'Stored route coordinates', routeProvider: 'stored-polyline',
      routeActivity: 'hiking', routeShape: entry.routeShape,
      updatedAtLocal: now, routeGeometryMetadata: metadata,
    };
    const archive = {coordinateSystem: 'WGS84', points: prepared.points,
      pointCount: prepared.points.length, updatedAt: now};
    const removedFields = ['dataSourceUrl', 'routeReferenceName', 'routeReferenceUrl',
      'routeReferenceNote', 'routeVerifiedAtLocal', 'osmRelationId'];
    if (Buffer.byteLength(JSON.stringify(firestoreFields(archive))) > 950000 ||
        Buffer.byteLength(JSON.stringify({...document, fields: {...f, ...firestoreFields(updates)}})) > 950000) {
      throw new Error('Import would exceed the Firestore document size budget.');
    }
    plans.push({document, revisionName, archive, updates, removedFields});
    console.log(JSON.stringify({trailId: entry.trailId, name: track.name,
      points: prepared.points.length, checkpoints: prepared.checkpoints.length,
      distanceKm: updates.distanceKm, elevationGainMeters: prepared.elevationGainMeters,
      maxVertexErrorMeters: prepared.maxErrorMeters, maxGapMeters: prepared.maxGapMeters,
      durationMinutes: entry.durationMinutes}));
  }
  if (!process.argv.includes('--apply')) { console.log('Validated; no Firebase writes.'); return; }
  for (const plan of plans) {
    const {document, revisionName, archive, updates, removedFields} = plan;
    await firestoreRequest(token,
      `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`, {
        method: 'POST', body: JSON.stringify({writes: [
          {update: {name: revisionName, fields: firestoreFields(archive)}, currentDocument: {exists: false}},
          {update: {name: document.name, fields: firestoreFields(updates)},
            updateMask: {fieldPaths: [...Object.keys(updates), ...removedFields]},
            currentDocument: {updateTime: document.updateTime}},
        ]}),
      });
    const live = await firestoreRequest(token, `https://firestore.googleapis.com/v1/${document.name}`);
    for (const [key, value] of Object.entries(updates)) {
      if (!live.fields[key] || !isDeepStrictEqual(decodeField(live.fields[key]), value)) {
        throw new Error(`Verification failed: ${key}`);
      }
    }
    const liveSource = await firestoreRequest(token, `https://firestore.googleapis.com/v1/${revisionName}`);
    if (!isDeepStrictEqual(decodeField(liveSource.fields.points), archive.points)) {
      throw new Error('Native coordinate verification failed.');
    }
    if (removedFields.some(key => live.fields[key] !== undefined)) {
      throw new Error('Obsolete reference fields were not removed.');
    }
    if (live.fields.routeEncodedPolyline.stringValue !== updates.routeEncodedPolyline ||
        live.fields.checkpoints.arrayValue.values.length !== updates.checkpoints.length) {
      throw new Error('Live geometry verification failed.');
    }
    console.log(`Imported and verified ${document.name.split('/').pop()}; native route coordinates stored in Firebase.`);
  }
}
if (require.main === module) main().catch(e => {console.error(e.message); process.exitCode = 1;});

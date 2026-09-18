/* eslint-disable no-console */
'use strict';

// Refresh the existing one-way Heritage Trail ascent, preserving user records.
// AllTrails is the route reference; geometry is fetched from Geoapify/OSM.
// Run without --apply to inspect the validated repair before writing.
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  buildTrail, existingTrails, firebaseAccessToken, firestoreFields,
  firestoreRequest, projectId, fromFirestoreValue,
} = require('./seed_malaysia_trails');

async function main() {
  const token = await firebaseAccessToken();
  const documents = await existingTrails(token);
  const matches = documents.filter((d) =>
    fromFirestoreValue(d.fields.name) === 'Bukit Bendera');
  if (matches.length !== 1) throw new Error('Expected exactly one Bukit Bendera trail.');
  const document = matches[0];
  const fields = document.fields;
  const waypoints = fields.checkpoints.arrayValue.values.map((value) => ({
    lat: fromFirestoreValue(value.mapValue.fields.latitude),
    lon: fromFirestoreValue(value.mapValue.fields.longitude),
  }));
  const trail = await buildTrail({
    name: 'Bukit Bendera', area: 'Air Itam', state: 'Penang',
    routeMode: 'geoapify-hike', routeShape: 'point-to-point',
    routeWaypoints: waypoints,
    // Allow for the steep staircase ascent and short breaks, not flat walking.
    duration: 150,
    // Conservative ascent estimate from the saved 79–740 m elevation range.
    elevation: 661,
    referenceDistanceKm: 2.7, maxDistanceDeltaRatio: 0.3,
    allTrailsName: 'Penang Hill Heritage Trail',
    allTrailsUrl: 'https://www.alltrails.com/trail/malaysia/penang/penang-hill-heritage-trail',
    referenceNote: 'One-way uphill leg of the Heritage Trail. AllTrails describes a 5.5 km out-and-back with approximately 691 m ascent. Geometry refreshed from Geoapify/OSM through the existing waypoints; not an AllTrails GPX import. Typical time is a 150-minute uphill planning estimate including short breaks. Elevation gain is a conservative 661 m estimate from the recorded 79–740 m range.',
  });
  const updates = Object.fromEntries([
    'distanceKm', 'estimatedDurationMinutes', 'elevationGainMeters',
    'routeEncodedPolyline', 'dataSource', 'dataSourceUrl', 'routeProvider',
    'routeActivity', 'routeShape', 'routeReferenceName', 'routeReferenceUrl',
    'routeReferenceNote', 'routeVerifiedAtLocal', 'updatedAtLocal',
  ].map((key) => [key, trail[key]]));
  console.log(JSON.stringify({
    before: { minutes: fromFirestoreValue(fields.estimatedDurationMinutes),
      distanceKm: fromFirestoreValue(fields.distanceKm),
      elevationGainMeters: fromFirestoreValue(fields.elevationGainMeters) },
    after: { minutes: trail.estimatedDurationMinutes, distanceKm: trail.distanceKm,
      elevationGainMeters: trail.elevationGainMeters, audit: trail.routeAudit },
  }, null, 2));
  if (!process.argv.includes('--apply')) return;
  const backup = path.join(os.tmpdir(), `bukit-bendera-backup-${Date.now()}.json`);
  fs.writeFileSync(backup, JSON.stringify(document), { mode: 0o600 });
  await firestoreRequest(token,
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`, {
      method: 'POST', body: JSON.stringify({ writes: [{
        update: { name: document.name, fields: firestoreFields(updates) },
        updateMask: { fieldPaths: Object.keys(updates) },
        currentDocument: { updateTime: document.updateTime },
      }] }),
    });
  const verified = await firestoreRequest(token,
    `https://firestore.googleapis.com/v1/${document.name}`);
  for (const [key, value] of Object.entries(updates)) {
    if (fromFirestoreValue(verified.fields[key]) !== value) {
      throw new Error(`Verification failed: ${key}`);
    }
  }
  console.log(`Updated and verified Bukit Bendera. Backup: ${backup}`);
}

if (require.main === module) main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});

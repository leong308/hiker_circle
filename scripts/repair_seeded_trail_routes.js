/* eslint-disable no-console */
'use strict';

// Rebuilds only the route and reference fields for the Malaysian seeded trails.
// Existing cover images, ratings, hazards, and user-facing records are preserved.
// Run without --apply for a read-only validation report.

const { trails } = require('./malaysia_trail_manifest');
const {
  buildTrail,
  existingTrails,
  firebaseAccessToken,
  firestoreDocumentRoot,
  firestoreFields,
  firestoreRequest,
  fromFirestoreValue,
  normalizedName,
  projectId,
  slug,
} = require('./seed_malaysia_trails');

const applyChanges = process.argv.includes('--apply');
const trailArgument = process.argv.find((argument) => argument.startsWith('--trail='));
const trailFilter = trailArgument ? trailArgument.slice('--trail='.length) : '';

const repairFieldNames = [
  'name',
  'area',
  'state',
  'country',
  'latitude',
  'longitude',
  'distanceKm',
  'difficulty',
  'estimatedDurationMinutes',
  'elevationGainMeters',
  'isVerifiedTrail',
  'checkpoints',
  'routeEncodedPolyline',
  'dataSource',
  'dataSourceUrl',
  'osmRelationId',
  'routeProvider',
  'routeActivity',
  'routeShape',
  'routeReferenceName',
  'routeReferenceUrl',
  'routeReferenceNote',
  'routeVerifiedAtLocal',
  'updatedAtLocal',
];

function selectedDefinitions() {
  if (!trailFilter) return trails;
  const normalizedFilter = normalizedName(trailFilter);
  const result = trails.filter((definition) => {
    const trailId = `malaysia-${slug(definition.name)}`;
    return normalizedName(definition.name) === normalizedFilter ||
      normalizedName(trailId) === normalizedFilter;
  });
  if (result.length === 0) throw new Error(`No seeded trail matches --trail=${trailFilter}`);
  return result;
}

function documentIdentity(document) {
  return document.name.slice(document.name.lastIndexOf('/') + 1);
}

function findExistingDocument(documents, builtTrail) {
  const exactId = documents.find((document) => documentIdentity(document) === builtTrail.trailId);
  if (exactId) return exactId;
  const matchingNames = documents.filter((document) => normalizedName(
    fromFirestoreValue(document.fields && document.fields.name) || '',
  ) === normalizedName(builtTrail.name));
  if (matchingNames.length !== 1) {
    throw new Error(
      `Expected one live Firestore document for ${builtTrail.name}; found ${matchingNames.length}.`,
    );
  }
  return matchingNames[0];
}

function repairFields(trail) {
  return {
    name: trail.name,
    area: trail.area,
    state: trail.state,
    country: trail.country,
    latitude: trail.latitude,
    longitude: trail.longitude,
    distanceKm: trail.distanceKm,
    difficulty: trail.difficulty,
    estimatedDurationMinutes: trail.estimatedDurationMinutes,
    elevationGainMeters: trail.elevationGainMeters,
    isVerifiedTrail: trail.isVerifiedTrail,
    checkpoints: trail.checkpoints,
    routeEncodedPolyline: trail.routeEncodedPolyline,
    dataSource: trail.dataSource,
    dataSourceUrl: trail.dataSourceUrl,
    osmRelationId: trail.osmRelationId || '',
    routeProvider: trail.routeProvider,
    routeActivity: trail.routeActivity,
    routeShape: trail.routeShape,
    routeReferenceName: trail.routeReferenceName,
    routeReferenceUrl: trail.routeReferenceUrl,
    routeReferenceNote: trail.routeReferenceNote || '',
    routeVerifiedAtLocal: trail.routeVerifiedAtLocal,
    updatedAtLocal: trail.updatedAtLocal,
  };
}

function auditLine(trail) {
  const audit = trail.routeAudit;
  const excluded = audit.excludedRoles.length === 0
    ? 'none'
    : [...new Set(audit.excludedRoles)].join(', ');
  return `${trail.name}: ${trail.distanceKm.toFixed(1)} km, ` +
    `${audit.maxSegmentMeters.toFixed(0)}m max segment, ` +
    `${audit.endpointGapMeters.toFixed(0)}m endpoint gap, excluded roles: ${excluded}`;
}

async function main() {
  const definitions = selectedDefinitions();
  const token = await firebaseAccessToken();
  const documents = await existingTrails(token);
  const repairs = [];

  // Every selected route is built and validated before any write is attempted.
  for (const [index, definition] of definitions.entries()) {
    console.log(`[${index + 1}/${definitions.length}] Validate ${definition.name}`);
    const trail = await buildTrail(definition);
    const document = findExistingDocument(documents, trail);
    console.log(`  ${auditLine(trail)}`);
    console.log(`  AllTrails reference: ${trail.routeReferenceUrl}`);
    repairs.push({ trail, document });
  }

  console.log(`Validated ${repairs.length} connected hiking route repair(s).`);
  if (!applyChanges) {
    console.log('Dry run complete. Re-run with --apply to update only route/reference fields.');
    return;
  }

  const writes = repairs.map(({ trail, document }) => ({
    update: {
      name: `${firestoreDocumentRoot}/trails/${documentIdentity(document)}`,
      fields: firestoreFields(repairFields(trail)),
    },
    updateMask: { fieldPaths: repairFieldNames },
    currentDocument: { exists: true },
  }));
  await firestoreRequest(
    token,
    `https://firestore.googleapis.com/v1/projects/${projectId}` +
      '/databases/(default)/documents:commit',
    { method: 'POST', body: JSON.stringify({ writes }) },
  );

  const verifiedDocuments = await existingTrails(token);
  for (const { trail, document } of repairs) {
    const verified = verifiedDocuments.find(
      (candidate) => documentIdentity(candidate) === documentIdentity(document),
    );
    if (!verified) throw new Error(`Live verification could not find ${trail.name}.`);
    const fields = verified.fields || {};
    const liveReference = fromFirestoreValue(fields.routeReferenceUrl) || '';
    const liveActivity = fromFirestoreValue(fields.routeActivity) || '';
    const livePolyline = fromFirestoreValue(fields.routeEncodedPolyline) || '';
    if (liveReference !== trail.routeReferenceUrl || liveActivity !== 'hiking' ||
        livePolyline !== trail.routeEncodedPolyline) {
      throw new Error(`Live route verification failed for ${trail.name}.`);
    }
  }
  console.log(`Updated and re-verified ${repairs.length} live Firestore hiking routes.`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error && error.stack || error);
    process.exitCode = 1;
  });
}

module.exports = { auditLine, findExistingDocument, repairFields, selectedDefinitions };

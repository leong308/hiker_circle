/* eslint-disable no-console */
'use strict';

// Seeds verified, route-backed Malaysian trails without overwriting a trail
// that already has the same name. Run without --apply for a read-only preview.

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const { trails } = require('./malaysia_trail_manifest');
const {
  assemblePrimaryRelation,
  haversine,
  mirrorOutAndBack,
  pointsFromGeoJsonGeometry,
  shortestPathInRelation,
  validateGeometry,
} = require('./lib/trail_route_geometry');

const projectId = 'hiker-circle';
const applyChanges = process.argv.includes('--apply');
const firestoreRoot =
  `https://firestore.googleapis.com/v1/projects/${projectId}` +
  '/databases/(default)/documents';
const firestoreDocumentRoot =
  `projects/${projectId}/databases/(default)/documents`;

const validStates = new Set([
  'Johor', 'Kedah', 'Kelantan', 'Malacca', 'Negeri Sembilan', 'Pahang',
  'Penang', 'Perak', 'Perlis', 'Sabah', 'Sarawak', 'Selangor',
  'Terengganu', 'Kuala Lumpur', 'Labuan', 'Putrajaya',
]);
const malaysiaStateAliases = new Map([
  ['johor', 'Johor'], ['kedah', 'Kedah'], ['kelantan', 'Kelantan'],
  ['malacca', 'Malacca'], ['melaka', 'Malacca'],
  ['negerisembilan', 'Negeri Sembilan'], ['pahang', 'Pahang'],
  ['penang', 'Penang'], ['pulaupinang', 'Penang'], ['perak', 'Perak'],
  ['perlis', 'Perlis'], ['sabah', 'Sabah'], ['sarawak', 'Sarawak'],
  ['selangor', 'Selangor'], ['terengganu', 'Terengganu'],
  ['kualalumpur', 'Kuala Lumpur'], ['labuan', 'Labuan'],
  ['putrajaya', 'Putrajaya'],
]);

function normalizedName(value) {
  return value.toLowerCase().replace(/[^a-z0-9]/g, '');
}

function slug(value) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

function sampleRoute(points, count) {
  if (points.length <= count) return points;
  const cumulative = [0];
  for (let index = 1; index < points.length; index += 1) {
    cumulative.push(cumulative[index - 1] + haversine(points[index - 1], points[index]));
  }
  const total = cumulative[cumulative.length - 1];
  const sampled = [];
  for (let sample = 0; sample < count; sample += 1) {
    const target = total * sample / (count - 1);
    let index = cumulative.findIndex((distance) => distance >= target);
    if (index < 0) index = points.length - 1;
    sampled.push(points[index]);
  }
  return sampled;
}

function encodePolyline(points) {
  let previousLat = 0;
  let previousLon = 0;
  let encoded = '';
  const encodeValue = (value) => {
    let current = value < 0 ? ~(value << 1) : value << 1;
    let output = '';
    while (current >= 0x20) {
      output += String.fromCharCode((0x20 | (current & 0x1f)) + 63);
      current >>= 5;
    }
    return output + String.fromCharCode(current + 63);
  };
  for (const point of points) {
    const lat = Math.round(point.lat * 100000);
    const lon = Math.round(point.lon * 100000);
    encoded += encodeValue(lat - previousLat) + encodeValue(lon - previousLon);
    previousLat = lat;
    previousLon = lon;
  }
  return encoded;
}

function validateTrail(trail) {
  if (!trail.name || !trail.area || !validStates.has(trail.state)) {
    throw new Error(`Invalid identity or state for ${trail.name}`);
  }
  if (!(trail.distanceKm > 0) || !(trail.estimatedDurationMinutes > 0)) {
    throw new Error(`Invalid distance or duration for ${trail.name}`);
  }
  if (!['easy', 'moderate', 'hard'].includes(trail.difficulty)) {
    throw new Error(`Invalid difficulty for ${trail.name}`);
  }
  if (trail.checkpoints.length < 3 || trail.checkpoints.length > 12) {
    throw new Error(`Invalid checkpoint count for ${trail.name}`);
  }
  for (const checkpoint of trail.checkpoints) {
    if (!Number.isFinite(checkpoint.latitude) || !Number.isFinite(checkpoint.longitude) ||
        checkpoint.latitude < 0.8 || checkpoint.latitude > 7.6 ||
        checkpoint.longitude < 99.5 || checkpoint.longitude > 119.5) {
      throw new Error(`Checkpoint outside Malaysia for ${trail.name}`);
    }
  }
  if (!trail.routeEncodedPolyline || trail.routeEncodedPolyline.length < 10) {
    throw new Error(`Missing route geometry for ${trail.name}`);
  }
}

function firestoreValue(value) {
  if (value === null) return { nullValue: null };
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(firestoreValue) } };
  }
  switch (typeof value) {
    case 'boolean': return { booleanValue: value };
    case 'number':
      return Number.isInteger(value)
        ? { integerValue: String(value) }
        : { doubleValue: value };
    case 'string': return { stringValue: value };
    case 'object': {
      const fields = {};
      for (const [key, item] of Object.entries(value)) fields[key] = firestoreValue(item);
      return { mapValue: { fields } };
    }
    default: throw new Error(`Unsupported Firestore value: ${typeof value}`);
  }
}

function firestoreFields(data) {
  const fields = {};
  for (const [key, value] of Object.entries(data)) fields[key] = firestoreValue(value);
  return fields;
}

function fromFirestoreValue(value) {
  if (!value) return null;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  return null;
}

async function firebaseAccessToken() {
  const npmExecutable = process.platform === 'win32' ? 'npm.cmd' : 'npm';
  const globalNodeModules = execFileSync(npmExecutable, ['root', '-g'], {
    encoding: 'utf8',
  }).trim();
  const firebaseToolsRoot = path.join(globalNodeModules, 'firebase-tools', 'lib');
  const auth = require(path.join(firebaseToolsRoot, 'auth.js'));
  const scopes = require(path.join(firebaseToolsRoot, 'scopes.js'));
  const account = auth.getGlobalDefaultAccount();
  if (!account) throw new Error('Firebase CLI is not signed in.');
  if (account.tokens.access_token && Date.now() < account.tokens.expires_at - 30000) {
    return account.tokens.access_token;
  }
  const refreshed = await auth.getAccessToken(account.tokens.refresh_token, [
    scopes.CLOUD_PLATFORM,
    scopes.FIREBASE_PLATFORM,
  ]);
  return refreshed.access_token;
}

async function firestoreRequest(token, url, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });
  if (!response.ok) {
    throw new Error(`Firestore ${response.status}: ${await response.text()}`);
  }
  return response.status === 204 ? {} : response.json();
}

async function existingTrails(token) {
  const documents = [];
  let pageToken = '';
  do {
    const url = new URL(`${firestoreRoot}/trails`);
    url.searchParams.set('pageSize', '300');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const data = await firestoreRequest(token, url);
    documents.push(...(data.documents || []));
    pageToken = data.nextPageToken || '';
  } while (pageToken);
  return documents;
}

async function fetchRelation(relationId) {
  const url = `https://api.openstreetmap.org/api/0.6/relation/${relationId}/full.json`;
  let lastError;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      const response = await fetch(url, {
        headers: { 'User-Agent': 'HikerCircleTrailSeeder/2.0' },
        signal: AbortSignal.timeout(60000),
      });
      if (!response.ok) throw new Error(`OpenStreetMap ${response.status}`);
      return await response.json();
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 1000 * (attempt + 1)));
  }
  throw lastError;
}

function dotenvValue(key) {
  if (process.env[key] && process.env[key].trim()) return process.env[key].trim();
  const dotenvPath = path.join(__dirname, '..', '.env');
  if (!fs.existsSync(dotenvPath)) return '';
  const prefix = `${key}=`;
  const line = fs.readFileSync(dotenvPath, 'utf8').split(/\r?\n/)
    .find((candidate) => candidate.startsWith(prefix));
  if (!line) return '';
  return line.slice(prefix.length).trim().replace(/^(['"])(.*)\1$/, '$2');
}

async function fetchGeoapifyHike(definition) {
  const apiKey = dotenvValue('GEOAPIFY_API_KEY');
  if (!apiKey) {
    throw new Error('GEOAPIFY_API_KEY is required for the Bukit Besar hiking repair.');
  }
  const url = new URL('https://api.geoapify.com/v1/routing');
  url.searchParams.set(
    'waypoints',
    definition.routeWaypoints.map((point) => `${point.lat},${point.lon}`).join('|'),
  );
  url.searchParams.set('mode', 'hike');
  url.searchParams.set('format', 'geojson');
  url.searchParams.set('details', 'elevation');
  url.searchParams.set('apiKey', apiKey);
  const response = await fetch(url, {
    headers: { 'User-Agent': 'HikerCircleTrailSeeder/2.0' },
    signal: AbortSignal.timeout(60000),
  });
  if (!response.ok) {
    throw new Error(`Geoapify hiking route ${response.status}: ${await response.text()}`);
  }
  const data = await response.json();
  const feature = data.features && data.features[0];
  if (!feature) throw new Error('Geoapify returned no hiking route for Bukit Besar.');
  return {
    points: pointsFromGeoJsonGeometry(feature.geometry),
    providerDistanceMeters: feature.properties && feature.properties.distance,
  };
}

async function buildRouteGeometry(definition) {
  if (definition.routeMode === 'geoapify-hike') {
    const result = await fetchGeoapifyHike(definition);
    return {
      ...result,
      dataSource: 'Geoapify hike routing over OpenStreetMap, verified against AllTrails',
      dataSourceUrl:
        'https://www.openstreetmap.org/?mlat=5.3070715&mlon=103.1349390#map=16/5.3070715/103.1349390',
      routeProvider: 'geoapify-hike',
      excludedRoles: [],
    };
  }

  const data = await fetchRelation(definition.relationId);
  const result = definition.routeMode === 'osm-shortest-path'
    ? shortestPathInRelation(
      data,
      definition.relationId,
      definition.routeStart,
      definition.routeEnd,
      { maxSnapMeters: 350 },
    )
    : assemblePrimaryRelation(data, definition.relationId, {
      startHint: definition.routeStart,
    });
  const points = definition.routeShape === 'out-and-back'
    ? mirrorOutAndBack(result.points)
    : result.points;
  return {
    ...result,
    points,
    dataSource: 'OpenStreetMap hiking relation, verified against AllTrails',
    dataSourceUrl: `https://www.openstreetmap.org/relation/${definition.relationId}`,
    routeProvider: definition.routeMode || 'osm-hiking-relation',
  };
}

async function buildTrail(definition) {
  const route = await buildRouteGeometry(definition);
  const points = route.points;
  const audit = validateGeometry(points, definition.routeShape);
  const checkpointPoints = sampleRoute(points, 7);
  const now = new Date().toISOString();
  const checkpoints = checkpointPoints.map((point, index) => ({
    name: index === 0
      ? 'Trailhead'
      : index === checkpointPoints.length - 1
        ? definition.routeShape === 'point-to-point'
          ? 'End point'
          : 'Return to trailhead'
        : `Waypoint ${index}`,
    latitude: point.lat,
    longitude: point.lon,
    order: index + 1,
  }));
  const trailId = `malaysia-${slug(definition.name)}`;
  const trail = {
    trailId,
    name: definition.name,
    area: definition.area,
    state: definition.state,
    country: 'Malaysia',
    latitude: checkpoints[0].latitude,
    longitude: checkpoints[0].longitude,
    distanceKm: Math.round(audit.distanceMeters / 100) / 10,
    difficulty: definition.difficulty,
    estimatedDurationMinutes: definition.duration,
    elevationGainMeters: definition.elevation,
    ratingAverage: 0,
    ratingCount: 0,
    ratingSum: 0,
    offlineMapAvailable: false,
    offlineMapDownloaded: false,
    isVerifiedTrail: true,
    routeFilePath: 'offline/maps/admin_added_trail.mbtiles',
    coverColorValue: 4281645139,
    coverImageUrl: [],
    checkpoints,
    weather: {
      summary: 'Weather unavailable',
      temperatureRange: 'Not provided',
      rainProbability: 0,
      cachedAtLocal: now,
    },
    hazards: [],
    routeEncodedPolyline: encodePolyline(points),
    dataSource: route.dataSource,
    dataSourceUrl: route.dataSourceUrl,
    ...(definition.relationId ? { osmRelationId: String(definition.relationId) } : {}),
    routeProvider: route.routeProvider,
    routeActivity: 'hiking',
    routeShape: definition.routeShape,
    routeReferenceName: definition.allTrailsName,
    routeReferenceUrl: definition.allTrailsUrl,
    ...(definition.referenceNote ? { routeReferenceNote: definition.referenceNote } : {}),
    routeVerifiedAtLocal: now,
    seededAtLocal: now,
    createdAtLocal: now,
    updatedAtLocal: now,
  };
  validateTrail(trail);
  Object.defineProperty(trail, 'routeAudit', {
    enumerable: false,
    value: {
      ...audit,
      excludedRoles: route.excludedRoles || [],
    },
  });
  return trail;
}

async function main() {
  const token = await firebaseAccessToken();
  const existing = await existingTrails(token);
  const names = new Set(existing.map((document) =>
    normalizedName(fromFirestoreValue(document.fields && document.fields.name) || ''),
  ));
  const now = new Date().toISOString();
  const regionWrites = existing.flatMap((document) => {
    const state = fromFirestoreValue(document.fields && document.fields.state) || '';
    const country = fromFirestoreValue(document.fields && document.fields.country) || '';
    const canonicalState = malaysiaStateAliases.get(normalizedName(state));
    if (!canonicalState || (country === 'Malaysia' && state === canonicalState)) return [];
    return [{
      update: {
        name: document.name,
        fields: firestoreFields({
          country: 'Malaysia',
          state: canonicalState,
          updatedAtLocal: now,
        }),
      },
      updateMask: { fieldPaths: ['country', 'state', 'updatedAtLocal'] },
      currentDocument: { exists: true },
    }];
  });

  const built = [];
  for (const [index, definition] of trails.entries()) {
    if (names.has(normalizedName(definition.name))) {
      console.log(`[${index + 1}/${trails.length}] Skip existing: ${definition.name}`);
      continue;
    }
    console.log(`[${index + 1}/${trails.length}] Fetch route: ${definition.name}`);
    const trail = await buildTrail(definition);
    const audit = trail.routeAudit;
    console.log(
      `  ${trail.distanceKm.toFixed(1)} km, ${audit.maxSegmentMeters.toFixed(0)}m max gap, ` +
      `${audit.endpointGapMeters.toFixed(0)}m endpoint gap, ` +
      `${audit.excludedRoles.length} non-primary member(s) excluded`,
    );
    built.push(trail);
  }

  console.log(
    `Validated ${built.length} new trails and ${regionWrites.length} region repairs; ` +
    `${existing.length} already exist.`,
  );
  if (!applyChanges || (built.length === 0 && regionWrites.length === 0)) {
    console.log(
      applyChanges ? 'Nothing to add or repair.' : 'Dry run complete. Re-run with --apply to write.',
    );
    return;
  }

  const writes = [...regionWrites, ...built.map((trail) => ({
    update: {
      name: `${firestoreDocumentRoot}/trails/${trail.trailId}`,
      fields: firestoreFields(trail),
    },
    currentDocument: { exists: false },
  }))];
  await firestoreRequest(
    token,
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`,
    { method: 'POST', body: JSON.stringify({ writes }) },
  );
  console.log(
    `Added ${built.length} validated Malaysian trails and repaired ` +
    `${regionWrites.length} existing regions in Firestore.`,
  );
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error && error.stack || error);
    process.exitCode = 1;
  });
}

module.exports = {
  buildTrail,
  existingTrails,
  firebaseAccessToken,
  firestoreDocumentRoot,
  firestoreFields,
  firestoreRequest,
  firestoreRoot,
  fromFirestoreValue,
  normalizedName,
  projectId,
  slug,
};

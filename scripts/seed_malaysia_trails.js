/* eslint-disable no-console */
'use strict';

// Seeds verified, route-backed Malaysian trails without overwriting a trail
// that already has the same name. Run without --apply for a read-only preview.

const path = require('path');

const projectId = 'hiker-circle';
const applyChanges = process.argv.includes('--apply');
const firestoreRoot =
  `https://firestore.googleapis.com/v1/projects/${projectId}` +
  '/databases/(default)/documents';
const firestoreDocumentRoot =
  `projects/${projectId}/databases/(default)/documents`;

const trails = [
  { relationId: 3112158, name: 'Mount Kinabalu Summit Trail', area: 'Kundasang', state: 'Sabah', distanceKm: 8.5, duration: 720, elevation: 2300, difficulty: 'hard' },
  { relationId: 17919247, name: 'Gunung Tahan Trans Trail', area: 'Taman Negara', state: 'Pahang', distanceKm: 56.5, duration: 3000, elevation: 2400, difficulty: 'hard' },
  { relationId: 19008365, name: 'Gunung Irau Mossy Forest Trail', area: 'Brinchang', state: 'Pahang', distanceKm: 5.6, duration: 240, elevation: 420, difficulty: 'hard' },
  { relationId: 17921986, name: 'Chemerong-Berembun-Lansir Trail', area: 'Hutan Lipur Chemerong', state: 'Terengganu', distanceKm: 15, duration: 720, elevation: 1200, difficulty: 'hard' },
  { relationId: 18027800, name: 'Gunung Baling Trail', area: 'Baling', state: 'Kedah', distanceKm: 4, duration: 240, elevation: 480, difficulty: 'hard' },
  { relationId: 11758413, name: 'Gunung Jasar Cameron Valley Trail', area: 'Tanah Rata', state: 'Pahang', distanceKm: 5, duration: 210, elevation: 470, difficulty: 'moderate' },
  { relationId: 11758337, name: 'Gunung Berembun via Trail 6', area: 'Tanah Rata', state: 'Pahang', distanceKm: 5.8, duration: 240, elevation: 520, difficulty: 'moderate' },
  { relationId: 19353291, name: 'Bukit Kiara Main Loop', area: 'Taman Tun Dr Ismail', state: 'Kuala Lumpur', distanceKm: 4, duration: 90, elevation: 180, difficulty: 'moderate' },
  { relationId: 19523909, name: 'The Habitat Penang Hill Route', area: 'Air Itam', state: 'Penang', distanceKm: 1.4, duration: 75, elevation: 120, difficulty: 'easy' },
  { relationId: 20372063, name: 'Bukit Kutu via Kampung Pertak', area: 'Kuala Kubu Bharu', state: 'Selangor', distanceKm: 10, duration: 360, elevation: 1050, difficulty: 'hard' },
  { relationId: 20376847, name: 'Gunung Rajah Trail', area: 'Bentong', state: 'Pahang', distanceKm: 23.2, duration: 600, elevation: 1400, difficulty: 'hard' },
  { relationId: 20378122, name: 'Bukit Batu Pahat Loop', area: 'Kuala Kubu Bharu', state: 'Selangor', distanceKm: 5, duration: 240, elevation: 500, difficulty: 'moderate' },
  { relationId: 20410216, name: 'Gunung Nuang via Janda Baik', area: 'Janda Baik', state: 'Pahang', distanceKm: 12, duration: 480, elevation: 1000, difficulty: 'hard' },
  { relationId: 21013108, name: 'Chiling Waterfall Trail', area: 'Kuala Kubu Bharu', state: 'Selangor', distanceKm: 4, duration: 180, elevation: 160, difficulty: 'moderate' },
  { relationId: 19203652, name: 'Bukit Ketumbar Loop', area: 'Cheras', state: 'Kuala Lumpur', distanceKm: 2, duration: 90, elevation: 250, difficulty: 'moderate' },
  { relationId: 17995342, name: 'Bukit Besar Round Trip', area: 'Kuala Terengganu', state: 'Terengganu', distanceKm: 4.5, duration: 180, elevation: 300, difficulty: 'moderate' },
  { relationId: 20410215, name: 'Bukit Repin via Janda Baik', area: 'Janda Baik', state: 'Pahang', distanceKm: 8.4, duration: 300, elevation: 700, difficulty: 'hard' },
  { relationId: 20623409, name: 'Pisang Falls Loop', area: 'Gombak', state: 'Selangor', distanceKm: 3.1, duration: 150, elevation: 250, difficulty: 'moderate' },
  { relationId: 20672000, name: 'Bukit Jugra Hiking Trail', area: 'Banting', state: 'Selangor', distanceKm: 3.4, duration: 120, elevation: 220, difficulty: 'moderate' },
  { relationId: 17941450, name: 'Gunung Panti Trail', area: 'Kota Tinggi', state: 'Johor', distanceKm: 16, duration: 480, elevation: 700, difficulty: 'hard' },
];

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

function haversine(a, b) {
  const radians = (degrees) => degrees * Math.PI / 180;
  const dLat = radians(b.lat - a.lat);
  const dLon = radians(b.lon - a.lon);
  const lat1 = radians(a.lat);
  const lat2 = radians(b.lat);
  const sinLat = Math.sin(dLat / 2);
  const sinLon = Math.sin(dLon / 2);
  const value = sinLat * sinLat + Math.cos(lat1) * Math.cos(lat2) * sinLon * sinLon;
  return 6371000 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
}

function routePoints(relation, waysById) {
  const result = [];
  for (const member of relation.members || []) {
    if (member.type !== 'way') continue;
    const way = waysById.get(member.ref);
    let geometry = (way && way.geometry || [])
      .filter((point) => Number.isFinite(point.lat) && Number.isFinite(point.lon))
      .map((point) => ({ lat: point.lat, lon: point.lon }));
    if (geometry.length < 2) continue;
    if (member.role === 'backward' || member.role === 'reverse') {
      geometry = geometry.reverse();
    } else if (result.length > 0) {
      const tail = result[result.length - 1];
      if (haversine(tail, geometry[geometry.length - 1]) < haversine(tail, geometry[0])) {
        geometry = geometry.reverse();
      }
    }
    for (const point of geometry) {
      const previous = result[result.length - 1];
      if (!previous || haversine(previous, point) > 0.5) result.push(point);
    }
  }
  return result;
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
  const firebaseToolsRoot = path.join(
    process.env.APPDATA || '', 'npm', 'node_modules', 'firebase-tools', 'lib',
  );
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
  const query = `[out:json][timeout:90];relation(${relationId});out body;>;out geom;`;
  const endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];
  let lastError;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    for (const endpoint of endpoints) {
      try {
        const url = new URL(endpoint);
        url.searchParams.set('data', query);
        const response = await fetch(url, {
          headers: { 'User-Agent': 'HikerCircleTrailSeeder/1.0' },
          signal: AbortSignal.timeout(90000),
        });
        if (!response.ok) throw new Error(`Overpass ${response.status}`);
        return await response.json();
      } catch (error) {
        lastError = error;
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 1000 * (attempt + 1)));
  }
  throw lastError;
}

async function buildTrail(definition) {
  const data = await fetchRelation(definition.relationId);
  const relation = (data.elements || []).find(
    (element) => element.type === 'relation' && element.id === definition.relationId,
  );
  if (!relation) throw new Error(`OSM relation ${definition.relationId} was not found.`);
  const ways = new Map(
    (data.elements || []).filter((element) => element.type === 'way')
      .map((way) => [way.id, way]),
  );
  const points = routePoints(relation, ways);
  if (points.length < 3) throw new Error(`OSM route geometry is incomplete for ${definition.name}.`);
  const checkpointPoints = sampleRoute(points, 7);
  const now = new Date().toISOString();
  const checkpoints = checkpointPoints.map((point, index) => ({
    name: index === 0
      ? 'Trailhead'
      : index === checkpointPoints.length - 1
        ? 'End point'
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
    distanceKm: definition.distanceKm,
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
    dataSource: 'OpenStreetMap hiking relation',
    dataSourceUrl: `https://www.openstreetmap.org/relation/${definition.relationId}`,
    osmRelationId: String(definition.relationId),
    seededAtLocal: now,
    createdAtLocal: now,
    updatedAtLocal: now,
  };
  validateTrail(trail);
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
    built.push(await buildTrail(definition));
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

main().catch((error) => {
  console.error(error && error.stack || error);
  process.exitCode = 1;
});

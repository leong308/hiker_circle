/* eslint-disable no-console */
'use strict';

// Adds one stored altitude range to existing trails. Opening a trail never
// calls the elevation provider. Run without --apply for a read-only preview.

const {
  existingTrails,
  firebaseAccessToken,
  firestoreFields,
  firestoreRequest,
} = require('./seed_malaysia_trails');

const applyChanges = process.argv.includes('--apply');
const force = process.argv.includes('--force');
const maximumSamples = 100;

function scalar(value) {
  if (!value) return null;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  return null;
}

function decodePolyline(encoded) {
  const points = [];
  let index = 0;
  let latitude = 0;
  let longitude = 0;
  const decodeValue = () => {
    let shift = 0;
    let result = 0;
    let byte;
    do {
      if (index >= encoded.length) throw new Error('Incomplete polyline');
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    return (result & 1) !== 0 ? ~(result >> 1) : result >> 1;
  };
  while (index < encoded.length) {
    latitude += decodeValue();
    longitude += decodeValue();
    points.push({ latitude: latitude / 1e5, longitude: longitude / 1e5 });
  }
  return points;
}

function sampled(points) {
  if (points.length <= maximumSamples) return points;
  return Array.from({ length: maximumSamples }, (_, index) => {
    const sourceIndex = Math.round(
      (points.length - 1) * index / (maximumSamples - 1),
    );
    return points[sourceIndex];
  });
}

async function elevationRange(points) {
  const coordinates = sampled(points);
  const url = new URL('https://api.opentopodata.org/v1/aster30m');
  url.searchParams.set(
    'locations',
    coordinates.map((point) => `${point.latitude},${point.longitude}`).join('|'),
  );
  let lastError;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      const response = await fetch(url, {
        headers: { 'User-Agent': 'HikerCircleElevationBackfill/1.0' },
        signal: AbortSignal.timeout(30000),
      });
      if (!response.ok) throw new Error(`Elevation HTTP ${response.status}`);
      const data = await response.json();
      const values = (data.results || [])
        .map((result) => result && result.elevation)
        .filter((value) => Number.isFinite(value));
      if (values.length < 2) throw new Error('Elevation response is incomplete');
      return {
        minElevationMeters: Math.round(Math.min(...values)),
        maxElevationMeters: Math.round(Math.max(...values)),
      };
    } catch (error) {
      lastError = error;
      if (attempt < 2) {
        await new Promise((resolve) => setTimeout(resolve, 1500 * (attempt + 1)));
      }
    }
  }
  throw lastError;
}

async function updateDocument(token, document, range) {
  const url = new URL(`https://firestore.googleapis.com/v1/${document.name}`);
  url.searchParams.append('updateMask.fieldPaths', 'minElevationMeters');
  url.searchParams.append('updateMask.fieldPaths', 'maxElevationMeters');
  await firestoreRequest(token, url, {
    method: 'PATCH',
    body: JSON.stringify({ fields: firestoreFields(range) }),
  });
}

async function main() {
  const token = await firebaseAccessToken();
  const documents = await existingTrails(token);
  const candidates = documents.filter((document) => {
    const fields = document.fields || {};
    const hasRange = Number.isFinite(scalar(fields.minElevationMeters)) &&
      Number.isFinite(scalar(fields.maxElevationMeters));
    return force || !hasRange;
  });
  console.log(
    `${documents.length} trails found; ${candidates.length} require an elevation range.`,
  );

  let completed = 0;
  const failures = [];
  for (const document of candidates) {
    const fields = document.fields || {};
    const name = scalar(fields.name) || document.name.split('/').at(-1);
    const encoded = scalar(fields.routeEncodedPolyline) || '';
    try {
      const points = decodePolyline(encoded);
      if (points.length < 2) throw new Error('No saved route geometry');
      const range = await elevationRange(points);
      if (range.maxElevationMeters < range.minElevationMeters) {
        throw new Error('Invalid elevation range');
      }
      console.log(
        `${name}: ${range.minElevationMeters} m – ${range.maxElevationMeters} m`,
      );
      if (applyChanges) await updateDocument(token, document, range);
      completed += 1;
    } catch (error) {
      failures.push(`${name}: ${error.message || error}`);
      console.warn(`Skipped ${name}: ${error.message || error}`);
    }
  }

  console.log(
    applyChanges
      ? `Updated ${completed} trail elevation ranges in Firestore.`
      : `Validated ${completed} ranges. Re-run with --apply to store them.`,
  );
  if (failures.length > 0) {
    throw new Error(`${failures.length} trail(s) could not be backfilled.`);
  }
}

main().catch((error) => {
  console.error(error && error.stack || error);
  process.exitCode = 1;
});

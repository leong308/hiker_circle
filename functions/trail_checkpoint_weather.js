'use strict';

const {sharedTrailWeather} = require('./trail_weather');
const FRESHNESS_MS = 3 * 60 * 60 * 1000;

// CheckpointWeatherError: Keep validation failures distinct from provider failures.
class CheckpointWeatherError extends Error {
  // constructor: Preserve a callable-compatible validation code and message.
  constructor(code, message) { super(message); this.code = code; }
}

// validPosition: Accept only finite geographic coordinates saved on the trail.
function validPosition(point) {
  return Number.isFinite(point?.latitude) && Math.abs(point.latitude) <= 90 &&
    Number.isFinite(point?.longitude) && Math.abs(point.longitude) <= 180;
}

// checkpointKey: A coordinate identity survives checkpoint renaming and reordering.
function checkpointKey(point) {
  return `${point.latitude.toFixed(5)}_${point.longitude.toFixed(5)}`;
}

// resolveCheckpoint: Prevent callers from using this endpoint for arbitrary locations.
function resolveCheckpoint(trail, key) {
  if (!Number.isFinite(trail?.distanceKm) || trail.distanceKm <= 3) {
    throw new CheckpointWeatherError('failed-precondition', 'Checkpoint forecasts are available for trails longer than 3 km.');
  }
  const checkpoint = Array.isArray(trail.checkpoints) && trail.checkpoints.find(
    (point) => validPosition(point) && checkpointKey(point) === key,
  );
  if (!checkpoint || (validPosition(trail) && checkpointKey(trail) === key)) {
    throw new CheckpointWeatherError('invalid-argument', 'Choose a saved checkpoint on this trail.');
  }
  return checkpoint;
}

// freshForecast: Expired or incomplete documents must never bypass a refresh.
function freshForecast(data, now) {
  const cachedAt = Date.parse(data?.weather?.cachedAtLocal || '');
  return data?.weather?.schemaVersion === 2 &&
    data.weather.forecastData?.daily?.time?.length > 0 &&
    data.weather.forecastData?.hourly?.time?.length > 0 &&
    Number.isFinite(cachedAt) && cachedAt <= now + 60000 && now - cachedAt < FRESHNESS_MS;
}

// loadCheckpointWeather: Share provider leases and persist additional forecasts under the trail.
async function loadCheckpointWeather(db, trailRef, key, {sharedWeather = sharedTrailWeather, now = Date.now} = {}) {
  // Query trail and checkpoint forecast
  const snapshot = await trailRef.get();
  if (!snapshot.exists) throw new CheckpointWeatherError('not-found', 'This trail no longer exists.');
  const checkpoint = resolveCheckpoint(snapshot.data(), key);
  const ref = trailRef.collection('checkpointWeather').doc(key);
  const cached = (await ref.get()).data();
  if (freshForecast(cached, now())) return cached.weather;

  // The existing coordinate cache prevents simultaneous hikers from duplicating provider requests.
  const weather = await sharedWeather(db, checkpoint.latitude, checkpoint.longitude);
  return db.runTransaction(async (tx) => {
    // Query current trail and checkpoint
    const currentTrail = await tx.get(trailRef);
    if (!currentTrail.exists) throw new CheckpointWeatherError('not-found', 'This trail no longer exists.');
    const currentCheckpoint = resolveCheckpoint(currentTrail.data(), key);
    const latest = (await tx.get(ref)).data();
    if (Date.parse(latest?.weather?.cachedAtLocal || '') >= Date.parse(weather.cachedAtLocal)) {
      return latest.weather;
    }
    // Update cloud: cache refreshed checkpoint forecast
    tx.set(ref, {
      latitude: currentCheckpoint.latitude,
      longitude: currentCheckpoint.longitude,
      checkpointName: typeof currentCheckpoint.name === 'string' ? currentCheckpoint.name : '',
      weather,
    });
    return weather;
  });
}

module.exports = {CheckpointWeatherError, checkpointKey, resolveCheckpoint, freshForecast, loadCheckpointWeather, FRESHNESS_MS};

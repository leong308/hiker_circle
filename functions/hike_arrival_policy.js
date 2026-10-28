// Recorded footprints, rather than current GPS alone, establish arrival at a saved summit or trail end.
'use strict';
const {dateMillis} = require('./trail_hazard_policy');
const {isUnlistedSessionTrail} = require('./unlisted_hikes');
const {routePoints} = require('./trail_route_cover');
const ARRIVAL_RADIUS_METERS = 100;
const MAX_ARRIVAL_ACCURACY_METERS = 100;

// Reject invalid or missing coordinates before any distance calculation.
function validPoint(point) {
  return !!point && Number.isFinite(point.latitude) && Number.isFinite(point.longitude)
    && Math.abs(point.latitude) <= 90 && Math.abs(point.longitude) <= 180;
}

// Measure a geographic radius in metres, including routes that cross longitude zero.
function distanceMeters(a, b) {
  const radians = value => value * Math.PI / 180;
  const lat = radians(b.latitude - a.latitude), lng = radians(b.longitude - a.longitude);
  const h = Math.sin(lat / 2) ** 2 + Math.cos(radians(a.latitude)) * Math.cos(radians(b.latitude)) * Math.sin(lng / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(Math.max(0, 1 - h)));
}

// Derive destinations only from the stored hike plan; unknown summits are never invented.
function arrivalPlan(hike) {
  const trail = hike?.trail || hike?.draft?.trail || {};
  if (isUnlistedSessionTrail(trail)) return null;
  const original = Array.isArray(hike?.checkpoints) ? hike.checkpoints
    : Array.isArray(hike?.draft?.customCheckpoints) ? hike.draft.customCheckpoints : trail.checkpoints;
  let checkpoints = (Array.isArray(original) ? original : []).filter(validPoint)
    .map(point => ({latitude: point.latitude, longitude: point.longitude, name: String(point.name || ''), order: Number(point.order || 0)}))
    .sort((a, b) => a.order - b.order);
  if (checkpoints.length < 2) {
    const geometry = routePoints(trail);
    if (geometry.length < 2) return null;
    checkpoints = [geometry[0], geometry[Math.floor(geometry.length / 2)], geometry.at(-1)]
      .map(([latitude, longitude], index) => ({latitude, longitude, name: index === 2 ? 'Trail end' : '', order: index}));
  }
  const start = checkpoints[0], end = checkpoints.at(-1);
  const candidates = [...checkpoints.slice(1).filter(point => /\b(peak|summit|puncak)\b/i.test(point.name)), end];
  const targets = [];
  for (const point of candidates) {
    const id = `${point.latitude.toFixed(5)},${point.longitude.toFixed(5)}`;
    if (targets.some(target => target.id === id)) continue;
    const gates = distanceMeters(start, point) <= ARRIVAL_RADIUS_METERS * 2
      ? checkpoints.slice(1, -1).filter(gate => distanceMeters(gate, point) > ARRIVAL_RADIUS_METERS * 2)
      : [];
    // A loop's initial trailhead fix cannot count as completing that loop.
    const requiresGate = distanceMeters(start, point) <= ARRIVAL_RADIUS_METERS * 2;
    targets.push({id, name: point.name || 'Trail end', latitude: point.latitude, longitude: point.longitude,
      requiresGate, gates: gates.map(gate => ({latitude: gate.latitude, longitude: gate.longitude}))});
  }
  const deadline = dateMillis(hike?.expectedReturnTimeLocal ?? hike?.expectedReturnTime ?? hike?.draft?.expectedReturnTime);
  const startedAt = dateMillis(hike?.startedAtLocal ?? hike?.startedAt ?? hike?.draft?.departureTime);
  return Number.isFinite(deadline) && Number.isFinite(startedAt)
    ? {targets, startedAtMillis: startedAt, latestArrivalAtMillis: deadline,
      radiusMeters: ARRIVAL_RADIUS_METERS, maximumAccuracyMeters: MAX_ARRIVAL_ACCURACY_METERS}
    : null;
}

// Read the actual fix time when available, rather than the later upload/recording time.
function sampleTime(sample) {
  return dateMillis(sample?.fixCapturedAtMillis ?? sample?.capturedAtLocal ?? sample?.recordedAtMillis);
}

// Advance durable gate/arrival evidence from one ordered footprint batch.
function advanceArrivalProof(plan, samples, previous = {}, now = Date.now()) {
  if (!plan) return previous;
  if (previous.arrivedAtMillis) return previous;
  const passedGates = {...previous.passedGates};
  const ordered = (Array.isArray(samples) ? samples : []).filter(validPoint).sort((a, b) => sampleTime(a) - sampleTime(b));
  for (const sample of ordered) {
    const time = sampleTime(sample), accuracy = sample.accuracyMeters;
    if (!Number.isFinite(time) || time < plan.startedAtMillis || time > now + 10000
      || !Number.isFinite(accuracy) || accuracy < 0 || accuracy > plan.maximumAccuracyMeters) continue;
    for (const target of plan.targets) {
      if (target.requiresGate && !passedGates[target.id]
        && target.gates.some(gate => distanceMeters(gate, sample) <= plan.radiusMeters)) {
        passedGates[target.id] = time;
      }
      if ((!target.requiresGate || Number(passedGates[target.id]) < time)
        && (!target.requiresGate || Number(passedGates[target.id]) >= plan.startedAtMillis)
        && distanceMeters(target, sample) <= plan.radiusMeters) {
        return {passedGates, arrivedAtMillis: time, targetId: target.id, targetName: target.name};
      }
    }
  }
  return {passedGates};
}

// Bind local responses and cloud work to one hike deadline, including after process restoration.
function arrivalEventId(sessionId, latestArrivalAtMillis) {
  return require('node:crypto').createHash('sha256').update(`${sessionId}:${latestArrivalAtMillis}`).digest('hex');
}

module.exports = {arrivalPlan, advanceArrivalProof, arrivalEventId, sampleTime, validPoint, distanceMeters,
  ARRIVAL_RADIUS_METERS, MAX_ARRIVAL_ACCURACY_METERS};

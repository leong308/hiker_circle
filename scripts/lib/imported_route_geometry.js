'use strict';
const { createHash } = require('crypto');
const { haversine, routeDistanceMeters } = require('./trail_route_geometry');
const sha256 = (value) => createHash('sha256').update(value).digest('hex');

function checkpointsHash(checkpoints) {
  return `sha256:${sha256([...checkpoints].sort((a, b) => a.order - b.order)
    .map((c) => `${c.latitude.toFixed(6)},${c.longitude.toFixed(6)}`).join(';'))}`;
}
function encodePolyline(points) {
  let lat = 0; let lon = 0; let result = '';
  function encode(delta) {
    let n = delta < 0 ? ~(delta << 1) : delta << 1;
    let encoded = '';
    while (n >= 32) { encoded += String.fromCharCode((32 | (n & 31)) + 63); n >>>= 5; }
    return encoded + String.fromCharCode(n + 63);
  }
  for (const p of points) {
    const a = Math.round(p.lat * 1e5); const b = Math.round(p.lon * 1e5);
    result += encode(a - lat) + encode(b - lon); lat = a; lon = b;
  }
  return result;
}
function decodePolyline(encoded) {
  let index = 0; let lat = 0; let lon = 0; const points = [];
  function next() {
    let value = 0; let shift = 0; let b;
    do {
      if (index >= encoded.length || shift > 30) throw new Error('Malformed polyline.');
      b = encoded.charCodeAt(index++) - 63;
      if (b < 0 || b > 63) throw new Error('Invalid polyline character.');
      value |= (b & 31) << shift; shift += 5;
    } while (b >= 32);
    return value & 1 ? ~(value >> 1) : value >> 1;
  }
  while (index < encoded.length) { lat += next(); lon += next(); points.push({lat: lat / 1e5, lon: lon / 1e5}); }
  return points;
}
function prepareTrack(track) {
  const points = track.points;
  if (!Array.isArray(points) || points.length < 3 || points.some(p =>
    !Number.isFinite(p.lat) || !Number.isFinite(p.lon) || Math.abs(p.lat) > 90 ||
    Math.abs(p.lon) > 180 || (p.ele !== undefined && !Number.isFinite(p.ele)))) {
    throw new Error('Invalid track coordinates.');
  }
  const distance = routeDistanceMeters(points);
  let maxGap = 0;
  for (let i = 1; i < points.length; i++) maxGap = Math.max(maxGap, haversine(points[i - 1], points[i]));
  if (distance <= 0 || maxGap > 250) throw new Error('Track is empty or has a gap greater than 250 m.');
  const polyline = encodePolyline(points);
  const decoded = decodePolyline(polyline);
  const maxError = Math.max(...points.map((p, i) => haversine(p, decoded[i])));
  if (decoded.length !== points.length || maxError > 1) throw new Error('Polyline fidelity check failed.');
  // Checkpoints are route controls, not every vertex of the full track.
  // Preserve explicit waypoints; create on-track controls when GPX has none.
  const controls = track.waypoints?.length ? track.waypoints :
    Array.from({length: 7}, (_, i) => points[Math.round((points.length - 1) * i / 6)]);
  if (controls.length > 12) throw new Error('More than 12 named waypoints: select route controls explicitly before import.');
  const checkpoints = controls.map((p, i) => ({name: p.name ||
    (i === 0 ? 'Trailhead' : i === controls.length - 1 ? 'Finish' : `Waypoint ${i}`),
    latitude: p.lat, longitude: p.lon, order: i + 1}));
  if (checkpoints.length < 3) throw new Error('At least 3 route controls are needed by the current editor.');
  for (const c of checkpoints) {
    if (!points.some(p => haversine(p, {lat:c.latitude,lon:c.longitude}) <= 30))
      throw new Error('A GPX waypoint is not on the exported track.');
  }
  const elevations = points.map(p => p.ele);
  let gain = 0;
  const hasElevation = elevations.every(Number.isFinite);
  if (hasElevation) {
    for (let i = 1; i < points.length; i++) gain += Math.max(0, elevations[i] - elevations[i - 1]);
  }
  return {points, checkpoints, polyline, distanceMeters: distance,
    maxGapMeters: maxGap, maxErrorMeters: maxError,
    ...(hasElevation ? {elevationGainMeters: Math.round(gain),
      minElevationMeters: Math.round(Math.min(...elevations)),
      maxElevationMeters: Math.round(Math.max(...elevations))} : {}),
    closed: haversine(points[0], points.at(-1)) <= 30};
}
module.exports = {sha256, checkpointsHash, encodePolyline, decodePolyline, prepareTrack};

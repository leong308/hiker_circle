'use strict';
const PROVIDER = 'recorded-location-hike';
function isUnlistedSessionTrail(trail) {
  return (
    trail?.routeProvider === PROVIDER &&
    /^unlisted_[A-Za-z0-9_-]{8,100}$/.test(String(trail.trailId || ''))
  );
}
function unlistedTrailSnapshot(trailId, raw) {
  if (!isUnlistedSessionTrail({ ...raw, trailId }))
    throw Error('invalid-unlisted-trail');
  const latitude = raw.latitude,
    longitude = raw.longitude;
  if (
    typeof latitude !== 'number' ||
    typeof longitude !== 'number' ||
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    Math.abs(latitude) > 90 ||
    Math.abs(longitude) > 180 ||
    (latitude === 0 && longitude === 0)
  )
    throw Error('invalid-unlisted-location');
  return {
    trailId,
    name: String(raw.name || 'Hike from current location')
      .trim()
      .slice(0, 160),
    area: String(raw.area || '').slice(0, 100),
    state: String(raw.state || '').slice(0, 100),
    country: String(raw.country || '').slice(0, 80),
    latitude,
    longitude,
    distanceKm: 0,
    estimatedDurationMinutes: Math.max(
      15,
      Math.min(1440, Number(raw.estimatedDurationMinutes) || 120),
    ),
    elevationGainMeters: 0,
    checkpoints: [],
    hazards: [],
    isVerifiedTrail: false,
    offlineMapAvailable: false,
    offlineMapDownloaded: false,
    routeProvider: PROVIDER,
    weather: raw.weather && typeof raw.weather === 'object' ? raw.weather : {},
    ratingAverage: 0,
    ratingCount: 0,
  };
}
module.exports = { PROVIDER, isUnlistedSessionTrail, unlistedTrailSnapshot };

'use strict';
const {isDeepStrictEqual} = require('node:util');

function sameWeather(left, right) { return isDeepStrictEqual(left, right); }
function weatherMillis(weather) { return Date.parse(weather?.cachedAtLocal || ''); }
async function syncTrailWeather(db, reference, observed, weather) {
  if (sameWeather(observed.weather, weather)) return {written: false, weather};
  return db.runTransaction(async tx => {
    const snapshot = await tx.get(reference);
    if (!snapshot.exists) return {written: false, missing: true, weather};
    const current = snapshot.data();
    if (current.latitude !== observed.latitude || current.longitude !== observed.longitude) {
      return {written: false, coordinatesChanged: true, weather: current.weather || weather};
    }
    if (sameWeather(current.weather, weather) || weatherMillis(current.weather) > weatherMillis(weather)) {
      return {written: false, weather: current.weather};
    }
    tx.update(reference, {weather});
    return {written: true, weather};
  });
}

function latestFcmTokensForUser(user = {}) {
  user = user && typeof user === 'object' ? user : {};
  const byApp = user.fcmTokenByAppId && typeof user.fcmTokenByAppId === 'object'
    && !Array.isArray(user.fcmTokenByAppId) ? user.fcmTokenByAppId : {};
  const currentApp = [user.boundAppInstanceId, user.lastSignedInAppInstanceId,
    user.currentAppId, user.activeFcmAppInstanceId].map(v => String(v || '').trim()).find(Boolean);
  const valid = token => typeof token === 'string' && token.trim().length > 20;
  if (currentApp) {
    if (valid(byApp[currentApp])) return [byApp[currentApp].trim()];
    // An explicit canonical entry (including an empty revoked token) is authoritative.
    if (Object.hasOwn(byApp, currentApp)) return [];
    if (user.fcmTokenSchemaVersion === 2) return [];
    if (user.activeFcmAppInstanceId === currentApp && valid(user.activeFcmToken)) {
      return [user.activeFcmToken.trim()];
    }
    return [];
  }
  if (user.fcmTokenSchemaVersion === 2) return [];
  const canonical = [...new Set(Object.values(byApp).filter(valid).map(v => v.trim()))];
  if (canonical.length) return canonical.length === 1 ? canonical : [];
  if (valid(user.lastFcmToken)) return [user.lastFcmToken.trim()];
  const legacy = [...new Set((Array.isArray(user.fcmTokens) ? user.fcmTokens : []).filter(valid))];
  return legacy.length === 1 ? legacy : [];
}

function canonicalUsername(user = {}, fallback = '') {
  user = user && typeof user === 'object' ? user : {};
  const values = [user.profile?.username, user.username, fallback];
  return values.find(v => typeof v === 'string' && v.trim())?.trim() || '';
}

function compactHistoricalWeather(weather) {
  if (!weather || typeof weather !== 'object' || Array.isArray(weather)) return weather;
  const {hourlyForecast, dailyForecast, forecastData, ...summary} = weather;
  if (forecastData && typeof forecastData === 'object' && !Array.isArray(forecastData)) {
    const {hourly, daily, ...current} = forecastData;
    if (Object.keys(current).length) summary.forecastData = current;
  }
  return summary;
}
function historicalForecastProjection(trail) {
  const weather = trail?.weather;
  const compact = compactHistoricalWeather(weather);
  return {changed: !sameWeather(weather, compact), weather: compact, archive: weather};
}

module.exports = {sameWeather, syncTrailWeather, latestFcmTokensForUser, canonicalUsername,
  compactHistoricalWeather, historicalForecastProjection};

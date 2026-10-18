// Canonical profile/device lookups and weather projections prevent stale writes and duplicated storage sources.
'use strict';
const {isDeepStrictEqual} = require('node:util');

function sameWeather(left, right) { return isDeepStrictEqual(left, right); }
function weatherMillis(weather) { return Date.parse(weather?.cachedAtLocal || ''); }
// syncTrailWeather: Recheck coordinates and freshness in the transaction before replacing a forecast.
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

// latestFcmTokensForUser: Choose the token for the canonical bound installation instead of old token copies.
function latestFcmTokensForUser(user = {}) {
  const currentApp = typeof user.boundAppInstanceId === 'string' ? user.boundAppInstanceId.trim() : '';
  const token = currentApp && user.fcmTokenByAppId?.[currentApp];
  return typeof token === 'string' && token.trim().length > 20 ? [token.trim()] : [];
}

function canonicalUsername(user = {}, fallback = '') {
  const value = user?.profile?.username;
  return typeof value === 'string' && value.trim() ? value.trim() : fallback;
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
// historicalForecastProjection: Keep compact historical weather while returning the complete source forecast for archiving.
function historicalForecastProjection(trail) {
  const weather = trail?.weather;
  const compact = compactHistoricalWeather(weather);
  return {changed: !sameWeather(weather, compact), weather: compact, archive: weather};
}

module.exports = {sameWeather, syncTrailWeather, latestFcmTokensForUser, canonicalUsername,
  compactHistoricalWeather, historicalForecastProjection};

// A shared Firestore weather cache leases Open-Meteo refreshes across callable and scheduled workers.
'use strict';

const { randomUUID } = require('node:crypto');
const TTL = 3 * 60 * 60 * 1000;
const CURRENT = 'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_gusts_10m,uv_index';
const HOURLY = 'temperature_2m,apparent_temperature,relative_humidity_2m,precipitation_probability,precipitation,weather_code,wind_speed_10m,wind_gusts_10m,wind_direction_10m,visibility,cloud_cover,uv_index';
const DAILY = 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,precipitation_hours,wind_speed_10m_max,wind_gusts_10m_max,uv_index_max,sunrise,sunset,daylight_duration';

function weatherUrl(latitude, longitude) {
  const url = new URL('https://api.open-meteo.com/v1/forecast');
  Object.entries({ latitude, longitude, current: CURRENT, hourly: HOURLY,
    daily: DAILY, timezone: 'auto', timeformat: 'unixtime', forecast_days: 7,
  }).forEach(([key, value]) => url.searchParams.set(key, value));
  return url;
}

// parseWeather: Keep the weather fields consumed by current forecasts and precaution calculations.
function parseWeather(body) {
  if (!body?.daily?.time?.length || !body?.hourly?.time?.length || !body.current) {
    throw new Error('Incomplete weather response');
  }
  const d = body.daily;
  const c = body.current;
  const optional = (value) => Number.isFinite(value) ? value : null;
  return {
    schemaVersion: 2,
    summary: weatherSummary(d.weather_code?.[0]),
    temperatureRange: `${d.temperature_2m_min[0]} °C – ${d.temperature_2m_max[0]} °C`,
    rainProbability: optional(d.precipitation_probability_max[0]),
    cachedAtLocal: new Date().toISOString(),
    humidity: optional(c.relative_humidity_2m), windSpeed: optional(c.wind_speed_10m),
    uvIndex: optional(c.uv_index), feelsLike: optional(c.apparent_temperature),
    forecastData: { current: c, daily: d, hourly: body.hourly,
      timezone: body.timezone, utc_offset_seconds: body.utc_offset_seconds,
      elevation: body.elevation },
  };
}

// A Firestore lease coordinates ALL function instances, including the scheduler.
// sharedTrailWeather: A database lease shares refresh work across instances while respecting freshness and retry cooldowns.
async function sharedTrailWeather(db, latitude, longitude, { fetcher = fetch, maxAgeMs = TTL } = {}) {
  const lat = latitude.toFixed(4);
  const lon = longitude.toFixed(4);
  const ref = db.collection('trailWeatherCache').doc(`${lat}_${lon}`);
  const token = randomUUID();
  const deadline = Date.now() + 16000;
  while (Date.now() < deadline) {
    const claim = await db.runTransaction(async (tx) => {
      // Query forecast and lease by coordinates
      const data = (await tx.get(ref)).data() || {};
      if (data.weather?.schemaVersion === 2 && Date.now() - data.updatedAtMs < maxAgeMs) {
        return { weather: data.weather };
      }
      if (data.retryAfterMs > Date.now()) {
        if (data.weather) return { weather: data.weather };
        throw new Error('Weather temporarily unavailable; retry later');
      }
      if (data.leaseUntilMs > Date.now()) return {};
      // Update cloud: claim weather refresh lease
      tx.set(ref, { leaseToken: token, leaseUntilMs: Date.now() + 30000 }, { merge: true });
      return { owner: true };
    });
    if (claim.weather) return claim.weather;
    if (!claim.owner) {
      await new Promise((resolve) => setTimeout(resolve, 400));
      continue;
    }
    try {
      // API: Open-Meteo trail forecast
      const response = await fetcher(weatherUrl(lat, lon), { signal: AbortSignal.timeout(12000) });
      if (!response.ok) throw new Error(`Weather provider returned ${response.status}`);
      const weather = parseWeather(await response.json());
      await db.runTransaction(async (tx) => {
        // Query current weather refresh lease
        const data = (await tx.get(ref)).data();
        if (data?.leaseToken !== token) throw new Error('Weather refresh lease expired');
        // Update cloud: cache forecast and release lease
        tx.set(ref, { weather, updatedAtMs: Date.now(), leaseUntilMs: 0, retryAfterMs: 0 });
      });
      return weather;
    } catch (error) {
      await db.runTransaction(async (tx) => {
        // Query latest weather refresh lease
        const data = (await tx.get(ref)).data();
        if (data?.leaseToken === token) {
          // Update cloud: save weather retry cooldown
          tx.set(ref, { leaseUntilMs: 0, retryAfterMs: Date.now() + 60000 }, { merge: true });
        }
      });
      throw error;
    }
  }
  throw new Error('Weather refresh is still in progress. Try again shortly.');
}

module.exports = { sharedTrailWeather, weatherUrl, parseWeather };

function weatherSummary(code) {
  if (code === 0) return 'Clear sky';
  if (code === 1) return 'Mainly clear';
  if (code === 2) return 'Partly cloudy';
  if (code === 3) return 'Overcast';
  if (code === 45 || code === 48) return 'Fog';
  if (code >= 95 && code <= 99) return 'Thunderstorms';
  if (code >= 51 && code <= 57) return 'Drizzle';
  if (code >= 61 && code <= 67) return 'Rain';
  if (code >= 80 && code <= 82) return 'Rain showers';
  if (code >= 71 && code <= 77 || code === 85 || code === 86) return 'Snow';
  return 'Conditions unavailable';
}

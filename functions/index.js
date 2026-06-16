const { onSchedule } = require('firebase-functions/v2/scheduler');
const { logger } = require('firebase-functions/v2');
const admin = require('firebase-admin');

admin.initializeApp();

const WMO_MAP = {
  0: 'Clear sky',
  1: 'Mainly clear',
  2: 'Partly cloudy',
  3: 'Overcast',
  45: 'Foggy',
  48: 'Depositing rime fog',
  51: 'Light drizzle',
  53: 'Moderate drizzle',
  55: 'Dense drizzle',
  56: 'Light freezing drizzle',
  57: 'Dense freezing drizzle',
  61: 'Slight rain',
  63: 'Moderate rain',
  65: 'Heavy rain',
  66: 'Light freezing rain',
  67: 'Heavy freezing rain',
  71: 'Slight snow',
  73: 'Moderate snow',
  75: 'Heavy snow',
  77: 'Snow grains',
  80: 'Slight rain showers',
  81: 'Moderate rain showers',
  82: 'Violent rain showers',
  85: 'Slight snow showers',
  86: 'Heavy snow showers',
  95: 'Thunderstorm',
  96: 'Thunderstorm with slight hail',
  99: 'Thunderstorm with heavy hail',
};

function wmoSummary(code) {
  return WMO_MAP[code] || 'Unknown';
}

exports.fetchWeatherForAllTrails = onSchedule(
  'every 60 minutes',
  async (event) => {
    const db = admin.firestore();
    const trailsSnapshot = await db.collection('trails').get();

    if (trailsSnapshot.empty) {
      logger.log('No trails found.');
      return;
    }

    const batch = db.batch();
    let updatedCount = 0;

    for (const doc of trailsSnapshot.docs) {
      const data = doc.data();
      const latitude = data.latitude;
      const longitude = data.longitude;

      if (typeof latitude !== 'number' || typeof longitude !== 'number') {
        continue;
      }

      try {
        const url = new URL('https://api.open-meteo.com/v1/forecast');
        url.searchParams.set('latitude', latitude.toFixed(4));
        url.searchParams.set('longitude', longitude.toFixed(4));
        url.searchParams.set(
          'current',
          'temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,uv_index'
        );
        url.searchParams.set(
          'daily',
          'temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code'
        );
        url.searchParams.set(
          'hourly',
          'temperature_2m,precipitation_probability,weather_code'
        );
        url.searchParams.set('timezone', 'auto');
        url.searchParams.set('forecast_hours', '12');

        const response = await fetch(url.toString());
        if (!response.ok) {
          logger.warn(
            `OpenMeteo ${response.status} for trail ${doc.id}`
          );
          continue;
        }

        const body = await response.json();
        const current = body.current || {};
        const daily = body.daily || {};
        const hourly = body.hourly || {};

        const currentTemp = current.temperature_2m;
        const currentCode = current.weather_code || 0;
        const tempMax = Array.isArray(daily.temperature_2m_max)
          ? daily.temperature_2m_max[0]
          : currentTemp;
        const tempMin = Array.isArray(daily.temperature_2m_min)
          ? daily.temperature_2m_min[0]
          : currentTemp;
        const precipProb = Array.isArray(daily.precipitation_probability_max)
          ? daily.precipitation_probability_max[0]
          : 0;
        const dailyCodes = Array.isArray(daily.weather_code)
          ? daily.weather_code[0]
          : currentCode;

        const maxTemp = typeof tempMax === 'number' ? tempMax : 0;
        const minTemp = typeof tempMin === 'number' ? tempMin : 0;
        const dailyCode = typeof dailyCodes === 'number' ? dailyCodes : 0;
        const rainProb =
          typeof precipProb === 'number'
            ? Math.max(0, Math.min(100, Math.round(precipProb)))
            : 0;

        const now = new Date();
        const hourlyTimes = hourly.time || [];
        const hourlyTemps = hourly.temperature_2m || [];
        const hourlyCodes = hourly.weather_code || [];
        const hourlyPrecipProbs = hourly.precipitation_probability || [];
        const hourlyForecast = [];
        let started = false;

        for (let i = 0; i < hourlyTimes.length && hourlyForecast.length < 24; i++) {
          const timeStr = hourlyTimes[i];
          const temp = hourlyTemps[i];
          const code = hourlyCodes[i];

          if (typeof timeStr !== 'string' || typeof temp !== 'number' || typeof code !== 'number') {
            continue;
          }

          const time = new Date(timeStr);
          if (isNaN(time.getTime())) continue;

          if (!started) {
            if (time <= now) continue;
            started = true;
          }

          const precip =
            Array.isArray(hourlyPrecipProbs) && i < hourlyPrecipProbs.length
              ? hourlyPrecipProbs[i]
              : 0;

          hourlyForecast.push({
            timeLocal: time.toISOString(),
            temperature: temp,
            precipitationProbability:
              typeof precip === 'number'
                ? Math.max(0, Math.min(100, Math.round(precip)))
                : 0,
            weatherCode: code,
          });
        }

        const weather = {
          summary: wmoSummary(dailyCode),
          temperatureRange: `${Math.round(minTemp)} °C - ${Math.round(maxTemp)} °C`,
          rainProbability: rainProb,
          cachedAtLocal: new Date().toISOString(),
          humidity:
            typeof current.relative_humidity_2m === 'number'
              ? current.relative_humidity_2m
              : null,
          windSpeed:
            typeof current.wind_speed_10m === 'number'
              ? current.wind_speed_10m
              : null,
          uvIndex:
            typeof current.uv_index === 'number' ? current.uv_index : null,
          feelsLike:
            typeof current.apparent_temperature === 'number'
              ? current.apparent_temperature
              : null,
          hourlyForecast:
            hourlyForecast.length > 0 ? hourlyForecast : null,
        };

        batch.update(doc.ref, { weather });
        updatedCount++;
      } catch (error) {
        logger.error(`Failed to fetch weather for trail ${doc.id}:`, error);
      }
    }

    if (updatedCount > 0) {
      await batch.commit();
    }

    logger.log(`Updated weather for ${updatedCount} trails.`);
  }
);

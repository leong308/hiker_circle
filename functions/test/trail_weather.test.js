const test = require('node:test');
const assert = require('node:assert/strict');
const { sharedTrailWeather, weatherUrl, parseWeather } = require('../trail_weather');

function database() {
  let state;
  let queue = Promise.resolve();
  return {
    collection: () => ({ doc: () => ({}) }),
    runTransaction(fn) {
      const result = queue.then(() => fn({
        get: async () => ({ data: () => state }),
        set: (_, data, options) => { state = options?.merge ? { ...state, ...data } : data; },
      }));
      queue = result.catch(() => {});
      return result;
    },
  };
}
const body = {
  current: { temperature_2m: 25 },
  daily: { time: [1788739200], temperature_2m_min: [22], temperature_2m_max: [30], precipitation_probability_max: [null] },
  hourly: { time: [1788739200], visibility: [null] },
  timezone: 'Asia/Kuala_Lumpur', utc_offset_seconds: 28800, elevation: 200,
};
test('concurrent requests share one provider fetch and reuse the cache', async () => {
  const db = database();
  let calls = 0;
  const options = { fetcher: async () => {
    calls++;
    await new Promise((resolve) => setTimeout(resolve, 20));
    return { ok: true, json: async () => body };
  } };
  const results = await Promise.all(Array.from({ length: 8 }, () => sharedTrailWeather(db, 3.1, 101.6, options)));
  assert.equal(calls, 1);
  assert.deepEqual(results[0], results[7]);
  await sharedTrailWeather(db, 3.1, 101.6, options);
  assert.equal(calls, 1);
});
test('provider failure cools down subsequent requests rather than retry storming', async () => {
  const db = database();
  let calls = 0;
  const options = { fetcher: async () => { calls++; throw Error('offline'); } };
  await assert.rejects(sharedTrailWeather(db, 3.1, 101.6, options));
  await assert.rejects(sharedTrailWeather(db, 3.1, 101.6, options));
  assert.equal(calls, 1);
});
test('request retains seven days, timestamps, and missing values', () => {
  assert.equal(weatherUrl(3, 101).searchParams.get('forecast_days'), '7');
  assert.equal(weatherUrl(3, 101).searchParams.get('timeformat'), 'unixtime');
  assert.equal(parseWeather(body).forecastData.utc_offset_seconds, 28800);
  assert.equal(parseWeather(body).forecastData.hourly.visibility[0], null);
  assert.throws(() => parseWeather({}));
});

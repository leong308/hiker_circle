'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {syncTrailWeather, latestFcmTokensForUser, historicalForecastProjection,
  compactHistoricalWeather, canonicalUsername} = require('../storage_normalization');
const {detailData, summaryData} = require('../hike_history_helpers');
const weather = {schemaVersion: 2, cachedAtLocal: '2026-10-02T00:00:00Z', summary: 'Rain',
  forecastData: {current: {temperature_2m: 25}, timezone: 'Asia/Kuala_Lumpur',
    hourly: {time: [1], temperature_2m: [25]}, daily: {sunset: [2]}}};
function database(data, exists = true) {
  const writes = [];
  let reads = 0;
  return {writes, get reads() {return reads;}, runTransaction: async action => action({
    get: async () => {reads++; return {exists, data: () => data};},
    update: (_, patch) => writes.push(patch),
  })};
}
const observed = {latitude: 3, longitude: 101, weather};
test('identical cached forecast causes no transaction or write', async () => {
  const db = database(observed);
  assert.equal((await syncTrailWeather(db, {}, structuredClone(observed), weather)).written, false);
  assert.equal(db.reads, 0);
});
test('fresh forecast is written once and concurrent identical update does not write again', async () => {
  const fresh = {...weather, cachedAtLocal: '2026-10-02T03:00:00Z'};
  const db = database(observed);
  assert.equal((await syncTrailWeather(db, {}, observed, fresh)).written, true);
  assert.deepEqual(db.writes, [{weather: fresh}]);
  const race = database({...observed, weather: fresh});
  assert.equal((await syncTrailWeather(race, {}, observed, fresh)).written, false);
  assert.equal(race.writes.length, 0);
});
test('deleted trails, changed coordinates and newer forecasts cannot be overwritten', async () => {
  const incoming = {...weather, cachedAtLocal: '2026-10-02T03:00:00Z'};
  for (const db of [database({}, false), database({...observed, latitude: 4}),
    database({...observed, weather: {...weather, cachedAtLocal: '2026-10-02T06:00:00Z'}})]) {
    assert.equal((await syncTrailWeather(db, {}, observed, incoming)).written, false);
    assert.equal(db.writes.length, 0);
  }
});
test('same forecast timestamp but changed content still repairs the trail', async () => {
  const db = database({...observed, weather: {...weather, summary: 'Old'}});
  assert.equal((await syncTrailWeather(db, {}, {...observed, weather: {}}, weather)).written, true);
});
const token = 'canonical-token'.repeat(4);
const old = 'old-token'.repeat(5);
test('canonical device token wins without broadcasting to another bound device', () => {
  assert.deepEqual(latestFcmTokensForUser({boundAppInstanceId: 'a', fcmTokenByAppId: {a: token, b: old},
    lastFcmToken: old, activeFcmToken: old, fcmTokens: [old]}), [token]);
  assert.deepEqual(latestFcmTokensForUser({boundAppInstanceId: 'a', fcmTokenByAppId: {b: token}}), []);
});
test('revoked normalized tokens cannot be revived by compatibility fields', () => {
  assert.deepEqual(latestFcmTokensForUser({boundAppInstanceId: 'a', fcmTokenByAppId: {a: ''},
    activeFcmAppInstanceId: 'a', activeFcmToken: old}), []);
  assert.deepEqual(latestFcmTokensForUser({boundAppInstanceId: 'a', fcmTokenSchemaVersion: 2,
    activeFcmAppInstanceId: 'a', activeFcmToken: old}), []);
  assert.deepEqual(latestFcmTokensForUser({fcmTokenSchemaVersion: 2, fcmTokenByAppId: {b: token}}), []);
});
test('legacy single-device registration remains supported, ambiguous tokens stay suppressed', () => {
  assert.deepEqual(latestFcmTokensForUser({lastFcmToken: old}), [old]);
  assert.deepEqual(latestFcmTokensForUser({activeFcmAppInstanceId: 'a', activeFcmToken: old}), [old]);
  assert.deepEqual(latestFcmTokensForUser({fcmTokenByAppId: {a: token}}), [token]);
  assert.deepEqual(latestFcmTokensForUser({fcmTokens: [token, old]}), []);
});
test('canonical username uses profile, retains top-level fallback', () => {
  assert.equal(canonicalUsername({profile: {username: 'New'}, username: 'Old'}), 'New');
  assert.equal(canonicalUsername({username: 'Legacy'}), 'Legacy');
  assert.equal(canonicalUsername({profile: null}, 'Hiker'), 'Hiker');
});
test('historical compaction keeps current weather and never mutates the full archive', () => {
  const source = structuredClone(weather);
  const compact = compactHistoricalWeather(source);
  assert.equal(compact.summary, 'Rain');
  assert.deepEqual(compact.forecastData.current, weather.forecastData.current);
  assert.equal(compact.forecastData.hourly, undefined);
  assert.equal(compact.forecastData.daily, undefined);
  assert.deepEqual(source, weather);
  assert.equal(historicalForecastProjection({weather: compact}).changed, false);
  assert.equal(historicalForecastProjection({}).changed, false);
});
test('solo/group history and exact tracks/checkpoints are unchanged by forecast compaction', () => {
  const trail = {trailId: 'trail', name: 'Historic name', weather, checkpoints: [{name: 'CP', latitude: 3, longitude: 101}]};
  for (const hikeType of ['solo', 'team']) {
    const session = {trail, hikeType, checkpoints: trail.checkpoints, teamBuddies: [{name: 'Buddy'}]};
    const compact = {...session, trail: {...trail, weather: compactHistoricalWeather(weather)}};
    const args = {sessionId: 'history', capture: {routePoints: [{latitude: 3, longitude: 101}]},
      locationPoints: [{latitude: 3, longitude: 101, altitude: 50, batteryLevel: 80}], checkIns: []};
    assert.deepEqual(summaryData('history', session), summaryData('history', compact));
    assert.deepEqual(detailData({...args, session}), detailData({...args, session: compact}));
    assert.deepEqual(compact.trail.checkpoints, session.trail.checkpoints);
  }
});

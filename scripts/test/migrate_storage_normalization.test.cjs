'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {firestoreFields} = require('../seed_malaysia_trails');
const {userPatch, historicalPatch, maintenancePatch, validItem} = require('../migrate_storage_normalization.cjs');
const makeDocument = (collection, data) => ({
  name: `projects/hiker-circle/databases/(default)/documents/${collection}/example`,
  updateTime: '2026-10-02T00:00:00Z', fields: firestoreFields(data),
});
const token = 'safe-device-token'.repeat(3);
test('canonical token migration retains delivery and deletes only redundant aliases', () => {
  const document = makeDocument('users', {boundAppInstanceId: 'app', fcmTokenByAppId: {app: token},
    fcmTokens: [token], activeFcmToken: token, lastFcmToken: token, profile: {username: 'Name'}, username: 'Name'});
  const patch = userPatch(document);
  assert.equal(validItem(patch), true);
  assert.deepEqual(patch.fields.fcmTokenByAppId.mapValue.fields.app, {stringValue: token});
  assert.equal(patch.fields.fcmTokens, undefined);
  assert.ok(patch.mask.includes('fcmTokens'));
  assert.equal(patch.mask.some(k => /password|authFactors|achievement/.test(k)), false);
});
test('ambiguous/unbound tokens are not blindly migrated or deleted', () => {
  assert.equal(userPatch(makeDocument('users', {lastFcmToken: token})), null);
  assert.equal(userPatch(makeDocument('users', {boundAppInstanceId: 'a',
    activeFcmAppInstanceId: 'b', activeFcmToken: token})), null);
});
test('profile normalization uses canonical name but preserves unrelated profile fields', () => {
  const patch = userPatch(makeDocument('users', {profile: {username: 'New', email: 'private'}, username: 'Old'}));
  assert.deepEqual(patch.mask, ['username']);
  assert.deepEqual(patch.fields.username, {stringValue: 'New'});
});
test('historical migration archives exact typed weather and updates only its compact projection', () => {
  const document = makeDocument('hikeSessions', {status: 'completed', trail: {name: 'Original',
    checkpoints: [{name: 'Real CP', latitude: 3}], routePoints: [{longitude: 101}],
    weather: {cachedAtLocal: 'old', humidity: 70, forecastData: {current: {temperature: 25},
      hourly: {time: [1]}, daily: {sunset: [2]}}}}});
  const patch = historicalPatch(document, '2026-10-02T01:00:00Z');
  assert.equal(validItem(patch), true);
  assert.deepEqual(patch.archive.fields.weather, document.fields.trail.mapValue.fields.weather);
  const compact = patch.fields.trail.mapValue.fields.weather.mapValue.fields.forecastData.mapValue.fields;
  assert.equal(compact.hourly, undefined);
  assert.deepEqual(compact.current, document.fields.trail.mapValue.fields.weather.mapValue.fields.forecastData.mapValue.fields.current);
  assert.deepEqual(patch.mask, ['trail.weather', 'trailSnapshotVersion', 'trailForecastArchivePath']);
  assert.equal(historicalPatch({...document, fields: {...document.fields, status: {stringValue: 'active'}}}, 'now'), null);
});
test('legacy maintenance flags are backfilled without reviving tombstones', () => {
  assert.equal(maintenancePatch(makeDocument('upcomingHikes', {expired: true}), 'upcomingHikes').fields.isDeleted.booleanValue, true);
  assert.equal(maintenancePatch(makeDocument('groupChats', {chatType: 'group'}), 'groupChats').fields.isDeleted.booleanValue, false);
  assert.equal(maintenancePatch(makeDocument('groupChats', {isDeleted: true}), 'groupChats'), null);
});
test('unexpected collection paths and mutation fields are refused', () => {
  const patch = userPatch(makeDocument('users', {username: 'Legacy'}));
  assert.equal(validItem({...patch, document: makeDocument('trails', {})}), false);
  assert.equal(validItem({...patch, mask: ['passwordHash']}), false);
});

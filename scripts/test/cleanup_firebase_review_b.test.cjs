'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {eligible, oldHosting, validTarget, removeDocument} = require('../cleanup_firebase_review_b.cjs');
const now = Date.parse('2026-10-02T00:00:00Z');
const hour = 3600000;
const day = 24 * hour;
const name = 'projects/hiker-circle/databases/(default)/documents/fcmOutbox/example';
const updateTime = '2026-08-01T00:00:00.000001Z';

test('B1–B4 select only expired records beyond the one-hour safety margin', () => {
  for (const collection of ['greenApiLoginChallenges', 'passwordResetChallenges',
    'passwordResetSessions', 'passwordResetPasskeyChallenges']) {
    assert.equal(eligible(collection, {expiresAtMillis: now - hour - 1}, now), true);
    assert.equal(eligible(collection, {expiresAtMillis: now - hour}, now), false);
    assert.equal(eligible(collection, {expiresAtMillis: now + hour, consumed: true, used: true}, now), false);
    assert.equal(eligible(collection, {consumed: true}, now), false);
    assert.equal(eligible(collection, {expiresAtMillis: 'invalid'}, now), false);
  }
});
test('B5 keeps inactive but unexpired shares; B7 keeps recent counters', () => {
  assert.equal(eligible('live_location_shares', {isActive: false,
    expiresAt: new Date(now + hour).toISOString()}, now), false);
  assert.equal(eligible('live_location_shares', {
    expiresAtLocal: new Date(now - 2 * hour).toISOString()}, now), true);
  assert.equal(eligible('upcomingHikeRateLimits', {windowStartedAtMillis: now - 25 * hour}, now), false);
  assert.equal(eligible('upcomingHikeRateLimits', {windowStartedAtMillis: now - 25 * hour - 1}, now), true);
  assert.equal(eligible('users', {windowStartedAtMillis: 1}, now), false);
});
test('B6 excludes pending, sending, uncertain, recently processed or changed deliveries', () => {
  const old = {processedAt: new Date(now - 31 * day).toISOString()};
  for (const status of ['sent', 'partial', 'failed', 'no_token']) {
    assert.equal(eligible('fcmOutbox', {...old, status}, now), true);
  }
  for (const status of ['pending', 'sending', 'delivery_uncertain', 'unknown']) {
    assert.equal(eligible('fcmOutbox', {...old, status}, now), false);
  }
  assert.equal(eligible('fcmOutbox', {status: 'sent', processedAtLocal: new Date(now).toISOString()}, now), false);
  assert.equal(eligible('fcmOutbox', {...old, status: 'sent', updatedAt: new Date(now).toISOString()}, now), false);
  assert.equal(eligible('fcmOutbox', {status: 'sent'}, now), false);
});
test('B6 protects unfinished or uncertain independent team-ready WhatsApp work', () => {
  const data = {status: 'sent', type: 'team_hike_ready',
    processedAt: new Date(now - 31 * day).toISOString()};
  assert.equal(eligible('fcmOutbox', data, now), false);
  assert.equal(eligible('fcmOutbox', {...data, teamReadinessWhatsAppStatus: 'delivery_uncertain',
    teamReadinessWhatsAppProcessedAtLocal: data.processedAt}, now), false);
  assert.equal(eligible('fcmOutbox', {...data, teamReadinessWhatsAppStatus: 'sent',
    teamReadinessWhatsAppProcessedAtLocal: data.processedAt}, now), true);
});
test('B9 protects active/rollback, recent, in-progress and deleted versions', () => {
  const state = {protectedVersions: ['sites/hiker-circle/versions/keep']};
  const version = {name: 'sites/hiker-circle/versions/old', status: 'FINALIZED',
    createTime: new Date(now - 31 * day).toISOString()};
  assert.equal(oldHosting(version, state, now), true);
  assert.equal(oldHosting({...version, name: state.protectedVersions[0]}, state, now), false);
  assert.equal(oldHosting({...version, createTime: new Date(now - 30 * day).toISOString()}, state, now), false);
  for (const status of ['CREATED', 'DELETED', 'ABANDONED']) {
    assert.equal(oldHosting({...version, status}, state, now), false);
  }
});
test('deletion targets cannot escape the approved collections or project', () => {
  assert.equal(validTarget({id: 'B6', document: {name}}), true);
  assert.equal(validTarget({id: 'B1', document: {name}}), false);
  assert.equal(validTarget({id: 'B8', document: {name:
    'projects/hiker-circle/databases/(default)/documents/upcomingHikes/x/reminderPreferences/y'}}), true);
  assert.equal(validTarget({id: 'B8', document: {name:
    'projects/hiker-circle/databases/(default)/documents/users/x/reminderPreferences/y'}}), false);
  assert.throws(() => validTarget({id: 'B6', document: {name: name.replace('hiker-circle', 'other-project')}}));
});
function mockRequests(t, responses) {
  const original = global.fetch;
  const calls = [];
  global.fetch = async (url, options) => {
    calls.push({url: String(url), body: options.body ? JSON.parse(options.body) : null});
    const response = responses.shift();
    assert.ok(response, 'unexpected request');
    return new Response(JSON.stringify(response.body), {status: response.status || 200});
  };
  t.after(() => {global.fetch = original;});
  return calls;
}
const document = {name, updateTime, fields: {status: {stringValue: 'sent'},
  processedAt: {timestampValue: '2026-08-01T00:00:00Z'}}};
const candidate = {id: 'B6', collection: 'fcmOutbox', document};
test('Firestore deletion uses the exact backed-up update-time precondition', async t => {
  const calls = mockRequests(t, [{body: document}, {body: {}}, {body: {commitTime: updateTime}}]);
  assert.equal(await removeDocument('test-token', candidate, now), 'deleted');
  assert.deepEqual(calls[2].body.writes, [{delete: name, currentDocument: {updateTime}}]);
});
test('changed documents and documents with descendants are preserved', async t => {
  const calls = mockRequests(t, [{body: {...document, updateTime: 'changed'}},
    {body: document}, {body: {collectionIds: ['keep']}}]);
  assert.equal(await removeDocument('test-token', candidate, now), 'changed_preserved');
  assert.equal(await removeDocument('test-token', candidate, now), 'descendants_preserved');
  assert.equal(calls.filter(c => c.body?.writes).length, 0);
});
test('B8 transaction confirms parent absence and protects parent recreation', async t => {
  const parent = 'projects/hiker-circle/databases/(default)/documents/upcomingHikes/x';
  const orphan = {name: `${parent}/reminderPreferences/y`, updateTime, fields: {}};
  const item = {id: 'B8', parent, document: orphan};
  const calls = mockRequests(t, [{body: orphan}, {body: {}}, {body: {transaction: 'tx'}},
    {body: [{missing: parent}, {found: orphan}]}, {body: {}}]);
  assert.equal(await removeDocument('test-token', item, now), 'deleted');
  assert.equal(calls[4].body.transaction, 'tx');
});
test('B8 keeps preferences when the parent has been recreated', async t => {
  const parent = 'projects/hiker-circle/databases/(default)/documents/upcomingHikes/x';
  const orphan = {name: `${parent}/reminderPreferences/y`, updateTime, fields: {}};
  const calls = mockRequests(t, [{body: orphan}, {body: {}}, {body: {transaction: 'tx'}},
    {body: [{found: {name: parent}}, {found: orphan}]}, {body: {}}]);
  assert.equal(await removeDocument('test-token', {id: 'B8', parent, document: orphan}, now),
    'parent_restored_preserved');
  assert.equal(calls.some(c => c.body?.writes), false);
  assert.equal(calls.at(-1).body.transaction, 'tx');
});

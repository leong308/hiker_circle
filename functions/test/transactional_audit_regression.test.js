'use strict';
const test = require('node:test');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require.resolve('../index'), 'utf8');
const assert = require('node:assert/strict');
const { recordLocationBatch, parseLocationBatch } = require('../location_batch');
const { activateLiveLocationShare } = require('../live_location_share');
const { removeMfaFactor } = require('../mfa_factor_removal');
const { reconcileCommentCount } = require('../community_comment_counter');
const { claimOutbox, beginOutbound, retryPreflight, updateClaim, LEASE_MILLIS } = require('../fcm_outbox_delivery');

class ApiError extends Error { constructor(code, message) { super(message); this.code = code; } }
function database(seed = {}) {
  const rows = new Map(Object.entries(seed)); let nextId = 0, queue = Promise.resolve();
  const snapshot = ref => ({ ref, id: ref.id, exists: rows.has(ref.path), data: () => structuredClone(rows.get(ref.path)) });
  const collection = path => ({ path, doc: id => reference(`${path}/${id || `opaque-share-${++nextId}`}`), select() { return this; } });
  const reference = path => ({ path, id: path.split('/').at(-1), collection: name => collection(`${path}/${name}`),
    parent: { parent: path.split('/').length > 2 ? reference(path.split('/').slice(0, -2).join('/')) : null },
    get: async () => snapshot(reference(path)),
    update: async data => { if (!rows.has(path)) { const error = new Error('missing'); error.code = 5; throw error; } rows.set(path, merge(rows.get(path), data)); },
  });
  const merge = (left, right) => {
    const result = { ...left };
    for (const [key, value] of Object.entries(right)) result[key] = value && typeof value === 'object' && !Array.isArray(value)
      ? merge(result[key], value) : value;
    return result;
  };
  return { rows, collection, getAll: async (...refs) => refs.map(snapshot), runTransaction(callback) {
    const run = queue.then(async () => {
      const writes = []; let writing = false;
      const tx = { get: async ref => {
        assert.equal(writing, false, 'all transaction reads precede writes');
        if (ref.doc) {
          const docs = [...rows.keys()].filter(p => p.startsWith(ref.path + '/') && p.split('/').length === ref.path.split('/').length + 1).map(p => snapshot(reference(p)));
          return { docs, size: docs.length, empty: docs.length === 0 };
        }
        return snapshot(ref);
      }, create(ref, data) { writing = true; assert.equal(rows.has(ref.path), false); writes.push(() => rows.set(ref.path, data)); },
      set(ref, data, options) { writing = true; writes.push(() => rows.set(ref.path, options?.merge ? merge(rows.get(ref.path), data) : data)); },
      update(ref, data) { writing = true; writes.push(() => { assert.ok(rows.has(ref.path)); rows.set(ref.path, merge(rows.get(ref.path), data)); }); },
      delete(ref) { writing = true; writes.push(() => rows.delete(ref.path)); } };
      const result = await callback(tx); writes.forEach(write => write()); return result;
    });
    queue = run.catch(() => {}); return run;
  } };
}
const now = Date.parse('2026-09-18T10:00:00Z');
const stamp = () => 'server-time';
const hike = { userId: '+60123456789', userPhoneNumber: '+60123456789', status: 'active', trailId: 'trail', startedAtLocal: new Date(now - 3600000).toISOString() };
const point = (offset = 0, overrides = {}) => ({ recordedAtMillis: now + offset, fixCapturedAtMillis: now + offset - 1000, latitude: 3.1, longitude: 101.5, ...overrides });
const record = (db, points, extra = {}) => recordLocationBatch(db, { sessionId: 'hike_1', uid: hike.userId, phoneNumber: hike.userPhoneNumber, points, ...extra }, ApiError, stamp, now);

test('stationary samples retain distinct timestamps; repeated/conflicting timestamp keeps first committed coordinates and exact acknowledgements', async () => {
  const db = database({ 'hikeSessions/hike_1': hike });
  const response = await record(db, [point(-5000), point(), point(0, { latitude: 9 })]);
  assert.deepEqual(response.committedRecordedAtMillis, [now - 5000, now]);
  assert.deepEqual(response.committedPointIds, [`hike_1_${now - 5000}`, `hike_1_${now}`]);
  assert.equal(response.sessionId, 'hike_1');
  await record(db, [point(0, { latitude: 8 })]);
  assert.equal(db.rows.get(`localLocationPoints/hike_1_${now}`).latitude, 3.1);
  assert.equal(db.rows.get('hikeSessions/hike_1').latestLocation.fixCapturedAtMillis, now - 1000);
  assert.equal(db.rows.size, 3);
});

test('late terminal backlog is accepted without rewinding latest location', async () => {
  const db = database({ 'hikeSessions/hike_1': { ...hike, status: 'completed', endedAtLocal: new Date(now).toISOString() } });
  await record(db, [point()]); await record(db, [point(-60000, { latitude: 1 })]);
  assert.equal(db.rows.get('hikeSessions/hike_1').latestLocation.latitude, 3.1);
  assert.equal(db.rows.size, 3);
});

test('foreign ownership, out-of-hike timestamps and invalid batches cannot commit partial points', async () => {
  const db = database({ 'hikeSessions/hike_1': hike });
  await assert.rejects(record(db, [point()], { uid: 'other' }), { code: 'permission-denied' });
  await assert.rejects(record(db, [point(-5000000), point()]), { code: 'invalid-argument' });
  assert.equal(db.rows.size, 1);
  for (const points of [[], Array.from({ length: 201 }, () => point()), [point(0, { latitude: NaN })], [point(0, { accuracyMeters: -1 })]]) {
    assert.throws(() => parseLocationBatch(points, ApiError, now), { code: 'invalid-argument' });
  }
});

test('live activation uses server lifetime, retry preserves expiry, revoked share gets new opaque link', async () => {
  const db = database({ [`users/${hike.userId}`]: { phoneNumber: hike.userPhoneNumber } });
  const activate = (time, latitude = 3) => activateLiveLocationShare(db, { uid: hike.userId, phoneNumber: hike.userPhoneNumber,
    location: { latitude, longitude: 101, capturedAtLocal: new Date(time).toISOString(), expiresAtMillis: now + 99e9 } }, ApiError, stamp, ms => ms, time);
  const first = await activate(now);
  const retry = await activate(now + 60000);
  assert.equal(first.expiresAtMillis, now + 24 * 3600000);
  assert.deepEqual(retry, first);
  db.rows.get(`live_location_shares/${first.shareId}`).isActive = false;
  const restarted = await activate(now + 120000);
  assert.notEqual(restarted.shareId, first.shareId);
  assert.equal(db.rows.get(`live_location_shares/${first.shareId}`).isActive, false);
});

test('concurrent factor removals serialize and retain a security method', async () => {
  const db = database({ 'users/u': {}, 'users/u/authFactors/a': { type: 'totp' }, 'users/u/authFactors/b': { type: 'passkey' } });
  const results = await Promise.allSettled(['a', 'b'].map(id => removeMfaFactor(db, 'u', id, ApiError, stamp)));
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(results.find(r => r.status === 'rejected').reason.code, 'failed-precondition');
  assert.equal(db.rows.get('users/u/modules/security').mfaFactorCount, 1);
  assert.equal([...db.rows.keys()].filter(p => p.includes('/authFactors/')).length, 1);
});

test('comment create/delete event reversal and replay reconcile current children without resurrecting parents', async () => {
  const db = database({ 'communityPosts/p': { commentCount: 0 } });
  await reconcileCommentCount(db, 'p', stamp); // delete delivered first
  await reconcileCommentCount(db, 'p', stamp); // stale create event
  assert.equal(db.rows.get('communityPosts/p').commentCount, 0);
  db.rows.set('communityPosts/p/comments/legacy', { text: 'legacy' });
  await reconcileCommentCount(db, 'p', stamp);
  assert.equal(db.rows.get('communityPosts/p').commentCount, 1);
  db.rows.delete('communityPosts/p');
  await reconcileCommentCount(db, 'p', stamp);
  assert.equal(db.rows.has('communityPosts/p'), false);
});

test('preflight failures retry and expired preflight leases fence old workers', async () => {
  const db = database({ 'fcmOutbox/m': { status: 'pending' } }); const ref = db.collection('fcmOutbox').doc('m');
  const first = await claimOutbox(db, ref, stamp, now);
  assert.equal(await claimOutbox(db, ref, stamp, now + 1), null);
  assert.equal(await retryPreflight(db, ref, first.attemptId, new Error('read'), now), true);
  assert.equal(await claimOutbox(db, ref, stamp, now + 1), null);
  const second = await claimOutbox(db, ref, stamp, now + 60001);
  const third = await claimOutbox(db, ref, stamp, now + 60001 + LEASE_MILLIS);
  assert.notEqual(second.attemptId, third.attemptId);
  assert.equal(await beginOutbound(db, ref, second.attemptId, now), false);
  assert.equal(await beginOutbound(db, ref, third.attemptId, now), true);
});

test('outbound process death and legacy stuck claims become uncertain without sending twice', async () => {
  const db = database({ 'fcmOutbox/m': { status: 'pending' }, 'fcmOutbox/legacy': { status: 'sending' } });
  const ref = db.collection('fcmOutbox').doc('m');
  const claim = await claimOutbox(db, ref, stamp, now);
  assert.equal(await beginOutbound(db, ref, claim.attemptId, now), true);
  assert.equal(await retryPreflight(db, ref, claim.attemptId, new Error('failure'), now), false);
  assert.equal(await claimOutbox(db, ref, stamp, now + LEASE_MILLIS), null);
  assert.equal(db.rows.get(ref.path).status, 'delivery_uncertain');
  assert.equal(await updateClaim(db, ref, claim.attemptId, { status: 'sent' }), false);
  const legacy = db.collection('fcmOutbox').doc('legacy');
  assert.equal(await claimOutbox(db, legacy, stamp, now), null);
  assert.equal(db.rows.get(legacy.path).status, 'delivery_uncertain');
});

function extractedFunction(name, nextName) {
  return source.slice(source.indexOf(`function ${name}(`), source.indexOf(nextName, source.indexOf(`function ${name}(`)));
}
function callback(name, endMarker, db, extra = {}) {
  const accessor = () => db;
  accessor.FieldValue = { serverTimestamp: stamp, increment: value => value };
  const context = { ...require('../user_modules'), exports: {}, onDocumentUpdated: (_, handler) => handler,
    onDocumentCreated: (_, handler) => handler, admin: { firestore: accessor },
    dateMillis: value => typeof value === 'number' ? value : Date.parse(value),
    phoneKeyFor: value => value.replace(/[^0-9]/g, ''),
    validFirestoreDocumentId: id => typeof id === 'string' && id.length > 0 && !id.includes('/'),
    sanitizedPlainValue: value => value, require: path => require('../' + path.replace('./', '')),
    claimAtMostOnceDelivery: async () => null, latestFcmTokensForUser: () => [],
    logger: { log() {} }, ...extra };
  vm.createContext(context);
  const start = source.indexOf(`exports.${name} =`);
  vm.runInContext(source.slice(start, source.indexOf(endMarker, start)), context);
  return context.exports[name];
}

test('reversed cloud location events never rewind a share and terminal sessions cannot publish delayed events', async () => {
  const shareId = 'opaque-share';
  const data = { ...hike, shareLiveLocation: true, liveLocationShareId: shareId,
    latestLocation: { latitude: 3.4, longitude: 101, recordedAtMillis: now - 1000 } };
  const db = database({ 'hikeSessions/hike_1': data, [`users/${hike.userId}`]: {},
    [`live_location_shares/${shareId}`]: { ownerUserId: hike.userId, isActive: true,
      expiresAt: Date.now() + 3600000, latestLocation: { latitude: 3.5, longitude: 101, recordedAtMillis: now } } });
  const mirror = callback('mirrorActiveHikeLocationToLiveShare', 'exports.manageBuddyRequest', db);
  const event = { params: { sessionId: 'hike_1' }, data: { before: { data: () => ({}) }, after: { data: () => data } } };
  await mirror(event);
  assert.equal(db.rows.get(`live_location_shares/${shareId}`).latestLocation.latitude, 3.5);
  data.latestLocation = { latitude: 4, longitude: 101, recordedAtMillis: now + 1000 };
  await mirror(event);
  assert.equal(db.rows.get(`live_location_shares/${shareId}`).latestLocation.latitude, 4);
  db.rows.set('hikeSessions/hike_1', { ...data, status: 'completed' });
  data.latestLocation = { latitude: 5, longitude: 101, recordedAtMillis: now + 2000 };
  await mirror(event);
  assert.equal(db.rows.get(`live_location_shares/${shareId}`).latestLocation.latitude, 4);
});

test('production chat callback does not resurrect deleted messages or regress a newer preview', async () => {
  const path = 'groupChats/c/messages/m';
  const db = database({ 'groupChats/c': { participantPhones: ['+60111111111', '+60222222222'],
    lastMessage: 'newer', lastMessageAtLocal: new Date(now).toISOString() } });
  const groupChatMessagePreview = vm.runInNewContext('(' + extractedFunction('groupChatMessagePreview', '\nasync function ensureAchievementDefinitions') + ')');
  const notify = callback('notifyGroupMembersAboutMessage', '\nasync function deliverFcmOutboxDocument', db, { groupChatMessagePreview });
  const message = { senderPhone: '+60111111111', sentAtLocal: new Date(now - 1000).toISOString(), text: 'old' };
  const event = { params: { chatId: 'c', messageId: 'm' }, data: { ref: db.collection('groupChats/c/messages').doc('m'), data: () => message } };
  await notify(event);
  assert.equal(db.rows.has(path), false);
  assert.equal(db.rows.get('groupChats/c').lastMessage, 'newer');
  db.rows.set(path, message);
  await notify(event);
  assert.equal(db.rows.get('groupChats/c').lastMessage, 'newer');
  db.rows.set(path, {});
  message.text = ''; message.attachment = { type: 'image' }; message.sentAtLocal = new Date(now + 1000).toISOString();
  await notify(event);
  assert.equal(db.rows.get('groupChats/c').lastMessage, 'Photo');
});

test('incomplete signup recovery excludes completed, disabled and password-bearing accounts', () => {
  const incomplete = vm.runInNewContext('(' + extractedFunction('isIncompleteRegistration', '\nfunction userDocumentIdForPhone') + ')');
  assert.equal(incomplete({ requiresOnboarding: true, profileSetupCompleted: false }), true);
  for (const patch of [{ passwordHash: 'hash' }, { profileSetupCompleted: true }, { accountDisabled: true }, { status: 'disabled' }, { requiresOnboarding: false }]) {
    assert.equal(incomplete({ requiresOnboarding: true, profileSetupCompleted: false, ...patch }), false);
  }
});

test('fresh GPS suppresses stale-monitoring classification without treating unrelated writes as activity', () => {
  const context = { dateMillis: value => typeof value === 'number' ? value : Date.parse(value) };
  const activity = vm.runInNewContext('(' + extractedFunction('latestHikeActivityMillis', '\nfunction shouldAbandonInactiveHike') + ')', context);
  assert.equal(activity({ ...hike, updatedAtLocal: new Date(now).toISOString() }), now - 3600000);
  assert.equal(activity({ ...hike, lastGpsActivityAtMillis: now }), now);
});

test('auto-abandoned hikes accept owner samples recorded while the device remained offline', async () => {
  const db = database({ 'hikeSessions/hike_1': { ...hike, status: 'abandoned', abandonedAtLocal: new Date(now - 1800000).toISOString() } });
  const result = await record(db, [point()]);
  assert.deepEqual(result.committedRecordedAtMillis, [now]);
});

test('cloud monitoring grace follows selected upload interval', () => {
  const staleAfter = vm.runInNewContext('(' + extractedFunction('hikeMonitoringStaleAfterMillis', '\nfunction latestHikeActivityMillis') + ')');
  assert.equal(staleAfter({ locationRecordingIntervalSeconds: 300 }), 10 * 60000);
  assert.equal(staleAfter({ locationRecordingIntervalSeconds: 5 }), 305000);
  assert.equal(staleAfter({ locationRecordingIntervalSeconds: 3600 }), 65 * 60000);
});

test('completed hikes accept delayed owner packets without reopening and retries remain unique', async () => {
  const db = database({ 'hikeSessions/hike_1': { ...hike, status: 'completed', endedAtLocal: new Date(now - 1800000).toISOString() } });
  await record(db, [point(-5000), point()]);
  await record(db, [point(-5000), point()]);
  assert.equal(db.rows.get('hikeSessions/hike_1').status, 'completed');
  assert.equal([...db.rows.keys()].filter(key => key.startsWith('localLocationPoints/')).length, 2);
});

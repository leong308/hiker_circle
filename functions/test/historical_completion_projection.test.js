'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const crypto = require('node:crypto');
const {historicalForecastProjection} = require('../storage_normalization');
const source = fs.readFileSync(require.resolve('../index'), 'utf8');
const block = source.slice(source.indexOf('exports.completeActiveHikeSession ='),
  source.indexOf('exports.submitCompletedHikeRating ='));
const forecast = {summary: 'Light rain', forecastData: {current: {temperature: 26},
  hourly: {time: [1, 2]}, daily: {sunset: [3]}}};
const trail = {trailId: 'trail', name: 'Historic name', weather: forecast,
  checkpoints: [{name: 'Crossing', latitude: 3, longitude: 101}], routeEncodedPolyline: 'exact-route'};
function fixture(offline, team) {
  const uid = 'owner';
  const phone = '+60111111111';
  const started = Date.now() - 3600000;
  const sessionId = offline ? `session_${started}` : 'cloud-hike';
  const rows = new Map([['users/owner', {}], ['trails/trail', trail]]);
  if (!offline) rows.set(`hikeSessions/${sessionId}`, {userId: uid, userPhoneNumber: phone,
    trailId: 'trail', status: 'active', trail, checkpoints: trail.checkpoints,
    teamHikeSessionId: team ? 'team' : '', latestLocation: {latitude: 3.2, longitude: 101.2}});
  if (team) rows.set('teamHikeSessions/team', {trailId: 'trail',
    participants: [{phone, status: 'active'}, {phone: '+60222222222', status: 'active', buddy: {name: 'Buddy'}}]});
  const reference = path => ({path, id: path.split('/').at(-1), collection: name => collection(`${path}/${name}`)});
  const collection = path => ({doc: id => reference(`${path}/${id}`)});
  let writes = 0;
  const db = {collection, async runTransaction(action) {
    const queued = [];
    const transaction = {
      async get(ref) {
        assert.equal(queued.length, 0, 'all reads must precede writes');
        return {ref, id: ref.id, exists: rows.has(ref.path), data: () => rows.get(ref.path)};
      },
      create(ref, value) {
        assert.equal(rows.has(ref.path), false, 'immutable archive must not be overwritten');
        queued.push(() => rows.set(ref.path, structuredClone(value)));
      },
      set(ref, value) {queued.push(() => rows.set(ref.path, {...rows.get(ref.path), ...structuredClone(value)}));},
      update(ref, patch) {
        queued.push(() => {
          const value = structuredClone(rows.get(ref.path));
          for (const [key, field] of Object.entries(patch)) {
            if (key === 'trail.weather') value.trail.weather = structuredClone(field);
            else value[key] = structuredClone(field);
          }
          rows.set(ref.path, value);
        });
      },
    };
    const result = await action(transaction);
    writes += queued.length;
    queued.forEach(write => write());
    return result;
  }};
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => 'server-time', delete: () => null};
  const exports = {};
  vm.runInNewContext(block, {
    ...require('../user_modules'),
    exports, onCall: (_, handler) => handler, admin: {firestore}, crypto,
    authenticatedPhoneFor: () => ({uid, phoneNumber: phone}),
    validFirestoreDocumentId: value => Boolean(value), dateMillis: Date.parse,
    legacyActiveHikeCanAdoptTeamSource: () => false,
    historicalForecastProjection,
    HttpsError: class extends Error {},
    validTeamParticipants: value => value.participants,
    teamParticipantPhone: value => value.phone, teamSourceMatchesRequest: () => true,
    sanitizedPlainValue: value => value, mergeSharedPlanWithCallerSafety: (_, draft) => draft,
    canonicalTrailSnapshot: (_, value) => value,
    sanitizedTeamDraft: (draft, canonicalTrail) => ({...draft, trail: canonicalTrail}),
    completedHikeSummaryData: () => ({distanceKm: 2, durationMinutes: 60,
      checkIns: 1, manualPins: 0, routePointCount: 10}),
    activeHikeDocumentData: data => ({userId: data.uid, userPhoneNumber: data.phoneNumber,
      trail: data.draft.trail, trailId: 'trail', checkpoints: trail.checkpoints}),
    assertWindowRate: () => {},
  });
  return {rows, get writes() {return writes;}, complete: exports.completeActiveHikeSession,
    request: {data: {sessionId, draft: {trail}, startedAtLocal: new Date(started).toISOString(),
      endedAtLocal: new Date().toISOString(), teamHikeSessionId: team ? 'team' : ''}}};
}
for (const [name, offline, team] of [['online solo', false, false], ['offline solo', true, false], ['team', false, true]]) {
  test(`${name} completion atomically archives weather, retains route/checkpoints, and is replay-safe`, async () => {
    const state = fixture(offline, team);
    const result = await state.complete(state.request);
    const session = state.rows.get(`hikeSessions/${result.sessionId}`);
    assert.equal(session.status, 'completed');
    assert.equal(session.trailSnapshotVersion, 2);
    assert.deepEqual(session.trail.checkpoints, trail.checkpoints);
    assert.equal(session.trail.routeEncodedPolyline, 'exact-route');
    assert.equal(session.trail.weather.forecastData.hourly, undefined);
    const archive = state.rows.get(session.trailForecastArchivePath);
    assert.deepEqual(archive.weather, forecast);
    if (!offline) assert.deepEqual(session.latestLocation, {latitude: 3.2, longitude: 101.2});
    const before = state.writes;
    assert.equal((await state.complete(state.request)).completed, true);
    assert.equal(state.writes, before, 'replay must not create another archive or write');
  });
}

test('new active team chats enter maintenance queries without reviving existing tombstones', async () => {
  const start = source.indexOf('async function ensureTeamChatDocument(');
  const helper = source.slice(start, source.indexOf('exports.cancelUpcomingHike =', start));
  const team = {phase: 'active', participants: [{phone: '+60111111111', buddy: {name: 'Host'}}]};
  for (const existing of [null, {isDeleted: true}]) {
    let saved = existing;
    const reference = {path: 'groupChats/team_team'};
    const db = {collection: () => ({doc: () => reference}),
      runTransaction: action => action({
        get: async () => ({exists: saved !== null, data: () => saved}),
        set: (_, patch) => {saved = {...saved, ...patch};},
      })};
    const ensure = vm.runInNewContext(helper + '\nensureTeamChatDocument', {
      validTeamParticipants: value => value.participants,
      teamParticipantPhone: value => value.phone,
      phoneKeyFor: value => value.replace(/\D/g, ''),
      admin: {firestore: {FieldValue: {serverTimestamp: () => 'server-time'}}},
    });
    await ensure(db, 'team', team);
    assert.equal(saved.isDeleted, existing ? true : false);
  }
});

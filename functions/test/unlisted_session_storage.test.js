'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {
  isUnlistedSessionTrail,
  unlistedTrailSnapshot,
} = require('../unlisted_hikes');
const source = fs.readFileSync(require.resolve('../index'), 'utf8');
const plain = source.slice(
  source.indexOf('function sanitizedPlainValue('),
  source.indexOf('function teamBuddyFromUser('),
);
const sanitizer = source.slice(
  source.indexOf('function sanitizedTeamDraft('),
  source.indexOf('function sharedHikePlan('),
);
const storage = source.slice(
  source.indexOf('function canonicalTrailSnapshot('),
  source.indexOf('async function ensureTeamChatDocument('),
);
const safety = source.slice(
  source.indexOf('function validTeamSafetySettings('),
  source.indexOf('function haversineMeters('),
);
const helpers = vm.runInNewContext(
  plain +
    sanitizer +
    storage +
    safety +
    '\n({canonicalTrailSnapshot, sanitizedTeamDraft, activeHikeDocumentData, validTeamSafetySettings})',
  {
    Buffer,
    isUnlistedSessionTrail,
    unlistedTrailSnapshot,
    dateMillis: Date.parse,
    HttpsError: class extends Error {
      constructor(code, message) {
        super(message);
        this.code = code;
      }
    },
    admin: {
      firestore: {
        Timestamp: class {
          static fromMillis(value) {
            return value;
          }
        },
        GeoPoint: class {},
        FieldValue: { serverTimestamp: () => 'server-time' },
      },
    },
  },
);
const trail = {
  trailId: 'unlisted_1234567890',
  routeProvider: 'recorded-location-hike',
  latitude: 5.1,
  longitude: 100.1,
};
function rawDraft(trail) {
  const now = Date.now();
  return {
    trail,
    departureTime: new Date(now).toISOString(),
    expectedArrivalTime: new Date(now + 3600000).toISOString(),
    expectedReturnTime: new Date(now + 3600000).toISOString(),
    pathDeviationEnabled: true,
    customCheckpoints: [{ name: 'Invented', latitude: 5.2, longitude: 100.2 }],
  };
}
function active(draft) {
  return helpers.activeHikeDocumentData({
    sessionId: 'session',
    uid: 'owner',
    phoneNumber: '+60123456789',
    draft,
    startedAtMillis: Date.now(),
  });
}
test('native session storage accepts a location hike without publishing a catalog route or invented checkpoints', () => {
  const snapshot = helpers.canonicalTrailSnapshot(
    trail.trailId,
    {},
    { ...trail, routeEncodedPolyline: 'invented', distanceKm: 99 },
  );
  const draft = helpers.sanitizedTeamDraft(rawDraft(snapshot), snapshot, []);
  const saved = active(draft);
  assert.equal(saved.trail.routeProvider, 'recorded-location-hike');
  assert.equal(saved.trail.latitude, trail.latitude);
  assert.equal(saved.trail.routeEncodedPolyline, undefined);
  assert.equal(saved.trail.distanceKm, 0);
  assert.equal(saved.pathDeviationEnabled, false);
  assert.equal(saved.checkpoints.length, 0);
  assert.equal(saved.status, 'active');
  assert.equal(saved.userId, 'owner');
});
test('normal session storage retains catalog checkpoints and deviation monitoring', () => {
  const catalog = {
    trailId: 'catalog',
    name: 'Catalog path',
    checkpoints: [{ name: 'Start', latitude: 5.1, longitude: 100.1 }],
    distanceKm: 2,
  };
  const snapshot = helpers.canonicalTrailSnapshot(
    catalog.trailId,
    catalog,
    trail,
  );
  const draft = helpers.sanitizedTeamDraft(
    { ...rawDraft(snapshot), customCheckpoints: [] },
    snapshot,
    [],
  );
  const saved = active(draft);
  assert.equal(saved.trail.name, 'Catalog path');
  assert.equal(saved.trail.routeProvider, undefined);
  assert.equal(saved.pathDeviationEnabled, true);
  assert.equal(saved.checkpoints.length, 1);
  assert.equal(saved.trail.distanceKm, 2);
});
test('canonical location snapshots reject missing GPS coordinates', () => {
  assert.throws(
    () =>
      helpers.canonicalTrailSnapshot(
        trail.trailId,
        {},
        { ...trail, latitude: null },
      ),
    (e) => e.code === 'invalid-argument',
  );
});

test('chosen deviation distance survives cloud draft sanitization and active hike storage', () => {
  const catalog = {trailId:'catalog', name:'Forest', checkpoints:[]};
  for (const distance of [10, 17, 37, 50]) {
    const draft = helpers.sanitizedTeamDraft({
      ...rawDraft(catalog), pathDeviationDistanceMeters:distance,
    }, catalog, []);
    assert.equal(draft.pathDeviationDistanceMeters, distance);
    assert.equal(active(draft).pathDeviationDistanceMeters, distance);
  }
});

test('deviation settings default to 30 m and clamp invalid distances in solo and team sessions', () => {
  const catalog = {trailId:'catalog', name:'Forest', checkpoints:[]};
  const ready = {liveLocationSharing:true, pathDeviationAlerts:true, teammateSeparationAlerts:true};
  for (const [value, expected] of [[undefined,30], [null,30], ['20',30], [NaN,30], [Infinity,30], [-1,10], [999,50], [36.7,37]]) {
    const draft = helpers.sanitizedTeamDraft({
      ...rawDraft(catalog), pathDeviationDistanceMeters:value,
    }, catalog, []);
    assert.equal(draft.pathDeviationDistanceMeters, expected);
    assert.equal(active(draft).pathDeviationDistanceMeters, expected);
    assert.equal(helpers.validTeamSafetySettings({
      ...ready, pathDeviationDistanceMeters:value,
    }).pathDeviationDistanceMeters, expected);
  }
});

test('team location hikes do not require fictitious deviation alerts; catalog teams still do', () => {
  const raw = {
    liveLocationSharing: true,
    teammateSeparationAlerts: true,
    pathDeviationAlerts: false,
  };
  const settings = helpers.validTeamSafetySettings(raw, false);
  assert.equal(settings.pathDeviationAlerts, false);
  assert.equal(settings.liveLocationSharing, true);
  assert.equal(settings.teammateSeparationAlerts, true);
  assert.throws(
    () => helpers.validTeamSafetySettings(raw),
    (e) => e.code === 'failed-precondition',
  );
});

test('long native pathways survive normal hike snapshots while oversized drafts remain bounded', () => {
  const encoded = 'AA'.repeat(100000);
  const catalog = {
    trailId: 'recorded-catalog',
    name: 'Recorded pathway',
    routeEncodedPolyline: encoded,
    checkpoints: [],
  };
  const snapshot = helpers.canonicalTrailSnapshot(catalog.trailId, catalog);
  const draft = helpers.sanitizedTeamDraft(rawDraft(snapshot), snapshot, []);
  assert.equal(active(draft).trail.routeEncodedPolyline, encoded);
  assert.throws(
    () =>
      helpers.sanitizedTeamDraft(
        { ...rawDraft(snapshot), extra: 'x'.repeat(900000) },
        snapshot,
        [],
      ),
    (e) => e.code === 'invalid-argument',
  );
  assert.throws(
    () =>
      helpers.canonicalTrailSnapshot(catalog.trailId, {
        ...catalog,
        routeEncodedPolyline: 'A'.repeat(650001),
      }),
    (e) => e.code === 'invalid-argument',
  );
});

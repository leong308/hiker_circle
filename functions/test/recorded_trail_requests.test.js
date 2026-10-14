'use strict';
const test = require('node:test'),
  assert = require('node:assert/strict');
const {
  isUnlistedSessionTrail,
  unlistedTrailSnapshot,
} = require('../unlisted_hikes');
const {
  routeHash,
  validateSelections,
  validateTrack,
  beginRequest,
  finalizeRequest,
} = require('../recorded_trail_requests');
const START = '2026-10-12T00:00:00.000Z',
  END = '2026-10-12T01:00:00.000Z';
const points = [
  { lat: 5.123456789, lon: 100.123456789, time: START },
  { lat: 5.124456789, lon: 100.124456789, time: '2026-10-12T00:30:00.000Z' },
  { lat: 5.125456789, lon: 100.125456789, time: END },
];
const trail = {
  trailId: 'unlisted_1234567890',
  routeProvider: 'recorded-location-hike',
  latitude: 5.12,
  longitude: 100.12,
};
const selections = [
  { index: 0, name: 'Start' },
  { index: 1, name: 'Lookout' },
  { index: 2, name: 'Finish' },
];
const proposed = {
  name: 'Forest path',
  area: 'Hill',
  state: 'Penang',
  country: 'Malaysia',
};
function fixture() {
  const rows = new Map([
    ['users/owner', {}],
    [
      'hikeSessions/session',
      {
        userId: 'owner',
        status: 'completed',
        trail,
        startedAtLocal: START,
        endedAtLocal: END,
        durationMinutes: 60,
        distanceKm: 1,
      },
    ],
  ]);
  const snap = (path) => ({
    exists: rows.has(path),
    data: () => structuredClone(rows.get(path)),
  });
  const ref = (path) => ({
    path,
    get: async () => snap(path),
    collection: (name) => ({ orderBy: () => ({ query: `${path}/${name}` }) }),
  });
  const db = {
    doc: ref,
    runTransaction: async (fn) => {
      const writes = [];
      const result = await fn({
        get: async (r) => {
          if (r.query) {
            const docs = [...rows.entries()]
              .filter(([p]) => p.startsWith(r.query + '/'))
              .sort((a, b) => a[1].index - b[1].index)
              .map(([p]) => snap(p));
            return { docs, size: docs.length };
          }
          return snap(r.path);
        },
        create: (r, data) => writes.push(() => rows.set(r.path, data)),
        update: (r, data) =>
          writes.push(() => rows.set(r.path, { ...rows.get(r.path), ...data })),
      });
      for (const write of writes) write();
      return result;
    },
  };
  return { db, rows };
}
const data = {
  sessionId: 'session',
  pointCount: 3,
  routeHash: routeHash(points),
  checkpoints: selections,
  proposed,
};
test('unlisted hike is explicit, rejects spoofed catalog IDs and clears invented geometry', () => {
  assert.equal(isUnlistedSessionTrail(trail), true);
  assert.equal(
    isUnlistedSessionTrail({ ...trail, trailId: 'catalog-trail' }),
    false,
  );
  const safe = unlistedTrailSnapshot(trail.trailId, {
    ...trail,
    distanceKm: 99,
    checkpoints: [{ name: 'Invented' }],
    routeEncodedPolyline: 'bad',
  });
  assert.equal(safe.distanceKm, 0);
  assert.deepEqual(safe.checkpoints, []);
  assert.equal(safe.routeEncodedPolyline, undefined);
  for (const value of [undefined, NaN, 91])
    assert.throws(() =>
      unlistedTrailSnapshot(trail.trailId, { ...trail, latitude: value }),
    );
});
test('track precision is retained and checkpoint coordinates derive only from chosen sample indices', async () => {
  const f = fixture();
  const result = await beginRequest({ db: f.db, uid: 'owner', data });
  f.rows.set(`trailRequests/${result.requestId}/routeChunks/0`, {
    index: 0,
    points,
  });
  const final = await finalizeRequest({
    db: f.db,
    uid: 'owner',
    requestId: result.requestId,
  });
  assert.equal(final.status, 'pending');
  const saved = f.rows.get(`trailRequests/${result.requestId}`);
  assert.equal(saved.checkpoints[1].latitude, points[1].lat);
  assert.equal(saved.checkpoints[1].name, 'Lookout');
  assert.equal(f.rows.get('hikeSessions/session').status, 'completed');
  assert.equal(
    [...f.rows.keys()].some((p) => p.startsWith('trails/')),
    false,
  );
});
test('begin and finalize retries are idempotent and upload metadata can be corrected before submission', async () => {
  const f = fixture();
  const one = await beginRequest({ db: f.db, uid: 'owner', data });
  const two = await beginRequest({
    db: f.db,
    uid: 'owner',
    data: { ...data, proposed: { ...proposed, name: 'Corrected' } },
  });
  assert.equal(one.requestId, two.requestId);
  f.rows.set(`trailRequests/${one.requestId}/routeChunks/0`, {
    index: 0,
    points,
  });
  await finalizeRequest({ db: f.db, uid: 'owner', requestId: one.requestId });
  assert.equal(
    f.rows.get(`trailRequests/${one.requestId}`).proposed.name,
    'Corrected',
  );
  assert.equal(
    (
      await finalizeRequest({
        db: f.db,
        uid: 'owner',
        requestId: one.requestId,
      })
    ).status,
    'pending',
  );
});
test('foreign, active, catalog and disabled accounts cannot submit a trail', async () => {
  for (const patch of [
    { userId: 'other' },
    { status: 'active' },
    { trail: { ...trail, routeProvider: 'stored-polyline' } },
  ]) {
    const f = fixture();
    f.rows.set('hikeSessions/session', {
      ...f.rows.get('hikeSessions/session'),
      ...patch,
    });
    await assert.rejects(beginRequest({ db: f.db, uid: 'owner', data }));
  }
  const f = fixture();
  f.rows.set('users/owner', { accountDisabled: true });
  await assert.rejects(
    beginRequest({ db: f.db, uid: 'owner', data }),
    (e) => e.code === 'permission-denied',
  );
});
test('incomplete or modified chunks never enter the admin pending queue', async () => {
  const f = fixture();
  const { requestId } = await beginRequest({ db: f.db, uid: 'owner', data });
  await assert.rejects(finalizeRequest({ db: f.db, uid: 'owner', requestId }));
  assert.equal(f.rows.get(`trailRequests/${requestId}`).status, 'uploading');
  f.rows.set(`trailRequests/${requestId}/routeChunks/0`, {
    index: 0,
    points: points.map((p, i) => (i === 1 ? { ...p, lat: 6 } : p)),
  });
  await assert.rejects(finalizeRequest({ db: f.db, uid: 'owner', requestId }));
  assert.equal(f.rows.get(`trailRequests/${requestId}`).status, 'uploading');
});
test('track bounds, chronological timestamps and first/last checkpoint anchors are enforced', () => {
  assert.deepEqual(
    validateTrack(points, { startedAtLocal: START, endedAtLocal: END }),
    points,
  );
  for (const changed of [
    [{ ...points[0], lat: 100 }, ...points.slice(1)],
    [points[1], points[0], points[2]],
    [{ ...points[0], time: '2000-01-01' }, ...points.slice(1)],
    [{ ...points[0], hiddenData: 'secret' }, ...points.slice(1)],
  ])
    assert.throws(() =>
      validateTrack(changed, { startedAtLocal: START, endedAtLocal: END }),
    );
  for (const changed of [
    [selections[0], selections[2]],
    [selections[0], selections[1], { index: 1, name: 'Duplicated' }],
    [{ index: 1, name: 'No start' }, selections[1], selections[2]],
  ])
    assert.throws(() => validateSelections(changed, 3));
});
test('finalization prevents another user reading or submitting the recording', async () => {
  const f = fixture();
  const { requestId } = await beginRequest({ db: f.db, uid: 'owner', data });
  await assert.rejects(
    finalizeRequest({ db: f.db, uid: 'other', requestId }),
    (e) => e.code === 'permission-denied',
  );
});

test('stationary recordings are rejected but out-and-back recordings remain valid', () => {
  const session = { startedAtLocal: START, endedAtLocal: END };
  const stationary = points.map((p) => ({
    ...p,
    lat: points[0].lat,
    lon: points[0].lon,
  }));
  assert.throws(() => validateTrack(stationary, session));
  const outAndBack = [points[0], points[1], { ...points[0], time: END }];
  assert.deepEqual(validateTrack(outAndBack, session), outAndBack);
});

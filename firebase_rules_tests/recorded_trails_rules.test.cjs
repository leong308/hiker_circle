const { before, after, test } = require('node:test');
const fs = require('node:fs'),
  path = require('node:path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  setDoc,
  getDoc,
  updateDoc,
  writeBatch,
} = require('firebase/firestore');
let env, owner, other, admin;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-hiker-circle',
    firestore: {
      host: '127.0.0.1',
      port: 8181,
      rules: fs.readFileSync(
        path.resolve(__dirname, '../firestore.rules'),
        'utf8',
      ),
    },
  });
  owner = env
    .authenticatedContext('owner', { phoneNumber: '+600000001' })
    .firestore();
  other = env
    .authenticatedContext('other', { phoneNumber: '+600000002' })
    .firestore();
  admin = env
    .authenticatedContext('admin', { phoneNumber: '+600000003', isAdmin: true })
    .firestore();
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'trailRequests/request'), {
      ownerId: 'owner',
      status: 'uploading',
      chunkCount: 2,
      pointCount: 600,
    });
  });
});
after(async () => env?.cleanup());
const points = [{ lat: 5.1, lon: 100.1, time: '2026-10-12T00:00:00.000Z' }];
test('only the hiker and admins can read a private request and its recording', async () => {
  await assertSucceeds(getDoc(doc(owner, 'trailRequests/request')));
  await assertSucceeds(getDoc(doc(admin, 'trailRequests/request')));
  await assertFails(getDoc(doc(other, 'trailRequests/request')));
  await assertFails(
    getDoc(
      doc(env.unauthenticatedContext().firestore(), 'trailRequests/request'),
    ),
  );
  await assertSucceeds(
    setDoc(doc(owner, 'trailRequests/request/routeChunks/0'), {
      index: 0,
      points,
    }),
  );
  await assertFails(getDoc(doc(other, 'trailRequests/request/routeChunks/0')));
});
test('chunk uploads are bounded and cannot forge manifests or enter the queue', async () => {
  await assertFails(
    setDoc(doc(other, 'trailRequests/request/routeChunks/1'), {
      index: 1,
      points,
    }),
  );
  await assertFails(
    setDoc(doc(owner, 'trailRequests/request/routeChunks/2'), {
      index: 2,
      points,
    }),
  );
  await assertFails(
    setDoc(doc(owner, 'trailRequests/request/routeChunks/1'), {
      index: 0,
      points,
    }),
  );
  await assertFails(
    setDoc(doc(owner, 'trailRequests/request/routeChunks/1'), {
      index: 1,
      points: Array(501).fill(points[0]),
    }),
  );
  await assertFails(
    updateDoc(doc(owner, 'trailRequests/request'), { status: 'pending' }),
  );
  await assertFails(
    setDoc(doc(owner, 'trailRequests/forged'), {
      ownerId: 'owner',
      status: 'pending',
    }),
  );
});
test('pending recordings are immutable; only admins can publish native trail geometry', async () => {
  await env.withSecurityRulesDisabled((c) =>
    updateDoc(doc(c.firestore(), 'trailRequests/request'), {
      status: 'pending',
    }),
  );
  await assertFails(
    setDoc(doc(owner, 'trailRequests/request/routeChunks/0'), {
      index: 0,
      points,
    }),
  );
  await assertFails(
    updateDoc(doc(owner, 'trailRequests/request'), { status: 'approved' }),
  );
  await assertFails(setDoc(doc(owner, 'trails/new'), { name: 'Forged' }));
  const batch = writeBatch(admin);
  batch.set(doc(admin, 'trails/new'), { name: 'Recorded route' });
  batch.set(doc(admin, 'trails/new/routeGeometry/hash'), {
    pointCount: 600,
    chunkCount: 2,
  });
  batch.set(doc(admin, 'trails/new/routeGeometry/hash/chunks/0'), {
    index: 0,
    points,
  });
  batch.update(doc(admin, 'trailRequests/request'), {
    status: 'approved',
    publishedTrailId: 'new',
    reviewedByAdminId: 'admin',
  });
  await assertSucceeds(batch.commit());
  await assertSucceeds(
    getDoc(doc(owner, 'trails/new/routeGeometry/hash/chunks/0')),
  );
  await assertFails(
    updateDoc(doc(admin, 'trailRequests/request'), { status: 'rejected' }),
  );
});

test('real Firestore transactions finalize an owned chunked recording without publishing a catalog trail', async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw Error('Emulator required');
  const runtimeRequire = require('node:module').createRequire(
    path.resolve(__dirname, '../functions/index.js'),
  );
  const { initializeApp, deleteApp } = runtimeRequire('firebase-admin/app');
  const { getFirestore } = runtimeRequire('firebase-admin/firestore');
  const {
    beginRequest,
    finalizeRequest,
    routeHash,
  } = require('../functions/recorded_trail_requests');
  const app = initializeApp(
    { projectId: 'demo-hiker-circle' },
    'recorded-route-integration',
  );
  try {
    const db = getFirestore(app);
    const samples = Array.from({ length: 600 }, (_, i) => ({
      lat: 5.123456789 + i * 0.00001,
      lon: 100.123456789 + i * 0.00001,
      time: new Date(
        Date.parse('2026-10-12T00:00:00Z') + i * 5000,
      ).toISOString(),
    }));
    await db.doc('users/owner').set({ accountDisabled: false });
    await db.doc('hikeSessions/location_session').set({
      userId: 'owner',
      status: 'completed',
      trail: {
        trailId: 'unlisted_1234567890',
        routeProvider: 'recorded-location-hike',
      },
      startedAtLocal: samples[0].time,
      endedAtLocal: samples.at(-1).time,
      durationMinutes: 50,
      distanceKm: 1,
    });
    const result = await beginRequest({
      db,
      uid: 'owner',
      data: {
        sessionId: 'location_session',
        proposed: {
          name: 'Demo route',
          area: 'Demo',
          state: 'Penang',
          country: 'Malaysia',
        },
        pointCount: samples.length,
        routeHash: routeHash(samples),
        checkpoints: [
          { index: 0, name: 'Start' },
          { index: 300, name: 'Lookout' },
          { index: 599, name: 'Finish' },
        ],
      },
    });
    await assertSucceeds(
      setDoc(doc(owner, `trailRequests/${result.requestId}/routeChunks/0`), {
        index: 0,
        points: samples.slice(0, 500),
      }),
    );
    await assertSucceeds(
      setDoc(doc(owner, `trailRequests/${result.requestId}/routeChunks/1`), {
        index: 1,
        points: samples.slice(500),
      }),
    );
    const finalized = await finalizeRequest({
      db,
      uid: 'owner',
      requestId: result.requestId,
    });
    if (finalized.status !== 'pending') throw Error('Did not finalize');
    const request = (
      await db.doc(`trailRequests/${result.requestId}`).get()
    ).data();
    if (request.checkpoints[1].latitude !== samples[300].lat)
      throw Error('Coordinates changed');
    await assertFails(
      setDoc(doc(owner, `trailRequests/${result.requestId}/routeChunks/0`), {
        index: 0,
        points: samples.slice(0, 500),
      }),
    );
  } finally {
    await deleteApp(app);
  }
});

test('production callables start, restore and complete location hikes without a catalog document', async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw Error('Emulator required');
  const runtimeRequire = require('node:module').createRequire(
    path.resolve(__dirname, '../functions/index.js'),
  );
  const { getFirestore } = runtimeRequire('firebase-admin/firestore');
  const { getApp, deleteApp } = runtimeRequire('firebase-admin/app');
  const callables = runtimeRequire('./index.js');
  const phone = '+60100000001';
  const auth = { uid: phone, token: { phoneNumber: phone } };
  const db = getFirestore();
  const hikerDb = env
    .authenticatedContext(phone, { phoneNumber: phone })
    .firestore();
  try {
    await db.doc(`users/${phone}`).set({ accountDisabled: false });
    for (const [index, mode] of [
      'online',
      'offline-restore',
      'offline-end',
    ].entries()) {
      const started = Date.now() - 300000 + index;
      const ended = Date.now();
      const draft = {
        trail: {
          trailId: `unlisted_123456789${index}`,
          routeProvider: 'recorded-location-hike',
          latitude: 5.123456789,
          longitude: 100.123456789,
        },
        departureTime: new Date(started).toISOString(),
        expectedArrivalTime: new Date(ended + 3600000).toISOString(),
        expectedReturnTime: new Date(ended + 3600000).toISOString(),
        pathDeviationEnabled: true,
      };
      let sessionId = `session_${started}`;
      if (mode === 'online') {
        const result = await callables.startActiveHikeSession.run({
          auth,
          data: {
            draft,
            creationKey: sessionId,
            startedAtLocal: draft.departureTime,
          },
        });
        sessionId = result.sessionId;
      } else if (mode === 'offline-restore') {
        const result = await callables.ensureActiveHikeSessionInCloud.run({
          auth,
          data: { sessionId, draft, startedAtLocal: draft.departureTime },
        });
        sessionId = result.sessionId;
      }
      const completion = await callables.completeActiveHikeSession.run({
        auth,
        data: {
          sessionId,
          draft,
          startedAtLocal: draft.departureTime,
          endedAtLocal: new Date(ended).toISOString(),
          summary: { distanceKm: 0.4, routePointCount: 3 },
        },
      });
      if (!completion.completed) throw Error('Completion failed');
      sessionId = completion.sessionId;
      const saved = (await db.doc(`hikeSessions/${sessionId}`).get()).data();
      if (
        saved.trail.routeProvider !== 'recorded-location-hike' ||
        saved.pathDeviationEnabled !== false ||
        saved.checkpoints.length !== 0
      )
        throw Error('Location hike was not preserved');
      if ((await db.doc(`trails/${draft.trail.trailId}`).get()).exists)
        throw Error('Private hike created a catalog trail');
      const samples = [0, 1, 2].map((i) => ({
        lat: 5.123456789 + i * 0.001,
        lon: 100.123456789 + i * 0.001,
        time: new Date(started + (i * (ended - started)) / 2).toISOString(),
      }));
      const { routeHash } = require('../functions/recorded_trail_requests');
      const begun = await callables.beginRecordedTrailRequest.run({
        auth,
        data: {
          sessionId,
          pointCount: 3,
          routeHash: routeHash(samples),
          checkpoints: samples.map((_, i) => ({ index: i, name: `Stop ${i}` })),
          proposed: {
            name: 'Demo',
            area: 'Forest',
            state: 'Penang',
            country: 'Malaysia',
          },
        },
      });
      await assertSucceeds(
        setDoc(doc(hikerDb, `trailRequests/${begun.requestId}/routeChunks/0`), {
          index: 0,
          points: samples,
        }),
      );
      const submitted = await callables.finalizeRecordedTrailRequest.run({
        auth,
        data: { requestId: begun.requestId },
      });
      if (submitted.status !== 'pending') throw Error('Submission failed');
    }
    const encoded = 'AA'.repeat(100000);
    const catalog = {
      trailId: 'native_long_recording',
      name: 'Recorded native trail',
      routeEncodedPolyline: encoded,
      checkpoints: [],
      latitude: 5.1,
      longitude: 100.1,
      distanceKm: 2,
      estimatedDurationMinutes: 120,
    };
    await db.doc(`trails/${catalog.trailId}`).set(catalog);
    const started = Date.now();
    const draft = {
      trail: catalog,
      departureTime: new Date(started).toISOString(),
      expectedArrivalTime: new Date(started + 3600000).toISOString(),
      expectedReturnTime: new Date(started + 3600000).toISOString(),
    };
    const launched = await callables.startActiveHikeSession.run({
      auth,
      data: {
        draft,
        creationKey: 'long_route_hike',
        startedAtLocal: draft.departureTime,
      },
    });
    const nativeSession = (
      await db.doc(`hikeSessions/${launched.sessionId}`).get()
    ).data();
    if (nativeSession.trail.routeEncodedPolyline !== encoded)
      throw Error('Native pathway was truncated');
    const scheduledDraft = {
      ...draft,
      departureTime: new Date(started + 3600000).toISOString(),
      expectedArrivalTime: new Date(started + 7200000).toISOString(),
      expectedReturnTime: new Date(started + 7200000).toISOString(),
    };
    await callables.scheduleUpcomingHike.run({
      auth,
      data: { draft: scheduledDraft, creationKey: 'long_route_schedule' },
    });
  } finally {
    await deleteApp(getApp());
  }
});

'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {schedulerJobName, createSchedulerClient, withMonitorRunLease} = require('../active_hike_monitor_schedule');
const {upcomingMembershipChanged, reconcileUpcomingHikeOperations, withUpcomingRunLease} = require('../upcoming_hike_schedule');

function fixture(listings, state = 'PAUSED') {
  const rows = new Map();
  let queue = Promise.resolve();
  const data = {listings, state, mutations: [], now: 1000};
  const snapshot = path => ({data: () => structuredClone(rows.get(path))});
  const db = {
    collection(name) {
      if (name === 'maintenanceState') return {doc: id => {
        const path = `${name}/${id}`;
        return {path, get: async () => snapshot(path)};
      }};
      assert.equal(name, 'upcomingHikes');
      return {where(field, op, value) {
        assert.deepEqual([field, op, value], ['isDeleted', '==', false]); return this;
      }, limit(n) {assert.equal(n, 1); return this;}, select() {return this;},
      get: async () => ({empty: !data.listings})};
    },
    runTransaction(callback) {
      const next = queue.then(async () => {
        const writes = [];
        const result = await callback({get: async ref => snapshot(ref.path),
          set: (ref, patch) => writes.push(() => rows.set(ref.path, {...rows.get(ref.path), ...patch}))});
        writes.forEach(write => write()); return result;
      });
      queue = next.catch(() => {}); return next;
    },
  };
  const scheduler = {name: schedulerJobName('hiker-circle', 'processUpcomingHikeOperations'),
    get: async () => ({state: data.state}),
    pause: async () => {data.mutations.push('pause'); data.state = 'PAUSED'; return {state: data.state};},
    resume: async () => {data.mutations.push('resume'); data.state = 'ENABLED'; return {state: data.state};}};
  return {db, scheduler, data, rows, now: () => data.now};
}

test('listing creation, cancellation, expiry, restoration and physical deletion change membership', () => {
  const live = {isDeleted: false};
  for (const [before, after] of [[null, live], [live, {isDeleted: true}],
    [{isDeleted: true}, live], [live, null]]) assert.equal(upcomingMembershipChanged(before, after), true);
  for (const [before, after] of [[live, {...live, participantPhones: ['member']}],
    [live, {...live, departureTimeLocal: 'tomorrow'}], [null, {isDeleted: true}],
    [{isDeleted: true}, null], [null, {}]]) assert.equal(upcomingMembershipChanged(before, after), false);
});
test('first listing resumes one job; more listings and duplicate events do not repeat resume', async () => {
  const f = fixture(true);
  await reconcileUpcomingHikeOperations(f);
  await reconcileUpcomingHikeOperations(f);
  assert.deepEqual(f.data.mutations, ['resume']);
  assert.equal(f.rows.get('maintenanceState/upcomingHikeOperationsSchedule').hasUpcomingListing, true);
  assert.equal(f.rows.has('maintenanceState/activeHikeMonitorSchedule'), false);
});
test('one remaining listing keeps enabled; last removal pauses once; stale event uses current truth', async () => {
  const f = fixture(true, 'ENABLED');
  await reconcileUpcomingHikeOperations(f);
  assert.deepEqual(f.data.mutations, []);
  f.data.listings = false;
  await reconcileUpcomingHikeOperations(f);
  await reconcileUpcomingHikeOperations(f);
  assert.deepEqual(f.data.mutations, ['pause']);
  f.data.listings = true;
  await reconcileUpcomingHikeOperations(f);
  assert.deepEqual(f.data.mutations, ['pause', 'resume']);
});
test('creation during pause and last removal during resume are rechecked', async () => {
  const f = fixture(false, 'ENABLED');
  const pause = f.scheduler.pause;
  f.scheduler.pause = async () => {const result = await pause(); f.data.listings = true; return result;};
  await reconcileUpcomingHikeOperations(f);
  assert.deepEqual(f.data.mutations, ['pause', 'resume']);
  const g = fixture(true);
  const resume = g.scheduler.resume;
  g.scheduler.resume = async () => {const result = await resume(); g.data.listings = false; return result;};
  await reconcileUpcomingHikeOperations(g);
  assert.deepEqual(g.data.mutations, ['resume', 'pause']);
});
test('competing controllers retry; transport failure releases lease; crashed owner recovers', async () => {
  const f = fixture(true);
  f.rows.set('maintenanceState/upcomingHikeOperationsSchedule', {leaseOwner: 'crashed', leaseExpiresAtMillis: 999});
  const resume = f.scheduler.resume;
  f.scheduler.resume = async () => {throw new Error('transport');};
  await assert.rejects(reconcileUpcomingHikeOperations(f), /transport/);
  assert.equal(f.rows.get('maintenanceState/upcomingHikeOperationsSchedule').leaseOwner, null);
  f.scheduler.resume = resume;
  await Promise.all([reconcileUpcomingHikeOperations(f), reconcileUpcomingHikeOperations(f).catch(error => {
    assert.equal(error.code, 'scheduler-control-busy');
  })]);
  await reconcileUpcomingHikeOperations(f);
  assert.deepEqual(f.data.mutations, ['resume']);
});
test('upcoming run lease exceeds its deadline, blocks overlap, and is separate from active monitoring', async () => {
  const f = fixture(true);
  let release, started;
  const gate = new Promise(resolve => {release = resolve;});
  const ready = new Promise(resolve => {started = resolve;});
  const first = withUpcomingRunLease(f.db, async () => {started(); await gate;}, f.now);
  await ready;
  assert.equal(f.rows.get('maintenanceState/upcomingHikeOperationsRun').leaseExpiresAtMillis, 601000);
  assert.deepEqual(await withUpcomingRunLease(f.db, () => assert.fail('overlap'), f.now), {skipped: true});
  assert.equal(await withMonitorRunLease(f.db, async () => 'active', f.now), 'active');
  release(); await first;
});
test('completed ticks do not repeat while failed ticks retry after lease release', async () => {
  const f = fixture(true);
  const tick = '2026-10-04T07:00:00Z';
  await assert.rejects(withUpcomingRunLease(f.db, async () => {throw new Error('failed');}, f.now, tick));
  let calls = 0;
  await withUpcomingRunLease(f.db, async () => {calls++;}, f.now, tick);
  await withUpcomingRunLease(f.db, async () => {calls++;}, f.now, tick);
  assert.equal(calls, 1);
});
test('Scheduler transport only targets the allowlisted existing upcoming job', async () => {
  const urls = [];
  const client = createSchedulerClient({projectId: 'hiker-circle', functionName: 'processUpcomingHikeOperations',
    accessToken: async () => 'private', fetchImpl: async url => {
      urls.push(url); return {ok: true, json: async () => ({state: 'ENABLED'})};
    }});
  await client.get(); await client.resume(); await client.pause();
  assert.equal(client.create, undefined);
  assert.ok(urls.every(url => url.includes('/jobs/firebase-schedule-processUpcomingHikeOperations-us-central1')));
  assert.throws(() => schedulerJobName('hiker-circle', '../other'), /Invalid/);
});

const source = fs.readFileSync(require.resolve('../index'), 'utf8');
test('expiry soft-hides legacy expired-but-not-deleted listings so they cannot keep the schedule alive', async () => {
  const start = source.indexOf('async function processUpcomingHikeLifecycleTask(');
  const block = source.slice(start, source.indexOf('async function reconcileUpcomingHikeOperationsSchedule()', start));
  const writes = [];
  const worker = vm.runInNewContext(block + '\nprocessUpcomingHikeLifecycleTask', {
    Date, Number, logger: {log() {}}, dateMillis: value => Date.parse(value),
    admin: {firestore: {FieldValue: {serverTimestamp: () => 'server-time'}}},
  });
  const now = Date.parse('2026-10-04T07:00:00Z');
  await worker({db: {}, now, snapshot: {docs: [{
    data: () => ({isDeleted: false, expired: true, departureTimeLocal: '2026-10-04T06:44:00Z'}),
    ref: {set: async patch => writes.push(patch)},
  }]}});
  assert.equal(writes.length, 1); assert.equal(writes[0].isDeleted, true);
  assert.equal(writes[0].deletedReason, 'departure_time_expired');
});
test('runtime wrapper uses modular Admin credentials and the upcoming job rather than active monitor', async () => {
  const start = source.indexOf('async function reconcileUpcomingHikeOperationsSchedule()');
  const block = source.slice(start, source.indexOf('exports.reconcileUpcomingHikeOperationsOnWrite', start));
  let config;
  const wrapper = vm.runInNewContext(block + '\nreconcileUpcomingHikeOperationsSchedule', {
    getApp: () => ({options: {projectId: 'hiker-circle', credential: {
      getAccessToken: async () => ({access_token: 'private'}),
    }}}), process: {env: {}}, admin: {firestore: () => ({})}, logger: {log() {}},
    createSchedulerClient: options => {config = options; return {};},
    reconcileUpcomingHikeOperations: async () => ({state: 'PAUSED'}),
  });
  assert.equal((await wrapper()).state, 'PAUSED');
  assert.equal(config.functionName, 'processUpcomingHikeOperations');
  assert.equal(await config.accessToken(), 'private');
});
test('retry-enabled write trigger handles create/remove but ignores notification/participant changes', async () => {
  const start = source.indexOf('exports.reconcileUpcomingHikeOperationsOnWrite =');
  const block = source.slice(start, source.indexOf('exports.processUpcomingHikeOperations =', start));
  let config, calls = 0;
  const handler = vm.runInNewContext(block + '\nexports.reconcileUpcomingHikeOperationsOnWrite', {
    exports: {}, onDocumentWritten: (options, fn) => {config = options; return fn;},
    upcomingMembershipChanged, reconcileUpcomingHikeOperationsSchedule: async () => {calls++;},
  });
  assert.equal(config.retry, true); assert.equal(config.timeoutSeconds, 60);
  const event = (before, after) => ({data: {before: {data: () => before}, after: {data: () => after}}});
  await handler(event(undefined, {isDeleted: false}));
  await handler(event({isDeleted: false}, {isDeleted: false, nearbyNotificationSentAt: 'now'}));
  await handler(event({isDeleted: false}, undefined));
  assert.equal(calls, 2);
});
test('scheduled worker reconciles empty snapshot and also after task failure/last expiry', async () => {
  const start = source.indexOf('exports.processUpcomingHikeOperations =');
  const block = source.slice(start, source.indexOf('async function abandonInactiveHikeDocument', start));
  for (const scenario of ['empty', 'last-expired', 'failure']) {
    let reconciled = 0, tasks = 0, config;
    const handler = vm.runInNewContext(block + '\nexports.processUpcomingHikeOperations', {
      exports: {}, Date, admin: {firestore: () => ({collection: () => ({where: () => ({get: async () => ({empty: scenario === 'empty'})})})})},
      onSchedule: (options, fn) => {config = options; return fn;},
      withUpcomingRunLease: async (_db, work) => work(),
      reconcileUpcomingHikeOperationsSchedule: async () => {reconciled++;},
      processUpcomingHikeLifecycleTask: () => {}, userDocumentIdForPhone: () => {}, latestFcmTokensForUser: () => {},
      logger: {error() {}}, runMaintenanceTasks: async () => {tasks++; if (scenario === 'failure') throw new Error('task failed');},
    });
    assert.equal(config.schedule, 'every 5 minutes'); assert.equal(config.maxInstances, 1);
    assert.equal(config.concurrency, 1); assert.equal(config.retryCount, 3);
    if (scenario === 'failure') await assert.rejects(handler({scheduleTime: '2026-10-04T07:00:00Z'}), /task failed/);
    else await handler({scheduleTime: '2026-10-04T07:00:00Z'});
    assert.equal(reconciled, 1); assert.equal(tasks, scenario === 'empty' ? 0 : 1);
  }
});

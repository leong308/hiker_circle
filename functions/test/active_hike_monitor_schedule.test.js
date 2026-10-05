'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {activeMembershipChanged, schedulerJobName, createSchedulerClient,
  reconcileActiveHikeMonitor, withMonitorRunLease, LEASE_MILLIS} = require('../active_hike_monitor_schedule');
function fixture(active, state = 'PAUSED') {
  const rows = new Map();
  let queue = Promise.resolve();
  const data = {active, state, reads: 0, mutations: [], now: 1000};
  const ref = path => ({path, get: async () => snapshot(path)});
  const snapshot = path => ({exists: rows.has(path), data: () => structuredClone(rows.get(path))});
  const db = {
    collection: name => name === 'maintenanceState' ? {doc: id => ref(`${name}/${id}`)} : {
      where(field, op, value) {
        assert.deepEqual([field, op, value], ['status', '==', 'active']); return this;
      },
      limit(count) {assert.equal(count, 1); return this;},
      select() {return this;},
      get: async () => {data.reads++; return {empty: !data.active};},
    },
    runTransaction(callback) {
      const run = queue.then(async () => {
        const writes = [];
        const result = await callback({get: async reference => snapshot(reference.path),
          set: (reference, patch) => writes.push(() => rows.set(reference.path,
            {...rows.get(reference.path), ...structuredClone(patch)}))});
        writes.forEach(write => write());
        return result;
      });
      queue = run.catch(() => {});
      return run;
    },
  };
  const scheduler = {name: schedulerJobName('hiker-circle'), get: async () => ({state: data.state}),
    pause: async () => {data.mutations.push('pause'); data.state = 'PAUSED'; return {state: data.state};},
    resume: async () => {data.mutations.push('resume'); data.state = 'ENABLED'; return {state: data.state};}};
  return {data, db, rows, scheduler, now: () => data.now};
}
test('only entry/exit of active membership affects the scheduler, not heartbeat updates', () => {
  assert.equal(activeMembershipChanged(null, {status: 'active'}), true);
  assert.equal(activeMembershipChanged({status: 'active'}, {status: 'completed'}), true);
  assert.equal(activeMembershipChanged({status: 'active'}, null), true);
  assert.equal(activeMembershipChanged({status: 'active'}, {status: 'active'}), false);
  assert.equal(activeMembershipChanged(null, {status: 'completed'}), false);
  assert.equal(activeMembershipChanged({status: 'completed'}, {status: 'abandoned'}), false);
});
test('first active hike resumes the same job once; other hikers and duplicate events do not resume again', async () => {
  const f = fixture(true);
  await reconcileActiveHikeMonitor(f);
  await Promise.all([reconcileActiveHikeMonitor(f), reconcileActiveHikeMonitor(f).catch(error => {
    assert.equal(error.code, 'scheduler-control-busy');
  })]);
  await reconcileActiveHikeMonitor(f); // A retried/out-of-order event reads current truth.
  assert.deepEqual(f.data.mutations, ['resume']);
  assert.equal(f.data.state, 'ENABLED');
});
test('one remaining active hiker keeps the schedule enabled; last end pauses it once', async () => {
  const f = fixture(true, 'ENABLED');
  await reconcileActiveHikeMonitor(f);
  assert.deepEqual(f.data.mutations, []);
  f.data.active = false;
  await reconcileActiveHikeMonitor(f);
  await reconcileActiveHikeMonitor(f);
  assert.deepEqual(f.data.mutations, ['pause']);
});
test('an old end event cannot pause the schedule when another hike is currently active', async () => {
  const f = fixture(true, 'ENABLED');
  await reconcileActiveHikeMonitor(f);
  assert.equal(f.data.state, 'ENABLED');
  assert.deepEqual(f.data.mutations, []);
});
test('a new hike appearing during pause is rechecked and immediately resumes the same job', async () => {
  const f = fixture(false, 'ENABLED');
  const pause = f.scheduler.pause;
  f.scheduler.pause = async () => {const result = await pause(); f.data.active = true; return result;};
  await reconcileActiveHikeMonitor(f);
  assert.deepEqual(f.data.mutations, ['pause', 'resume']);
  assert.equal(f.data.state, 'ENABLED');
});
test('last hike ending during resume is rechecked and pauses the job', async () => {
  const f = fixture(true);
  const resume = f.scheduler.resume;
  f.scheduler.resume = async () => {const result = await resume(); f.data.active = false; return result;};
  await reconcileActiveHikeMonitor(f);
  assert.deepEqual(f.data.mutations, ['resume', 'pause']);
  assert.equal(f.data.state, 'PAUSED');
});
test('permission/transport failure releases control and retry converges without duplicating the job', async () => {
  const f = fixture(true);
  const resume = f.scheduler.resume;
  f.scheduler.resume = async () => {throw Object.assign(new Error('denied'), {code: 'scheduler-http-403'});};
  await assert.rejects(reconcileActiveHikeMonitor(f), /denied/);
  assert.equal(f.rows.get('maintenanceState/activeHikeMonitorSchedule').leaseOwner, null);
  f.scheduler.resume = resume;
  await reconcileActiveHikeMonitor(f);
  assert.deepEqual(f.data.mutations, ['resume']);
});
test('a crashed controller lease can be reclaimed, and expired owners cannot mutate the scheduler', async () => {
  const f = fixture(true);
  f.rows.set('maintenanceState/activeHikeMonitorSchedule', {leaseOwner: 'crashed', leaseExpiresAtMillis: 999});
  await reconcileActiveHikeMonitor(f);
  assert.equal(f.data.state, 'ENABLED');
  f.data.state = 'PAUSED';
  f.scheduler.get = async () => {f.data.now += LEASE_MILLIS + 1; return {state: 'PAUSED'};};
  await assert.rejects(reconcileActiveHikeMonitor(f), /lease expired/);
  assert.deepEqual(f.data.mutations, ['resume']);
});
test('overlapping monitor ticks skip duplicate work and release their lease on failure', async () => {
  const f = fixture(true);
  let started, finish;
  const gate = new Promise(resolve => {finish = resolve;});
  const ready = new Promise(resolve => {started = resolve;});
  const first = withMonitorRunLease(f.db, async () => {started(); await gate; return 'done';}, f.now);
  await ready;
  assert.deepEqual(await withMonitorRunLease(f.db, () => assert.fail('duplicate work'), f.now), {skipped: true});
  finish();
  assert.equal(await first, 'done');
  await assert.rejects(withMonitorRunLease(f.db, async () => {throw new Error('work failed');}, f.now));
  assert.equal(f.rows.get('maintenanceState/activeHikeMonitorRun').leaseOwner, null);
});
test('invalid/missing scheduler jobs are surfaced, never created or silently ignored', async () => {
  const f = fixture(true, 'UPDATE_FAILED');
  await assert.rejects(reconcileActiveHikeMonitor(f), /controllable/);
  const client = createSchedulerClient({projectId: 'hiker-circle', accessToken: async () => 'private',
    fetchImpl: async () => ({ok: false, status: 404})});
  await assert.rejects(client.get(), /HTTP 404/);
  assert.equal(client.create, undefined);
});
test('completed or older schedule deliveries do not run twice, while failed deliveries can retry', async () => {
  const f = fixture(true);
  const tick = '2026-10-04T01:02:00Z';
  let count = 0;
  const work = () => {count++;};
  await withMonitorRunLease(f.db, work, f.now, tick);
  await withMonitorRunLease(f.db, work, f.now, tick);
  await withMonitorRunLease(f.db, work, f.now, '2026-10-04T01:00:00Z');
  assert.equal(count, 1);
  const next = '2026-10-04T01:04:00Z';
  await assert.rejects(withMonitorRunLease(f.db, async () => {throw new Error('failed');}, f.now, next));
  await withMonitorRunLease(f.db, work, f.now, next);
  assert.equal(count, 2);
});
test('Scheduler transport uses one fixed job and empty pause/resume requests', async () => {
  const requests = [];
  const client = createSchedulerClient({projectId: 'hiker-circle', accessToken: async () => 'private',
    fetchImpl: async (url, options) => {
      requests.push({url, options});
      return {ok: true, json: async () => ({state: url.endsWith(':pause') ? 'PAUSED' : 'ENABLED'})};
    }});
  await client.get(); await client.pause(); await client.resume();
  assert.deepEqual(requests.map(r => r.options.method), ['GET', 'POST', 'POST']);
  for (const request of requests) {
    assert.ok(request.url.includes('/jobs/firebase-schedule-monitorActiveHikes-us-central1'));
    assert.equal(request.options.body, undefined);
  }
  assert.throws(() => schedulerJobName('../other-project'), /Invalid/);
});
test('existing lifecycle triggers reconcile status changes and deletes, with retries, without another trigger', () => {
  const source = fs.readFileSync(require.resolve('../index'), 'utf8');
  assert.match(source, /activeMembershipChanged\(null, hike\)/);
  assert.match(source, /activeMembershipChanged\(before, after\)/);
  assert.match(source, /activeMembershipChanged\(hike, null\)/);
  assert.match(source, /preserveDeletedHikeTerminalState = onDocumentDeleted\([\s\S]*?retry: true/);
  assert.match(source, /maxInstances: 1, concurrency: 1/);
  assert.match(source, /snapshot\.empty[\s\S]*?reconcileActiveHikeMonitorSchedule/);
});
test('runtime scheduler wrapper uses the supported modular Admin app credential', async () => {
  const {initializeApp, getApp, deleteApp} = require('firebase-admin/app');
  const name = 'monitor-credential-regression';
  initializeApp({projectId: 'hiker-circle'}, name);
  assert.equal(typeof getApp(name).options.credential.getAccessToken, 'function');
  await deleteApp(getApp(name));
  const source = fs.readFileSync(require.resolve('../index'), 'utf8');
  const start = source.indexOf('async function reconcileActiveHikeMonitorSchedule()');
  const wrapper = source.slice(start, source.indexOf('exports.monitorActiveHikes =', start));
  assert.doesNotMatch(wrapper, /admin\.app\(/);
  let config;
  const fn = vm.runInNewContext(wrapper + '\nreconcileActiveHikeMonitorSchedule', {
    getApp: () => ({options: {projectId: 'hiker-circle', credential: {
      getAccessToken: async () => ({access_token: 'private-credential'}),
    }}}),
    process: {env: {}}, createSchedulerClient: options => {config = options; return {};},
    reconcileActiveHikeMonitor: async () => ({state: 'PAUSED'}),
    admin: {firestore: () => ({})}, logger: {log() {}},
  });
  assert.equal((await fn()).state, 'PAUSED');
  assert.equal(config.projectId, 'hiker-circle');
  assert.equal(await config.accessToken(), 'private-credential');
});

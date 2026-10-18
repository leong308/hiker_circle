// Firestore leases coordinate active-hike and upcoming-hike Cloud Scheduler jobs without duplicate workers.
'use strict';
const {randomUUID} = require('node:crypto');
const CONTROL_DOCUMENT = 'activeHikeMonitorSchedule';
const RUN_DOCUMENT = 'activeHikeMonitorRun';
const LEASE_MILLIS = 120000;

function activeMembershipChanged(before, after) {
  return (before?.status === 'active') !== (after?.status === 'active');
}
function schedulerJobName(projectId, functionName = 'monitorActiveHikes') {
  if (!/^[a-z][a-z0-9-]{4,62}$/.test(projectId || '')) throw new Error('Invalid scheduler project.');
  if (!['monitorActiveHikes', 'processUpcomingHikeOperations'].includes(functionName)) {
    throw new Error('Invalid scheduler function.');
  }
  return `projects/${projectId}/locations/us-central1/jobs/firebase-schedule-${functionName}-us-central1`;
}
function createSchedulerClient({projectId, accessToken, fetchImpl = fetch, functionName}) {
  const name = schedulerJobName(projectId, functionName);
  async function request(action) {
    const token = await accessToken();
    const response = await fetchImpl(`https://cloudscheduler.googleapis.com/v1/${name}${action ? ':' + action : ''}`, {
      method: action ? 'POST' : 'GET',
      headers: {Authorization: `Bearer ${token}`},
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) {
      const error = new Error(`Hike scheduler ${action || 'read'} failed (HTTP ${response.status}).`);
      error.code = `scheduler-http-${response.status}`;
      throw error; // Never log the access token, response body or create another job.
    }
    return response.json();
  }
  return {name, get: () => request(), pause: () => request('pause'), resume: () => request('resume')};
}
// acquireLease: Fence competing scheduler controllers and already completed schedule ticks.
async function acquireLease(db, documentId, now = Date.now, tickMillis, leaseMillis = LEASE_MILLIS) {
  const ref = db.collection('maintenanceState').doc(documentId);
  const owner = randomUUID();
  const claimed = await db.runTransaction(async tx => {
    const snapshot = await tx.get(ref);
    const current = snapshot.data() || {};
    if (Number.isFinite(tickMillis) && Number(current.lastCompletedTickMillis) >= tickMillis) return false;
    if (current.leaseOwner && Number(current.leaseExpiresAtMillis) > now()) return false;
    tx.set(ref, {leaseOwner: owner, leaseExpiresAtMillis: now() + leaseMillis}, {merge: true});
    return true;
  });
  return claimed ? {ref, owner} : null;
}
async function releaseLease(db, lease, details = {}) {
  await db.runTransaction(async tx => {
    const snapshot = await tx.get(lease.ref);
    if (snapshot.data()?.leaseOwner !== lease.owner) return;
    tx.set(lease.ref, {...details, leaseOwner: null, leaseExpiresAtMillis: 0}, {merge: true});
  });
}
async function assertLease(db, lease, now) {
  const snapshot = await lease.ref.get();
  if (snapshot.data()?.leaseOwner !== lease.owner || Number(snapshot.data()?.leaseExpiresAtMillis) <= now()) {
    throw new Error('Active hike scheduler lease expired.');
  }
}
async function hasActiveHike(db) {
  return !(await db.collection('hikeSessions').where('status', '==', 'active').limit(1).select().get()).empty;
}
async function reconcileActiveHikeMonitor({db, scheduler, now = Date.now}) {
  return reconcileHikeSchedule({db, scheduler, now, controlDocument: CONTROL_DOCUMENT,
    hasWork: hasActiveHike, membershipField: 'hasActiveHike'});
}
// reconcileHikeSchedule: Recheck current work around pause/resume calls so membership races converge on the existing job.
async function reconcileHikeSchedule({db, scheduler, now = Date.now, controlDocument, hasWork, membershipField}) {
  const lease = await acquireLease(db, controlDocument, now);
  if (!lease) {
    const error = new Error('Active hike scheduler reconciliation is already running; retry this event.');
    error.code = 'scheduler-control-busy';
    throw error; // Lifecycle triggers retry: a crashed owner cannot swallow a wake-up event.
  }
  let details = {};
  try {
    for (let pass = 0; pass < 3; pass++) {
      const active = await hasWork(db);
      const desiredState = active ? 'ENABLED' : 'PAUSED';
      const job = await scheduler.get();
      if (!['ENABLED', 'PAUSED'].includes(job.state)) {
        throw new Error('Active hike scheduler is not in a controllable state.');
      }
      await assertLease(db, lease, now);
      if (job.state !== desiredState) {
        const updated = await scheduler[active ? 'resume' : 'pause']();
        if (updated.state !== desiredState) throw new Error('Active hike scheduler state change was not confirmed.');
      }
      // A first-start/last-end race must be decided using live data, not event order.
      if (await hasWork(db) !== active) continue;
      details = {jobName: scheduler.name, jobState: desiredState, [membershipField]: active,
        lastReconciledAtMillis: now(), lastErrorCode: null};
      return {state: desiredState, [membershipField]: active};
    }
    throw new Error('Active hikes changed during reconciliation; retry this event.');
  } catch (error) {
    details = {lastErrorCode: String(error.code || 'reconciliation-failed'), lastErrorAtMillis: now()};
    throw error;
  } finally {
    await releaseLease(db, lease, details);
  }
}
async function withMonitorRunLease(db, work, now = Date.now, scheduleTime) {
  return withMaintenanceRunLease({db, work, now, scheduleTime, documentId: RUN_DOCUMENT});
}
// withMaintenanceRunLease: Release only the current worker lease and retain successful tick identity.
async function withMaintenanceRunLease({db, work, now = Date.now, scheduleTime, documentId,
  leaseMillis = LEASE_MILLIS}) {
  const tickMillis = Date.parse(scheduleTime || '');
  const lease = await acquireLease(db, documentId, now, tickMillis, leaseMillis);
  if (!lease) return {skipped: true};
  let details = {};
  try {
    const result = await work();
    if (Number.isFinite(tickMillis)) details = {lastCompletedTickMillis: tickMillis};
    return result;
  } finally {await releaseLease(db, lease, details);}
}
module.exports = {activeMembershipChanged, schedulerJobName, createSchedulerClient,
  reconcileActiveHikeMonitor, withMonitorRunLease, LEASE_MILLIS,
  reconcileHikeSchedule, withMaintenanceRunLease};

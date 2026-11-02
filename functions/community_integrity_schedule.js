// One server-owned deadline coordinates scheduled and administrator-requested checks.
'use strict';

const INTERVAL_MILLIS = 30 * 60 * 1000;
const LEASE_MILLIS = 5 * 60 * 1000;

// Ignore absent or malformed legacy timestamps when restoring the next deadline.
function millis(value) {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null;
}

// Claim one scan atomically, with manual checks bypassing only the interval, never the active lease.
async function beginIntegrityRun({db, owner, force = false, now = Date.now}) {
  const runRef = db.doc('maintenanceState/communityModerationRun');
  const healthRef = db.doc('communityModerationStatus/current');
  return db.runTransaction(async tx => {
    const [record, healthRecord] = await Promise.all([tx.get(runRef), tx.get(healthRef)]);
    const state = record.data() || {};
    const health = healthRecord.data() || {};
    const time = now();
    if ((millis(state.leaseExpiresAtMillis) ?? 0) > time) {
      return {acquired: false, result: {...health, skipped: true, reason: 'busy', status: 'running',
        nextRunAtMillis: null, updatedAtMillis: millis(state.startedAtMillis) ?? time,
        serverNowMillis: time}};
    }
    const previous = millis(health.lastRunAtMillis);
    const next = millis(state.nextRunAtMillis) ?? millis(health.nextRunAtMillis)
      ?? (previous == null ? 0 : previous + INTERVAL_MILLIS);
    if (!force && next > time) {
      return {acquired: false, result: {...health, skipped: true, reason: 'not-due',
        nextRunAtMillis: next, serverNowMillis: time}};
    }
    tx.set(runRef, {leaseOwner: owner, leaseExpiresAtMillis: time + LEASE_MILLIS,
      startedAtMillis: time, nextRunAtMillis: time}, {merge: true});
    tx.set(healthRef, {status: 'running', startedAtMillis: time, updatedAtMillis: time,
      nextRunAtMillis: null, intervalMinutes: 30, mode: 'local_rules',
      trigger: force ? 'manual' : 'scheduled'}, {merge: true});
    return {acquired: true, state};
  });
}

// Publish a result, release its lease and restart the thirty minutes in one fenced transaction.
async function finishIntegrityRun({db, owner, result, force = false, now = Date.now}) {
  const runRef = db.doc('maintenanceState/communityModerationRun');
  const healthRef = db.doc('communityModerationStatus/current');
  return db.runTransaction(async tx => {
    const record = await tx.get(runRef);
    if (record.data()?.leaseOwner !== owner) return null;
    const time = now();
    const health = {...result, status: result.status, lastRunAtMillis: time,
      nextRunAtMillis: time + INTERVAL_MILLIS, updatedAtMillis: time,
      intervalMinutes: 30, mode: 'local_rules', trigger: force ? 'manual' : 'scheduled'};
    tx.set(runRef, {leaseOwner: null, leaseExpiresAtMillis: 0,
      nextRunAtMillis: health.nextRunAtMillis, lastRunAtMillis: time,
      ...(result.status === 'completed' ? {postCursor: result.postCursor ?? null,
        commentCursor: result.commentCursor ?? null, policyHash: result.policyHash ?? null,
        policyVersion: result.policyVersion ?? null} : {})}, {merge: true});
    tx.set(healthRef, health);
    return {...health, serverNowMillis: time};
  });
}

// Allow a retry if publication failed, without releasing another scan's lease.
async function releaseIntegrityRun({db, owner}) {
  const runRef = db.doc('maintenanceState/communityModerationRun');
  await db.runTransaction(async tx => {
    const record = await tx.get(runRef);
    if (record.data()?.leaseOwner === owner) {
      tx.set(runRef, {leaseOwner: null, leaseExpiresAtMillis: 0}, {merge: true});
    }
  });
}

// The protected account authorizes the operation; client input cannot choose its clock or force mode.
async function runManualIntegrityCheck({request, authorization, db, fieldPath, run}) {
  authorization.requireAdminAccess(request);
  return run({db, fieldPath, force: true});
}

module.exports = {INTERVAL_MILLIS, LEASE_MILLIS, beginIntegrityRun, finishIntegrityRun,
  releaseIntegrityRun, runManualIntegrityCheck};

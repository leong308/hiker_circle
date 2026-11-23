'use strict';

const LEASE_MILLIS = 10 * 60 * 1000;

// Query scan progress and claim the feed.
async function beginIntegrityRun({db, owner, eventRef, now}) {
  const runRef = db.doc('maintenanceState/communityModerationRun');
  const healthRef = db.doc('communityModerationStatus/current');
  return db.runTransaction(async tx => {
    const progress = eventRef ? (await tx.get(eventRef)).data() : null;
    if (progress?.completed) return {skipped: true, reason: 'already-checked'};
    const state = (await tx.get(runRef)).data() || {};
    const time = now();
    if (state.leaseExpiresAtMillis > time) {
      if (eventRef) throw new Error('Community scan is busy. Retry this post event.');
      return {...(await tx.get(healthRef)).data(), skipped: true, status: 'running', reason: 'busy'};
    }
    // Update cloud: claim moderation scan
    tx.set(runRef, {leaseOwner: owner, leaseExpiresAtMillis: time + LEASE_MILLIS});
    tx.set(healthRef, {status: 'running', startedAtMillis: time, updatedAtMillis: time,
      nextRunAtMillis: null, intervalMinutes: null, trigger: eventRef ? 'post_created' : 'manual'}, {merge: true});
    return {progress};
  });
}

// Update cloud: publish the result and release the scan.
async function finishIntegrityRun({db, owner, eventRef, now, result}) {
  const runRef = db.doc('maintenanceState/communityModerationRun');
  return db.runTransaction(async tx => {
    if ((await tx.get(runRef)).data()?.leaseOwner !== owner) throw new Error('Community scan lease expired.');
    const time = now();
    const health = {...result, updatedAtMillis: time, lastRunAtMillis: time,
      mode: 'local_rules', trigger: eventRef ? 'post_created' : 'manual'};
    if (eventRef && result.status === 'completed') tx.set(eventRef, {completed: true});
    tx.set(runRef, {leaseOwner: null, leaseExpiresAtMillis: 0});
    tx.set(db.doc('communityModerationStatus/current'), health);
    return health;
  });
}

async function runManualIntegrityCheck({request, authorization, db, fieldPath, run}) {
  authorization.requireAdminAccess(request);
  return run({db, fieldPath});
}

module.exports = {beginIntegrityRun, finishIntegrityRun, runManualIntegrityCheck};

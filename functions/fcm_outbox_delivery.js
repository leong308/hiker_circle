'use strict';
const { randomUUID } = require('node:crypto');
const LEASE_MILLIS = 5 * 60000;

async function claimOutbox(db, ref, timestamp, now = Date.now()) {
  const attemptId = randomUUID();
  return db.runTransaction(async tx => {
    const snapshot = await tx.get(ref);
    const data = snapshot.data() || {};
    if (!snapshot.exists) return null;
    const status = String(data.status || 'pending');
    if (status === 'sending') {
      const lease = Number(data.deliveryLeaseExpiresAtMillis || 0);
      if (lease > now) return null;
      // An expired outbound lease cannot distinguish process death before FCM
      // from death after acceptance. Record that uncertainty without resending.
      if (data.deliveryPhase !== 'preflight') {
        tx.update(ref, { status: 'delivery_uncertain', error: 'expired_outbound_lease',
          processedAt: timestamp(), processedAtLocal: new Date(now).toISOString() });
        return null;
      }
    } else if (status !== 'pending' || Number(data.retryAfterMillis || 0) > now) {
      return null;
    }
    tx.update(ref, { status: 'sending', deliveryPhase: 'preflight', deliveryAttemptId: attemptId,
      deliveryLeaseExpiresAtMillis: now + LEASE_MILLIS, deliveryClaimedAt: timestamp(),
      deliveryClaimedAtLocal: new Date(now).toISOString(), attemptCount: Number(data.attemptCount || 0) + 1 });
    return { payload: data, attemptId };
  });
}

async function updateClaim(db, ref, attemptId, update, expectedPhase) {
  return db.runTransaction(async tx => {
    const snapshot = await tx.get(ref), current = snapshot.data() || {};
    if (!snapshot.exists || current.status !== 'sending' || current.deliveryAttemptId !== attemptId
        || (expectedPhase && current.deliveryPhase !== expectedPhase)) return false;
    tx.update(ref, update);
    return true;
  });
}
async function beginOutbound(db, ref, attemptId, now = Date.now()) {
  return updateClaim(db, ref, attemptId, { deliveryPhase: 'outbound',
    deliveryLeaseExpiresAtMillis: now + LEASE_MILLIS }, 'preflight');
}
async function retryPreflight(db, ref, attemptId, error, now = Date.now()) {
  return updateClaim(db, ref, attemptId, { status: 'pending', retryAfterMillis: now + 60000,
    error: String(error?.code || error?.name || 'preflight_error').slice(0, 160) }, 'preflight');
}
module.exports = { claimOutbox, updateClaim, beginOutbound, retryPreflight, LEASE_MILLIS };

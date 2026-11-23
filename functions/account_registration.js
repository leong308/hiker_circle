'use strict';

function timestampMillis(value) {
  if (typeof value?.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'string') return Date.parse(value);
  return NaN;
}

// Retained authentication documents must not become credentials for a newly
// registered account at the same phone-number path. Hiking records are separate.
function belongsToAccount(account, artifact) {
  if (!account?.exists) return false;
  const createdAt = timestampMillis(account.data()?.createdAt ?? account.createTime);
  if (!Number.isFinite(createdAt)) return true; // Existing accounts without a recorded birth time.
  const recordedAt = timestampMillis(artifact?.createdAt ?? artifact?.createdAtLocal);
  return Number.isFinite(recordedAt) && recordedAt >= createdAt;
}

// Call only after a sign-up WhatsApp challenge has been verified and consumed.
// Old account modules and history survive deletion; reset only sign-in state.
async function createSignupAccountIfMissing({db, auth, uid, phoneNumber, HttpsError, timestamp}) {
  const reference = db.collection('users').doc(uid);
  // Query signup account and Auth identity
  if ((await reference.get()).exists) return false;
  try {
    const previous = await auth.getUser(uid);
    if (previous.disabled) {
      throw new HttpsError('permission-denied', 'This account is disabled.');
    }
    // Repair an orphan left by the earlier document-only deletion behaviour.
    // Update cloud: remove orphaned Auth identity
    await auth.deleteUser(uid);
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
  }
  const now = new Date().toISOString();
  await db.runTransaction(async transaction => {
    // Query signup account in transaction
    const current = await transaction.get(reference);
    if (current.exists) {
      throw new HttpsError('failed-precondition', 'Account setup changed. Start registration again.');
    }
    // Update cloud: create account, modules and session
    transaction.create(reference, {
      phoneNumber, createdAt: timestamp(), createdAtLocal: now,
      role: 'hiker', isAdmin: false, isSuperAdmin: false,
      accountDisabled: false, status: 'active',
    });
    transaction.set(reference.collection('modules').doc('security'), {
      mfaRequired: true, mfaFactorCount: 0, mfaMethods: [],
    });
    transaction.set(reference.collection('modules').doc('profile'), {
      requiresOnboarding: true, profileSetupCompleted: false, onboardingVersion: 1,
    }, {merge: true});
    transaction.set(db.collection('mobileSessions').doc(uid), {
      activeSessionId: '', reason: 'fresh-registration',
      endedAt: timestamp(), endedAtLocal: now,
    }, {merge: true});
  });
  return true;
}

module.exports = {belongsToAccount, createSignupAccountIfMissing};

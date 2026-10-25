// Full MFA establishes one server-owned mobile session; replacement, reauthentication, and revocation share this authority.
'use strict';

const crypto = require('node:crypto');

const RECENT_VERIFICATION_MS = 10 * 60 * 1000;
const CANDIDATE_TTL_MS = 10 * 60 * 1000;

function cleanDevice(raw) {
  const appInstanceId = String(raw?.appInstanceId || '').trim();
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(appInstanceId)) {
    throw new Error('invalid-device');
  }
  const label = String(raw?.name || '').replace(/[\x00-\x1f\x7f]/g, '').trim().slice(0, 100);
  const platform = ['android', 'ios'].includes(raw?.platform) ? raw.platform : 'other';
  return {appInstanceId, name: label || (platform === 'ios' ? 'iPhone' : 'Android phone'), platform};
}

function recentVerification(auth, now = Date.now()) {
  const at = Number(auth?.token?.auth_time || 0) * 1000;
  return auth?.token?.mfa === true && at > 0 && at <= now + 30_000
    && now - at <= RECENT_VERIFICATION_MS;
}

function enabledAccount(snapshot) {
  const account = snapshot.data() || {};
  return snapshot.exists && account.accountDisabled !== true && account.status !== 'disabled';
}

function createMobileSessionSecurity({db, auth, HttpsError, timestamp, setUser}) {
  const stateRef = uid => db().collection('mobileSessions').doc(uid);
  const candidateRef = sid => db().collection('mobileSessionCandidates').doc(sid);
  const fail = (message, reason = 'session-ended') => {
    throw new HttpsError('unauthenticated', message, {reason});
  };
  // identity: Require the full MFA token and opaque mobile session claim before checking server state.
  function identity(request) {
    const uid = String(request.auth?.uid || '');
    const token = request.auth?.token || {};
    if (!/^\+[1-9]\d{7,14}$/.test(uid) || token.phoneNumber !== uid || token.mfa !== true
      || !/^[a-f0-9]{64}$/.test(String(token.mobileSessionId || ''))) {
      fail('Sign in again with WhatsApp and your security method.');
    }
    return {uid, sid: token.mobileSessionId};
  }
  // requireActive: Check both the active session record and the enabled account on each business request.
  async function requireActive(request) {
    const {uid, sid} = identity(request);
    const [state, account] = await Promise.all([
      stateRef(uid).get(), db().collection('users').doc(uid).get(),
    ]);
    if (!enabledAccount(account)) fail('This account is unavailable or disabled.', 'account-disabled');
    if (state.data()?.activeSessionId !== sid) {
      fail('This account was signed out because a new session started on another device.', 'session-replaced');
    }
    return {uid, sid, state: state.data(), account: account.data()};
  }
  function requireRecent(request) {
    if (!recentVerification(request.auth)) {
      throw new HttpsError('failed-precondition',
        'Verify your identity again before changing account security.',
        {reason: 'recent-verification-required'});
    }
  }
  // createCandidate: Create a short-lived login candidate, or keep the existing session during purpose-limited reauthentication.
  async function createCandidate({uid, phoneNumber, method, reauthSessionId = '', initialSetup = false}) {
    let record;
    try { record = await auth().getUser(uid); }
    catch (error) {
      if (error.code !== 'auth/user-not-found' || !initialSetup) throw error;
      record = await auth().createUser({uid});
    }
    if (record.disabled) fail('This account is disabled.', 'account-disabled');
    if (reauthSessionId) {
      const state = await stateRef(uid).get();
      if (state.data()?.activeSessionId !== reauthSessionId) fail('This session has ended. Sign in again.');
      return {mobileSessionId: reauthSessionId, initialPasswordSetup: initialSetup};
    }
    const sid = crypto.randomBytes(32).toString('hex');
    await candidateRef(sid).create({uid,
      createdAt: timestamp(), expiresAtMillis: Date.now() + CANDIDATE_TTL_MS,
      activated: false});
    return {mobileSessionId: sid, initialPasswordSetup: initialSetup};
  }
  async function prepare(request) {
    const {uid, sid} = identity(request);
    requireRecent(request);
    let device;
    try { device = cleanDevice(request.data?.device); }
    catch (_) { throw new HttpsError('invalid-argument', 'The device information is invalid.'); }
    return db().runTransaction(async tx => {
      const [candidate, state, account] = await Promise.all([
        tx.get(candidateRef(sid)), tx.get(stateRef(uid)), tx.get(db().collection('users').doc(uid)),
      ]);
      if (!enabledAccount(account)) fail('This account is unavailable or disabled.');
      const value = candidate.data() || {};
      if (state.data()?.activeSessionId === sid && value.activated === true) {
        return {replacementRequired: false, previousDeviceName: device.name, expectedPreviousSessionId: sid};
      }
      if (!candidate.exists || value.uid !== uid || value.activated
        || Date.now() > Number(value.expiresAtMillis || 0)) fail('This login has expired. Start again.');
      if (value.device && value.device.appInstanceId !== device.appInstanceId) fail('This login belongs to another installation.');
      tx.set(candidate.ref, {device}, {merge: true});
      const previous = state.data() || {};
      return {
        replacementRequired: Boolean(previous.activeSessionId && previous.activeSessionId !== sid),
        previousDeviceName: previous.device?.name || 'your previous phone',
        expectedPreviousSessionId: previous.activeSessionId || '',
      };
    });
  }
  // activate: Fence the expected previous session and commit replacement plus security notification together.
  async function activate(request) {
    const {uid, sid} = identity(request);
    requireRecent(request);
    const expected = String(request.data?.expectedPreviousSessionId || '');
    const result = await db().runTransaction(async tx => {
      const [candidate, state, account] = await Promise.all([
        tx.get(candidateRef(sid)), tx.get(stateRef(uid)), tx.get(db().collection('users').doc(uid)),
      ]);
      if (!enabledAccount(account)) fail('This account is unavailable or disabled.');
      const next = candidate.data() || {};
      const previous = state.data() || {};
      if (previous.activeSessionId === sid && next.activated === true) return {activated: true};
      if (!candidate.exists || next.uid !== uid || next.activated || !next.device
        || Date.now() > Number(next.expiresAtMillis || 0)) fail('This login has expired. Start again.');
      if ((previous.activeSessionId || '') !== expected) {
        throw new HttpsError('failed-precondition', 'The active device changed. Review the device warning again.',
          {reason: 'active-device-changed'});
      }
      // Installation labels/IDs are informational, not proof of physical identity.
      // Every new login replaces the old session, even if its device ID is copied.
      const changedDevice = Boolean(previous.activeSessionId && previous.activeSessionId !== sid);
      const now = new Date().toISOString();
      tx.set(state.ref, {activeSessionId: sid, device: next.device,
        activatedAt: timestamp(), activatedAtLocal: now, reason: changedDevice ? 'new-device-login' : 'login'});
      tx.update(candidate.ref, {activated: true, activatedAt: timestamp()});
      setUser(tx, account.ref, {boundAppInstanceId: next.device.appInstanceId,
        boundAppInstanceUpdatedAt: timestamp(), boundAppInstanceUpdatedAtLocal: now,
        lastSignedInAt: timestamp(), lastSignedInAtLocal: now,
        ...(changedDevice ? {previousBoundAppInstanceId: previous.device.appInstanceId,
          deviceReboundAt: timestamp(), deviceReboundAtLocal: now, deviceRebindVerifiedBy: 'full_mfa'} : {})});
      tx.create(db().collection('sessionSecurityOutbox').doc(sid), {uid, phoneNumber: uid,
        newDevice: next.device, previousDevice: previous.device || null, replacedSession: changedDevice,
        createdAt: timestamp(), createdAtLocal: now, status: 'pending'});
      return {activated: true, deviceName: next.device.name, replacedOtherDevice: changedDevice, sendNotice: true};
    });
    return result;
  }
  // revokeInTransaction: Clear active session authority in the same transaction as the security action.
  function revokeInTransaction(tx, uid, reason) {
    tx.set(stateRef(uid), {activeSessionId: '', reason, endedAt: timestamp(),
      endedAtLocal: new Date().toISOString()}, {merge: true});
  }
  async function end(request) {
    const {uid, sid} = identity(request);
    await db().runTransaction(async tx => {
      const state = await tx.get(stateRef(uid));
      if (state.data()?.activeSessionId === sid) revokeInTransaction(tx, uid, 'signed-out');
    });
    return {ended: true};
  }
  return {requireActive, requireRecent, createCandidate, prepare, activate, end, revokeInTransaction};
}

module.exports = {createMobileSessionSecurity, recentVerification, cleanDevice,
  enabledAccount, RECENT_VERIFICATION_MS, CANDIDATE_TTL_MS};

// Administrator directory and immutable, superadmin-only role transitions.
'use strict';
const {FieldPath} = require('firebase-admin/firestore');
const {accountRole, isSuperAdminUser} = require('./admin_authorization');
const {contentHash} = require('./mobile_cache_helpers');

// Expose only the three requested directory fields plus an opaque action identity.
function userRow(snapshot, profile, username) {
  const data = snapshot.data() || {};
  return {userId: snapshot.id, username: username(profile || {}, 'Hiker').slice(0, 160),
    phoneNumber: typeof data.phoneNumber === 'string' && /^\+[1-9]\d{7,14}$/.test(data.phoneNumber) ? data.phoneNumber : snapshot.id,
    role: accountRole(data)};
}

// All privileges come from the active protected account, never from client role flags.
function createAdminUsers({database, authorization, HttpsError, username, timestamp}) {
  const fail = (code, message) => {throw new HttpsError(code, message);};
  const id = value => typeof value === 'string' && /^\+[1-9]\d{7,14}$/.test(value);
  const pageArgs = data => {
    const limit = data?.limit ?? 50, cursor = data?.cursor;
    if (!Number.isInteger(limit) || limit < 1 || limit > 100 || (cursor != null && !id(cursor))) fail('invalid-argument', 'Invalid directory page.');
    return {limit, cursor};
  };
  // Read profile modules in one bounded batch without exposing other account fields.
  async function listUsers(request) {
    authorization.requireAdminAccess(request);
    const {limit, cursor} = pageArgs(request.data);
    let query = database().collection('users').orderBy(FieldPath.documentId());
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.limit(limit + 1).get();
    const docs = snapshot.docs.slice(0, limit);
    const profiles = docs.length ? await database().getAll(...docs.map(doc => doc.ref.collection('modules').doc('profile'))) : [];
    return {users: docs.filter(doc => id(doc.id)).map(doc => userRow(doc, profiles[docs.indexOf(doc)]?.data(), username)),
      nextCursor: snapshot.docs.length > limit ? docs.at(-1).id : null};
  }
  // Recheck the actor inside the same transaction that changes the target and writes its audit record.
  async function changeRole(request) {
    authorization.requireSuperAdminAccess(request);
    const {targetUserId, role, expectedRole, operationId} = request.data || {};
    if (!id(targetUserId) || !['admin','hiker'].includes(role) || !['admin','hiker'].includes(expectedRole)
      || typeof operationId !== 'string' || !/^[A-Za-z0-9_-]{8,128}$/.test(operationId)) fail('invalid-argument', 'Invalid role change.');
    const actorId = request.auth.uid;
    const sessionId = request.auth.token?.mobileSessionId;
    if (typeof sessionId !== 'string' || !sessionId) fail('unauthenticated', 'Your secure session is unavailable.');
    if (actorId === targetUserId) fail('failed-precondition', 'You cannot change your own role here.');
    const db = database(), actor = db.doc(`users/${actorId}`), target = db.doc(`users/${targetUserId}`);
    const audit = db.collection('userRoleHistory').doc(contentHash([actorId, operationId]));
    return db.runTransaction(async tx => {
      const [actorDoc, targetDoc, previous, actorProfile, targetProfile, session] = await tx.getAll(actor, target, audit,
        actor.collection('modules').doc('profile'), target.collection('modules').doc('profile'), db.doc(`mobileSessions/${actorId}`));
      if (session.data()?.activeSessionId !== sessionId) fail('unauthenticated', 'Your secure session changed. Sign in again.');
      if (!actorDoc.exists || !isSuperAdminUser(actorDoc.data())) fail('permission-denied', 'Superadmin access is required.');
      if (!targetDoc.exists) fail('not-found', 'This hiker is unavailable.');
      if (previous.exists) {
        const row = previous.data();
        if (row.targetUserId !== targetUserId || row.toRole !== role) fail('already-exists', 'This operation was already used.');
        return {role: accountRole(targetDoc.data()), changed: false};
      }
      const fromRole = accountRole(targetDoc.data());
      if (fromRole === 'superadmin') fail('permission-denied', 'Superadmin roles cannot be changed here.');
      if (fromRole === role) return {role, changed: false};
      if (fromRole !== expectedRole) fail('failed-precondition', 'This role changed. Refresh the list and try again.');
      tx.update(target, {isAdmin: role === 'admin', isSuperAdmin: false, role, roles: [role]});
      tx.create(audit, {actorUserId: actorId, actorUsername: username(actorProfile.data() || {}, 'Hiker').slice(0, 160),
        actorPhoneNumber: actorId, targetUserId,
        targetUsername: username(targetProfile.data() || {}, 'Hiker').slice(0, 160), targetPhoneNumber: targetUserId,
        fromRole, toRole: role, changedAt: timestamp()});
      return {role, changed: true};
    });
  }
  // Audits are ordered, paginated and readable only by a current superadmin.
  async function history(request) {
    authorization.requireSuperAdminAccess(request);
    const limit = request.data?.limit ?? 50, cursor = request.data?.cursor;
    if (!Number.isInteger(limit) || limit < 1 || limit > 100 || (cursor != null && !/^[a-f0-9]{64}$/.test(cursor))) fail('invalid-argument', 'Invalid role-history page.');
    let query = database().collection('userRoleHistory').orderBy('changedAt', 'desc').orderBy(FieldPath.documentId(), 'desc');
    if (cursor) {
      const doc = await database().doc(`userRoleHistory/${cursor}`).get();
      if (!doc.exists) fail('not-found', 'This history page is unavailable.');
      query = query.startAfter(doc);
    }
    const snapshot = await query.limit(limit + 1).get(), docs = snapshot.docs.slice(0, limit);
    return {history: docs.map(doc => ({historyId: doc.id, ...doc.data(), changedAt: doc.data().changedAt?.toDate().toISOString() || ''})),
      nextCursor: snapshot.docs.length > limit ? docs.at(-1).id : null};
  }
  return {listUsers, changeRole, history};
}
module.exports = {createAdminUsers, userRow};

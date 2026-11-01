// Host-only projections keep request history private and leave decisions in the existing transaction.
'use strict';
const {joinRequestLifecycle, upcomingHikeUnavailableReason} = require('./upcoming_hike_join_request_helpers');
const {safeJoinAlias} = require('./join_request_hiker_stats');

// validId: Accept a single bounded Firestore document identity.
function validId(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 200
    && !/[\/\x00-\x1f]/.test(value) && value !== '.' && value !== '..';
}

// iso: Normalize legacy timestamps without exposing their raw record.
function iso(value) {
  const date = value?.toDate ? value.toDate() : new Date(value || '');
  return Number.isFinite(date.getTime()) ? date.toISOString() : '';
}

// ownedHike: Require the current host even when the caller already knows a request ID.
async function ownedHike(db, hikeId, hostPhone, ErrorType) {
  if (!validId(hikeId)) throw new ErrorType('invalid-argument', 'The upcoming hike is invalid.');
  const snapshot = await db.collection('upcomingHikes').doc(hikeId).get();
  if (!snapshot.exists || String(snapshot.data()?.creatorPhone || '') !== hostPhone) {
    throw new ErrorType('permission-denied', 'Only this hike’s host can view its join requests.');
  }
  return snapshot.data();
}

// pendingCount: Use the canonical pending records, with no migration or approximate local count.
async function pendingCount(db, hikeId, hike, now) {
  if (upcomingHikeUnavailableReason(hike, now)) return 0;
  const snapshot = await db.collection('upcomingHikeJoinRequests')
    .where('hikeId', '==', hikeId).where('status', '==', 'pending').count().get();
  return snapshot.data().count;
}

// listRequests: Return bounded counts or a cursor-paged, privacy-filtered request list.
async function listRequests({db, hostPhone, input, ErrorType, documentId, now = Date.now()}) {
  if (input?.mode === 'counts') {
    if (!Array.isArray(input.hikeIds) || input.hikeIds.length > 30
        || input.hikeIds.some(id => !validId(id))) {
      throw new ErrorType('invalid-argument', 'Choose up to 30 hosted hikes.');
    }
    const counts = await Promise.all([...new Set(input.hikeIds)].map(async hikeId => {
      const hike = await ownedHike(db, hikeId, hostPhone, ErrorType);
      return [hikeId, await pendingCount(db, hikeId, hike, now)];
    }));
    return {counts: Object.fromEntries(counts)};
  }
  const hikeId = input?.hikeId;
  const hike = await ownedHike(db, hikeId, hostPhone, ErrorType);
  const bucket = input.bucket || 'pending';
  if (!['pending', 'history'].includes(bucket)) {
    throw new ErrorType('invalid-argument', 'Choose pending requests or request history.');
  }
  const unavailable = Boolean(upcomingHikeUnavailableReason(hike, now));
  const count = await pendingCount(db, hikeId, hike, now);
  if (bucket === 'pending' && unavailable) return {rows: [], pendingCount: 0, hasMore: false};
  const limit = input.limit == null ? 30 : input.limit;
  if (!Number.isInteger(limit) || limit < 1 || limit > 40) {
    throw new ErrorType('invalid-argument', 'The request page size is invalid.');
  }
  const statuses = bucket === 'pending' ? ['pending']
    : unavailable ? ['accepted', 'rejected', 'expired', 'pending'] : ['accepted', 'rejected', 'expired'];
  let query = db.collection('upcomingHikeJoinRequests')
    .where('hikeId', '==', hikeId).where('status', 'in', statuses)
    .orderBy('createdAt', 'desc').orderBy(documentId, 'desc');
  if (input.afterRequestId != null) {
    if (!/^join_[a-f0-9]{48}$/.test(input.afterRequestId)) {
      throw new ErrorType('invalid-argument', 'The request page cursor is invalid.');
    }
    const cursor = await db.collection('upcomingHikeJoinRequests').doc(input.afterRequestId).get();
    if (!cursor.exists || cursor.data()?.hikeId !== hikeId || cursor.data()?.hostPhone !== hostPhone
        || !statuses.includes(cursor.data()?.status)) {
      throw new ErrorType('invalid-argument', 'Refresh this request list before continuing.');
    }
    query = query.startAfter(cursor);
  }
  const result = await query.limit(limit + 1).get();
  const page = result.docs.slice(0, limit);
  const rows = page.filter(doc => doc.data().hostPhone === hostPhone).map(doc => {
    const data = doc.data(), lifecycle = joinRequestLifecycle(data, hike, now);
    return {requestId: doc.id, hikeId, requesterName: safeJoinAlias(data.requesterName),
      status: lifecycle.status, reason: lifecycle.reason,
      createdAtLocal: iso(data.createdAt || data.createdAtLocal),
      decidedAtLocal: iso(data.resolvedAt || data.resolvedAtLocal || data.updatedAtLocal)};
  });
  return {rows, pendingCount: count, hasMore: result.size > limit,
    nextCursor: page.length ? page[page.length - 1].id : null};
}

module.exports = {listRequests};

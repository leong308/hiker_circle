// Host-only projections keep request history private and leave decisions in the existing transaction.
'use strict';
const {joinRequestDocumentId, joinRequestLifecycle, upcomingHikeUnavailableReason} = require('./upcoming_hike_join_request_helpers');
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
  // Query hike join inbox owner
  const snapshot = await db.collection('upcomingHikes').doc(hikeId).get();
  if (!snapshot.exists || String(snapshot.data()?.creatorPhone || '') !== hostPhone) {
    throw new ErrorType('permission-denied', 'Only this hike’s host can view its join requests.');
  }
  return snapshot.data();
}

// pendingCount: Use the canonical pending records, with no migration or approximate local count.
async function pendingCount(db, hikeId, hike, now) {
  if (upcomingHikeUnavailableReason(hike, now)) return 0;
  // Query pending hike join requests
  const snapshot = await db.collection('upcomingHikeJoinRequests')
    .where('hikeId', '==', hikeId).where('status', '==', 'pending').count().get();
  return snapshot.data().count;
}

function requestRow(doc, hikeId, hike, now) {
  const data = doc.data(), lifecycle = joinRequestLifecycle(data, hike, now);
  return {requestId: doc.id, hikeId, requesterName: safeJoinAlias(data.requesterName),
    status: lifecycle.status, reason: lifecycle.reason,
    createdAtLocal: iso(data.createdAt || data.createdAtLocal),
    decidedAtLocal: iso(data.resolvedAt || data.resolvedAtLocal || data.updatedAtLocal)};
}

async function* documentPages(query, firstPage, size) {
  let page = firstPage;
  while (true) {
    const batch = await page.limit(size).get();
    if (batch.size) yield batch.docs;
    if (batch.size < size) return;
    page = query.startAfter(batch.docs[batch.size - 1]);
  }
}

function joinReceipt(doc, chatId) {
  const data = doc.data(), phone = data?.senderPhone;
  return data?.isSystemMessage === true && data.chatId === chatId &&
    typeof phone === 'string' && /^\+[1-9]\d{7,14}$/.test(phone) &&
    doc.id === `joined_${phone.slice(1)}` &&
    typeof data.sentAtLocal === 'string' && Boolean(iso(data.sentAtLocal));
}

function historyPosition(token, hikeId, ErrorType) {
  // Each source starts at null and becomes false once exhausted.
  if (token == null) return {request: null, message: null};
  // Accept the previous request-only cursor during an app update.
  if (typeof token === 'string' && /^join_[a-f0-9]{48}$/.test(token)) return {request: token, message: null};
  try {
    if (typeof token !== 'string' || token.length > 1024) throw Error();
    const pos = JSON.parse(Buffer.from(token, 'base64url').toString());
    if (pos.hikeId !== hikeId || !(pos.request === null || pos.request === false ||
        (typeof pos.request === 'string' && /^join_[a-f0-9]{48}$/.test(pos.request)))) throw Error();
    const m = pos.message;
    if (!(m === false || m === null || (Array.isArray(m) && m.length === 2 &&
        typeof m[0] === 'string' && m[0].length <= 64 &&
        typeof m[1] === 'string' && /^join_[a-f0-9]{48}$/.test(m[1])))) throw Error();
    return pos;
  } catch {
    throw new ErrorType('invalid-argument', 'Refresh the hike history before continuing.');
  }
}

async function historyPage({db, hikeId, hike, hostPhone, now, query, statuses, input, limit, ErrorType}) {
  const pos = historyPosition(input.afterRequestId, hikeId, ErrorType);
  const chatId = `hike_${hikeId}`;
  const messages = db.collection('groupChats').doc(chatId).collection('messages');
  async function* decisions() {
    if (pos.request === false) return;
    let first = query;
    if (pos.request) {
      const cursor = await db.collection('upcomingHikeJoinRequests').doc(pos.request).get();
      if (!cursor.exists || cursor.data().hostPhone !== hostPhone || cursor.data().hikeId !== hikeId ||
          !statuses.includes(cursor.data().status)) {
        throw new ErrorType('invalid-argument', 'Refresh the hike history before continuing.');
      }
      first = query.startAfter(cursor);
    }
    for await (const page of documentPages(query, first, limit + 1)) {
      const owned = page.filter(doc => doc.data().hostPhone === hostPhone);
      const approvals = owned.map(doc => doc.data())
        .filter(row => row.status === 'accepted' && /^\+[1-9]\d{7,14}$/.test(row.requesterPhone));
      const refs = approvals.map(row => messages.doc(`joined_${row.requesterPhone.slice(1)}`));
      // Query join receipts for approvals
      const receipts = refs.length ? await db.getAll(...refs,
        {fieldMask: ['sentAtLocal', 'isSystemMessage', 'chatId', 'senderPhone']}) : [];
      const joined = new Set(receipts.filter(doc => doc.exists && joinReceipt(doc, chatId))
        .map(doc => doc.data().senderPhone));
      for (const doc of owned) {
        const data = doc.data();
        if (data.status !== 'accepted' || !joined.has(data.requesterPhone)) {
          const row = requestRow(doc, hikeId, hike, now);
          yield {row, time: row.createdAtLocal};
        }
        pos.request = doc.id;
      }
    }
    pos.request = false;
  }
  async function* memberships() {
    if (pos.message === false) return;
    // Query recorded hike joins
    const system = messages.where('isSystemMessage', '==', true)
      .select('sentAtLocal', 'isSystemMessage', 'chatId', 'senderPhone', 'senderName');
    const ordered = system.orderBy('sentAtLocal', 'desc');
    let first = ordered;
    if (pos.message) {
      // Resolve ties without sending phone-based message IDs to the client.
      const [time, key] = pos.message;
      const ties = await system.where('sentAtLocal', '==', time).get();
      const last = ties.docs.find(doc => joinReceipt(doc, chatId) &&
        joinRequestDocumentId(hikeId, doc.data().senderPhone) === key);
      if (!last) throw new ErrorType('invalid-argument', 'Refresh the hike history before continuing.');
      first = ordered.startAfter(last);
    }
    for await (const page of documentPages(ordered, first, limit + 1)) {
      for (const doc of page) {
        const data = doc.data();
        if (!joinReceipt(doc, chatId) || data.senderPhone === hostPhone) continue;
        const joinedAtLocal = iso(data.sentAtLocal), key = joinRequestDocumentId(hikeId, data.senderPhone);
        yield {time: joinedAtLocal, row: {requestId: key + '_joined', hikeId,
          requesterName: safeJoinAlias(data.senderName), status: 'accepted', reason: 'joined',
          createdAtLocal: joinedAtLocal, decidedAtLocal: joinedAtLocal, joinedAtLocal}};
        pos.message = [data.sentAtLocal, key];
      }
    }
    pos.message = false;
  }
  const sources = [decisions(), memberships()];
  const heads = await Promise.all(sources.map(source => source.next()));
  const rows = [];
  while (rows.length < limit && heads.some(head => !head.done)) {
    const i = heads[0].done || (!heads[1].done && heads[1].value.time >= heads[0].value.time) ? 1 : 0;
    rows.push(heads[i].value.row);
    heads[i] = await sources[i].next();
  }
  const hasMore = heads.some(head => !head.done);
  return {rows, hasMore, nextCursor: hasMore ?
    Buffer.from(JSON.stringify({hikeId, request: pos.request, message: pos.message})).toString('base64url') : null};
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
  if (bucket === 'history') {
    const history = await historyPage({db, hikeId, hike, hostPhone, now, query, statuses, input, limit, ErrorType});
    return {...history, pendingCount: count};
  }
  if (input.afterRequestId != null) {
    if (!/^join_[a-f0-9]{48}$/.test(input.afterRequestId)) {
      throw new ErrorType('invalid-argument', 'The request page cursor is invalid.');
    }
    // Query join request cursor and page
    const cursor = await db.collection('upcomingHikeJoinRequests').doc(input.afterRequestId).get();
    if (!cursor.exists || cursor.data()?.hikeId !== hikeId || cursor.data()?.hostPhone !== hostPhone
        || !statuses.includes(cursor.data()?.status)) {
      throw new ErrorType('invalid-argument', 'Refresh this request list before continuing.');
    }
    query = query.startAfter(cursor);
  }
  const result = await query.limit(limit + 1).get();
  const page = result.docs.slice(0, limit);
  const rows = page.filter(doc => doc.data().hostPhone === hostPhone)
    .map(doc => requestRow(doc, hikeId, hike, now));
  return {rows, pendingCount: count, hasMore: result.size > limit,
    nextCursor: page.length ? page[page.length - 1].id : null};
}

module.exports = {listRequests};

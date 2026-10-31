// Derived public routes contain only post-consent GPS, bounded to one point per five-second slot.
'use strict';

const ROUTE_COLLECTION = 'live_location_route_chunks';
const SLOT_MILLIS = 5000;
const BUCKET_MILLIS = 5 * 60000;
const SHARE_LIFETIME_MILLIS = 24 * 3600000;
const BACKFILL_PAGE_SIZE = 25;

function millis(value) {
  if (typeof value?.toMillis === 'function') return value.toMillis();
  if (typeof value?.toDate === 'function') return value.toDate().getTime();
  if (typeof value === 'number') return value;
  return typeof value === 'string' ? Date.parse(value) : NaN;
}

function validId(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 1500 && !value.includes('/');
}

function activeShareWindow(share, now) {
  const expiresAtMillis = millis(share?.expiresAt);
  if (share?.isActive !== true || !Number.isSafeInteger(expiresAtMillis) || expiresAtMillis <= now) return null;
  const startedAtMillis = [millis(share.createdAtLocal), millis(share.createdAt), expiresAtMillis - SHARE_LIFETIME_MILLIS]
    .find(value => Number.isSafeInteger(value) && value > 0 && value <= now);
  if (!startedAtMillis || expiresAtMillis <= startedAtMillis) return null;
  return {startedAtMillis, expiresAtMillis};
}

function normalizeRoutePoint(sample, window, now) {
  if (!window || !sample || typeof sample !== 'object') return null;
  const latitude = sample.latitude, longitude = sample.longitude;
  const recordedAtMillis = millis(sample.recordedAtMillis ?? sample.capturedAtLocal);
  const fixCapturedAtMillis = millis(sample.fixCapturedAtMillis ?? sample.capturedAtLocal ?? sample.recordedAtMillis);
  if (typeof latitude !== 'number' || !Number.isFinite(latitude) || Math.abs(latitude) > 90
      || typeof longitude !== 'number' || !Number.isFinite(longitude) || Math.abs(longitude) > 180
      || !Number.isSafeInteger(recordedAtMillis) || !Number.isSafeInteger(fixCapturedAtMillis)
      || recordedAtMillis < window.startedAtMillis || fixCapturedAtMillis < window.startedAtMillis
      || recordedAtMillis >= window.expiresAtMillis || fixCapturedAtMillis >= window.expiresAtMillis
      || recordedAtMillis > now + 5 * 60000 || fixCapturedAtMillis > now + 5 * 60000
      || fixCapturedAtMillis > recordedAtMillis + 5 * 60000) return null;
  return {latitude, longitude, recordedAtMillis, fixCapturedAtMillis};
}

function comparePoints(a, b) {
  return a.recordedAtMillis - b.recordedAtMillis || a.fixCapturedAtMillis - b.fixCapturedAtMillis
    || a.latitude - b.latitude || a.longitude - b.longitude;
}

// Read every affected bucket before returning write plans so callers preserve Firestore transaction ordering.
async function prepareRouteChunkWrites(transaction, shareReference, share, samples, now = Date.now()) {
  const window = activeShareWindow(share, now);
  if (!window) return [];
  const bucketCount = Math.ceil((window.expiresAtMillis - window.startedAtMillis) / BUCKET_MILLIS);
  const groups = new Map();
  for (const sample of samples || []) {
    const point = normalizeRoutePoint(sample, window, now);
    if (!point) continue;
    const bucket = Math.floor((point.recordedAtMillis - window.startedAtMillis) / BUCKET_MILLIS);
    if (bucket < 0 || bucket >= bucketCount) continue;
    if (!groups.has(bucket)) groups.set(bucket, []);
    groups.get(bucket).push(point);
  }
  const entries = [...groups].sort(([a], [b]) => a - b);
  const snapshots = await Promise.all(entries.map(([bucket]) => transaction.get(
    shareReference.collection(ROUTE_COLLECTION).doc(String(bucket).padStart(4, '0'))
  )));
  const writes = [];
  entries.forEach(([bucket, incoming], index) => {
    const snapshot = snapshots[index];
    const previous = snapshot.data() || {};
    // Never shorten TTL while an explicit renewal is preparing route history.
    // Public reads remain gated by the parent's actual expiry, not this field.
    const retention = millis(share.routeRetentionExpiresAt) > window.expiresAtMillis
      ? share.routeRetentionExpiresAt : share.expiresAt;
    const chunkExpiry = millis(previous.expiresAt) > millis(retention) ? previous.expiresAt : retention;
    const slots = new Map();
    for (const sample of [...(Array.isArray(previous.points) ? previous.points : []), ...incoming]) {
      const point = normalizeRoutePoint(sample, window, now);
      if (!point || Math.floor((point.recordedAtMillis - window.startedAtMillis) / BUCKET_MILLIS) !== bucket) continue;
      const slot = Math.floor((point.recordedAtMillis - window.startedAtMillis) / SLOT_MILLIS);
      const old = slots.get(slot);
      if (!old || comparePoints(point, old) < 0) slots.set(slot, point);
    }
    const points = [...slots.values()].sort(comparePoints);
    const bucketStartMillis = window.startedAtMillis + bucket * BUCKET_MILLIS;
    if (snapshot.exists && previous.schemaVersion === 1 && previous.bucketStartMillis === bucketStartMillis
        && millis(previous.expiresAt) === millis(chunkExpiry)
        && JSON.stringify(previous.points) === JSON.stringify(points)) return;
    writes.push({reference: snapshot.ref, data: {schemaVersion: 1, bucketStartMillis, points, expiresAt: chunkExpiry}});
  });
  return writes;
}

function applyRouteChunkWrites(transaction, writes) {
  for (const write of writes) transaction.set(write.reference, write.data);
}

function hikeConsentsToShare(hike, share, {shareId, uid, phoneNumber}, now) {
  return hike?.status === 'active' && hike.shareLiveLocation === true
    && hike.userId === uid && hike.userPhoneNumber === phoneNumber
    && hike.liveLocationShareId === shareId && share?.ownerUserId === uid
    && share.phoneNumber === phoneNumber && Boolean(activeShareWindow(share, now));
}

// Flutter and both native uploaders already use the same canonical footprint transaction.
async function prepareHikeRouteWrites(transaction, db, {hike, samples, uid, phoneNumber}, now = Date.now()) {
  const shareId = hike?.liveLocationShareId;
  if (hike?.status !== 'active' || hike.shareLiveLocation !== true || !validId(shareId)) return [];
  const shareReference = db.collection('live_location_shares').doc(shareId);
  const snapshot = await transaction.get(shareReference);
  const share = snapshot.data();
  if (!snapshot.exists || !hikeConsentsToShare(hike, share, {shareId, uid, phoneNumber}, now)) return [];
  return prepareRouteChunkWrites(transaction, shareReference, share, samples, now);
}

// Parent-write events reuse the existing standalone location upload. Replayed and out-of-order events merge safely.
async function projectShareLocation(db, {shareId, location}, now = Date.now()) {
  if (!validId(shareId)) return {writtenCount: 0, deletedCount: 0};
  const shareReference = db.collection('live_location_shares').doc(shareId);
  let writtenCount = 0, deletedCount = 0;
  while (true) {
    const result = await db.runTransaction(async transaction => {
      const snapshot = await transaction.get(shareReference);
      const share = snapshot.data();
      if (!snapshot.exists || !activeShareWindow(share, now)) {
        const chunks = await transaction.get(shareReference.collection(ROUTE_COLLECTION).limit(200));
        for (const chunk of chunks.docs) transaction.delete(chunk.ref);
        return {writtenCount: 0, deletedCount: chunks.docs.length, cleanup: true};
      }
      const writes = await prepareRouteChunkWrites(transaction, shareReference, share, [location], now);
      applyRouteChunkWrites(transaction, writes);
      return {writtenCount: writes.length, deletedCount: 0, cleanup: false};
    });
    writtenCount += result.writtenCount;
    deletedCount += result.deletedCount;
    if (!result.cleanup || result.deletedCount < 200) return {writtenCount, deletedCount};
  }
}

// Link recovery scans only private chunks overlapping this share's lifetime, never the entire hike.
async function backfillHikeRoute(db, {sessionId, shareId, uid, phoneNumber}, clock = Date.now) {
  if (!validId(sessionId) || !validId(shareId)) return {writtenCount: 0, pageCount: 0};
  const sessionReference = db.collection('hikeSessions').doc(sessionId);
  const shareReference = db.collection('live_location_shares').doc(shareId);
  let cursor = null, writtenCount = 0, pageCount = 0;
  while (true) {
    const result = await db.runTransaction(async transaction => {
      const now = typeof clock === 'function' ? clock() : clock;
      const [hikeSnapshot, shareSnapshot] = await Promise.all([
        transaction.get(sessionReference), transaction.get(shareReference),
      ]);
      const hike = hikeSnapshot.data(), share = shareSnapshot.data();
      if (!hikeSnapshot.exists || !shareSnapshot.exists
          || !hikeConsentsToShare(hike, share, {shareId, uid, phoneNumber}, now)) return {stop: true};
      const window = activeShareWindow(share, now);
      let query = db.collection('footprints').where('sessionId', '==', sessionId)
        .where('lastRecordedAtMillis', '>=', window.startedAtMillis)
        .where('firstRecordedAtMillis', '<', window.expiresAtMillis)
        .orderBy('lastRecordedAtMillis').orderBy('firstRecordedAtMillis').limit(BACKFILL_PAGE_SIZE);
      if (cursor) query = query.startAfter(cursor);
      const chunks = await transaction.get(query);
      const references = new Set((Array.isArray(hike.footprint) ? hike.footprint : []).map(ref => ref?.path));
      const samples = [];
      for (const chunk of chunks.docs) {
        const data = chunk.data();
        if (!references.has(chunk.ref.path) || data?.sessionId !== sessionId
            || !Array.isArray(data.samples) || data.samples.length > 50) continue;
        samples.push(...data.samples);
      }
      const writes = await prepareRouteChunkWrites(transaction, shareReference, share, samples, now);
      applyRouteChunkWrites(transaction, writes);
      return {count: chunks.docs.length, last: chunks.docs.at(-1), writtenCount: writes.length};
    });
    if (result.stop) return {writtenCount, pageCount};
    pageCount += 1;
    writtenCount += result.writtenCount;
    if (result.count < BACKFILL_PAGE_SIZE) return {writtenCount, pageCount};
    cursor = result.last;
  }
}

module.exports = {ROUTE_COLLECTION, SLOT_MILLIS, BUCKET_MILLIS, BACKFILL_PAGE_SIZE,
  activeShareWindow, normalizeRoutePoint, prepareRouteChunkWrites, applyRouteChunkWrites,
  prepareHikeRouteWrites, projectShareLocation, backfillHikeRoute};

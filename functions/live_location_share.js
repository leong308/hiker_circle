// Explicit activation renews an owned share for 24 hours without resetting its consent boundary.
const {readUser, setUser} = require('./user_modules');
'use strict';
const { milliseconds } = require('./footprint_batch');
const SHARE_LIFETIME_MILLIS = 24 * 3600000;
const ROUTE_REFRESH_PAGE_SIZE = 200;

function locationVersion(location) {
  return milliseconds(location?.recordedAtMillis ?? location?.capturedAtLocal);
}

// The ISO creation time is server-generated at activation and preserves the
// original consent boundary across renewals; the commit timestamp is a fallback.
function originalShareStartedAtMillis(share, expiresAtMillis, now) {
  const candidates = [milliseconds(share.createdAtLocal), milliseconds(share.createdAt),
    expiresAtMillis - SHARE_LIFETIME_MILLIS];
  return candidates.find(value => Number.isFinite(value) && value > 0 && value <= now)
    ?? Math.min(now, Math.max(1, expiresAtMillis - SHARE_LIFETIME_MILLIS));
}

// normalizeLocation: Reject invalid coordinates and normalize the GPS sample version.
function normalizeLocation(data, ErrorType, now) {
  const latitude = data?.latitude, longitude = data?.longitude;
  if (typeof latitude !== 'number' || !Number.isFinite(latitude) || Math.abs(latitude) > 90
      || typeof longitude !== 'number' || !Number.isFinite(longitude) || Math.abs(longitude) > 180) {
    throw new ErrorType('invalid-argument', 'A valid location is required.');
  }
  const captured = milliseconds(data.capturedAtLocal ?? now);
  if (!Number.isFinite(captured) || captured > now + 5 * 60000) {
    throw new ErrorType('invalid-argument', 'The location capture time is invalid.');
  }
  const accuracy = data.accuracyMeters;
  if (accuracy != null && (typeof accuracy !== 'number' || !Number.isFinite(accuracy) || accuracy < 0 || accuracy > 10000)) {
    throw new ErrorType('invalid-argument', 'The location accuracy is invalid.');
  }
  return { latitude, longitude, capturedAtLocal: new Date(captured).toISOString(),
    ...(accuracy != null ? { accuracyMeters: accuracy } : {}),
    universalMapLink: `https://www.google.com/maps/search/?api=1&query=${latitude},${longitude}` };
}

// Extend route retention before publishing the renewed expiry. The reservation is
// not public access: recipients still need an active, unexpired parent share.
// Route writers also honour this reservation, including chunks added behind the
// pagination cursor while a renewal is in progress.
async function refreshRouteRetention(db, shareRef, uid, ErrorType, clock) {
  let cursor = null;
  while (true) {
    const result = await db.runTransaction(async tx => {
      // Query live share and stored route chunks
      const snapshot = await tx.get(shareRef);
      const share = snapshot.data() || {};
      const expiry = milliseconds(share.expiresAt);
      if (!snapshot.exists || share.ownerUserId !== uid || share.isActive !== true
          || !Number.isFinite(expiry) || expiry <= clock()) {
        throw new ErrorType('failed-precondition', 'The share stopped or expired. Start sharing again.');
      }
      const retention = share.routeRetentionExpiresAt;
      if (!Number.isFinite(milliseconds(retention))) {
        throw new ErrorType('failed-precondition', 'The share renewal could not be prepared.');
      }
      let query = shareRef.collection('live_location_route_chunks')
        .orderBy('__name__').limit(ROUTE_REFRESH_PAGE_SIZE);
      if (cursor) query = query.startAfter(cursor);
      const chunks = await tx.get(query);
      for (const chunk of chunks.docs) {
        if (!(milliseconds(chunk.data().expiresAt) >= milliseconds(retention))) {
          // Update cloud: extend route chunk retention
          tx.set(chunk.ref, {expiresAt: retention}, {merge: true});
        }
      }
      return {count: chunks.docs.length, last: chunks.docs.at(-1)};
    });
    if (result.count < ROUTE_REFRESH_PAGE_SIZE) return;
    cursor = result.last;
  }
}

function requireAvailableAccount(snapshot, phoneNumber, ErrorType) {
  const user = snapshot.data() || {};
  if (!snapshot.exists || user.phoneNumber !== phoneNumber || user.accountDisabled === true || user.status === 'disabled') {
    throw new ErrorType('permission-denied', 'Your account is unavailable.');
  }
  return user;
}

// activateLiveLocationShare: Renew the same active link; revoked or expired links get a fresh opaque ID.
async function activateLiveLocationShare(db, { uid, phoneNumber, location }, ErrorType, fieldTimestamp, timestampFromMillis, clock = Date.now) {
  const now = typeof clock === 'function' ? clock() : clock;
  const currentTime = () => typeof clock === 'function' ? Math.max(now, clock()) : now;
  const safeLocation = normalizeLocation(location, ErrorType, now);
  const userRef = db.collection('users').doc(uid);
  const newShareRef = db.collection('live_location_shares').doc();
  const expiresAtMillis = now + SHARE_LIFETIME_MILLIS;
  const writeActivation = (tx, shareRef, old, reuse, startedAtMillis, expiry) => {
    const shareUrl = `https://hiker-circle.web.app/live-location?share=${shareRef.id}`;
    const latestLocation = reuse && locationVersion(old.latestLocation) > locationVersion(safeLocation)
      ? old.latestLocation : safeLocation;
    // Update cloud: save share and owner reference
    tx.set(shareRef, { shareId: shareRef.id, ownerUserId: uid, phoneNumber,
      ownerUserDocumentPath: userRef.path, isActive: true, latestLocation, shareUrl,
      expiresAt: timestampFromMillis(expiry), expiresAtLocal: new Date(expiry).toISOString(),
      updatedAt: fieldTimestamp(), updatedAtLocal: new Date(now).toISOString(),
      ...(!reuse ? { createdAt: fieldTimestamp(), createdAtLocal: new Date(now).toISOString() } : {}),
    }, { merge: true });
    setUser(tx, userRef, { liveLocationEnabled: true, liveLocationShareId: shareRef.id,
      liveLocationShareUrl: shareUrl, liveLocation: latestLocation,
      liveLocationStartedAt: timestampFromMillis(startedAtMillis), liveLocationStartedAtLocal: new Date(startedAtMillis).toISOString(),
      liveLocationExpiresAt: timestampFromMillis(expiry), liveLocationExpiresAtLocal: new Date(expiry).toISOString(),
      liveLocationUpdatedAt: fieldTimestamp(), liveLocationUpdatedAtLocal: new Date(now).toISOString(),
    }, { merge: true });
    return { shareId: shareRef.id, shareUrl, startedAtMillis, expiresAtMillis: expiry };
  };
  const prepared = await db.runTransaction(async tx => {
    // Query owner's location module and previous share
    const userSnapshot = await readUser(userRef, ["location"], tx);
    const user = requireAvailableAccount(userSnapshot, phoneNumber, ErrorType);
    const oldId = String(user.liveLocationShareId || '');
    const oldRef = oldId && !oldId.includes('/') ? db.collection('live_location_shares').doc(oldId) : null;
    const oldSnapshot = oldRef ? await tx.get(oldRef) : null;
    const old = oldSnapshot?.data() || {};
    // Each explicit activation renews expiry. Reuse only an active owned link;
    // a revoked or expired URL must never become public again.
    const reuse = oldSnapshot?.exists && old.ownerUserId === uid && old.isActive === true
      && milliseconds(old.expiresAt) > now;
    if (!reuse) return {result: writeActivation(tx, newShareRef, {}, false, now, expiresAtMillis)};
    const startedAtMillis = originalShareStartedAtMillis(old, milliseconds(old.expiresAt), now);
    const retentionMillis = Math.max(expiresAtMillis, milliseconds(old.routeRetentionExpiresAt) || 0);
    // Update cloud: update previous live share
    tx.set(oldRef, {
      routeRetentionExpiresAt: timestampFromMillis(retentionMillis),
      // Older shares without a stored creation instant must retain their
      // reconstructed consent boundary when the expiry moves forward.
      ...(![old.createdAtLocal, old.createdAt].some(value => {
        const time = milliseconds(value);
        return Number.isFinite(time) && time > 0 && time <= now;
      }) ? {createdAtLocal: new Date(startedAtMillis).toISOString()} : {}),
    }, {merge: true});
    return {shareRef: oldRef, startedAtMillis};
  });
  if (prepared.result) return prepared.result;
  await refreshRouteRetention(db, prepared.shareRef, uid, ErrorType, currentTime);
  // A failed refresh leaves public expiry untouched. Recheck owner and stop
  // state after paging so a concurrent opt-out cannot be undone by renewal.
  return db.runTransaction(async tx => {
    // Query current settings and prepared share
    const userSnapshot = await readUser(userRef, ["location"], tx);
    const user = requireAvailableAccount(userSnapshot, phoneNumber, ErrorType);
    const snapshot = await tx.get(prepared.shareRef);
    const share = snapshot.data() || {};
    const currentExpiry = milliseconds(share.expiresAt);
    if (user.liveLocationShareId !== prepared.shareRef.id || !snapshot.exists
        || share.ownerUserId !== uid || share.isActive !== true
        || !Number.isFinite(currentExpiry) || currentExpiry <= currentTime()) {
      throw new ErrorType('failed-precondition', 'The share stopped or expired. Start sharing again.');
    }
    return writeActivation(tx, prepared.shareRef, share, true, prepared.startedAtMillis,
      Math.max(expiresAtMillis, currentExpiry));
  });
}
module.exports = { locationVersion, normalizeLocation, activateLiveLocationShare };

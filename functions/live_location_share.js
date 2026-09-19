'use strict';
const { milliseconds } = require('./location_batch');

function locationVersion(location) {
  return milliseconds(location?.recordedAtMillis ?? location?.capturedAtLocal);
}

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

async function activateLiveLocationShare(db, { uid, phoneNumber, location }, ErrorType, fieldTimestamp, timestampFromMillis, now = Date.now()) {
  const safeLocation = normalizeLocation(location, ErrorType, now);
  const userRef = db.collection('users').doc(uid);
  const newShareRef = db.collection('live_location_shares').doc();
  return db.runTransaction(async tx => {
    const userSnapshot = await tx.get(userRef);
    const user = userSnapshot.data() || {};
    if (!userSnapshot.exists || user.phoneNumber !== phoneNumber || user.accountDisabled === true || user.status === 'disabled') {
      throw new ErrorType('permission-denied', 'Your account is unavailable.');
    }
    const oldId = String(user.liveLocationShareId || '');
    const oldRef = oldId && !oldId.includes('/') ? db.collection('live_location_shares').doc(oldId) : null;
    const oldSnapshot = oldRef ? await tx.get(oldRef) : null;
    const old = oldSnapshot?.data() || {};
    // Retry an activation without extending its original lifetime. Revoked or
    // expired shares get a fresh opaque ID, so old links remain revoked.
    const reuse = oldSnapshot?.exists && old.ownerUserId === uid && old.isActive === true
      && milliseconds(old.expiresAt) > now;
    const shareRef = reuse ? oldRef : newShareRef;
    const expiresAtMillis = reuse ? milliseconds(old.expiresAt) : now + 24 * 3600000;
    const shareUrl = `https://hiker-circle.web.app/live-location?share=${shareRef.id}`;
    const latestLocation = reuse && locationVersion(old.latestLocation) > locationVersion(safeLocation)
      ? old.latestLocation : safeLocation;
    tx.set(shareRef, { shareId: shareRef.id, ownerUserId: uid, phoneNumber,
      ownerUserDocumentPath: userRef.path, isActive: true, latestLocation, shareUrl,
      expiresAt: timestampFromMillis(expiresAtMillis), expiresAtLocal: new Date(expiresAtMillis).toISOString(),
      updatedAt: fieldTimestamp(), updatedAtLocal: new Date(now).toISOString(),
      ...(!reuse ? { createdAt: fieldTimestamp(), createdAtLocal: new Date(now).toISOString() } : {}),
    }, { merge: true });
    tx.set(userRef, { liveLocationEnabled: true, liveLocationShareId: shareRef.id,
      liveLocationShareUrl: shareUrl, liveLocation: latestLocation,
      liveLocationExpiresAt: timestampFromMillis(expiresAtMillis), liveLocationExpiresAtLocal: new Date(expiresAtMillis).toISOString(),
      liveLocationUpdatedAt: fieldTimestamp(), liveLocationUpdatedAtLocal: new Date(now).toISOString(),
    }, { merge: true });
    return { shareId: shareRef.id, shareUrl, expiresAtMillis };
  });
}
module.exports = { locationVersion, normalizeLocation, activateLiveLocationShare };

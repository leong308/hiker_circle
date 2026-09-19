'use strict';

function milliseconds(value) {
  if (typeof value?.toMillis === 'function') return value.toMillis();
  if (typeof value?.toDate === 'function') return value.toDate().getTime();
  if (typeof value === 'number') return value;
  return typeof value === 'string' ? Date.parse(value) : NaN;
}

function parseLocationBatch(points, ErrorType, now = Date.now()) {
  if (!Array.isArray(points) || points.length < 1 || points.length > 200) {
    throw new ErrorType('invalid-argument', 'Send between one and 200 location samples.');
  }
  const unique = new Map();
  for (const point of points) {
    const time = point?.recordedAtMillis;
    const lat = point?.latitude;
    const lng = point?.longitude;
    const fixTime = point?.fixCapturedAtMillis ?? time;
    if (!Number.isSafeInteger(time) || time <= 0 || time > now + 5 * 60000
        || !Number.isSafeInteger(fixTime) || fixTime <= 0 || fixTime > time + 5 * 60000
        || typeof lat !== 'number' || !Number.isFinite(lat) || Math.abs(lat) > 90
        || typeof lng !== 'number' || !Number.isFinite(lng) || Math.abs(lng) > 180) {
      throw new ErrorType('invalid-argument', 'A location sample has invalid coordinates or timestamps.');
    }
    const safe = { recordedAtMillis: time, fixCapturedAtMillis: fixTime,
      latitude: lat, longitude: lng, recordedAtLocal: new Date(time).toISOString(),
      pointType: String(point.pointType || 'automatic').slice(0, 40) };
    for (const [key, min, max] of [['accuracyMeters', 0, 10000], ['altitudeMeters', -1000, 100000], ['batteryLevel', 0, 100]]) {
      if (point[key] != null) {
        if (typeof point[key] !== 'number' || !Number.isFinite(point[key]) || point[key] < min || point[key] > max) {
          throw new ErrorType('invalid-argument', `Invalid ${key} in location sample.`);
        }
        safe[key] = key === 'batteryLevel' ? Math.round(point[key]) : point[key];
      }
    }
    // Identity belongs to the sample timestamp, never its coordinates.
    if (!unique.has(time)) unique.set(time, safe);
  }
  return [...unique.values()].sort((a, b) => a.recordedAtMillis - b.recordedAtMillis);
}

async function recordLocationBatch(db, { sessionId, uid, phoneNumber, points }, ErrorType, timestamp, now = Date.now()) {
  const samples = parseLocationBatch(points, ErrorType, now);
  const sessionRef = db.collection('hikeSessions').doc(sessionId);
  const pointRefs = samples.map(p => db.collection('localLocationPoints')
    .doc(`${sessionId.replace(/[^A-Za-z0-9_-]/g, '_')}_${p.recordedAtMillis}`));
  return db.runTransaction(async tx => {
    const [sessionSnapshot, ...existing] = await Promise.all([
      tx.get(sessionRef), ...pointRefs.map(ref => tx.get(ref)),
    ]);
    const hike = sessionSnapshot.data() || {};
    if (!sessionSnapshot.exists || hike.userId !== uid || hike.userPhoneNumber !== phoneNumber) {
      throw new ErrorType('permission-denied', 'This hike does not belong to your account.');
    }
    if (!['active', 'completed', 'abandoned'].includes(hike.status)) {
      throw new ErrorType('failed-precondition', 'This hike cannot receive saved location samples.');
    }
    const start = milliseconds(hike.startedAtLocal || hike.startedAt);
    const canonical = samples.map((sample, index) => {
      // A terminal cloud decision can precede an offline device receiving it.
      // Preserve owner telemetry without changing or reopening lifecycle state.
      if (!Number.isFinite(start) || sample.recordedAtMillis < start - 10 * 60000) {
        throw new ErrorType('invalid-argument', 'The sample timestamp is outside this hike.');
      }
      if (existing[index].exists) {
        const old = existing[index].data() || {};
        if (old.userId !== uid || old.sessionId !== sessionId) {
          throw new ErrorType('permission-denied', 'A sample identity conflicts with another hike.');
        }
        return old;
      }
      const data = { ...sample, sessionId, userId: uid, userPhoneNumber: phoneNumber,
        trailId: String(hike.trailId || ''), isSynced: true, committedAt: timestamp(),
        ...(sample.altitudeMeters != null ? { altitude: sample.altitudeMeters } : {}) };
      tx.create(pointRefs[index], data);
      return data;
    });
    const latest = canonical.reduce((a, b) => Number(a.recordedAtMillis || 0) > Number(b.recordedAtMillis || 0) ? a : b);
    const previousTime = milliseconds(hike.latestLocation?.recordedAtMillis
      ?? hike.latestLocation?.capturedAtLocal ?? hike.latestLocationUpdatedAtLocal);
    if (!Number.isFinite(previousTime) || latest.recordedAtMillis > previousTime) {
      tx.set(sessionRef, {
        latestLocation: { latitude: latest.latitude, longitude: latest.longitude,
          recordedAtMillis: latest.recordedAtMillis, fixCapturedAtMillis: latest.fixCapturedAtMillis,
          capturedAtLocal: new Date(latest.fixCapturedAtMillis ?? latest.recordedAtMillis).toISOString(),
          ...(latest.accuracyMeters != null ? { accuracyMeters: latest.accuracyMeters } : {}) },
        latestLocationUpdatedAt: timestamp(),
        latestLocationUpdatedAtLocal: new Date(latest.recordedAtMillis).toISOString(),
        lastGpsActivityAtMillis: latest.fixCapturedAtMillis ?? latest.recordedAtMillis,
        updatedAt: timestamp(),
      }, { merge: true });
    }
    return { sessionId, committedCount: samples.length,
      committedRecordedAtMillis: samples.map(p => p.recordedAtMillis),
      committedPointIds: pointRefs.map(ref => ref.id) };
  });
}

module.exports = { milliseconds, parseLocationBatch, recordLocationBatch };

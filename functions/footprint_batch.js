// Private GPS footprints pack up to 50 timestamp-identified samples per chunk with durable acknowledgements.
'use strict';

const { createHash } = require('node:crypto');
const MAX_SAMPLES = 50;
// Leave room for later safety/lifecycle updates on the parent hike.
const DOCUMENT_BUDGET = 960 * 1024;

function valueBytes(value) {
  if (value == null || typeof value === 'boolean') return 1;
  if (typeof value === 'string') return Buffer.byteLength(value, 'utf8') + 1;
  if (typeof value === 'number' || value instanceof Date || typeof value.toMillis === 'function') return 8;
  if (Buffer.isBuffer(value)) return value.length;
  if (typeof value.path === 'string' && value.firestore) return referenceBytes(value.path);
  if (Array.isArray(value)) return value.reduce((sum, item) => sum + valueBytes(item), 0);
  return 32 + Object.entries(value).reduce((sum, [key, item]) => sum + valueBytes(key) + valueBytes(item), 0);
}

function referenceBytes(path) {
  return path.split('/').reduce((sum, part) => sum + valueBytes(part), 16);
}

function documentBytes(path, data) { return referenceBytes(path) + valueBytes(data); }

function footprintId(sessionId, index) {
  return `${createHash('sha256').update(sessionId).digest('hex').slice(0, 32)}_${index}`;
}

function milliseconds(value) {
  if (typeof value?.toMillis === 'function') return value.toMillis();
  if (typeof value?.toDate === 'function') return value.toDate().getTime();
  if (typeof value === 'number') return value;
  return typeof value === 'string' ? Date.parse(value) : NaN;
}

// parseFootprintBatch: Validate sample bounds, then deduplicate by recorded time instead of coordinates.
function parseFootprintBatch(points, ErrorType, now = Date.now()) {
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
      latitude: lat, longitude: lng,
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

// appendFootprints: Serialize ownership, chunk allocation, sample identity, and latest-location updates through the parent hike.
async function appendFootprints(db, { sessionId, uid, phoneNumber, footprints }, ErrorType, timestamp, now = Date.now()) {
  const samples = parseFootprintBatch(footprints, ErrorType, now);
  const sessionRef = db.collection('hikeSessions').doc(sessionId);
  return db.runTransaction(async tx => {
    const sessionSnapshot = await tx.get(sessionRef);
    const hike = sessionSnapshot.data() || {};
    if (!sessionSnapshot.exists || hike.userId !== uid || hike.userPhoneNumber !== phoneNumber) {
      throw new ErrorType('permission-denied', 'This hike does not belong to your account.');
    }
    if (!['active', 'completed', 'abandoned'].includes(hike.status)) {
      throw new ErrorType('failed-precondition', 'This hike cannot receive saved location samples.');
    }
    const start = milliseconds(hike.startedAtLocal || hike.startedAt);
    for (const sample of samples) {
      // A terminal cloud decision can precede an offline device receiving it.
      // Preserve owner telemetry without changing or reopening lifecycle state.
      if (!Number.isFinite(start) || sample.recordedAtMillis < start - 10 * 60000) {
        throw new ErrorType('invalid-argument', 'The sample timestamp is outside this hike.');
      }
    }
    const references = Array.isArray(hike.footprint) ? [...hike.footprint] : [];
    if (references.some((ref) => typeof ref?.path !== 'string' || !/^footprints\/[^/]+$/.test(ref.path))) {
      throw new ErrorType('failed-precondition', 'The hike footprint references are invalid.');
    }
    // Range overlap finds retries even when a device uploads old offline samples.
    // Reading the parent serializes concurrent Flutter/native writers and chunk allocation.
    const overlaps = await tx.get(db.collection('footprints')
      .where('sessionId', '==', sessionId)
      .where('lastRecordedAtMillis', '>=', samples[0].recordedAtMillis)
      .where('firstRecordedAtMillis', '<=', samples.at(-1).recordedAtMillis)
      .orderBy('lastRecordedAtMillis').orderBy('firstRecordedAtMillis'));
    const snapshots = new Map(overlaps.docs.map((snapshot) => [snapshot.ref.path, snapshot]));
    const tailRef = references.at(-1);
    if (tailRef && !snapshots.has(tailRef.path)) snapshots.set(tailRef.path, await tx.get(tailRef));
    const existing = new Map();
    for (const snapshot of snapshots.values()) {
      const chunk = snapshot.data();
      if (!snapshot.exists || chunk.sessionId !== sessionId || !Array.isArray(chunk.samples)
          || chunk.samples.length > MAX_SAMPLES || !references.some(ref => ref.path === snapshot.ref.path)) {
        throw new ErrorType('failed-precondition', 'A footprint chunk is missing or inconsistent.');
      }
      for (const sample of chunk.samples) existing.set(sample.recordedAtMillis, sample);
    }
    const canonical = samples.map(sample => existing.get(sample.recordedAtMillis) || sample);
    const pending = samples.filter(sample => !existing.has(sample.recordedAtMillis));
    const changes = [];
    let tailSamples = tailRef ? [...snapshots.get(tailRef.path).data().samples] : [];
    let ref = tailRef;
    for (const sample of pending) {
      if (!ref || tailSamples.length === MAX_SAMPLES) {
        if (ref && changes.at(-1)?.ref.path === ref.path) changes.at(-1).samples = tailSamples;
        ref = db.collection('footprints').doc(footprintId(sessionId, references.length));
        references.push(ref);
        tailSamples = [];
      }
      if (changes.at(-1)?.ref.path !== ref.path) changes.push({ ref, samples: tailSamples });
      tailSamples.push(sample);
    }
    for (const change of changes) {
      change.samples.sort((a, b) => a.recordedAtMillis - b.recordedAtMillis);
      change.data = { sessionId, samples: change.samples,
        firstRecordedAtMillis: change.samples[0].recordedAtMillis,
        lastRecordedAtMillis: change.samples.at(-1).recordedAtMillis };
      if (documentBytes(change.ref.path, change.data) > DOCUMENT_BUDGET) {
        throw new ErrorType('resource-exhausted', 'The footprint chunk is too large; samples remain queued on your device.');
      }
    }
    const patch = pending.length ? { footprint: references } : {};
    const latest = canonical.reduce((a, b) => Number(a.recordedAtMillis || 0) > Number(b.recordedAtMillis || 0) ? a : b);
    const previousTime = milliseconds(hike.latestLocation?.recordedAtMillis
      ?? hike.latestLocation?.capturedAtLocal ?? hike.latestLocationUpdatedAtLocal);
    if (!Number.isFinite(previousTime) || latest.recordedAtMillis > previousTime) {
      Object.assign(patch, {
        latestLocation: { latitude: latest.latitude, longitude: latest.longitude,
          recordedAtMillis: latest.recordedAtMillis, fixCapturedAtMillis: latest.fixCapturedAtMillis,
          capturedAtLocal: new Date(latest.fixCapturedAtMillis ?? latest.recordedAtMillis).toISOString(),
          ...(latest.accuracyMeters != null ? { accuracyMeters: latest.accuracyMeters } : {}) },
        latestLocationUpdatedAt: timestamp(),
        latestLocationUpdatedAtLocal: new Date(latest.recordedAtMillis).toISOString(),
        lastGpsActivityAtMillis: latest.fixCapturedAtMillis ?? latest.recordedAtMillis,
        updatedAt: timestamp(),
      });
    }
    // A fresh recorded arrival cancels overdue-arrival work before any sender can claim it.
    if (hike.arrivalSafety?.enabled) {
      const {arrivalPlan, advanceArrivalProof} = require('./hike_arrival_policy');
      const plan = arrivalPlan(hike);
      const proof = advanceArrivalProof(plan, canonical, hike.arrivalSafety.proof, now);
      patch.arrivalSafety = {...hike.arrivalSafety, proof,
        ...(proof.arrivedAtMillis ? {enabled: false, status: 'arrived', arrivedAtMillis: proof.arrivedAtMillis, targetName: proof.targetName} : {})};
    }
    // Estimate with concrete timestamps, not FieldValue sentinels.
    const sizedPatch = { ...patch, ...(patch.updatedAt ? { updatedAt: new Date(now), latestLocationUpdatedAt: new Date(now) } : {}) };
    if (Object.keys(patch).length && documentBytes(sessionRef.path, { ...hike, ...sizedPatch }) > DOCUMENT_BUDGET) {
      throw new ErrorType('resource-exhausted', 'The hike reference list is full; samples remain queued on your device.');
    }
    const liveRoute = require('./live_location_route');
    const publicRouteWrites = await liveRoute.prepareHikeRouteWrites(tx, db, {
      hike, samples: canonical, uid, phoneNumber,
    }, now);
    for (const change of changes) {
      if (snapshots.has(change.ref.path)) tx.set(change.ref, change.data);
      else tx.create(change.ref, change.data);
    }
    if (Object.keys(patch).length) tx.set(sessionRef, patch, { merge: true });
    liveRoute.applyRouteChunkWrites(tx, publicRouteWrites);
    return { sessionId, committedCount: samples.length,
      committedRecordedAtMillis: samples.map(p => p.recordedAtMillis) };
  });
}

// loadFootprints: Verify every referenced chunk belongs to the requested hike before assembling its chronological route.
async function loadFootprints(db, sessionId, references) {
  const samples = new Map();
  const refs = Array.isArray(references) ? references : [];
  // Bounded reads avoid one very large getAll request on long hikes.
  for (let offset = 0; offset < refs.length; offset += 100) {
    const batch = refs.slice(offset, offset + 100);
    if (batch.some(ref => typeof ref?.path !== 'string' || !/^footprints\/[^/]+$/.test(ref.path))) {
      throw new Error('Invalid footprint reference.');
    }
    for (const snapshot of await db.getAll(...batch)) {
      const chunk = snapshot.data();
      if (!snapshot.exists || chunk.sessionId !== sessionId || !Array.isArray(chunk.samples)) {
        throw new Error('Missing or inconsistent footprint chunk.');
      }
      for (const sample of chunk.samples) if (!samples.has(sample.recordedAtMillis)) samples.set(sample.recordedAtMillis, sample);
    }
  }
  return [...samples.values()].sort((a, b) => a.recordedAtMillis - b.recordedAtMillis);
}

module.exports = { milliseconds, parseFootprintBatch, appendFootprints, loadFootprints,
  footprintId, documentBytes, MAX_SAMPLES, DOCUMENT_BUDGET };

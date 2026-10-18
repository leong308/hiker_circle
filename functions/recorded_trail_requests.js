// Recorded-route submissions validate owner tracks and chunk integrity before publishing a reviewable trail request.
'use strict';
const { createHash } = require('node:crypto');
const { isUnlistedSessionTrail } = require('./unlisted_hikes');
const MAX_POINTS = 100000,
  CHUNK_SIZE = 500;
const sha = (text) => createHash('sha256').update(text).digest('hex');
function invalid() {
  const e = Error('Invalid recorded route or checkpoint selection.');
  e.code = 'invalid-argument';
  throw e;
}
function routeHash(points) {
  return sha(
    points
      .map(
        (p) =>
          `${Number(p.lat).toFixed(8)},${Number(p.lon).toFixed(8)},${p.time}`,
      )
      .join('\n'),
  );
}
function identity(raw) {
  const result = {};
  for (const key of ['name', 'area', 'state', 'country']) {
    if (
      typeof raw?.[key] !== 'string' ||
      !raw[key].trim() ||
      raw[key].length > 160
    )
      invalid();
    result[key] = raw[key].trim();
  }
  return result;
}
function validateSelections(values, count) {
  if (!Array.isArray(values) || values.length < 3 || values.length > 12)
    invalid();
  let previous = -1;
  const rows = values.map((row) => {
    if (
      !row ||
      typeof row !== 'object' ||
      !Number.isInteger(row.index) ||
      row.index <= previous ||
      row.index >= count ||
      typeof row.name !== 'string' ||
      !row.name.trim() ||
      row.name.length > 100
    )
      invalid();
    previous = row.index;
    return { index: row.index, name: row.name.trim() };
  });
  if (rows[0].index !== 0 || rows.at(-1).index !== count - 1) invalid();
  return rows;
}
// validateTrack: Verify ordered coordinates belong to the completed source hike before accepting its geometry.
function validateTrack(points, session) {
  if (
    !Array.isArray(points) ||
    points.length < 3 ||
    points.length > MAX_POINTS ||
    points.some((p) => !p || typeof p !== 'object' || Array.isArray(p)) ||
    new Set(points.map((p) => `${p.lat},${p.lon}`)).size < 2
  )
    invalid();
  let previous = -Infinity;
  const start = Date.parse(session.startedAtLocal),
    end = Date.parse(session.endedAtLocal);
  if (!Number.isFinite(start) || !Number.isFinite(end)) invalid();
  for (const p of points) {
    if (
      Object.keys(p).some(
        (k) =>
          !['lat', 'lon', 'time', 'altitudeMeters', 'accuracyMeters'].includes(
            k,
          ),
      )
    )
      invalid();
    const t = Date.parse(p.time);
    if (
      typeof p.time !== 'string' ||
      typeof p.lat !== 'number' ||
      typeof p.lon !== 'number' ||
      !Number.isFinite(p.lat) ||
      !Number.isFinite(p.lon) ||
      Math.abs(p.lat) > 90 ||
      Math.abs(p.lon) > 180 ||
      !Number.isFinite(t) ||
      t < previous ||
      t < start - 300000 ||
      t > end + 300000
    )
      invalid();
    previous = t;
    for (const key of ['altitudeMeters', 'accuracyMeters'])
      if (
        p[key] !== undefined &&
        (typeof p[key] !== 'number' || !Number.isFinite(p[key]))
      )
        invalid();
  }
  return points;
}
// beginRequest: Reserve one owner request identity with a stable route hash and expected chunk count.
async function beginRequest({ db, uid, data, now = Date.now }) {
  if (
    !/^[A-Za-z0-9_-]{1,240}$/.test(data?.sessionId || '') ||
    !Number.isInteger(data.pointCount) ||
    data.pointCount < 3 ||
    data.pointCount > MAX_POINTS ||
    !/^[a-f0-9]{64}$/.test(data.routeHash || '')
  )
    invalid();
  const proposed = identity(data.proposed);
  const selections = validateSelections(data.checkpoints, data.pointCount);
  const id = sha(`${uid}:${data.sessionId}`);
  const ref = db.doc(`trailRequests/${id}`);
  const result = await db.runTransaction(async (tx) => {
    const hike = await tx.get(db.doc(`hikeSessions/${data.sessionId}`));
    const existing = await tx.get(ref);
    const session = hike.data() || {};
    const account = await tx.get(db.doc(`users/${uid}`));
    if (
      !account.exists ||
      account.data()?.accountDisabled === true ||
      account.data()?.status === 'disabled'
    ) {
      const e = Error('Your account is unavailable.');
      e.code = 'permission-denied';
      throw e;
    }
    if (
      !hike.exists ||
      session.userId !== uid ||
      session.status !== 'completed' ||
      !isUnlistedSessionTrail(session.trail)
    ) {
      const e = Error(
        'Sync and complete your location hike before submitting a trail.',
      );
      e.code = 'failed-precondition';
      throw e;
    }
    if (existing.exists) {
      const current = existing.data();
      if (
        current.routeHash !== data.routeHash ||
        current.pointCount !== data.pointCount
      ) {
        const e = Error('This hike already has a different trail request.');
        e.code = 'already-exists';
        throw e;
      }
      if (current.status === 'uploading')
        tx.update(ref, { proposed, checkpointSelections: selections });
      return { requestId: id, status: current.status };
    }
    tx.create(ref, {
      ownerId: uid,
      sessionId: data.sessionId,
      status: 'uploading',
      proposed,
      checkpointSelections: selections,
      pointCount: data.pointCount,
      chunkCount: Math.ceil(data.pointCount / CHUNK_SIZE),
      routeHash: data.routeHash,
      createdAtMillis: now(),
    });
    return { requestId: id, status: 'uploading' };
  });
  return result;
}
// finalizeRequest: Re-read every route chunk and publish only after point/hash validation succeeds.
async function finalizeRequest({ db, uid, requestId, now = Date.now }) {
  if (!/^[a-f0-9]{64}$/.test(requestId || '')) invalid();
  const ref = db.doc(`trailRequests/${requestId}`);
  return db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const request = snapshot.data() || {};
    if (!snapshot.exists || request.ownerId !== uid) {
      const e = Error('This request is unavailable.');
      e.code = 'permission-denied';
      throw e;
    }
    if (request.status !== 'uploading')
      return { requestId, status: request.status };
    const chunks = await tx.get(ref.collection('routeChunks').orderBy('index'));
    const hike = await tx.get(db.doc(`hikeSessions/${request.sessionId}`));
    const session = hike.data() || {};
    const account = await tx.get(db.doc(`users/${uid}`));
    if (
      !account.exists ||
      account.data()?.accountDisabled === true ||
      account.data()?.status === 'disabled'
    ) {
      const e = Error('Your account is unavailable.');
      e.code = 'permission-denied';
      throw e;
    }
    if (session.userId !== uid || session.status !== 'completed') invalid();
    if (chunks.size !== request.chunkCount) invalid();
    const points = [];
    chunks.docs.forEach((doc, i) => {
      const c = doc.data();
      if (
        c.index !== i ||
        !Array.isArray(c.points) ||
        c.points.length !==
          Math.min(CHUNK_SIZE, request.pointCount - i * CHUNK_SIZE)
      )
        invalid();
      points.push(...c.points);
    });
    validateTrack(points, session);
    if (routeHash(points) !== request.routeHash) invalid();
    const selections = validateSelections(
      request.checkpointSelections,
      points.length,
    );
    const checkpoints = selections.map((selection, i) => ({
      name: selection.name,
      order: i + 1,
      latitude: points[selection.index].lat,
      longitude: points[selection.index].lon,
    }));
    tx.update(ref, {
      status: 'pending',
      submittedAtMillis: now(),
      checkpoints,
      durationMinutes: Number(session.durationMinutes) || 0,
      distanceKm: Number(session.distanceKm) || 0,
    });
    return { requestId, status: 'pending' };
  });
}

module.exports = {
  MAX_POINTS,
  CHUNK_SIZE,
  routeHash,
  identity,
  validateSelections,
  validateTrack,
  beginRequest,
  finalizeRequest,
};

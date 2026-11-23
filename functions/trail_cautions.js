// Community trail cautions validate evidence and transact confirmations, resolutions, and reopened report cycles.
'use strict';
const {randomUUID} = require('node:crypto');
const {TYPE_CATEGORIES, classifyHazard, hazardExpiry, hazardLifetimeMs, REPORT_LIFETIME_MS} = require('./trail_hazard_policy');
const MAX_MEDIA_BYTES = 50 * 1024 * 1024;
const LIFETIME_MS = REPORT_LIFETIME_MS;
const TYPES = TYPE_CATEGORIES;
const MIME = {'jpg':'image/jpeg','jpeg':'image/jpeg','png':'image/png','webp':'image/webp','gif':'image/gif','heic':'image/heic','heif':'image/heif','mp4':'video/mp4','mov':'video/quicktime','m4v':'video/x-m4v'};
function fail(code, message) { const e = Error(message); e.code = code; throw e; }
function id(value) { if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,180}$/.test(value)) fail('invalid-argument','Invalid caution identity.'); return value; }
function note(value) { if (value == null) return ''; if (typeof value !== 'string' || value.length > 1000) fail('invalid-argument','Keep your note under 1,000 characters.'); return value.trim(); }
function expires(report) { return hazardExpiry(report); }
function active(report, now) { return !['rejected','deleted'].includes(report.status) && Number.isFinite(expires(report)) && now < expires(report); }

// mediaFor: Verify owner paths, MIME types, file sizes, and the combined media budget.
async function mediaFor({bucket, uid, hazardId, media = []}) {
  if (!Array.isArray(media) || media.length > 6) fail('invalid-argument','Choose up to six photos or videos, totaling at most 50 MB.');
  const paths = new Set(); let total = 0; const result = [];
  for (const item of media) {
    const path = item?.storagePath;
    if (typeof path !== 'string' || !path.startsWith(`trail_cautions/${uid}/${hazardId}/`) || paths.has(path)
        || !/^[A-Za-z0-9_./-]+$/.test(path) || path.includes('..') || path.split('/').length !== 4) {
      fail('invalid-argument','Media must belong to this caution and your account.');
    }
    paths.add(path);
    const file = bucket.file(path); let metadata;
    // Query trail caution image metadata
    try { [metadata] = await file.getMetadata(); } catch (error) {
      if (Number(error.code) === 404) fail('invalid-argument','Media upload is incomplete. Please retry.');
      fail('unavailable','Evidence could not be verified yet. Please retry.');
    }
    const size = Number(metadata.size), contentType = MIME[path.split('.').at(-1).toLowerCase()];
    if (!contentType || metadata.contentType !== contentType || !Number.isSafeInteger(size) || size <= 0
        || metadata.metadata?.ownerUid !== uid || metadata.metadata?.hazardId !== hazardId) {
      fail('invalid-argument','This media file is not supported.');
    }
    total += size;
    if (total > MAX_MEDIA_BYTES) fail('invalid-argument','Photos and videos must total at most 50 MB.');
    let token = metadata.metadata?.firebaseStorageDownloadTokens?.split(',')[0];
    // Update cloud: save caution image download metadata
    if (!token) { token = randomUUID(); await file.setMetadata({metadata:{...metadata.metadata, firebaseStorageDownloadTokens:token}}); }
    result.push({storagePath:path, contentType, sizeBytes:size,
      name: typeof item.name === 'string' ? item.name.substring(0,160) : path.split('/').at(-1),
      url:`https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucket.name)}/o/${encodeURIComponent(path)}?alt=media&token=${encodeURIComponent(token)}`});
  }
  return result;
}

// submit: Create the caution and its initial confirmation vote under one stable report ID.
async function submit({db, bucket, uid, phone, data, now = Date.now(), timestamp}) {
  const hazardId = id(data?.hazardId), trailId = id(data?.trailId);
  if (data.expectedOwnerUid != null && data.expectedOwnerUid !== uid) {
    fail('permission-denied', 'This caution belongs to another reporting account.');
  }
  const description = note(data.description);
  if (!TYPES.has(data.hazardType) || typeof data.trailName !== 'string' || data.trailName.length > 180
      || !Number.isFinite(data.latitude) || Math.abs(data.latitude) > 90 || !Number.isFinite(data.longitude) || Math.abs(data.longitude) > 180) {
    fail('invalid-argument','Select a caution and a valid current location.');
  }
  const reference = db.collection('hazardReports').doc(hazardId);
  const media = await mediaFor({bucket, uid, hazardId, media:data.media});
  return db.runTransaction(async tx => {
    // Query existing caution by ID
    const existing = await tx.get(reference);
    if (existing.exists) {
      if (existing.data().reportedBy !== uid) fail('permission-denied','This report belongs to another hiker.');
      return {hazardId};
    }
    // Offline retries preserve when the hiker observed the caution. Do not
    // restart an old weather warning's lifetime at the time it finally uploads.
    const suppliedObservedAt = data.observedAtMillis;
    if (suppliedObservedAt != null && (!Number.isSafeInteger(suppliedObservedAt)
        || suppliedObservedAt <= 0 || suppliedObservedAt > now + 5 * 60000)) {
      fail('invalid-argument', 'The caution observation time is invalid. Check your device clock.');
    }
    const observedAt = Math.min(now, suppliedObservedAt ?? now);
    if (observedAt + hazardLifetimeMs(data.hazardType) <= now) {
      fail('failed-precondition', 'This saved caution is too old to publish. Submit a new report if it is still present.');
    }
    const reportedAt = timestamp(observedAt);
    // Update cloud: create hazard report and vote
    tx.create(reference, {hazardId, trailId, trailName:data.trailName.trim(), hazardType:data.hazardType,
      description, latitude:data.latitude, longitude:data.longitude, media, ...classifyHazard(data.hazardType),
      reportedBy:uid, reportedByPhoneNumber:phone, status:'unverified', reportLabel:'Community report',
      reportedAt, reportedAtLocal:new Date(observedAt).toISOString(),
      receivedAt:timestamp(now), receivedAtLocal:new Date(now).toISOString(),
      expiresAt:timestamp(observedAt + hazardLifetimeMs(data.hazardType)),
      reportCount:1, resolutionCount:0, cycle:0, resolutionId:null});
    tx.create(reference.collection('votes').doc(`0_confirm_${uid}`), {uid, kind:'confirm', cycle:0, createdAt:reportedAt});
    return {hazardId};
  });
}

// update: Fence the report cycle and apply each evidence-backed action once.
async function update({db, bucket, uid, data, now = Date.now(), timestamp}) {
  const hazardId = id(data?.hazardId), requestId = id(data?.requestId);
  const action = data.action;
  if (!['confirm','resolve','confirmResolution','reopen'].includes(action)) fail('invalid-argument','Choose a caution action.');
  const description = note(data.description);
  if (action === 'reopen' && (data.confirmed !== true || (!description && !data.media?.length))) {
    fail('failed-precondition','Confirm that the caution is present again and provide a note or media evidence.');
  }
  const media = await mediaFor({bucket, uid, hazardId, media:data.media});
  const reference = db.collection('hazardReports').doc(hazardId);
  return db.runTransaction(async tx => {
    // Query caution, update and viewer vote
    const reportSnapshot = await tx.get(reference);
    if (!reportSnapshot.exists) fail('not-found','This caution is unavailable.');
    const report = reportSnapshot.data();
    const eventRef = reference.collection('updates').doc(requestId);
    const existingEvent = await tx.get(eventRef);
    if (existingEvent.exists) {
      if (existingEvent.data().uid !== uid) fail('permission-denied','This update belongs to another hiker.');
      return {hazardId, duplicate:true};
    }
    if (!active(report, now)) fail('failed-precondition','This caution has expired. Submit a new report if it is still present.');
    let cycle = Number.isSafeInteger(report.cycle) ? report.cycle : 0;
    const resolved = report.status === 'resolved';
    if (action === 'confirm' && resolved) fail('failed-precondition','Reopening this caution requires confirmation and evidence.');
    if (action === 'reopen' && !resolved) fail('failed-precondition','The caution is already open. Confirm it instead.');
    if (action === 'confirmResolution' && !report.resolutionId) fail('failed-precondition','No resolution has been reported yet.');
    if (action === 'resolve' && resolved) return {hazardId, duplicate:true};
    const kind = ['resolve','confirmResolution'].includes(action) ? 'resolution' : 'confirm';
    if (action === 'reopen') cycle++;
    const voteRef = reference.collection('votes').doc(`${cycle}_${kind}_${uid}`);
    const vote = await tx.get(voteRef);
    const at = timestamp(now);
    if (vote.exists || (action === 'confirm' && cycle === 0 && report.reportedBy === uid)) {
      if (action === 'resolve' && (description || media.length)) {
        // Update cloud: save caution resolution evidence
        tx.create(eventRef, {uid, action, cycle, description, media, createdAt:at});
      }
      return {hazardId, duplicate:true};
    }
    const patch = {cycle, updatedAt:at, ...classifyHazard(report.hazardType)};
    if (kind === 'resolution') {
      patch.resolutionCount = (report.resolutionCount || 0) + 1;
      patch.resolutionId = report.resolutionId || requestId;
      if (patch.resolutionCount >= 3) { patch.status = 'resolved'; patch.resolvedAt = at; }
    } else {
      patch.reportCount = (report.reportCount || 1) + 1;
      if (action === 'reopen') {
        Object.assign(patch, {status:'unverified', resolutionCount:0, resolutionId:null, resolvedAt:null,
          latestEvidence:{description, media}});
      }
    }
    // Update cloud: save caution, vote and update
    tx.update(reference, patch);
    tx.create(voteRef, {uid, kind, cycle, createdAt:at});
    tx.create(eventRef, {uid, action, cycle, description, media, createdAt:at});
    return {hazardId, reportCount:patch.reportCount ?? report.reportCount ?? 1,
      resolutionCount:patch.resolutionCount ?? report.resolutionCount ?? 0, status:patch.status ?? report.status};
  });
}
module.exports = {submit, update, mediaFor, active, expires, MAX_MEDIA_BYTES, LIFETIME_MS};

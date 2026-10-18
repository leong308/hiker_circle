// Canonical community publishing, reactions, comments, moderation, and media cleanup share server-owned transactions.
'use strict';

const { getDownloadURL } = require('firebase-admin/storage');
const MAX_IMAGES = 6;
const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const MAX_PREVIEW_POINTS = 80;

function validId(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 200
    && !value.includes('/') && !/[\u0000-\u001f]/.test(value);
}
function fail(ErrorType, code, message) { throw new ErrorType(code, message); }
function requireId(value, label, ErrorType) {
  if (!validId(value)) fail(ErrorType, 'invalid-argument', `The ${label} is invalid.`);
  return value;
}
function captionValue(value, ErrorType) {
  if (typeof value !== 'string' || value.length > 5000) fail(ErrorType, 'invalid-argument', 'Captions can contain up to 5,000 characters.');
  return value.trim();
}
function milliseconds(value) {
  if (typeof value?.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number') return value;
  return typeof value === 'string' ? Date.parse(value) : NaN;
}
function positive(value) { return Number.isFinite(Number(value)) && Number(value) >= 0 ? Number(value) : 0; }
function coordinate(value) {
  return typeof value?.latitude === 'number' && Number.isFinite(value.latitude) && Math.abs(value.latitude) <= 90
    && typeof value?.longitude === 'number' && Number.isFinite(value.longitude) && Math.abs(value.longitude) <= 180
    ? { latitude: value.latitude, longitude: value.longitude } : null;
}
function routePreview(points) {
  const valid = (Array.isArray(points) ? points : []).map(coordinate).filter(Boolean);
  if (valid.length <= MAX_PREVIEW_POINTS) return valid;
  return Array.from({ length: MAX_PREVIEW_POINTS }, (_, index) => valid[Math.round(index * (valid.length - 1) / (MAX_PREVIEW_POINTS - 1))]);
}
function authorSnapshot(user) {
  const profile = user?.profile || {};
  const name = String(profile.username || profile.name || 'Hiker').trim().slice(0, 160) || 'Hiker';
  const photoURL = String(profile.photoURL || '').trim();
  return { name, ...(photoURL && photoURL.length <= 4096 ? { photoURL } : {}) };
}
function hikeSnapshot(sessionId, session, capture = {}, now = Date.now()) {
  const summary = capture.summaryReport || session.summaryReport || {};
  const endedAt = session.status === 'active' ? now : milliseconds(session.endedAt || session.endedAtLocal);
  const elapsedMinutes = Number.isFinite(endedAt) ? Math.max(0, Math.floor((endedAt - milliseconds(session.startedAt || session.startedAtLocal)) / 60000)) : 0;
  const preview = routePreview(capture.routePoints);
  const altitude = (Array.isArray(capture.routePoints) ? capture.routePoints : [])
    .map(point => point?.altitudeMeters ?? point?.altitude).filter(value => typeof value === 'number' && Number.isFinite(value));
  return { sessionId, state: session.status,
    distanceKm: positive(summary.distanceKm ?? session.distanceKm),
    durationMinutes: positive(summary.durationMinutes ?? (summary.durationSeconds == null ? null : Math.floor(summary.durationSeconds / 60))
      ?? (session.status === 'active' ? elapsedMinutes : session.durationMinutes) ?? elapsedMinutes),
    checkIns: Math.round(positive(summary.checkIns ?? session.checkIns)),
    manualPins: Math.round(positive(summary.manualPins ?? session.manualPins)),
    routePointCount: Math.round(positive(capture.routePointCount ?? preview.length)),
    ...(altitude.length ? { highestAltitudeMeters: altitude.reduce((max, value) => Math.max(max, value), -Infinity) } : {}),
    routePreview: preview };
}
function imagePaths(value, ErrorType) {
  if (!Array.isArray(value) || value.length > MAX_IMAGES || value.some(path => typeof path !== 'string')
    || new Set(value).size !== value.length) fail(ErrorType, 'invalid-argument', 'Choose up to six different photos.');
  return value;
}
async function verifiedImages(bucket, paths, uid, postId, ErrorType, downloadURL = getDownloadURL) {
  return Promise.all(paths.map(async path => {
    if (!path.startsWith(`community_posts/${uid}/${postId}/`) || path.split('/').length !== 4
      || !path.split('/').at(-1)) fail(ErrorType, 'permission-denied', 'A photo does not belong to this post.');
    const file = bucket.file(path);
    let metadata;
    try { [metadata] = await file.getMetadata(); }
    catch (_) { fail(ErrorType, 'failed-precondition', 'A selected photo has not finished uploading.'); }
    if (metadata.metadata?.ownerUserId !== uid || metadata.metadata?.postId !== postId
      || !/^image\/(jpeg|png|gif|webp|heic|heif)$/.test(metadata.contentType || '')
      || !Number.isSafeInteger(Number(metadata.size)) || Number(metadata.size) <= 0 || Number(metadata.size) > MAX_IMAGE_BYTES) {
      fail(ErrorType, 'invalid-argument', 'A photo is invalid or exceeds 10 MB.');
    }
    return { path, url: await downloadURL(file) };
  }));
}
function samePublication(current, next) {
  return current.authorId === next.authorId && current.caption === next.caption && current.kind === next.kind
    && (current.hike?.sessionId || null) === (next.hike?.sessionId || null)
    && (current.trail?.id || null) === (next.trail?.id || null)
    && JSON.stringify((current.images || []).map(image => image.path)) === JSON.stringify(next.images.map(image => image.path));
}

// publishPost: Validate media and owner hike sources before creating a retry-stable post ID.
async function publishPost({ db, bucket, uid, phoneNumber, author, input, ErrorType, timestamp, now = Date.now(), downloadURL }) {
  const postId = requireId(input?.postId, 'post', ErrorType);
  const caption = captionValue(input.caption, ErrorType);
  const paths = imagePaths(input.imagePaths || [], ErrorType);
  const sessionId = input.sessionId == null ? null : requireId(input.sessionId, 'hike', ErrorType);
  const trailId = input.trailId == null ? null : requireId(input.trailId, 'trail', ErrorType);
  if (!caption && !paths.length && !sessionId) fail(ErrorType, 'invalid-argument', 'Add a message, a photo, or a hike to your post.');
  const images = await verifiedImages(bucket, paths, uid, postId, ErrorType, downloadURL);
  const postRef = db.collection('communityPosts').doc(postId);
  return db.runTransaction(async tx => {
    const [existing, sessionDocument, captureDocument, trailDocument] = await Promise.all([
      tx.get(postRef),
      sessionId ? tx.get(db.collection('hikeSessions').doc(sessionId)) : null,
      sessionId ? tx.get(db.collection('hikeRouteCaptures').doc(sessionId)) : null,
      !sessionId && trailId ? tx.get(db.collection('trails').doc(trailId)) : null,
    ]);
    const post = { authorId: uid, author, kind: sessionId ? 'hike' : 'note', caption, images,
      visibility: 'public', likeCount: 0, commentCount: 0, createdAt: timestamp(now), updatedAt: timestamp(now) };
    if (sessionId) {
      const session = sessionDocument?.data() || {};
      if (!sessionDocument?.exists || session.userId !== uid || session.userPhoneNumber !== phoneNumber) {
        fail(ErrorType, 'permission-denied', 'This hike does not belong to your account.');
      }
      if (!['active', 'completed'].includes(session.status)) fail(ErrorType, 'failed-precondition', 'Only an active or completed hike can be shared.');
      const capture = captureDocument?.data() || {};
      if (captureDocument?.exists && (capture.userId !== uid || capture.userPhoneNumber !== phoneNumber || capture.sessionId !== sessionId)) {
        fail(ErrorType, 'permission-denied', 'This route does not belong to your hike.');
      }
      post.hike = hikeSnapshot(sessionId, session, capture, now);
      post.trail = { id: String(session.trailId || ''), name: String(session.trail?.name || session.trailName || 'Hike').slice(0, 160) };
    } else if (trailId) {
      if (!trailDocument?.exists) fail(ErrorType, 'not-found', 'This trail is no longer available.');
      post.trail = { id: trailId, name: String(trailDocument.data()?.name || 'Trail').slice(0, 160) };
    }
    if (existing.exists) {
      if (!samePublication(existing.data() || {}, post)) fail(ErrorType, 'already-exists', 'This post ID has already been used.');
      return { postId, updatedAtMillis: milliseconds(existing.data().updatedAt) };
    }
    tx.create(postRef, post);
    return { postId, updatedAtMillis: now };
  });
}

// setLike: Commit desired reaction membership and the public like total together.
async function setLike({ db, uid, input, ErrorType, timestamp, now = Date.now() }) {
  const postId = requireId(input?.postId, 'post', ErrorType);
  if (typeof input.liked !== 'boolean') fail(ErrorType, 'invalid-argument', 'Choose whether to like this post.');
  const postRef = db.collection('communityPosts').doc(postId);
  const reactionRef = postRef.collection('reactions').doc(uid);
  return db.runTransaction(async tx => {
    const [snapshot, reaction] = await Promise.all([tx.get(postRef), tx.get(reactionRef)]);
    const post = snapshot.data() || {};
    if (!snapshot.exists || post.visibility !== 'public') fail(ErrorType, 'not-found', 'This post is no longer available.');
    const oldCount = Math.round(positive(post.likeCount));
    if (reaction.exists === input.liked) return { postId, liked: input.liked, likeCount: oldCount };
    const likeCount = Math.max(0, oldCount + (input.liked ? 1 : -1));
    if (input.liked) tx.create(reactionRef, { createdAt: timestamp(now) });
    else tx.delete(reactionRef);
    tx.update(postRef, { likeCount });
    return { postId, liked: input.liked, likeCount };
  });
}

// writeComment: Stable comment IDs make repeated creates harmless while preserving content edit identity.
async function writeComment({ db, uid, author, input, ErrorType, timestamp, now = Date.now() }) {
  const postId = requireId(input?.postId, 'post', ErrorType);
  const commentId = requireId(input.commentId, 'comment', ErrorType);
  if (typeof input.body !== 'string' || !input.body.trim() || input.body.length > 2000) fail(ErrorType, 'invalid-argument', 'Comments must contain between 1 and 2,000 characters.');
  const body = input.body.trim();
  const postRef = db.collection('communityPosts').doc(postId), commentRef = postRef.collection('comments').doc(commentId);
  return db.runTransaction(async tx => {
    const [post, comment] = await Promise.all([tx.get(postRef), tx.get(commentRef)]);
    if (!post.exists || post.data().visibility !== 'public') fail(ErrorType, 'not-found', 'This post is no longer available.');
    if (comment.exists) {
      if (comment.data().authorId !== uid) fail(ErrorType, 'permission-denied', 'You can only edit your own comments.');
      if (comment.data().body !== body) tx.update(commentRef, { body, updatedAt: timestamp(now) });
      return { commentId, commentCount: Math.round(positive(post.data().commentCount)) };
    }
    tx.create(commentRef, { authorId: uid, author, body, createdAt: timestamp(now), updatedAt: timestamp(now) });
    const commentCount = Math.round(positive(post.data().commentCount)) + 1;
    tx.update(postRef, { commentCount });
    return { commentId, commentCount };
  });
}

async function removeComment({ db, uid, isAdmin = false, input, ErrorType }) {
  const postId = requireId(input?.postId, 'post', ErrorType), commentId = requireId(input.commentId, 'comment', ErrorType);
  const postRef = db.collection('communityPosts').doc(postId), commentRef = postRef.collection('comments').doc(commentId);
  return db.runTransaction(async tx => {
    const [post, comment] = await Promise.all([tx.get(postRef), tx.get(commentRef)]);
    if (!comment.exists) return { commentId, deleted: true };
    if (comment.data().authorId !== uid && !isAdmin) fail(ErrorType, 'permission-denied', 'You can only remove your own comments.');
    tx.delete(commentRef);
    if (post.exists) tx.update(postRef, { commentCount: Math.max(0, Math.round(positive(post.data().commentCount)) - 1) });
    return { commentId, deleted: true };
  });
}

// editPost: Require the expected content revision and retain only media already owned by this post.
async function editPost({ db, uid, isAdmin = false, input, ErrorType, timestamp, now = Date.now() }) {
  const postId = requireId(input?.postId, 'post', ErrorType), caption = captionValue(input.caption, ErrorType);
  const paths = imagePaths(input.retainedImagePaths, ErrorType), postRef = db.collection('communityPosts').doc(postId);
  return db.runTransaction(async tx => {
    const snapshot = await tx.get(postRef), post = snapshot.data() || {};
    if (!snapshot.exists) fail(ErrorType, 'not-found', 'This post is no longer available.');
    if (post.authorId !== uid && !isAdmin) fail(ErrorType, 'permission-denied', 'You can only edit your own posts.');
    if (!Number.isFinite(input.expectedUpdatedAtMillis) || milliseconds(post.updatedAt) !== input.expectedUpdatedAtMillis) {
      fail(ErrorType, 'aborted', 'This post changed. Refresh it before editing again.');
    }
    const byPath = new Map((post.images || []).map(image => [image.path, image]));
    if (paths.some(path => !byPath.has(path))) fail(ErrorType, 'invalid-argument', 'Only existing post photos can be retained.');
    if (!caption && !paths.length && !post.hike) fail(ErrorType, 'invalid-argument', 'Keep a message, a photo, or a hike in your post.');
    const images = paths.map(path => byPath.get(path));
    const patch = { caption, images, updatedAt: timestamp(now),
      ...(isAdmin ? { moderation: { ...(post.moderation || {}), adminId: uid, at: timestamp(now) } } : {}) };
    tx.update(postRef, patch);
    return { postId, updatedAtMillis: now, removedImages: (post.images || []).filter(image => !paths.includes(image.path)) };
  });
}

async function moderatePost({ db, uid, input, ErrorType, timestamp, now = Date.now() }) {
  const postId = requireId(input?.postId, 'post', ErrorType);
  if (!['approved', 'hidden', 'removed'].includes(input.status) || typeof (input.reason ?? '') !== 'string' || String(input.reason || '').length > 1000) {
    fail(ErrorType, 'invalid-argument', 'The moderation decision is invalid.');
  }
  return db.runTransaction(async tx => {
    const ref = db.collection('communityPosts').doc(postId), post = await tx.get(ref);
    if (!post.exists) fail(ErrorType, 'not-found', 'This post is no longer available.');
    if (input.expectedUpdatedAtMillis != null && milliseconds(post.data().updatedAt) !== input.expectedUpdatedAtMillis) fail(ErrorType, 'aborted', 'This post changed. Refresh it before reviewing again.');
    tx.update(ref, { visibility: input.status === 'approved' ? 'public' : input.status,
      moderation: { status: input.status, reason: String(input.reason || '').trim(), adminId: uid, at: timestamp(now) }, updatedAt: timestamp(now) });
    return { postId, updatedAtMillis: now };
  });
}

async function deletePost({ db, uid, isAdmin = false, input, ErrorType }) {
  const postId = requireId(input?.postId, 'post', ErrorType), ref = db.collection('communityPosts').doc(postId);
  return db.runTransaction(async tx => {
    const snapshot = await tx.get(ref);
    if (!snapshot.exists) return { postId, deleted: true };
    if (snapshot.data().authorId !== uid && !isAdmin) fail(ErrorType, 'permission-denied', 'You can only remove your own posts.');
    tx.delete(ref);
    return { postId, deleted: true };
  });
}

// cleanupDeletedPost: Delete child engagement and known media without touching a reused parent document.
async function cleanupDeletedPost({ db, bucket, postId, post }) {
  const ref = db.collection('communityPosts').doc(postId);
  // Never remove a new document if an identifier was deliberately reused.
  if ((await ref.get()).exists) return;
  for (const name of ['comments', 'reactions']) await db.recursiveDelete(ref.collection(name));
  await removeImages(bucket, post.images || [], post.authorId, postId);
}
async function removeImages(bucket, images, uid, postId) {
  await Promise.all(images.map(async image => {
    const path = String(image?.path || '');
    if (!path.startsWith(`community_posts/${uid}/${postId}/`) && !path.startsWith(`community_hikes/${uid}/`)) return;
    try { await bucket.file(path).delete({ ignoreNotFound: true }); }
    catch (error) { if (Number(error.code) !== 404) throw error; }
  }));
}

module.exports = { MAX_IMAGES, MAX_IMAGE_BYTES, MAX_PREVIEW_POINTS, validId, milliseconds, authorSnapshot, routePreview, hikeSnapshot,
  verifiedImages, publishPost, setLike, writeComment, removeComment, editPost, moderatePost, deletePost, cleanupDeletedPost, removeImages };

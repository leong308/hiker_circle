'use strict';

const {FieldPath, GeoPoint} = require('firebase-admin/firestore');
const {classifyHazard, isActiveHazard, HAZARD_POLICY_VERSION} = require('./trail_hazard_policy');

const CLOUD_RESOURCE_TYPES = Object.freeze([
  'trail_catalog', 'trail_weather', 'checkpoint_weather', 'trail_hazards', 'community_posts',
  'community_post', 'community_comments', 'chat_messages',
]);
const MAX_CATALOG_ROWS = 1000;
const MAX_HAZARD_ROWS = 500;
const MAX_REPORT_UPDATES = 1000;
const MAX_CHAT_MESSAGES = 1000;
const ID = /^[^/\x00-\x1f]{1,240}$/;
const CHECKPOINT = /^-?\d{1,2}\.\d{5}_-?\d{1,3}\.\d{5}$/;

// Preserve complete route geometry and nested snapshots instead of truncating arrays or text.
function cloudPlainValue(value, depth = 0) {
  if (depth > 32) throw new Error('Cloud snapshot nesting is too deep.');
  if (value == null || typeof value === 'string' || typeof value === 'boolean') return value;
  if (typeof value === 'number') return Number.isFinite(value) ? value : 0;
  if (value instanceof Date) return value.toISOString();
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  if (value instanceof GeoPoint) {
    return {latitude: value.latitude, longitude: value.longitude};
  }
  if (Buffer.isBuffer(value)) return value.toString('base64');
  if (Array.isArray(value)) return value.map(item => cloudPlainValue(item, depth + 1));
  if (typeof value.path === 'string' && value.firestore) return value.path;
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, cloudPlainValue(item, depth + 1)]));
}

// Accept only named projections and bounded arguments, never arbitrary document paths.
function validateCloudArguments(type, args, HttpsError) {
  const fail = () => { throw new HttpsError('invalid-argument', 'Invalid cloud cache resource.'); };
  if (!CLOUD_RESOURCE_TYPES.includes(type) || !args || typeof args !== 'object' || Array.isArray(args)
    || ![Object.prototype, null].includes(Object.getPrototypeOf(args))) fail();
  const keys = type === 'trail_catalog' ? []
    : type === 'checkpoint_weather' ? ['trailId', 'checkpointKey']
      : type === 'community_posts' ? ['limit', 'afterPostId', 'authorId']
        : type === 'community_post' ? ['postId']
          : type === 'community_comments' ? ['postId', 'limit', 'afterCommentId']
            : type === 'chat_messages' ? ['chatId'] : ['trailId'];
  if (Object.keys(args).some(key => !keys.includes(key))) fail();
  if (type === 'community_posts') {
    if (args.limit !== undefined && (!Number.isInteger(args.limit) || args.limit < 1 || args.limit > 100)) fail();
    for (const key of ['afterPostId', 'authorId']) {
      if (args[key] !== undefined && (typeof args[key] !== 'string' || !ID.test(args[key]))) fail();
    }
  } else if (['community_post', 'community_comments', 'chat_messages'].includes(type)) {
    const key = type === 'chat_messages' ? 'chatId' : 'postId';
    if (typeof args[key] !== 'string' || !ID.test(args[key])) fail();
    if (args.limit !== undefined && (!Number.isInteger(args.limit) || args.limit < 1 || args.limit > 100)) fail();
    if (args.afterCommentId !== undefined
      && (typeof args.afterCommentId !== 'string' || !ID.test(args.afterCommentId))) fail();
  } else if (type !== 'trail_catalog') {
    if (typeof args.trailId !== 'string' || !ID.test(args.trailId)) fail();
    if (type === 'checkpoint_weather' && (typeof args.checkpointKey !== 'string' || !CHECKPOINT.test(args.checkpointKey))) fail();
  }
  return {...args};
}

// A partial list must never replace a complete downloaded snapshot.
function requireComplete(snapshot, maximum, HttpsError) {
  if (snapshot.docs.length > maximum) {
    throw new HttpsError('resource-exhausted', 'The cloud snapshot exceeds its complete-read limit.');
  }
  return snapshot.docs;
}

// Cloud-first comparisons only read stored data; they never publish edits or fetch a weather provider.
function createCloudResourceReader({database, authorize, sanitize = cloudPlainValue, HttpsError}) {
  return async function readCloudResource(request) {
    const identity = authorize(request);
    const type = request.data?.resourceType;
    const args = validateCloudArguments(type, request.data?.resourceArgs ?? {}, HttpsError);
    const db = database();

    // Query trail
    if (type === 'trail_catalog') {
      const snapshot = await db.collection('trails').orderBy('isVerifiedTrail', 'desc')
        .orderBy('ratingAverage', 'desc').limit(MAX_CATALOG_ROWS + 1).get();
      return {trails: requireComplete(snapshot, MAX_CATALOG_ROWS, HttpsError)
        .map(doc => ({...sanitize(doc.data()), trailId: doc.id}))};
    }
    if (type === 'trail_weather' || type === 'checkpoint_weather') {
      // Query trail or checkpoint weather
      let ref = db.collection('trails').doc(args.trailId);
      if (type === 'checkpoint_weather') ref = ref.collection('checkpointWeather').doc(args.checkpointKey);
      const snapshot = await ref.get();
      if (!snapshot.exists) throw new HttpsError('not-found', 'The saved trail forecast is unavailable.');
      const weather = snapshot.data()?.weather;
      if (!weather || typeof weather !== 'object' || Array.isArray(weather)) {
        throw new HttpsError('unavailable', 'No shared forecast is saved yet.');
      }
      return {weather: sanitize(weather)};
    }
    if (type === 'trail_hazards') {
      // Query trail hazards by trail ID
      const snapshot = await db.collection('hazardReports').where('trailId', '==', args.trailId)
        .limit(MAX_HAZARD_ROWS + 1).get();
      const reports = requireComplete(snapshot, MAX_HAZARD_ROWS, HttpsError);
      let updateRows = 0;
      const hazards = [];
      for (const doc of reports) {
        const report = doc.data();
        const policy = classifyHazard(report.hazardType);
        const serverPolicy = report.hazardPolicyVersion === HAZARD_POLICY_VERSION
          && ['fatal', 'normal'].includes(report.riskLevel);
        const category = serverPolicy ? report.hazardCategory || policy.hazardCategory : policy.hazardCategory;
        const risk = serverPolicy ? report.riskLevel : policy.riskLevel;
        let reportUpdates = [];
        if (isActiveHazard(report) && category === 'Weather' && risk === 'fatal') {
          // Query fatal weather hazard updates
          const updates = await doc.ref.collection('updates').limit(MAX_REPORT_UPDATES - updateRows + 1).get();
          const rows = requireComplete(updates, MAX_REPORT_UPDATES - updateRows, HttpsError);
          updateRows += rows.length;
          reportUpdates = rows.map(update => sanitize(update.data()));
        }
        hazards.push({...sanitize(report), hazardId: doc.id, reportUpdates});
      }
      return {hazards};
    }
    if (type === 'chat_messages') {
      // Query chat membership
      const chat = db.collection('groupChats').doc(args.chatId);
      const snapshot = await chat.get();
      const phone = identity?.phoneNumber || request.auth.uid;
      // Match the messages rule: being an administrator alone grants no access.
      if (!snapshot.exists || !Array.isArray(snapshot.data()?.participantPhones)
        || !snapshot.data().participantPhones.includes(phone)) {
        throw new HttpsError('permission-denied', 'This conversation is unavailable.');
      }
      // Query chat messages newest first
      const messages = await chat.collection('messages').orderBy('sentAtLocal', 'desc')
        .orderBy(FieldPath.documentId(), 'desc').limit(MAX_CHAT_MESSAGES + 1).get();
      return {messages: requireComplete(messages, MAX_CHAT_MESSAGES, HttpsError)
        .map(doc => ({...sanitize(doc.data()), messageId: doc.id}))};
    }
    if (type === 'community_post' || type === 'community_comments') {
      // Query community post by ID
      const ref = db.collection('communityPosts').doc(args.postId);
      const snapshot = await ref.get();
      if (!snapshot.exists) throw new HttpsError('not-found', 'The post is unavailable.');
      const data = snapshot.data();
      if (data.visibility !== 'public' && data.authorId !== request.auth.uid) {
        throw new HttpsError('permission-denied', 'The post is unavailable.');
      }
      // Query viewer's post reaction
      const liked = data.visibility === 'public'
        ? (await ref.collection('reactions').doc(request.auth.uid).get()).exists : false;
      const post = {...sanitize(data), postId: snapshot.id, isLiked: liked};
      if (type === 'community_post') return {post};
      // Query paginated comments by post
      let query = ref.collection('comments').orderBy('createdAt', 'desc')
        .orderBy(FieldPath.documentId(), 'desc');
      if (args.afterCommentId) {
        // Query comment pagination cursor
        const cursor = await ref.collection('comments').doc(args.afterCommentId).get();
        if (!cursor.exists) return {post, comments: [], pageComplete: true};
        query = query.startAfter(cursor);
      }
      const limit = args.limit || 50;
      const comments = await query.limit(limit).get();
      return {post, comments: comments.docs.map(doc => ({...sanitize(doc.data()), commentId: doc.id})),
        pageComplete: comments.docs.length < limit};
    }
    // Shared feeds are public. An author may also view their own non-public posts,
    // with their reaction state isolated by the authenticated owner's cache key.
    // Query community feed by visibility or author
    let query = db.collection('communityPosts');
    if (args.authorId) query = query.where('authorId', '==', args.authorId);
    const ownPosts = args.authorId === request.auth.uid;
    if (!ownPosts) query = query.where('visibility', '==', 'public');
    query = query.orderBy('createdAt', 'desc').orderBy(FieldPath.documentId(), 'desc');
    if (args.afterPostId) {
      // Query post pagination cursor
      const cursor = await db.collection('communityPosts').doc(args.afterPostId).get();
      if (!cursor.exists) return {posts: [], pageComplete: true};
      if (cursor.data()?.visibility !== 'public' && cursor.data()?.authorId !== request.auth.uid) {
        throw new HttpsError('permission-denied', 'The post is unavailable.');
      }
      query = query.startAfter(cursor);
    }
    const limit = args.limit || 20;
    const snapshot = await query.limit(limit).get();
    const posts = await Promise.all(snapshot.docs.map(async doc => {
      const data = doc.data();
      // Query feed viewer reactions
      const liked = data.visibility === 'public'
        ? (await doc.ref.collection('reactions').doc(request.auth.uid).get()).exists : false;
      return {...sanitize(data), postId: doc.id, isLiked: liked};
    }));
    return {posts, pageComplete: snapshot.docs.length < limit};
  };
}

module.exports = {CLOUD_RESOURCE_TYPES, MAX_CATALOG_ROWS, MAX_HAZARD_ROWS, MAX_CHAT_MESSAGES,
  validateCloudArguments, cloudPlainValue, createCloudResourceReader};

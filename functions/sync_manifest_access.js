// Cheap live guards preserve authorization and clock boundaries on manifest hits.
'use strict';

const {Filter} = require('firebase-admin/firestore');

// Snapshot versions preserve nanoseconds and distinguish absent documents from deleted ones.
function snapshotVersion(snapshot) {
  return [snapshot.ref.path, snapshot.exists,
    snapshot.updateTime?.seconds || 0, snapshot.updateTime?.nanoseconds || 0];
}

// Recheck access from canonical documents, rather than treating a stored hash as permission.
function createManifestGuard({database, authorize, HttpsError, clock = Date.now}) {
  return async function guard(request, callable, args) {
    const {uid, phoneNumber} = authorize(request);
    const db = database();
    const versions = [];
    const get = async path => {
      const snapshot = await db.doc(path).get();
      versions.push(snapshotVersion(snapshot));
      return snapshot;
    };
    const deny = (code, message) => { throw new HttpsError(code, message); };
    let validUntilMillis;
    if (callable === 'readMobileResource') {
      const modules = {preferences: ['preferences', 'safety'], profile: ['profile'],
        social: ['social'], sos_preferences: ['sos']};
      for (const module of modules[args.resourceType] || []) await get(`users/${uid}/modules/${module}`);
    }
    if (callable === 'readCloudResource' || callable === 'fetchWeatherForTrail') {
      const type = callable === 'fetchWeatherForTrail' ? 'trail_weather' : args.resourceType;
      const a = callable === 'fetchWeatherForTrail' ? {trailId: args.trailId} : args.resourceArgs;
      if (type === 'chat_messages') {
        const chat = await get(`groupChats/${a.chatId}`);
        if (!chat.exists || !Array.isArray(chat.data()?.participantPhones)
          || !chat.data().participantPhones.includes(phoneNumber)) deny('permission-denied', 'This conversation is unavailable.');
      } else if (['community_post', 'community_comments'].includes(type)) {
        const post = await get(`communityPosts/${a.postId}`);
        if (!post.exists) deny('not-found', 'The post is unavailable.');
        if (post.data().visibility !== 'public' && post.data().authorId !== uid) deny('permission-denied', 'The post is unavailable.');
        if (a.afterCommentId) await get(`communityPosts/${a.postId}/comments/${a.afterCommentId}`);
      } else if (type === 'community_posts' && a.afterPostId) {
        const post = await get(`communityPosts/${a.afterPostId}`);
        if (post.exists && post.data().visibility !== 'public' && post.data().authorId !== uid) deny('permission-denied', 'The post is unavailable.');
      } else if (['trail_weather', 'checkpoint_weather'].includes(type)) {
        const path = `trails/${a.trailId}` + (type === 'checkpoint_weather' ? `/checkpointWeather/${a.checkpointKey}` : '');
        const saved = await get(path);
        if (!saved.exists) deny('not-found', 'The saved trail forecast is unavailable.');
        if (!saved.data()?.weather || typeof saved.data().weather !== 'object' || Array.isArray(saved.data().weather)) {
          deny('unavailable', 'No shared forecast is saved yet.');
        }
      }
    }
    if (callable === 'loadMyHikeHistoryDetail') {
      let teamId;
      if (args.sessionId.startsWith('team-history_')) teamId = args.sessionId.slice('team-history_'.length);
      else {
        const session = await get(`hikeSessions/${args.sessionId}`);
        const data = session.data() || {};
        if (!session.exists || data.userId !== uid || data.userPhoneNumber !== phoneNumber) deny('not-found', 'This hike is not in your history.');
        if (data.status !== 'completed') deny('failed-precondition', 'This hike has not been completed.');
        teamId = data.teamHikeSessionId;
      }
      if (teamId) {
        if (typeof teamId !== 'string' || !/^[^/\x00-\x1f]{1,200}$/.test(teamId)) deny('not-found', 'This team history is unavailable.');
        const snapshot = await get(`teamHikeSessions/${teamId}`);
        const team = snapshot.data() || {};
        const member = (Array.isArray(team.participants) ? team.participants : [])
          .find(p => String(p.phoneNumber || p.buddy?.phoneNumber || '').trim() === phoneNumber);
        if (!snapshot.exists || member?.status !== 'ended' || !team.startedAtLocal) deny('not-found', 'This team hike is not in your completed history.');
      }
    }
    if (callable === 'listExpiredScheduledHikes'
      || (callable === 'readMobileResource' && args.resourceType === 'my_upcoming_hikes')) {
      const now = clock();
      // One indexed row detects a start-window crossing, including an empty expired list.
      const next = await db.collection('upcomingHikes')
        .where(Filter.or(Filter.where('creatorUserId', '==', uid), Filter.where('participantPhones', 'array-contains', phoneNumber)))
        .where('departureTimeLocal', '>', new Date(now - 15 * 60 * 1000).toISOString())
        .orderBy('departureTimeLocal').limit(1).get();
      versions.push(...next.docs.map(snapshotVersion));
      if (next.docs.length) validUntilMillis = Date.parse(next.docs[0].data().departureTimeLocal) + 15 * 60 * 1000;
    }
    return {token: versions, validUntilMillis};
  };
}

module.exports = {snapshotVersion, createManifestGuard};

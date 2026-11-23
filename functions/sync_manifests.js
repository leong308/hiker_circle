// Server-only content manifests avoid rebuilding unchanged mobile projections.
'use strict';

const {contentHash} = require('./mobile_cache_helpers');
const {hazardExpiry} = require('./trail_hazard_policy');
const SCHEMA = 1;
const MAX_AGE_MS = 15 * 60 * 1000;

// Dependencies describe fixed server projections, never client-supplied database paths.
function resourceDependencies(callable, args, owner) {
  if (callable === 'fetchWeatherForTrail') return [`trails/${args.trailId}`];
  if (callable === 'readCloudResource') {
    const a = args.resourceArgs || {};
    switch (args.resourceType) {
      case 'trail_catalog': return ['trails'];
      case 'trail_weather': return [`trails/${a.trailId}`];
      case 'checkpoint_weather': return [`checkpointWeather/${a.trailId}/${a.checkpointKey}`];
      case 'trail_hazards': return ['hazardReports'];
      case 'chat_messages': return [`chat/${a.chatId}`];
      default: return ['communityPosts'];
    }
  }
  if (callable === 'readMobileResource') {
    switch (args.resourceType) {
      case 'preferences': return [`user/${owner}/preferences`, `user/${owner}/safety`];
      case 'social': return [`user/${owner}/social`];
      case 'sos_preferences': return [`user/${owner}/sos`];
      case 'profile': return [`user/${owner}/profile`];
      case 'my_upcoming_hikes': return [`plans/${owner}`];
      case 'chat_list': return [`chats/${owner}`];
      case 'achievement_progress': return ['achievements', `awards/${owner}`];
      case 'my_feedback': return [`feedback/${owner}`];
      default: throw new Error('Unsupported manifest projection.');
    }
  }
  if (callable === 'listExpiredScheduledHikes') return [`plans/${owner}`];
  if (callable === 'listMyHikeHistory') return [`history/${owner}`, 'teamHikeSessions'];
  if (callable === 'loadMyHikeHistoryDetail') return ['historyDetails', 'teamHikeSessions', 'groupChats', 'trails'];
  if (callable === 'getPublicProfiles') return ['publicProfiles'];
  if (callable === 'loadPublicHikerProfile') return ['publicProfiles', 'userAchievements', 'completedHikes'];
  if (callable === 'loadAchievementLeaderboard') return ['publicProfiles', 'userAchievements'];
  throw new Error('Unsupported manifest callable.');
}

// Include both old and new ownership so moves, removals and deletions invalidate both sides.
function changedDependencies(path, before, after) {
  const p = path.split('/');
  const rows = [before, after].filter(Boolean);
  const keys = new Set();
  const participants = row => Array.isArray(row.participantPhones) ? row.participantPhones : [];
  const add = key => { if (key) keys.add(key); };
  const each = (field, prefix) => rows.forEach(row => { if (row[field]) add(`${prefix}/${row[field]}`); });
  if (p.length === 4) {
    if (p[0] === 'users' && p[2] === 'modules') {
      if (['profile', 'preferences', 'safety', 'sos', 'social', 'achievements'].includes(p[3])) add(`user/${p[1]}/${p[3]}`);
      if (['profile', 'achievements'].includes(p[3])) add('publicProfiles');
    } else if (p[0] === 'trails' && p[2] === 'checkpointWeather') {
      add(`checkpointWeather/${p[1]}/${p[3]}`);
    } else if (p[0] === 'trails' && p[2] === 'ratings') add('historyDetails');
    else if (p[0] === 'hazardReports' && p[2] === 'updates') add('hazardReports');
    else if (p[0] === 'groupChats' && p[2] === 'messages') add(`chat/${p[1]}`);
    else if (p[0] === 'communityPosts' && ['comments', 'reactions'].includes(p[2])) add('communityPosts');
    return [...keys].sort();
  }
  if (p.length !== 2) return [];
  switch (p[0]) {
    case 'trails': add('trails'); add(path); break;
    case 'users': add('publicProfiles'); break;
    case 'hazardReports': add('hazardReports'); break;
    case 'communityPosts': add('communityPosts'); break;
    case 'achievements': add('achievements'); break;
    case 'userAchievements': add('userAchievements'); each('userId', 'awards'); break;
    case 'appFeedback': each('uid', 'feedback'); break;
    case 'upcomingHikes':
      rows.forEach(row => [row.creatorUserId, row.creatorPhone, ...participants(row)]
        .filter(value => typeof value === 'string' && value).forEach(owner => add(`plans/${owner}`)));
      break;
    case 'groupChats':
      add('groupChats'); add(`chat/${p[1]}`);
      rows.forEach(row => participants(row).filter(owner => typeof owner === 'string' && owner)
        .forEach(owner => add(`chats/${owner}`)));
      break;
    case 'hikeSessions':
      add('historyDetails');
      if (rows.some(row => row.status === 'completed')) { add('completedHikes'); each('userId', 'history'); }
      break;
    case 'teamHikeSessions': add('teamHikeSessions'); break;
    case 'hikeRouteCaptures': case 'footprints': case 'checkIns': add('historyDetails'); break;
  }
  return [...keys].sort();
}

// Compare nanosecond event times without losing precision or depending on delivery order.
function eventVersion(event) {
  const match = /^(.*?)(?:\.(\d{1,9}))?Z$/.exec(String(event.time || ''));
  if (!match) throw new Error('A Firestore event timestamp is required.');
  const seconds = Date.parse(`${match[1]}Z`) / 1000;
  if (!Number.isSafeInteger(seconds) || seconds < 0) throw new Error('Invalid Firestore event time.');
  return `${String(seconds).padStart(12, '0')}.${(match[2] || '').padEnd(9, '0')}`;
}

// Time-derived views expire at their next semantic boundary, even without a database write.
function payloadDeadline(callable, args, payload, now) {
  let until = now + MAX_AGE_MS;
  if (callable === 'readMobileResource' && args.resourceType === 'my_upcoming_hikes') {
    for (const hike of payload.hikes || []) {
      const boundary = Date.parse(hike.departureTimeLocal) + 15 * 60 * 1000;
      if (boundary > now) until = Math.min(until, boundary);
    }
  }
  if (callable === 'readCloudResource' && args.resourceType === 'trail_hazards') {
    for (const hazard of payload.hazards || []) {
      const boundary = hazardExpiry(hazard);
      if (boundary > now) until = Math.min(until, boundary);
    }
  }
  if (callable === 'loadAchievementLeaderboard') {
    const date = new Date(now);
    until = Math.min(until, args.period === 'year'
      ? Date.UTC(date.getUTCFullYear() + 1, 0, 1)
      : Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1));
  }
  return until;
}

// Store only hashes and bounded metadata; source documents and payloads remain authoritative.
function createSyncManifests({database, guard, projectionVersion, timestamp, expiresAt, clock = Date.now,
  onCacheError = () => {}}) {
  const sourceRef = key => database().collection('syncManifestSources').doc(contentHash(key));

  // A write advances source revisions once; duplicate or older events cannot roll them back.
  async function observeWrite(event) {
    const before = event.data?.before?.exists ? event.data.before.data() : null;
    const after = event.data?.after?.exists ? event.data.after.data() : null;
    const path = event.data?.after?.ref?.path || event.data?.before?.ref?.path;
    if (!path) return;
    const keys = changedDependencies(path, before, after);
    if (!keys.length) return;
    // Version the write without hashing Firestore references.
    const version = eventVersion(event);
    const refs = keys.map(sourceRef);
    await database().runTransaction(async tx => {
      // Query affected resource revisions
      const snapshots = await tx.getAll(...refs);
      snapshots.forEach((snapshot, i) => {
        if (String(snapshot.data()?.version || '') < version) {
          // Update cloud: update resource revisions
          tx.set(refs[i], {version, sourceHash: contentHash([keys[i], version]), updatedAt: timestamp()});
        }
      });
    });
  }

  // One request shares revision reads across duplicate and overlapping descriptors.
  function createRequestContext() {
    const reads = new Map();
    return {get: ref => {
      // Query saved resource revision
      if (!reads.has(ref.path)) reads.set(ref.path, ref.get());
      return reads.get(ref.path);
    }};
  }

  // Only a matching, still-authorized manifest can bypass the source projection.
  async function read(request, callable, args, resolve, context = createRequestContext()) {
    const owner = request.auth.uid;
    const identity = {schema: SCHEMA, projectionVersion, owner, callable, args};
    const manifestId = contentHash(identity);
    const readSource = async () => {
      const payload = await resolve();
      const hash = contentHash(payload);
      return {payload, hash, revisionHash: hash, manifestId, manifestHit: false};
    };
    // A caution notification can arrive before its cache revision changes.
    if (callable === 'readCloudResource' && args.resourceType === 'trail_hazards') {
      await guard(request, callable, args);
      return readSource();
    }
    const ref = database().collection('syncManifests').doc(manifestId);
    const dependencies = resourceDependencies(callable, args, owner).sort();
    const refs = dependencies.map(sourceRef);
    // Query manifest and dependency revisions
    const [metadata, access] = await Promise.all([
      Promise.all([context.get(ref), Promise.all(refs.map(context.get))])
        .catch(error => { onCacheError(error); return null; }),
      guard(request, callable, args),
    ]);
    // Manifest storage is an optimization; its failure never blocks a fresh authorized read.
    if (!metadata) return readSource();
    const [saved, sources] = metadata;
    const versions = sources.map(snapshot => snapshot.data()?.version || '');
    const revisionHash = contentHash({versions, guard: access.token || ''});
    const manifest = saved.data();
    const now = clock();
    if (manifest?.schema === SCHEMA && manifest.revisionHash === revisionHash
      && /^[a-f0-9]{64}$/.test(manifest.contentHash || '')
      && manifest.validUntilMillis > now && request.data?.forcePayload !== true
      && request.data?.knownContentHash === manifest.contentHash) {
      return {hash: manifest.contentHash, revisionHash, manifestId, manifestHit: true};
    }
    const payload = await resolve();
    const hash = contentHash(payload);
    const validUntilMillis = Math.min(payloadDeadline(callable, args, payload, now), access.validUntilMillis || Infinity);
    // A concurrent source event must not publish a hash under the newer source revision.
    await database().runTransaction(async tx => {
      // Query current manifest revisions
      const current = refs.length ? await tx.getAll(...refs) : [];
      if (current.some((snapshot, i) => (snapshot.data()?.version || '') !== versions[i])) return;
      // Update cloud: save validated cache manifest
      tx.set(ref, {schema: SCHEMA, contentHash: hash, revisionHash,
        ownerHash: contentHash(owner), resourceHash: contentHash({callable, args}),
        validUntilMillis, checkedAt: timestamp(), expiresAt: expiresAt(clock() + 7 * 86400000)});
    }).catch(onCacheError);
    return {payload, hash, revisionHash, manifestId, manifestHit: false};
  }
  return {read, observeWrite, createRequestContext};
}

module.exports = {SCHEMA, MAX_AGE_MS, resourceDependencies, changedDependencies,
  eventVersion, payloadDeadline, createSyncManifests};

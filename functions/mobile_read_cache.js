// One authenticated batch validates explicitly supported mobile read resources.
'use strict';

const {canonical, contentHash, conditionalPayload} = require('./mobile_cache_helpers');

const OWNER_RESOURCE_TYPES = Object.freeze([
  'preferences', 'my_upcoming_hikes', 'social', 'chat_list',
  'sos_preferences', 'profile', 'achievement_progress', 'my_feedback',
]);
const MAX_RESOURCES = 128;
const MAX_RESPONSE_BYTES = 4 * 1024 * 1024;
const MAX_ARGUMENT_BYTES = 16384;
const MAX_READ_WORK_UNITS = 16384;
const MAX_ACHIEVEMENT_ROWS = 1000;
const HASH = /^[a-f0-9]{64}$/;
const ID = /^[^/\x00-\x1f]{1,240}$/;
const PHONE = /^\+[1-9]\d{7,14}$/;
const AUTH_ERRORS = new Set(['unauthenticated', 'functions/unauthenticated']);
const PUBLIC_ERROR_CODES = new Set([
  'invalid-argument', 'not-found', 'permission-denied', 'failed-precondition',
  'resource-exhausted', 'unavailable', 'deadline-exceeded',
]);

function plain(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    && (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
}

function invalid(ErrorType, message) { throw new ErrorType('invalid-argument', message); }
function onlyKeys(value, allowed, ErrorType) {
  if (!plain(value) || Object.keys(value).some(key => !allowed.includes(key))) {
    invalid(ErrorType, 'Unsupported mobile read arguments.');
  }
}
function boundedLimit(value, fallback, maximum, ErrorType) {
  if (value === undefined) return fallback;
  if (!Number.isInteger(value) || value < 1 || value > maximum) {
    invalid(ErrorType, 'The mobile read limit is invalid.');
  }
  return value;
}
function validText(value, regex, ErrorType) {
  if (typeof value !== 'string' || !regex.test(value)) {
    invalid(ErrorType, 'The mobile read identifier is invalid.');
  }
  return value;
}

// A descriptor selects a fixed domain projection, never a Firestore path.
function validateArguments(callable, args, ErrorType) {
  const base = {...args};
  for (const field of ['expectedOwner', 'knownContentHash', 'knownRevision', 'forcePayload']) delete base[field];
  switch (callable) {
    case 'readMobileResource': {
      onlyKeys(base, ['resourceType', 'resourceArgs'], ErrorType);
      if (!OWNER_RESOURCE_TYPES.includes(base.resourceType)) invalid(ErrorType, 'Unsupported mobile resource.');
      const resourceArgs = base.resourceArgs ?? {};
      const listType = ['my_upcoming_hikes', 'chat_list', 'my_feedback'].includes(base.resourceType);
      onlyKeys(resourceArgs, listType ? ['limit'] : [], ErrorType);
      if (listType) boundedLimit(resourceArgs.limit, base.resourceType === 'my_feedback' ? 100 : 200,
        base.resourceType === 'my_feedback' ? 100 : 200, ErrorType);
      return {...base, resourceArgs};
    }
    case 'listMyHikeHistory':
      onlyKeys(base, ['limit'], ErrorType);
      boundedLimit(base.limit, 100, 200, ErrorType);
      return base;
    case 'loadMyHikeHistoryDetail':
      onlyKeys(base, ['sessionId'], ErrorType);
      validText(base.sessionId, ID, ErrorType);
      return base;
    case 'listExpiredScheduledHikes':
      onlyKeys(base, ['limit', 'cursor'], ErrorType);
      boundedLimit(base.limit, 100, 200, ErrorType);
      if (base.cursor != null) {
        onlyKeys(base.cursor, ['hikeId', 'departureTimeLocal'], ErrorType);
        validText(base.cursor.hikeId, ID, ErrorType);
        if (typeof base.cursor.departureTimeLocal !== 'string'
          || base.cursor.departureTimeLocal.length > 64
          || !Number.isFinite(Date.parse(base.cursor.departureTimeLocal))) {
          invalid(ErrorType, 'The mobile history cursor is invalid.');
        }
      }
      return base;
    case 'getPublicProfiles':
      onlyKeys(base, ['phoneNumbers', 'userIds', 'phoneNumber', 'userId', 'limit'], ErrorType);
      boundedLimit(base.limit, 80, 80, ErrorType);
      for (const [name, regex] of [['phoneNumbers', PHONE], ['userIds', ID]]) {
        if (base[name] !== undefined) {
          if (!Array.isArray(base[name]) || base[name].length > 50) invalid(ErrorType, 'Too many profiles requested.');
          base[name].forEach(item => validText(item, regex, ErrorType));
        }
      }
      if (base.phoneNumber !== undefined) validText(base.phoneNumber, PHONE, ErrorType);
      if (base.userId !== undefined) validText(base.userId, ID, ErrorType);
      return base;
    case 'loadPublicHikerProfile':
      onlyKeys(base, ['phoneNumber', 'userId'], ErrorType);
      if (!base.phoneNumber && !base.userId) invalid(ErrorType, 'A hiker profile is required.');
      if (base.phoneNumber !== undefined && base.phoneNumber !== '') validText(base.phoneNumber, PHONE, ErrorType);
      if (base.userId !== undefined && base.userId !== '') validText(base.userId, ID, ErrorType);
      return base;
    case 'loadAchievementLeaderboard':
      onlyKeys(base, ['period'], ErrorType);
      if (base.period !== undefined && !['month', 'year'].includes(base.period)) invalid(ErrorType, 'Invalid leaderboard period.');
      return base;
    default:
      invalid(ErrorType, 'Unsupported mobile read callable.');
  }
}

function payloadOnly(result) {
  if (!plain(result) || result.notModified === true) throw new Error('Fresh mobile payload is required.');
  const payload = {...result};
  for (const field of ['contentHash', 'revisionHash', 'payloadChecked', 'notModified']) delete payload[field];
  return canonical(payload);
}

// A truncated award/catalogue is not a complete replacement for cached progress.
function completeAchievementPayload(achievements, awards, ErrorType) {
  if (!Array.isArray(achievements) || !Array.isArray(awards)
    || achievements.length > MAX_ACHIEVEMENT_ROWS || awards.length > MAX_ACHIEVEMENT_ROWS) {
    throw new ErrorType('resource-exhausted', 'Achievement progress is too large for a complete mobile snapshot.');
  }
  return {achievements, awards};
}

// Project only user-facing owner data; account roles, devices and security are absent.
function projectOwnerResource(type, account = {}) {
  const pick = fields => Object.fromEntries(fields.filter(key => Object.hasOwn(account, key))
    .map(key => [key, account[key]]));
  switch (type) {
    case 'preferences':
      return {preferences: pick(['preferredTimeZone', 'groupChatNotificationsEnabled',
        'groupChatMutedUntil', 'pinnedChats', 'autoShareLiveLocationOnHikeStart']),
      safety: pick(['teamSafetyPreferences'])};
    case 'social':
      return {buddyPhoneNumbers: Array.isArray(account.buddyPhoneNumbers) ? account.buddyPhoneNumbers : [],
        buddyRequestsIncoming: plain(account.buddyRequestsIncoming) ? account.buddyRequestsIncoming : {},
        buddyRequestsOutgoing: plain(account.buddyRequestsOutgoing) ? account.buddyRequestsOutgoing : {}};
    case 'sos_preferences': {
      const contacts = (Array.isArray(account.sos_contacts) ? account.sos_contacts : []).slice(0, 3)
        .filter(plain).map(row => ({name: String(row.name || '').slice(0, 160),
          phoneNumber: String(row.phoneNumber || '').slice(0, 32), relationship: String(row.relationship || '').slice(0, 80)}));
      const rawNotes = plain(account.sosWhatsappNotes) ? account.sosWhatsappNotes : {};
      const sosWhatsappNotes = Object.fromEntries(['manual', 'medical', 'fall_stillness', 'prolonged_stillness', 'duress']
        .filter(key => typeof rawNotes[key] === 'string').map(key => [key, rawNotes[key].slice(0, 4000)]));
      return {contacts, sosWhatsappNotes};
    }
    case 'profile': return {profile: plain(account.profile) ? account.profile : {}};
    default: throw new Error('Unsupported owner projection.');
  }
}

// Bounds expensive projections as well as request size. Units are a conservative
// workload estimate, not a claim about the exact number of billable reads.
function readWorkUnits(callable, args) {
  if (callable === 'loadMyHikeHistoryDetail') return 2500;
  if (callable === 'listMyHikeHistory') return 2 * (args.limit || 100) + 1;
  if (callable === 'listExpiredScheduledHikes') return 2000;
  if (callable === 'loadAchievementLeaderboard') return 2500;
  if (callable === 'getPublicProfiles') return 3 * (args.phoneNumbers?.length || args.userIds?.length || args.limit || 80);
  if (callable === 'loadPublicHikerProfile') return 100;
  if (args.resourceType === 'achievement_progress') return 2000;
  if (args.resourceType === 'my_feedback') return args.resourceArgs.limit || 100;
  if (['my_upcoming_hikes', 'chat_list'].includes(args.resourceType)) return args.resourceArgs.limit || 200;
  return 4;
}

function createMobileReadCacheService({handlers, readOwnerResource, authorize, HttpsError,
  maxResources = MAX_RESOURCES, maxResponseBytes = MAX_RESPONSE_BYTES,
  maxReadWorkUnits = MAX_READ_WORK_UNITS, concurrency = 4}) {
  const resolve = async (request, callable, args) => {
    const clean = validateArguments(callable, args, HttpsError);
    const child = {...request, data: {...clean, expectedOwner: request.auth.uid, forcePayload: true}};
    const result = callable === 'readMobileResource'
      ? await readOwnerResource(child, clean.resourceType, clean.resourceArgs)
      : await handlers[callable](child);
    return payloadOnly(result);
  };
  async function readResource(request) {
    authorize(request);
    const args = validateArguments('readMobileResource', request.data || {}, HttpsError);
    const payload = await resolve(request, 'readMobileResource', args);
    return conditionalPayload(payload, request.data || {}, contentHash(payload));
  }
  async function reconcile(request) {
    authorize(request);
    const rows = request.data?.resources;
    if (!Array.isArray(rows) || rows.length > maxResources) invalid(HttpsError, 'Too many mobile cache resources.');
    const seen = new Set();
    // Validate the complete request before starting any resource reads.
    const descriptors = rows.map(row => {
      onlyKeys(row, ['key', 'type', 'id', 'callable', 'arguments', 'knownContentHash', 'knownRevision'], HttpsError);
      validText(row.key, /^[^\x00-\x1f]{1,1000}$/, HttpsError);
      if (seen.has(row.key)) invalid(HttpsError, 'Duplicate mobile cache resource.');
      seen.add(row.key);
      if (typeof row.type !== 'string' || row.type.length > 100 || typeof row.id !== 'string' || row.id.length > 1000) {
        invalid(HttpsError, 'Invalid mobile cache identity.');
      }
      if (row.knownContentHash != null && row.knownContentHash !== '' && !HASH.test(row.knownContentHash)) {
        invalid(HttpsError, 'Invalid mobile content hash.');
      }
      if (!Object.hasOwn(handlers, row.callable) && row.callable !== 'readMobileResource') {
        invalid(HttpsError, 'Unsupported mobile read callable.');
      }
      if (!plain(row.arguments ?? {}) || Buffer.byteLength(JSON.stringify(row.arguments ?? {})) > MAX_ARGUMENT_BYTES) {
        invalid(HttpsError, 'Mobile resource arguments are too large.');
      }
      return {...row, arguments: validateArguments(row.callable, row.arguments ?? {}, HttpsError)};
    });
    const results = new Array(descriptors.length);
    const reads = new Map();
    let readWork = 0;
    let next = 0;
    let fatalError;
    await Promise.all(Array.from({length: Math.min(concurrency, descriptors.length)}, async () => {
      while (next < descriptors.length && !fatalError) {
        const index = next++, row = descriptors[index];
        try {
          const identity = contentHash({callable: row.callable, arguments: row.arguments});
          let read = reads.get(identity);
          if (!read) {
            const work = readWorkUnits(row.callable, row.arguments);
            if (readWork + work > maxReadWorkUnits) {
              throw new HttpsError('resource-exhausted', 'This refresh contains too many expensive resources.');
            }
            readWork += work;
            read = resolve(request, row.callable, row.arguments);
            reads.set(identity, read);
          }
          const payload = await read;
          const hash = contentHash(payload);
          results[index] = hash === row.knownContentHash
            ? {key: row.key, status: 'unchanged', contentHash: hash, revisionHash: hash}
            : {key: row.key, status: 'changed', contentHash: hash, revisionHash: hash,
              payload: {...payload, contentHash: hash, revisionHash: hash, payloadChecked: true}};
        } catch (error) {
          if (AUTH_ERRORS.has(error?.code)) {
            fatalError = error;
            throw error;
          }
          const code = String(error?.code || '').replace(/^functions\//, '');
          results[index] = {key: row.key, status: 'unavailable',
            code: PUBLIC_ERROR_CODES.has(code) ? code : 'unavailable'};
        }
      }
    }));
    // Successfully checked resources retain their hashes even when large bodies
    // are deferred. Unavailable/budget-limited rows explicitly carry no hash.
    // Reserve the complete deferred envelope first, including its markers.
    // Replacing one row then changes the serialized size by exactly this delta;
    // counting the payload alone would omit its JSON property and separators.
    const bounded = results.map(({payload, ...row}) => payload ? {...row, deferred: true} : row);
    let bytes = Buffer.byteLength(JSON.stringify({resources: bounded}));
    if (bytes > maxResponseBytes) {
      throw new HttpsError('resource-exhausted', 'The mobile cache result envelope is too large.');
    }
    for (let index = 0; index < results.length; index++) {
      if (!results[index].payload) continue;
      const delta = Buffer.byteLength(JSON.stringify(results[index]))
        - Buffer.byteLength(JSON.stringify(bounded[index]));
      if (bytes + delta <= maxResponseBytes) {
        bounded[index] = results[index];
        bytes += delta;
      }
    }
    return {resources: bounded};
  }
  return {readResource, reconcile};
}

module.exports = {OWNER_RESOURCE_TYPES, MAX_RESOURCES, MAX_RESPONSE_BYTES, MAX_READ_WORK_UNITS,
  MAX_ACHIEVEMENT_ROWS, completeAchievementPayload, readWorkUnits, validateArguments,
  projectOwnerResource, payloadOnly, createMobileReadCacheService};

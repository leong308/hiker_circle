// User account and fixed module documents provide one physical source for each profile, security, device, and safety concern.
'use strict';

// One physical source for each concern. These helpers assemble selected modules
// in memory for domain logic; they never read migrated fields from the parent.
const ACCOUNT_FIELDS = Object.freeze([
  'phoneNumber', 'createdAt', 'createdAtLocal', 'isAdmin', 'role', 'roles',
  'accountDisabled', 'status',
]);
const MODULES = Object.freeze([
  'profile', 'devices', 'security', 'preferences', 'safety', 'sos', 'location',
  'social', 'achievements',
]);
const RETIRED_FIELDS = Object.freeze([
  'username', 'photoURL', 'profilePhotoURL', 'firebaseUid', 'currentAppId',
  'lastSignedInAppInstanceId', 'activeFcmAppInstanceId', 'fcmTokenSchemaVersion',
  'fcmTokens', 'activeFcmToken', 'lastFcmToken', 'sosAlertReferenceVersion',
  'sosAlertReferencesMigratedAt', 'sosAlertReferencesMigratedAtLocal',
  'latest_sos_alert', 'sos_alerts',
  'latest_sos_messaging_test', 'sosMessagingTestUpdatedAt',
  'sosMessagingTestUpdatedAtLocal',
]);

// moduleForField: Assign every user field to one account/module owner and reject retired aliases.
function moduleForField(field) {
  const name = field.split('.')[0];
  if (ACCOUNT_FIELDS.includes(name)) return null;
  if (RETIRED_FIELDS.includes(name)) throw new Error(`Retired user field: ${name}`);
  if (/^(profile|requiresOnboarding|onboarding)/.test(name)) return 'profile';
  if (/^(boundApp|previousBoundApp|deviceRebind|deviceRebound|fcmTokenByAppId|lastFcmTokenUpdated|lastSignedInAt)/.test(name)) return 'devices';
  if (/^(password|initialPassword|safetyQuestions|mfa|lastMfa|lastPassword|lastFirebaseAuthenticated|loginFailed|loginCooldown)/.test(name)) return 'security';
  if (/^(preferredTimeZone|groupChat|pinnedChats|autoShareLiveLocation)/.test(name)) return 'preferences';
  if (/^teamSafety/.test(name)) return 'safety';
  if (/^(sos|latestSos|recentSos)/.test(name)) return 'sos';
  if (/^liveLocation/.test(name)) return 'location';
  if (/^(buddy|buddies)/.test(name)) return 'social';
  if (/^(achievement|hikerLevel)/.test(name)) return 'achievements';
  throw new Error(`Unassigned user field: ${name}`);
}

function userModule(reference, module) {
  if (!MODULES.includes(module)) throw new Error(`Unknown user module: ${module}`);
  return reference.collection('modules').doc(module);
}

// projectUserSnapshot: Assemble only requested modules in memory; misplaced persisted fields fail explicitly.
function projectUserSnapshot(account, snapshots, modules) {
  if (!account.exists) return {id: account.id, ref: account.ref, exists: false, data: () => undefined};
  const raw = account.data() || {};
  const data = Object.fromEntries(ACCOUNT_FIELDS.filter(k => Object.hasOwn(raw, k)).map(k => [k, raw[k]]));
  snapshots.forEach((snapshot, index) => {
    for (const [key, value] of Object.entries(snapshot.data() || {})) {
      if (moduleForField(key) !== modules[index]) throw new Error(`Misplaced user field in ${modules[index]}: ${key}`);
      data[key] = value;
    }
  });
  return {id: account.id, ref: account.ref, exists: true, updateTime: account.updateTime, data: () => data};
}

async function readUser(reference, modules, transaction) {
  const unique = [...new Set(modules)];
  const refs = [reference, ...unique.map(name => userModule(reference, name))];
  const snapshots = await Promise.all(refs.map(ref => transaction ? transaction.get(ref) : ref.get()));
  return projectUserSnapshot(snapshots[0], snapshots.slice(1), unique);
}

// A bounded getAll avoids an individual network round trip for every profile.
async function hydrateUsers(accounts, modules, reader) {
  if (!accounts.length) return [];
  const unique = [...new Set(modules)];
  if (!unique.length) return accounts.map(account => projectUserSnapshot(account, [], []));
  const references = accounts.flatMap(account => unique.map(name => userModule(account.ref, name)));
  const snapshots = [];
  for (let start = 0; start < references.length; start += 200) {
    snapshots.push(...await reader.getAll(...references.slice(start, start + 200)));
  }
  return accounts.map((account, index) => projectUserSnapshot(account,
    snapshots.slice(index * unique.length, (index + 1) * unique.length), unique));
}

async function readUserQuery(query, modules) {
  const snapshot = await query.get();
  const docs = await hydrateUsers(snapshot.docs, modules, query.firestore);
  return {docs, size: docs.length, empty: docs.length === 0};
}

async function readUsers(reader, references, modules) {
  if (!references.length) return [];
  const accounts = await reader.getAll(...references);
  return hydrateUsers(accounts, modules, reader);
}

function partitionUserFields(data) {
  const groups = new Map();
  for (const [key, value] of Object.entries(data)) {
    const module = moduleForField(key);
    if (!groups.has(module)) groups.set(module, {});
    groups.get(module)[key] = value;
  }
  return groups;
}

// setUser: Partition writes to their canonical physical documents using the caller's transaction or batch.
function setUser(writer, reference, data, options = {merge: true}) {
  const batch = writer || reference.firestore.batch();
  for (const [module, fields] of partitionUserFields(data)) {
    batch.set(module ? userModule(reference, module) : reference, fields, options);
  }
  return writer ? writer : batch.commit();
}

function updateUser(writer, reference, data) {
  // Use mergeFields to retain update() map-replacement semantics while allowing
  // a first write to a previously unused module. Dotted paths stay field paths.
  const batch = writer || reference.firestore.batch();
  for (const [module, fields] of partitionUserFields(data)) {
    const nested = {};
    for (const [path, value] of Object.entries(fields)) {
      const parts = path.split('.'); let cursor = nested;
      for (const part of parts.slice(0, -1)) cursor = cursor[part] ||= {};
      cursor[parts.at(-1)] = value;
    }
    batch.set(module ? userModule(reference, module) : reference, nested, {mergeFields: Object.keys(fields)});
  }
  return writer ? writer : batch.commit();
}

module.exports = {ACCOUNT_FIELDS, MODULES, RETIRED_FIELDS, moduleForField,
  userModule, projectUserSnapshot, readUser, readUsers, readUserQuery, hydrateUsers, partitionUserFields,
  setUser, updateUser};

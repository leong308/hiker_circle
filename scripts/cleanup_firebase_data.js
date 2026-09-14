/* eslint-disable no-console */
'use strict';

// Conservative Firebase cleanup for HikerCircle.
//
// The default mode is read-only. Pass --apply to back up and delete only:
// - expired authentication/password-reset challenges and sessions;
// - expired live-location shares;
// - rate-limit counters whose longest possible window ended over an hour ago;
// - terminal FCM outbox entries retained for at least 30 days;
// - upcoming-hike reminder preferences whose parent document is gone;
// - storage objects from explicitly replaceable asset families that have no
//   reference in Firestore, Firebase Auth, or the checked-in app manifests.

const fs = require('fs');
const path = require('path');
const {
  firebaseAccessToken,
  firestoreRequest,
  projectId,
} = require('./seed_malaysia_trails');

const expectedProjectId = 'hiker-circle';
const bucketName = 'hiker-circle.firebasestorage.app';
const firestoreRoot =
  `https://firestore.googleapis.com/v1/projects/${projectId}` +
  '/databases/(default)/documents';
const apply = process.argv.includes('--apply');
const now = Date.now();
const hour = 60 * 60 * 1000;
const day = 24 * hour;

if (projectId !== expectedProjectId) {
  throw new Error(`Refusing to run against unexpected project ${projectId}.`);
}

function decodeValue(value) {
  if (!value || typeof value !== 'object') return null;
  if ('nullValue' in value) return null;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return Number(value.doubleValue);
  if ('booleanValue' in value) return value.booleanValue;
  if ('timestampValue' in value) return value.timestampValue;
  if ('geoPointValue' in value) return value.geoPointValue;
  if ('referenceValue' in value) return value.referenceValue;
  if ('bytesValue' in value) return value.bytesValue;
  if (value.arrayValue) {
    return (value.arrayValue.values || []).map(decodeValue);
  }
  if (value.mapValue) return decodeFields(value.mapValue.fields || {});
  return null;
}

function decodeFields(fields) {
  return Object.fromEntries(
    Object.entries(fields || {}).map(([name, value]) => [name, decodeValue(value)]),
  );
}

function millis(value) {
  if (typeof value === 'number') return value;
  if (typeof value === 'string') {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : Number(value);
  }
  return NaN;
}

function relativeDocumentPath(document) {
  const marker = '/documents/';
  const index = document.name.indexOf(marker);
  if (index < 0) throw new Error(`Unexpected Firestore name ${document.name}.`);
  return document.name.slice(index + marker.length);
}

function encodedDocumentPath(relativePath) {
  return relativePath.split('/').map(encodeURIComponent).join('/');
}

async function listRootDocuments(token, collectionId) {
  const documents = [];
  let pageToken = '';
  do {
    const url = new URL(`${firestoreRoot}/${encodeURIComponent(collectionId)}`);
    url.searchParams.set('pageSize', '300');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const response = await firestoreRequest(token, url);
    documents.push(...(response.documents || []));
    pageToken = response.nextPageToken || '';
  } while (pageToken);
  return documents;
}

async function queryCollectionGroup(token, collectionId) {
  const response = await firestoreRequest(token, `${firestoreRoot}:runQuery`, {
    method: 'POST',
    body: JSON.stringify({
      structuredQuery: {from: [{collectionId, allDescendants: true}]},
    }),
  });
  return (response || []).map((row) => row.document).filter(Boolean);
}

async function documentExists(token, relativePath) {
  const response = await fetch(`${firestoreRoot}/${encodedDocumentPath(relativePath)}`, {
    headers: {Authorization: `Bearer ${token}`},
  });
  if (response.status === 404) return false;
  if (!response.ok) throw new Error(`Firestore ${response.status}: ${await response.text()}`);
  return true;
}

function isExpiredChallenge(data) {
  return data.consumed === true || millis(data.expiresAtMillis) < now;
}

function isExpiredResetSession(data) {
  return data.used === true || millis(data.expiresAtMillis) < now;
}

function isExpiredLiveShare(data) {
  return data.isActive === false || millis(data.expiresAt || data.expiresAtLocal) < now;
}

function isStaleRateLimit(data) {
  // The longest application rate-limit window is 24 hours. The extra hour
  // avoids deleting a counter at the exact boundary while another call runs.
  return millis(data.windowStartedAtMillis) < now - (25 * hour);
}

function isOldTerminalOutbox(data) {
  const terminal = new Set(['sent', 'partial', 'failed', 'no_token']);
  const processed = millis(data.processedAt || data.processedAtLocal || data.updatedAt);
  return terminal.has(String(data.status || '')) && processed < now - (30 * day);
}

async function firestoreCandidates(token) {
  const candidates = [];
  const selectors = new Map([
    ['greenApiLoginChallenges', isExpiredChallenge],
    ['passwordResetChallenges', isExpiredChallenge],
    ['passwordResetSessions', isExpiredResetSession],
    ['live_location_shares', isExpiredLiveShare],
    ['fcmOutbox', isOldTerminalOutbox],
  ]);
  const rateCollections = [
    'activeHikeStartRateLimits',
    'buddyRequestRateLimits',
    'directChatActionRateLimits',
    'hikeCompletionRateLimits',
    'hikeSessionRecoveryRateLimits',
    'sosMessageRateLimits',
    'teamHikeActionRateLimits',
    'upcomingHikeJoinRequestRateLimits',
    'upcomingHikeRateLimits',
  ];
  for (const collection of rateCollections) selectors.set(collection, isStaleRateLimit);

  for (const [collection, predicate] of selectors.entries()) {
    const documents = await listRootDocuments(token, collection);
    for (const document of documents) {
      if (predicate(decodeFields(document.fields || {}))) {
        candidates.push({kind: 'firestore', reason: collection, document});
      }
    }
  }

  for (const document of await queryCollectionGroup(token, 'reminderPreferences')) {
    const relativePath = relativeDocumentPath(document);
    const segments = relativePath.split('/');
    if (segments.length !== 4 || segments[0] !== 'upcomingHikes') continue;
    const parentPath = segments.slice(0, 2).join('/');
    if (!await documentExists(token, parentPath)) {
      candidates.push({kind: 'firestore', reason: 'orphanedReminderPreference', document});
    }
  }
  return candidates;
}

function collectStorageReferences(value, references) {
  if (typeof value === 'string') {
    const match = value.match(/\/o\/([^?]+)/);
    if (match && value.includes('firebasestorage.googleapis.com')) {
      references.add(decodeURIComponent(match[1]));
    } else if (/^[a-z_]+\//.test(value)) {
      references.add(value);
    }
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) collectStorageReferences(item, references);
    return;
  }
  if (value && typeof value === 'object') {
    for (const item of Object.values(value)) collectStorageReferences(item, references);
  }
}

async function allFirestoreStorageReferences(token) {
  const references = new Set();
  const ids = await firestoreRequest(token, `${firestoreRoot}:listCollectionIds`, {
    method: 'POST',
    body: JSON.stringify({pageSize: 1000}),
  });
  for (const collectionId of ids.collectionIds || []) {
    for (const document of await listRootDocuments(token, collectionId)) {
      collectStorageReferences(decodeFields(document.fields || {}), references);
    }
  }
  for (const collectionId of ['authFactors', 'comments', 'messages', 'ratings', 'reports']) {
    for (const document of await queryCollectionGroup(token, collectionId)) {
      collectStorageReferences(decodeFields(document.fields || {}), references);
    }
  }
  return references;
}

function collectCheckedInStorageReferences(references) {
  const files = [
    path.join(__dirname, '..', 'assets', 'guides', 'first_aid_guide.json'),
    path.join(__dirname, '..', 'web', 'site', 'beta-release.json'),
  ];
  for (const file of files) {
    if (!fs.existsSync(file)) continue;
    collectStorageReferences(JSON.parse(fs.readFileSync(file, 'utf8')), references);
  }
}

async function collectAuthPhotoReferences(token, references) {
  let nextPageToken = '';
  do {
    const url = new URL(
      `https://identitytoolkit.googleapis.com/v1/projects/${projectId}/accounts:batchGet`,
    );
    url.searchParams.set('maxResults', '1000');
    if (nextPageToken) url.searchParams.set('nextPageToken', nextPageToken);
    const response = await firestoreRequest(token, url);
    for (const user of response.users || []) {
      collectStorageReferences(String(user.photoUrl || ''), references);
    }
    nextPageToken = response.nextPageToken || '';
  } while (nextPageToken);
}

async function listStorageObjects(token) {
  const objects = [];
  let pageToken = '';
  do {
    const url = new URL(`https://storage.googleapis.com/storage/v1/b/${bucketName}/o`);
    url.searchParams.set('maxResults', '1000');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const response = await firestoreRequest(token, url);
    objects.push(...(response.items || []));
    pageToken = response.nextPageToken || '';
  } while (pageToken);
  return objects;
}

function replaceableStorageObject(name) {
  return name.startsWith('first_aid/videos/')
    || name.startsWith('profile_photos/')
    || name.startsWith('trail_covers/curated/');
}

async function storageCandidates(token) {
  const references = await allFirestoreStorageReferences(token);
  collectCheckedInStorageReferences(references);
  await collectAuthPhotoReferences(token, references);
  const objects = await listStorageObjects(token);
  return objects
    .filter((object) => replaceableStorageObject(object.name))
    .filter((object) => !references.has(object.name))
    .map((object) => ({kind: 'storage', reason: 'unreferencedReplaceableAsset', object}));
}

async function hostingCandidates(token) {
  const siteRoot =
    `https://firebasehosting.googleapis.com/v1beta1/projects/${projectId}` +
    `/sites/${projectId}`;
  const [versionResponse, channelResponse] = await Promise.all([
    firestoreRequest(token, `${siteRoot}/versions?pageSize=1000`),
    firestoreRequest(token, `${siteRoot}/channels?pageSize=100`),
  ]);
  const activeVersions = new Set(
    (channelResponse.channels || [])
      .map((channel) => channel.release?.version?.name)
      .filter(Boolean),
  );
  return (versionResponse.versions || [])
    .filter((version) => version.status !== 'DELETED')
    .filter((version) => !activeVersions.has(version.name))
    .filter((version) => millis(version.createTime) < now - (30 * day))
    .map((version) => ({kind: 'hosting', reason: 'supersededHostingVersion', version}));
}

function safeBackupSegment(value) {
  return String(value).replace(/[^A-Za-z0-9._+-]/g, '_');
}

async function backUpStorageObject(token, candidate, root) {
  const name = candidate.object.name;
  const target = path.join(root, 'storage', ...name.split('/').map(safeBackupSegment));
  fs.mkdirSync(path.dirname(target), {recursive: true});
  const mediaUrl =
    `https://storage.googleapis.com/storage/v1/b/${bucketName}/o/` +
    `${encodeURIComponent(name)}?alt=media`;
  const response = await fetch(mediaUrl, {headers: {Authorization: `Bearer ${token}`}});
  if (!response.ok) throw new Error(`Storage backup ${response.status}: ${await response.text()}`);
  fs.writeFileSync(target, Buffer.from(await response.arrayBuffer()));
  return target;
}

async function deleteFirestoreDocument(token, document) {
  const relativePath = relativeDocumentPath(document);
  const response = await fetch(`${firestoreRoot}/${encodedDocumentPath(relativePath)}`, {
    method: 'DELETE',
    headers: {Authorization: `Bearer ${token}`},
  });
  if (!response.ok) throw new Error(`Firestore delete ${response.status}: ${await response.text()}`);
}

async function deleteStorageObject(token, object) {
  const url =
    `https://storage.googleapis.com/storage/v1/b/${bucketName}/o/` +
    encodeURIComponent(object.name);
  const response = await fetch(url, {
    method: 'DELETE',
    headers: {Authorization: `Bearer ${token}`},
  });
  if (!response.ok) throw new Error(`Storage delete ${response.status}: ${await response.text()}`);
}

async function deleteHostingVersion(token, version) {
  const response = await fetch(
    `https://firebasehosting.googleapis.com/v1beta1/${version.name}`,
    {method: 'DELETE', headers: {Authorization: `Bearer ${token}`}},
  );
  if (!response.ok) throw new Error(`Hosting delete ${response.status}: ${await response.text()}`);
}

function publicSummary(firestore, storage, hosting) {
  const byReason = {};
  for (const item of [...firestore, ...storage, ...hosting]) {
    byReason[item.reason] = (byReason[item.reason] || 0) + 1;
  }
  return {
    mode: apply ? 'apply' : 'dry-run',
    projectId,
    firestoreDocuments: firestore.length,
    storageObjects: storage.length,
    storageBytes: storage.reduce((sum, item) => sum + Number(item.object.size || 0), 0),
    hostingVersions: hosting.length,
    hostingVersionBytes: hosting.reduce(
      (sum, item) => sum + Number(item.version.versionBytes || 0),
      0,
    ),
    byReason,
  };
}

async function main() {
  const token = await firebaseAccessToken();
  const firestore = await firestoreCandidates(token);
  const storage = await storageCandidates(token);
  const hosting = await hostingCandidates(token);
  console.log(JSON.stringify(publicSummary(firestore, storage, hosting), null, 2));
  if (!apply) return;

  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupRoot = path.join(__dirname, '..', 'tmp', `firebase-cleanup-backup-${stamp}`);
  fs.mkdirSync(backupRoot, {recursive: true});
  const manifest = {
    generatedAt: new Date().toISOString(),
    projectId,
    firestore: firestore.map((item) => ({
      reason: item.reason,
      relativePath: relativeDocumentPath(item.document),
      document: item.document,
    })),
    storage: storage.map((item) => ({reason: item.reason, object: item.object})),
    hosting: hosting.map((item) => ({
      reason: item.reason,
      version: {
        name: item.version.name,
        status: item.version.status,
        createTime: item.version.createTime,
        finalizeTime: item.version.finalizeTime,
        fileCount: item.version.fileCount,
        versionBytes: item.version.versionBytes,
      },
    })),
  };
  fs.writeFileSync(
    path.join(backupRoot, 'manifest.json'),
    JSON.stringify(manifest, null, 2),
  );

  for (const candidate of storage) await backUpStorageObject(token, candidate, backupRoot);
  for (const candidate of firestore) await deleteFirestoreDocument(token, candidate.document);
  for (const candidate of storage) await deleteStorageObject(token, candidate.object);
  for (const candidate of hosting) await deleteHostingVersion(token, candidate.version);
  console.log(`Backup: ${backupRoot}`);
  console.log(
    `Deleted ${firestore.length} Firestore documents, ${storage.length} storage objects, ` +
    `and ${hosting.length} superseded Hosting versions.`,
  );
}

main().catch((error) => {
  console.error(error && error.stack || error);
  process.exitCode = 1;
});

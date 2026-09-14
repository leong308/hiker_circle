/* eslint-disable no-console */
'use strict';

// Read-only live Firebase inventory. Values are reduced to field/type metadata;
// the report intentionally contains no message bodies, phone numbers, tokens,
// coordinates, profile text, or other user content.

const fs = require('fs');
const path = require('path');
const {
  firebaseAccessToken,
  firestoreRequest,
  projectId,
} = require('./seed_malaysia_trails');

const firestoreRoot =
  `https://firestore.googleapis.com/v1/projects/${projectId}` +
  '/databases/(default)/documents';
const bucketName = 'hiker-circle.firebasestorage.app';

function valueType(value) {
  if (!value || typeof value !== 'object') return 'unknown';
  const key = Object.keys(value)[0] || '';
  return key.replace(/Value$/, '') || 'unknown';
}

function decodedScalar(value) {
  if (!value || typeof value !== 'object') return null;
  if ('timestampValue' in value) return value.timestampValue;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('nullValue' in value) return null;
  return undefined;
}

function collectFieldSchema(target, fields) {
  for (const [name, value] of Object.entries(fields || {})) {
    const field = target[name] || { present: 0, types: {} };
    field.present += 1;
    const type = valueType(value);
    field.types[type] = (field.types[type] || 0) + 1;
    target[name] = field;
  }
}

function collectExpiry(summary, fields) {
  const expiresAt = decodedScalar(fields && fields.expiresAt);
  if (typeof expiresAt !== 'string') return;
  const milliseconds = Date.parse(expiresAt);
  if (Number.isFinite(milliseconds) && milliseconds < Date.now()) {
    summary.expiredDocuments += 1;
  }
}

function collectStorageReferences(value, references, fieldPath = '') {
  if (!value || typeof value !== 'object') return;
  if ('stringValue' in value) {
    const text = value.stringValue || '';
    const match = text.match(/\/o\/([^?]+)/);
    if (match && text.includes('firebasestorage.googleapis.com')) {
      references.add(decodeURIComponent(match[1]));
    } else if (
      /^(trail_covers|community_hikes|group_chats|profile_photos|app_feedback|releases|first_aid)\//
        .test(text)
    ) {
      references.add(text);
    }
    return;
  }
  if (value.mapValue && value.mapValue.fields) {
    for (const [name, nested] of Object.entries(value.mapValue.fields)) {
      collectStorageReferences(nested, references, `${fieldPath}.${name}`);
    }
  }
  if (value.arrayValue && Array.isArray(value.arrayValue.values)) {
    for (const nested of value.arrayValue.values) {
      collectStorageReferences(nested, references, fieldPath);
    }
  }
}

function collectPlainStorageReferences(value, references) {
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
    for (const nested of value) collectPlainStorageReferences(nested, references);
    return;
  }
  if (value && typeof value === 'object') {
    for (const nested of Object.values(value)) {
      collectPlainStorageReferences(nested, references);
    }
  }
}

async function listCollectionIds(token) {
  const result = [];
  let pageToken = '';
  do {
    const body = { pageSize: 1000 };
    if (pageToken) body.pageToken = pageToken;
    const response = await firestoreRequest(
      token,
      `${firestoreRoot}:listCollectionIds`,
      { method: 'POST', body: JSON.stringify(body) },
    );
    result.push(...(response.collectionIds || []));
    pageToken = response.nextPageToken || '';
  } while (pageToken);
  return [...new Set(result)].sort();
}

async function listRootDocuments(token, collectionId, visitor) {
  let pageToken = '';
  do {
    const url = new URL(`${firestoreRoot}/${encodeURIComponent(collectionId)}`);
    url.searchParams.set('pageSize', '300');
    url.searchParams.set('showMissing', 'false');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const response = await firestoreRequest(token, url);
    for (const document of response.documents || []) visitor(document);
    pageToken = response.nextPageToken || '';
  } while (pageToken);
}

async function queryCollectionGroup(token, collectionId, visitor) {
  const response = await firestoreRequest(token, `${firestoreRoot}:runQuery`, {
    method: 'POST',
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId, allDescendants: true }],
      },
    }),
  });
  for (const row of response || []) {
    if (row.document) visitor(row.document);
  }
}

async function storageObjects(token) {
  const objects = [];
  let pageToken = '';
  do {
    const url = new URL(`https://storage.googleapis.com/storage/v1/b/${bucketName}/o`);
    url.searchParams.set('maxResults', '1000');
    url.searchParams.set('fields', 'items(name,size,contentType,timeCreated,updated),nextPageToken');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const response = await firestoreRequest(token, url);
    objects.push(...(response.items || []));
    pageToken = response.nextPageToken || '';
  } while (pageToken);
  return objects;
}

function summarizeDocuments() {
  return { documentCount: 0, expiredDocuments: 0, fields: {} };
}

function visitDocument(summary, references, document) {
  summary.documentCount += 1;
  collectFieldSchema(summary.fields, document.fields);
  collectExpiry(summary, document.fields);
  for (const [name, value] of Object.entries(document.fields || {})) {
    collectStorageReferences(value, references, name);
  }
}

function storagePrefix(name) {
  const slash = name.indexOf('/');
  return slash < 0 ? '(root)' : name.slice(0, slash);
}

async function main() {
  const token = await firebaseAccessToken();
  const storageReferences = new Set();
  const collections = {};
  const collectionIds = await listCollectionIds(token);
  for (const [index, collectionId] of collectionIds.entries()) {
    const summary = summarizeDocuments();
    await listRootDocuments(token, collectionId, (document) => {
      visitDocument(summary, storageReferences, document);
    });
    collections[collectionId] = summary;
    console.log(`[${index + 1}/${collectionIds.length}] ${collectionId}: ${summary.documentCount}`);
  }

  const knownSubcollections = [
    'authFactors',
    'comments',
    'messages',
    'ratings',
    'reminderPreferences',
    'reports',
  ];
  const subcollections = {};
  for (const collectionId of knownSubcollections) {
    const summary = summarizeDocuments();
    await queryCollectionGroup(token, collectionId, (document) => {
      visitDocument(summary, storageReferences, document);
    });
    subcollections[collectionId] = summary;
  }

  for (const relativePath of [
    ['assets', 'guides', 'first_aid_guide.json'],
    ['web', 'site', 'beta-release.json'],
  ]) {
    const localPath = path.join(__dirname, '..', ...relativePath);
    if (fs.existsSync(localPath)) {
      collectPlainStorageReferences(
        JSON.parse(fs.readFileSync(localPath, 'utf8')),
        storageReferences,
      );
    }
  }

  const objects = await storageObjects(token);
  const prefixes = {};
  let totalBytes = 0;
  for (const object of objects) {
    const prefix = storagePrefix(object.name);
    const size = Number(object.size) || 0;
    totalBytes += size;
    prefixes[prefix] = prefixes[prefix] || { objectCount: 0, totalBytes: 0 };
    prefixes[prefix].objectCount += 1;
    prefixes[prefix].totalBytes += size;
  }
  const referencedObjects = objects.filter((object) => storageReferences.has(object.name));
  const unreferencedObjects = objects
    .filter((object) => !storageReferences.has(object.name))
    .map((object) => ({
      name: object.name,
      size: Number(object.size) || 0,
      contentType: object.contentType || '',
      timeCreated: object.timeCreated || '',
    }));

  const report = {
    generatedAt: new Date().toISOString(),
    projectId,
    firestore: { collections, subcollections },
    storage: {
      bucketName,
      objectCount: objects.length,
      totalBytes,
      prefixes,
      referencedObjectCount: referencedObjects.length,
      unreferencedObjects,
    },
  };
  const output = path.join(__dirname, '..', 'tmp', 'firebase_inventory.json');
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, JSON.stringify(report, null, 2));
  console.log(`Inventory written to ${output}`);
}

main().catch((error) => {
  console.error(error && error.stack || error);
  process.exitCode = 1;
});

/* eslint-disable no-console */
'use strict';

// Normalizes bulky SOS copies out of users/{uid}. The canonical event remains
// in sosAlerts/{alertId}; users keep only the latest path, up to 30 recent
// paths, and summary metadata. Read-only unless --apply is supplied.

const fs = require('fs');
const path = require('path');
const {
  firebaseAccessToken,
  firestoreRequest,
  projectId,
} = require('./seed_malaysia_trails');

const expectedProjectId = 'hiker-circle';
const apply = process.argv.includes('--apply');
const verifyOnly = process.argv.includes('--verify');
const firestoreRoot =
  `https://firestore.googleapis.com/v1/projects/${projectId}` +
  '/databases/(default)/documents';
const maxRecentReferences = 30;

if (projectId !== expectedProjectId) {
  throw new Error(`Refusing to run against unexpected project ${projectId}.`);
}

function stringValue(value) {
  return value && typeof value.stringValue === 'string' ? value.stringValue : '';
}

function documentId(document) {
  return document.name.split('/').at(-1);
}

function embeddedAlertMaps(user) {
  const result = [];
  const array = user.fields?.sos_alerts?.arrayValue?.values || [];
  for (const value of array) {
    if (value.mapValue?.fields) result.push(value.mapValue.fields);
  }
  const latest = user.fields?.latest_sos_alert?.mapValue?.fields;
  if (latest) result.push(latest);
  return result;
}

function alertIdFromFields(fields) {
  return stringValue(fields?.id).trim();
}

function alertMillis(fields, fallback = '') {
  const local = stringValue(fields?.triggeredAtLocal);
  const timestamp = fields?.triggeredAt?.timestampValue || fallback;
  const parsed = Date.parse(local || timestamp || '');
  return Number.isFinite(parsed) ? parsed : 0;
}

async function listDocuments(token, collection) {
  const documents = [];
  let pageToken = '';
  do {
    const url = new URL(`${firestoreRoot}/${encodeURIComponent(collection)}`);
    url.searchParams.set('pageSize', '300');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const response = await firestoreRequest(token, url);
    documents.push(...(response.documents || []));
    pageToken = response.nextPageToken || '';
  } while (pageToken);
  return documents;
}

function canonicalByUser(alertDocuments) {
  const result = new Map();
  for (const document of alertDocuments) {
    const userId = stringValue(document.fields?.userId);
    if (!userId) continue;
    if (!result.has(userId)) result.set(userId, []);
    result.get(userId).push(document);
  }
  return result;
}

function uniqueLegacyAlerts(user) {
  const result = new Map();
  for (const fields of embeddedAlertMaps(user)) {
    const id = alertIdFromFields(fields);
    if (id && !result.has(id)) result.set(id, fields);
  }
  return result;
}

function publicPlan(users, canonicalAlerts) {
  const byUser = canonicalByUser(canonicalAlerts);
  return users.map((user, index) => {
    const legacy = uniqueLegacyAlerts(user);
    const canonical = byUser.get(documentId(user)) || [];
    const canonicalIds = new Set(canonical.map(documentId));
    return {
      user: index + 1,
      encodedBytesBefore: Buffer.byteLength(JSON.stringify(user)),
      embeddedAlertCopies: legacy.size,
      canonicalAlertDocuments: canonical.length,
      missingCanonicalDocuments: [...legacy.keys()].filter((id) => !canonicalIds.has(id)).length,
      recentReferencesAfter: Math.min(
        maxRecentReferences,
        new Set([...canonicalIds, ...legacy.keys()]).size,
      ),
    };
  });
}

function missingCanonicalWrites(users, canonicalAlerts) {
  const known = new Set(canonicalAlerts.map(documentId));
  const writes = [];
  for (const user of users) {
    const userId = documentId(user);
    const phoneNumber = user.fields?.phoneNumber;
    for (const [alertId, legacyFields] of uniqueLegacyAlerts(user)) {
      if (known.has(alertId)) continue;
      const fields = {
        ...legacyFields,
        userId: {stringValue: userId},
        cloudLogPath: {stringValue: `sosAlerts/${alertId}`},
        ...(phoneNumber ? {phoneNumber} : {}),
      };
      writes.push({
        update: {
          name: `${firestoreRoot}/sosAlerts/${alertId}`,
          fields,
        },
        updateTransforms: [
          {fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME'},
        ],
        currentDocument: {exists: false},
      });
      known.add(alertId);
    }
  }
  return writes;
}

function userReferenceWrites(users, canonicalAlerts, missingWrites) {
  const allCanonical = [
    ...canonicalAlerts,
    ...missingWrites.map((write) => ({
      name: write.update.name,
      fields: write.update.fields,
      createTime: '',
    })),
  ];
  const byUser = canonicalByUser(allCanonical);
  const nowIso = new Date().toISOString();
  return users.map((user) => {
    const userId = documentId(user);
    const alerts = [...(byUser.get(userId) || [])].sort((a, b) =>
      alertMillis(b.fields, b.createTime) - alertMillis(a.fields, a.createTime)
    );
    const recentPaths = alerts
      .slice(0, maxRecentReferences)
      .map((alert) => `sosAlerts/${documentId(alert)}`);
    const latestPath = recentPaths[0] || '';
    const fields = {
      recentSosAlertPaths: {
        arrayValue: {
          values: recentPaths.map((value) => ({stringValue: value})),
        },
      },
      sosAlertsCount: {integerValue: String(alerts.length)},
      sosAlertReferenceVersion: {integerValue: '1'},
      sosAlertReferencesMigratedAtLocal: {stringValue: nowIso},
      ...(latestPath ? {latestSosAlertPath: {stringValue: latestPath}} : {}),
    };
    return {
      update: {name: user.name, fields},
      updateMask: {
        fieldPaths: [
          'latest_sos_alert',
          'sos_alerts',
          'latestSosAlertPath',
          'recentSosAlertPaths',
          'sosAlertsCount',
          'sosAlertReferenceVersion',
          'sosAlertReferencesMigratedAtLocal',
        ],
      },
      updateTransforms: [
        {
          fieldPath: 'sosAlertReferencesMigratedAt',
          setToServerValue: 'REQUEST_TIME',
        },
      ],
      currentDocument: {exists: true},
    };
  });
}

async function commitWrites(token, writes) {
  for (let index = 0; index < writes.length; index += 400) {
    await firestoreRequest(token, `${firestoreRoot}:commit`, {
      method: 'POST',
      body: JSON.stringify({writes: writes.slice(index, index + 400)}),
    });
  }
}

async function verify(token) {
  const [users, alerts] = await Promise.all([
    listDocuments(token, 'users'),
    listDocuments(token, 'sosAlerts'),
  ]);
  const byUser = canonicalByUser(alerts);
  for (const user of users) {
    const fields = user.fields || {};
    if (fields.latest_sos_alert || fields.sos_alerts) {
      throw new Error(`Legacy embedded SOS fields remain on ${documentId(user)}.`);
    }
    const canonical = [...(byUser.get(documentId(user)) || [])].sort((a, b) =>
      alertMillis(b.fields, b.createTime) - alertMillis(a.fields, a.createTime)
    );
    const canonicalPaths = new Set(
      canonical.map((alert) => `sosAlerts/${documentId(alert)}`),
    );
    const paths = (fields.recentSosAlertPaths?.arrayValue?.values || [])
      .map(stringValue)
      .filter(Boolean);
    if (paths.length > maxRecentReferences) {
      throw new Error(`Too many recent SOS references on ${documentId(user)}.`);
    }
    if (paths.some((alertPath) => !canonicalPaths.has(alertPath))) {
      throw new Error(`A recent SOS reference is not owned by ${documentId(user)}.`);
    }
    const expectedLatest = canonical[0]
      ? `sosAlerts/${documentId(canonical[0])}`
      : '';
    if (stringValue(fields.latestSosAlertPath) !== expectedLatest) {
      throw new Error(`Latest SOS reference mismatch on ${documentId(user)}.`);
    }
    const expectedCount = canonical.length;
    const actualCount = Number(fields.sosAlertsCount?.integerValue || 0);
    if (actualCount !== expectedCount) {
      throw new Error(`SOS count mismatch on ${documentId(user)}.`);
    }
  }
  return users.map((user, index) => ({
    user: index + 1,
    encodedBytesAfter: Buffer.byteLength(JSON.stringify(user)),
    recentReferences: user.fields?.recentSosAlertPaths?.arrayValue?.values?.length || 0,
    canonicalAlertDocuments: (byUser.get(documentId(user)) || []).length,
  }));
}

async function main() {
  const token = await firebaseAccessToken();
  const [users, alerts] = await Promise.all([
    listDocuments(token, 'users'),
    listDocuments(token, 'sosAlerts'),
  ]);
  const plan = publicPlan(users, alerts);
  console.log(JSON.stringify({mode: apply ? 'apply' : verifyOnly ? 'verify' : 'dry-run', users: plan}, null, 2));
  if (!apply) {
    if (verifyOnly) console.log(JSON.stringify({verified: await verify(token)}, null, 2));
    return;
  }

  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupRoot = path.join(
    __dirname,
    '..',
    'tmp',
    `firebase-sos-reference-migration-${stamp}`,
  );
  fs.mkdirSync(backupRoot, {recursive: true});
  fs.writeFileSync(
    path.join(backupRoot, 'users-before.json'),
    JSON.stringify({projectId, generatedAt: new Date().toISOString(), users}, null, 2),
  );

  const missingWrites = missingCanonicalWrites(users, alerts);
  await commitWrites(token, missingWrites);
  // Canonical documents are committed first. Only then are duplicate embedded
  // fields removed from users and replaced with lightweight paths.
  const freshAlerts = await listDocuments(token, 'sosAlerts');
  const referenceWrites = userReferenceWrites(users, freshAlerts, []);
  await commitWrites(token, referenceWrites);
  const verified = await verify(token);
  console.log(JSON.stringify({backup: backupRoot, verified}, null, 2));
}

main().catch((error) => {
  console.error(error && error.stack || error);
  process.exitCode = 1;
});

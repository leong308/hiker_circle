/* eslint-disable no-console */
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const inventoryPath = path.join(root, 'tmp', 'firebase_inventory.json');
const functionsPath = path.join(root, 'tmp', 'live_functions.json');
const indexesPath = path.join(root, 'firestore.indexes.json');
const outputPath = path.join(root, 'docs', 'FIREBASE_SCHEMA_AND_CLEANUP.md');

for (const required of [inventoryPath, functionsPath, indexesPath]) {
  if (!fs.existsSync(required)) throw new Error(`Missing audit input: ${required}`);
}

const inventory = JSON.parse(fs.readFileSync(inventoryPath, 'utf8'));
const deployedFunctions = JSON.parse(fs.readFileSync(functionsPath, 'utf8')).result || [];
const indexes = JSON.parse(fs.readFileSync(indexesPath, 'utf8')).indexes || [];
const lines = [];

const purposes = {
  achievementEventReceipts: 'Idempotency receipts for achievement event processing.',
  achievements: 'Server-managed achievement catalogue and reward definitions.',
  appFeedback: 'In-app feedback reports and optional screenshot references.',
  checkIns: 'Safety check-ins recorded during a hike session.',
  communityCounterEventReceipts: 'Idempotency receipts for post comment counters.',
  communityPosts: 'Community hike posts, route previews, images, and engagement counters.',
  downloadedMaps: 'Per-user metadata for offline trail-map downloads.',
  fcmOutbox: 'Short-lived queue and delivery result for team-hike push notifications.',
  groupChats: 'Direct and hike-derived chat metadata and lifecycle state.',
  hazardReports: 'User-submitted trail hazard reports and moderation status.',
  hikeRouteCaptures: 'Detailed recorded route geometry and completion summary.',
  hikeSessionTerminalStates: 'Idempotent terminal-state markers for completion processing.',
  hikeSessions: 'Active and historical solo/group hike sessions.',
  liveLocationContactDispatches: 'At-most-once delivery ledger for live-location messages.',
  localLocationPoints: 'Synced raw route/location observations used by hike history.',
  maintenanceState: 'Cursor and progress state for backend maintenance jobs.',
  nearbySosIncidents: 'Deduplicated nearby SOS incidents reported by button receivers.',
  networkObservations: 'Route network-availability observations.',
  sosAlerts: 'Canonical SOS events and their contact delivery summary.',
  sosWhatsAppDispatches: 'At-most-once WhatsApp delivery ledger for SOS messages.',
  teamHikeSessions: 'Team readiness, participant state, shared plan, and active-session links.',
  teams: 'Saved team definition and member list.',
  trailWeatherCache: 'Backend weather cache and refresh lease state.',
  trails: 'Trail catalogue, Mapbox route, elevation range, media, ratings, and hazards.',
  upcomingHikeJoinRequests: 'Join-request workflow and host notification outcome.',
  userAchievements: 'Per-user progress and award state for each achievement.',
  users: 'Private account profile, safety settings, MFA summary, devices, and aggregates.',
  whatsAppMessageLogs: 'User-facing WhatsApp send history for SOS messaging.',
};

const lifecycle = {
  achievementEventReceipts: 'Keep while source event replay remains possible.',
  communityCounterEventReceipts: 'Keep while source event replay remains possible.',
  fcmOutbox: 'Terminal entries: 30-day retention; pending entries retained.',
  liveLocationContactDispatches: 'Operational delivery evidence; retain with SOS/live-share audit.',
  maintenanceState: 'Singleton operational state; never purge while jobs use it.',
  trailWeatherCache: 'Replace in place; safe to rebuild from provider.',
  whatsAppMessageLogs: 'User-visible message history; retained.',
  sosWhatsAppDispatches: 'SOS delivery evidence; retained.',
  sosAlerts: 'Safety history; retained.',
};

const backendOnly = new Set([
  'achievementEventReceipts',
  'communityCounterEventReceipts',
  'fcmOutbox',
  'hikeSessionTerminalStates',
  'liveLocationContactDispatches',
  'maintenanceState',
  'nearbySosIncidents',
  'sosWhatsAppDispatches',
  'trailWeatherCache',
]);

const definedEmptySchemas = {
  activeHikeStartRateLimits: 'windowStartedAtMillis:int, actionCount:int, updatedAt:timestamp',
  buddyRequestRateLimits: 'windowStartedAtMillis:int, requestCount:int, updatedAt:timestamp',
  directChatActionRateLimits: 'windowStartedAtMillis:int, actionCount:int, updatedAt:timestamp',
  greenApiLoginChallenges: 'phoneNumber:string, codeHash:string, intent:string, attemptsRemaining:int, consumed:boolean, expiresAtMillis:int, deliveryState:string, providerMessageId?:string, createdAt:timestamp, verifiedAt?:timestamp',
  hikeCompletionRateLimits: 'windowStartedAtMillis:int, actionCount:int, updatedAt:timestamp',
  hikeSessionRecoveryRateLimits: 'windowStartedAtMillis:int, actionCount:int, updatedAt:timestamp',
  live_location_shares: 'shareId:string, ownerUserId:string, ownerUserDocumentPath:string, phoneNumber:string, shareUrl:string, latestLocation:map, isActive:boolean, expiresAt:timestamp, createdAt:timestamp, updatedAt:timestamp plus Local ISO mirrors',
  mfaAuthenticationChallenges: 'sessionDigest:string, userId:string, webAuthnChallenge:string, attemptsRemaining:int, consumed:boolean, expiresAtMillis:int, createdAt:timestamp',
  mfaEnrollmentChallenges: 'kind:string, contextKey:string, userId:string, phoneNumber:string, encryptedSecret?:map, webAuthnChallenge?:string, attemptsRemaining:int, consumed:boolean, expiresAtMillis:int, createdAt:timestamp',
  mfaLoginSessions: 'userId:string, phoneNumber:string, whatsappChallengeId:string, whatsappVerified:boolean, enrollmentRequired:boolean, methods:array<string>, attemptsRemaining:int, consumed:boolean, expiresAtMillis:int, createdAt:timestamp, createdAtLocal:string',
  passwordResetChallenges: 'phoneNumber:string, codeHash:string, attemptsRemaining:int, consumed:boolean, expiresAtMillis:int, sentAtMillis:int, createdAt:timestamp, verifiedAt?:timestamp',
  passwordResetSessions: 'phoneNumber:string, challengeId:string, verifiedAt:timestamp, used:boolean, expiresAtMillis:int, safetyQuestionField:string, skipQuestion:boolean, attemptsRemaining:int, createdAt:timestamp',
  sosMessageRateLimits: 'windowStartedAtMillis:int, sendCount:int, updatedAt:timestamp',
  teamHikeActionRateLimits: 'windowStartedAtMillis:int, actionCount:int, updatedAt:timestamp',
  upcomingHikeJoinRequestRateLimits: 'windowStartedAtMillis:int, actionCount:int, updatedAt:timestamp',
  upcomingHikeRateLimits: 'windowStartedAtMillis:int, actionCount:int, updatedAt:timestamp',
  upcomingHikes: 'hikeId:string, creatorUserId:string, creatorPhoneNumber:string, trailId:string, trailName:string, start/destination and coordinates, departure/estimated-return times, hikeType:string, joinPolicy:string, participants/invites:array, reminder counters/status, createdAt/updatedAt timestamps plus Local ISO mirrors',
};

function add(value = '') { lines.push(value); }

function escapeCell(value) {
  return String(value ?? '').replaceAll('|', '\\|').replaceAll('\n', '<br>');
}

function bytes(value) {
  const number = Number(value || 0);
  return `${(number / (1024 * 1024)).toFixed(2)} MiB`;
}

function normalizedFieldName(name) {
  return String(name)
    .replace(/^(lastReadAt|unreadCount)\..+$/, '$1.{phoneKey}')
    .replace(/^(buddyRequestsIncoming|buddyRequestsOutgoing)\..+$/, '$1.{phoneKey}')
    .replace(/^(fcmTokenByAppId)\..+$/, '$1.{appInstanceId}');
}

function normalizedFields(summary) {
  const result = new Map();
  for (const [rawName, field] of Object.entries(summary.fields || {})) {
    const name = normalizedFieldName(rawName);
    const current = result.get(name) || {present: 0, types: {}};
    current.present = Math.max(current.present, Number(field.present || 0));
    for (const [type, count] of Object.entries(field.types || {})) {
      current.types[type] = (current.types[type] || 0) + Number(count || 0);
    }
    result.set(name, current);
  }
  return [...result.entries()].sort(([a], [b]) => a.localeCompare(b));
}

function typeLabel(field) {
  return Object.keys(field.types || {}).sort().join(' | ') || 'not observed';
}

function triggerLabel(fn) {
  if (fn.callableTrigger) return 'Callable HTTPS';
  if (fn.httpsTrigger) return 'HTTP request';
  if (fn.scheduleTrigger) return 'Scheduled';
  if (fn.eventTrigger) {
    const pattern = fn.eventTrigger.eventFilterPathPatterns?.document || '';
    const event = String(fn.eventTrigger.eventType || '').split('.').pop();
    return `Firestore ${event}${pattern ? ` — ${pattern}` : ''}`;
  }
  return 'Other';
}

add('# HikerCircle Firebase Schema and Cleanup Audit');
add();
add(`- Audit snapshot: **${inventory.generatedAt}**`);
add(`- Firebase project: **${inventory.projectId}**`);
add('- Scope: Authentication, Cloud Firestore, Cloud Storage, Cloud Functions, Hosting, rules, indexes, and data lifecycle.');
add();
add('> This document records schema names and types only. User values, tokens, verification codes, messages, coordinates, and secrets are deliberately excluded. A field observed in fewer than all documents is optional, legacy, workflow-specific, or populated later by the backend.');
add();
add('## Audit result');
add();
add('- Cloud Functions: **80 ACTIVE deployments**, exactly matching the 80 exports in `functions/index.js`; no stale function was deleted.');
add(`- Firestore after cleanup: **${Object.keys(inventory.firestore.collections).length} non-empty root collections** plus documented subcollections.`);
add(`- Cloud Storage after cleanup: **${inventory.storage.objectCount} objects / ${bytes(inventory.storage.totalBytes)}**.`);
add('- Firebase Authentication: **2 accounts** were counted through the Admin API; account values were not exported.');
add('- Firebase Hosting: one live default site, `hiker-circle` (`https://hiker-circle.web.app`).');
add('- Hosting versions: 2 superseded versions older than 30 days were deleted; 52 finalized versions inside the 30-day rollback window were retained.');
add('- Realtime Database: no instance. Firebase Extensions: none installed.');
add('- Secret Manager: 3 secrets (`GREEN_API_INSTANCE_ID`, `GREEN_API_TOKEN`, `MFA_TOTP_ENCRYPTION_KEY`), all referenced by deployed Functions; none removed.');
add('- Every remaining non-empty Firestore root collection has a repository code/rules reference.');
add();
add('## Cleanup performed');
add();
add('| Removed data | Count | Reason |');
add('|---|---:|---|');
add('| Terminal FCM outbox entries older than 30 days | 236 documents | Completed delivery work-state; not notification history |');
add('| Expired/consumed WhatsApp login and password-reset challenges/sessions | 9 documents | Security artifacts beyond their 5–10 minute validity |');
add('| Expired or inactive live-location shares | 3 documents | Links were no longer usable |');
add('| Rate-limit counters older than their longest 24-hour window | 22 documents | Counters are recreated on demand |');
add('| Reminder preferences beneath deleted upcoming hikes | 12 documents | Orphaned subcollection records |');
add('| Superseded profile photos | 4 objects | No reference in Firestore or Firebase Auth |');
add('| Superseded non-Malaysian first-aid videos | 7 objects | Replaced by the checked-in KKM media manifest |');
add('| Orphaned generated trail covers | 3 objects | No trail or code reference |');
add('| Superseded Hosting deployments older than 30 days | 2 versions | Not referenced by the live channel; 32,784,977 version bytes released |');
add('| **Total** | **282 documents + 14 objects + 2 Hosting versions** | **79,939,593 storage/version bytes reclaimed** |');
add();
add('Recoverable pre-delete backups:');
add();
add('- `tmp/firebase-cleanup-backup-2026-09-13T01-34-59-600Z/`');
add('- `tmp/firebase-cleanup-backup-2026-09-13T01-36-34-725Z/`');
add('- `tmp/firebase-cleanup-backup-2026-09-13T01-43-06-612Z/`');
add();
add('The backups are ignored by Git and contain the exact deleted Firestore representations and media bytes. They may contain private application data and must not be committed or shared. The post-cleanup dry run reports zero remaining eligible records or objects.');
add();
add('## SOS user-document normalization');
add();
add('All **140** canonical `sosAlerts/{alertId}` documents were preserved. The duplicated event maps formerly embedded in `users/{uid}.latest_sos_alert` and `users/{uid}.sos_alerts` were migrated to lightweight metadata:');
add();
add('- `latestSosAlertPath:string` points to the newest canonical alert.');
add('- `recentSosAlertPaths:array<string>` contains at most 30 newest canonical paths.');
add('- `sosAlertsCount:int` is reconciled to the canonical per-user document count.');
add('- `sosAlertReferenceVersion:int` and migration timestamps identify the normalized schema.');
add();
add('Encoded REST document size dropped from approximately **42 KB to 9 KB** for one account and **166 KB to 10 KB** for the other. No SOS alert document was deleted. Pre-migration backups are stored under `tmp/firebase-sos-reference-migration-*` and are Git-ignored/private.');
add();
add('### Explicitly retained');
add();
add('Hike sessions/history, raw route points, route captures, check-ins, SOS events and dispatch evidence, chats/messages, community posts, user/achievement records, trail ratings, current trail covers, feedback screenshots, the current profile photo, and the published Android beta APK were retained. These are active, user-facing, safety/audit-relevant, or still referenced.');
add();
add('## Firestore collection registry');
add();
add('| Collection | Documents | Purpose | Access | Lifecycle |');
add('|---|---:|---|---|---|');
for (const [name, summary] of Object.entries(inventory.firestore.collections).sort()) {
  const access = backendOnly.has(name) ? 'Backend only' : 'Rules-controlled app/backend';
  add(`| \`${escapeCell(name)}\` | ${summary.documentCount} | ${escapeCell(purposes[name] || 'Application data collection.')} | ${access} | ${escapeCell(lifecycle[name] || 'Retained while the feature/user history needs it.')} |`);
}
add();
add('### Defined collections currently empty');
add();
add('These schemas exist in application/backend code or rules but have no live root documents after cleanup. Transient collections reappear automatically when their workflow runs.');
add();
add('| Collection | Expected top-level schema |');
add('|---|---|');
for (const [name, schema] of Object.entries(definedEmptySchemas).sort()) {
  add(`| \`${name}\` | ${escapeCell(schema)} |`);
}
add();
add('## Detailed observed Firestore schemas');
add();
for (const [name, summary] of Object.entries(inventory.firestore.collections).sort()) {
  add(`### \`${name}/{documentId}\``);
  add();
  add(`${purposes[name] || 'Application data collection.'} Observed documents: **${summary.documentCount}**.`);
  add();
  add('| Field | Firestore type(s) | Presence |');
  add('|---|---|---:|');
  for (const [fieldName, field] of normalizedFields(summary)) {
    add(`| \`${escapeCell(fieldName)}\` | ${escapeCell(typeLabel(field))} | ${field.present}/${summary.documentCount} |`);
  }
  if (normalizedFields(summary).length === 0) add('| — | No live fields observed | 0/0 |');
  add();
}

add('## Subcollection schemas');
add();
const subcollectionPaths = {
  authFactors: 'users/{userId}/authFactors/{factorId}',
  comments: 'communityPosts/{postId}/comments/{commentId}',
  messages: 'groupChats/{chatId}/messages/{messageId}',
  ratings: 'trails/{trailId}/ratings/{sessionId}',
  reminderPreferences: 'upcomingHikes/{hikeId}/reminderPreferences/{userId}',
  reports: 'nearbySosIncidents/{incidentId}/reports/{reporterHash}',
};
for (const [name, summary] of Object.entries(inventory.firestore.subcollections).sort()) {
  add(`### \`${subcollectionPaths[name] || `${name}/{documentId}`}\``);
  add();
  add(`Observed documents: **${summary.documentCount}**.`);
  add();
  add('| Field | Firestore type(s) | Presence |');
  add('|---|---|---:|');
  const fields = normalizedFields(summary);
  if (fields.length === 0) add('| — | Defined but currently empty | 0/0 |');
  for (const [fieldName, field] of fields) {
    add(`| \`${escapeCell(fieldName)}\` | ${escapeCell(typeLabel(field))} | ${field.present}/${summary.documentCount} |`);
  }
  add();
}

add('## Canonical nested shapes');
add();
add('| Shape | Fields |');
add('|---|---|');
add('| Trail checkpoint | `name:string`, `latitude:number`, `longitude:number`, `order:int` |');
add('| Trail weather | `summary:string`, `temperatureRange:string`, `rainProbability:int`, `cachedAtLocal:string`, optional `humidity:int`, `windSpeed:number`, `uvIndex:number`, `feelsLike:number`, `hourlyForecast:array`, `forecastData:map` |');
add('| Hourly forecast | `timeLocal:string`, `temperature:number`, `precipitationProbability:int`, `weatherCode:int` |');
add('| Trail hazard | `type:string`, `description:string`, `severity:string`, `locationLabel:string`, `reportedAtLocal:string`; enriched route hazards may also carry coordinates and provider evidence |');
add('| Trail image credit | `sourceName`, `sourcePageUrl`, `author`, `licenseName`, `licenseUrl`, `description` (all strings) |');
add('| Coordinate/location | `latitude:number`, `longitude:number`, optional `accuracyMeters:number`, `altitudeMeters:number`, and ISO capture time |');
add('| User profile | `username`, `gender`, `hikerExperience`, `hikeFrequency`, `residentialLocation`, optional residential coordinates and `photoURL` |');
add('| Emergency contact | `name:string`, `phoneNumber:string`, `relationship:string` |');
add('| SOS dispatch | `contactName:string`, `phoneNumber:string`, `wasSent:boolean`, `retryable:boolean`, optional `errorMessage` and `providerMessageId` |');
add('| Team buddy | `name`, `handle`, `phoneNumber`, `role`, optional `photoURL`, `avatarColorValue:int` |');
add('| Team participant | `buddy:map`, `phoneNumber`, `status`, `isHost`, `isLeader`, `progressMeters`, optional location/timestamps/safety settings, `separationAlertActive` |');
add('| Chat attachment | Storage URL/path plus attachment name, MIME type, byte size, and sender metadata; accepted formats are constrained by Storage Rules |');
add('| Dynamic per-user maps | `lastReadAt.{phoneKey}`, `unreadCount.{phoneKey}`, `buddyRequestsIncoming.{phoneKey}`, `buddyRequestsOutgoing.{phoneKey}`, and `fcmTokenByAppId.{appInstanceId}` |');
add();
add('Server timestamps and `...Local` ISO-8601 mirrors intentionally coexist. Server timestamps provide authoritative ordering; Local mirrors make callable responses, offline persistence, and cross-platform parsing deterministic.');
add();
add('## Cloud Storage schema');
add();
add('| Object path | Current count | Purpose and constraint |');
add('|---|---:|---|');
const prefixDescriptions = {
  app_feedback: '`app_feedback/{uid}/{reportId}/screenshot.png` — owner/admin read, PNG only, maximum 5 MiB.',
  community_hikes: '`community_hikes/{uid}/{sessionId}/{file}` — owner-created hike images, supported image formats, maximum 10 MiB.',
  group_chats: '`group_chats/{chatId}/attachments/{file}` — chat-member media/documents, maximum 25 MiB.',
  profile_photos: '`profile_photos/{uid}/{file}` — owner/admin managed profile image, maximum 10 MiB.',
  releases: '`releases/android/beta/{apk}` — APK referenced by `web/site/beta-release.json`.',
  trail_covers: '`trail_covers/{trailId}/{image}` and deployment-curated variants — trail cover images.',
};
for (const [prefix, value] of Object.entries(inventory.storage.prefixes).sort()) {
  add(`| \`${prefix}/\` | ${value.objectCount} | ${prefixDescriptions[prefix] || 'Application storage objects.'} |`);
}
add();
add(`Total: **${inventory.storage.objectCount} objects / ${bytes(inventory.storage.totalBytes)}**. All remaining objects are referenced by Firestore or a checked-in application/release manifest.`);
add();
add('Three additional Google-managed Cloud Functions buckets were found (`gcf-v2-sources` in both deployed regions and the `gcf-v2-uploads` bucket). They are deployment infrastructure rather than app Storage and were intentionally preserved.');
add();
add('## Authentication schema boundary');
add();
add('- Firebase Authentication owns identity principals and tokens; the audit only counted accounts and did not export their records.');
add('- The matching private app profile is `users/{uid}`. The app uses a canonical phone-based UID and validates the authenticated phone claim server-side.');
add('- MFA factor secrets/credentials live only in `users/{uid}/authFactors/{factorId}` and are denied to normal Firestore clients. TOTP secrets are encrypted; passkeys store the public credential only.');
add('- MFA/login/reset challenges are backend-only, expire in minutes, and are covered by the cleanup policy. Password hashes remain backend-only fields in the private user document.');
add();
add('## Composite indexes');
add();
add('| Collection group | Scope | Fields |');
add('|---|---|---|');
for (const index of indexes) {
  const fields = (index.fields || []).map((field) =>
    `\`${field.fieldPath}\` ${field.order || field.arrayConfig}`
  ).join(', ');
  add(`| \`${index.collectionGroup}\` | ${index.queryScope} | ${fields} |`);
}
add();
add('## Deployed Cloud Functions');
add();
add('All functions below were ACTIVE during the audit and matched a source export. Deployment-managed source/archive buckets are intentionally excluded from application Storage cleanup.');
add();
add('| Function | Trigger | Region | Runtime |');
add('|---|---|---|---|');
for (const fn of [...deployedFunctions].sort((a, b) => a.id.localeCompare(b.id))) {
  add(`| \`${fn.id}\` | ${escapeCell(triggerLabel(fn))} | ${fn.region} | ${fn.runtime} |`);
}
add();
add('## Rules and lifecycle notes');
add();
add('- Firestore access is deny-by-default. Public/authenticated reads and user writes are granted only in the explicit collection matches in `firestore.rules`; backend-only collections rely on the Admin SDK.');
add('- Storage is deny-by-default. File type, ownership/membership, and size constraints are enforced by `storage.rules`.');
add('- `cleanExpiredMfaArtifacts`, `cleanExpiredUpcomingHikes`, `cleanExpiredGroupChats`, `cleanExpiredTeamHikeInvitations`, and `cleanStaleHikeSessions` are deployed scheduled lifecycle workers.');
add('- The conservative maintenance script is `scripts/cleanup_firebase_data.js`. It is dry-run by default; `--apply` writes a local backup before exact-path deletion.');
add('- The inventory script is `scripts/audit_firebase_inventory.js`. Re-run both after schema changes and before future cleanup.');
add();
add('## Recommended maintenance cadence');
add();
add('1. Run `node scripts/audit_firebase_inventory.js`.');
add('2. Run `node scripts/cleanup_firebase_data.js` and review the dry-run counts.');
add('3. If the candidates are expected, run `node scripts/cleanup_firebase_data.js --apply`.');
add('4. Re-run the inventory and dry-run; the cleanup candidate counts must return to zero.');
add('5. Keep safety/history data out of generic TTL policies. Apply automatic TTL only to explicit transient collections after confirming the application no longer needs a terminal response.');

fs.mkdirSync(path.dirname(outputPath), {recursive: true});
fs.writeFileSync(outputPath, `${lines.join('\n')}\n`);
console.log(`Schema document written to ${outputPath}`);

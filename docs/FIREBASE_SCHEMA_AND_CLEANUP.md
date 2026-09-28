# HikerCircle Firebase Schema and Cleanup Audit

- Audit snapshot: **2026-09-27T17:55:27.789Z**
- Firebase project: **hiker-circle**
- Scope: Authentication, Cloud Firestore, Cloud Storage, Cloud Functions, Hosting, rules, indexes, and data lifecycle.

> This document records schema names and types only. User values, tokens, verification codes, messages, coordinates, and secrets are deliberately excluded. A field observed in fewer than all documents is optional, legacy, workflow-specific, or populated later by the backend.

## Audit result

- Cloud Functions: **80 ACTIVE deployments**, exactly matching the 80 exports in `functions/index.js`; no stale function was deleted.
- Firestore after cleanup: **42 non-empty root collections** plus documented subcollections.
- Cloud Storage after cleanup: **57 objects / 204.84 MiB**.
- Firebase Authentication: **2 accounts** were counted through the Admin API; account values were not exported.
- Firebase Hosting: one live default site, `hiker-circle` (`https://hiker-circle.web.app`).
- Hosting versions: 2 superseded versions older than 30 days were deleted; 52 finalized versions inside the 30-day rollback window were retained.
- Realtime Database: no instance. Firebase Extensions: none installed.
- Secret Manager: 3 secrets (`GREEN_API_INSTANCE_ID`, `GREEN_API_TOKEN`, `MFA_TOTP_ENCRYPTION_KEY`), all referenced by deployed Functions; none removed.
- Every remaining non-empty Firestore root collection has a repository code/rules reference.

## Cleanup performed

| Removed data | Count | Reason |
|---|---:|---|
| Terminal FCM outbox entries older than 30 days | 236 documents | Completed delivery work-state; not notification history |
| Expired/consumed WhatsApp login and password-reset challenges/sessions | 9 documents | Security artifacts beyond their 5–10 minute validity |
| Expired or inactive live-location shares | 3 documents | Links were no longer usable |
| Rate-limit counters older than their longest 24-hour window | 22 documents | Counters are recreated on demand |
| Reminder preferences beneath deleted upcoming hikes | 12 documents | Orphaned subcollection records |
| Superseded profile photos | 4 objects | No reference in Firestore or Firebase Auth |
| Superseded non-Malaysian first-aid videos | 7 objects | Replaced by the checked-in KKM media manifest |
| Orphaned generated trail covers | 3 objects | No trail or code reference |
| Superseded Hosting deployments older than 30 days | 2 versions | Not referenced by the live channel; 32,784,977 version bytes released |
| **Total** | **282 documents + 14 objects + 2 Hosting versions** | **79,939,593 storage/version bytes reclaimed** |

Recoverable pre-delete backups:

- `tmp/firebase-cleanup-backup-2026-09-13T01-34-59-600Z/`
- `tmp/firebase-cleanup-backup-2026-09-13T01-36-34-725Z/`
- `tmp/firebase-cleanup-backup-2026-09-13T01-43-06-612Z/`

The backups are ignored by Git and contain the exact deleted Firestore representations and media bytes. They may contain private application data and must not be committed or shared. The post-cleanup dry run reports zero remaining eligible records or objects.

## SOS user-document normalization

All **140** canonical `sosAlerts/{alertId}` documents were preserved. The duplicated event maps formerly embedded in `users/{uid}.latest_sos_alert` and `users/{uid}.sos_alerts` were migrated to lightweight metadata:

- `latestSosAlertPath:string` points to the newest canonical alert.
- `recentSosAlertPaths:array<string>` contains at most 30 newest canonical paths.
- `sosAlertsCount:int` is reconciled to the canonical per-user document count.
- `sosAlertReferenceVersion:int` and migration timestamps identify the normalized schema.

Encoded REST document size dropped from approximately **42 KB to 9 KB** for one account and **166 KB to 10 KB** for the other. No SOS alert document was deleted. Pre-migration backups are stored under `tmp/firebase-sos-reference-migration-*` and are Git-ignored/private.

### Explicitly retained

Hike sessions/history, raw route points, route captures, check-ins, SOS events and dispatch evidence, chats/messages, community posts, user/achievement records, trail ratings, current trail covers, feedback screenshots, the current profile photo, and the published Android beta APK were retained. These are active, user-facing, safety/audit-relevant, or still referenced.

## Firestore collection registry

| Collection | Documents | Purpose | Access | Lifecycle |
|---|---:|---|---|---|
| `achievementEventReceipts` | 56 | Idempotency receipts for achievement event processing. | Backend only | Keep while source event replay remains possible. |
| `achievements` | 24 | Server-managed achievement catalogue and reward definitions. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `activeHikeStartRateLimits` | 1 | Application data collection. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `appFeedback` | 2 | In-app feedback reports and optional screenshot references. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `assistantUsage` | 2 | Application data collection. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `checkIns` | 28 | Safety check-ins recorded during a hike session. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `communityCounterEventReceipts` | 1 | Idempotency receipts for post comment counters. | Backend only | Keep while source event replay remains possible. |
| `communityPosts` | 3 | Community hike posts, route previews, images, and engagement counters. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `downloadedMaps` | 2 | Per-user metadata for offline trail-map downloads. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `fcmOutbox` | 14 | Short-lived queue and delivery result for team-hike push notifications. | Backend only | Terminal entries: 30-day retention; pending entries retained. |
| `greenApiLoginChallenges` | 2 | Application data collection. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `groupChats` | 48 | Direct and hike-derived chat metadata and lifecycle state. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `hazardReports` | 2 | User-submitted trail hazard reports and moderation status. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `hikeCompletionRateLimits` | 1 | Application data collection. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `hikePrecautionDeliveries` | 4 | Application data collection. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `hikeRouteCaptures` | 51 | Detailed recorded route geometry and completion summary. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `hikeSessionTerminalStates` | 11 | Idempotent terminal-state markers for completion processing. | Backend only | Retained while the feature/user history needs it. |
| `hikeSessions` | 96 | Active and historical solo/group hike sessions. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `liveLocationContactDispatches` | 4 | At-most-once delivery ledger for live-location messages. | Backend only | Operational delivery evidence; retain with SOS/live-share audit. |
| `live_location_shares` | 1 | Application data collection. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `localLocationPoints` | 559 | Synced raw route/location observations used by hike history. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `maintenanceState` | 1 | Cursor and progress state for backend maintenance jobs. | Backend only | Singleton operational state; never purge while jobs use it. |
| `mfaAuthenticationChallenges` | 1 | Application data collection. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `mfaLoginSessions` | 1 | Application data collection. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `nearbySosIncidents` | 6 | Deduplicated nearby SOS incidents reported by button receivers. | Backend only | Retained while the feature/user history needs it. |
| `networkObservations` | 59 | Route network-availability observations. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `passwordResetChallenges` | 1 | Application data collection. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `passwordResetPasskeyChallenges` | 6 | Application data collection. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `passwordResetSessions` | 5 | Application data collection. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `sosAlerts` | 141 | Canonical SOS events and their contact delivery summary. | Rules-controlled app/backend | Safety history; retained. |
| `sosMessageRateLimits` | 1 | Application data collection. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `sosWhatsAppDispatches` | 61 | At-most-once WhatsApp delivery ledger for SOS messages. | Backend only | SOS delivery evidence; retained. |
| `teamHikeSessions` | 29 | Team readiness, participant state, shared plan, and active-session links. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `teams` | 1 | Saved team definition and member list. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `trailWeatherCache` | 35 | Backend weather cache and refresh lease state. | Backend only | Replace in place; safe to rebuild from provider. |
| `trails` | 35 | Trail catalogue, Mapbox route, elevation range, media, ratings, and hazards. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `upcomingHikeJoinRequests` | 2 | Join-request workflow and host notification outcome. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `upcomingHikeRateLimits` | 2 | Application data collection. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `upcomingHikes` | 3 | Application data collection. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `userAchievements` | 38 | Per-user progress and award state for each achievement. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `users` | 2 | Private account profile, safety settings, MFA summary, devices, and aggregates. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `whatsAppMessageLogs` | 49 | User-facing WhatsApp send history for SOS messaging. | Rules-controlled app/backend | User-visible message history; retained. |

### Defined collections currently empty

These schemas exist in application/backend code or rules but have no live root documents after cleanup. Transient collections reappear automatically when their workflow runs.

| Collection | Expected top-level schema |
|---|---|
| `activeHikeStartRateLimits` | windowStartedAtMillis:int, actionCount:int, updatedAt:timestamp |
| `buddyRequestRateLimits` | windowStartedAtMillis:int, requestCount:int, updatedAt:timestamp |
| `directChatActionRateLimits` | windowStartedAtMillis:int, actionCount:int, updatedAt:timestamp |
| `greenApiLoginChallenges` | phoneNumber:string, codeHash:string, intent:string, attemptsRemaining:int, consumed:boolean, expiresAtMillis:int, deliveryState:string, providerMessageId?:string, createdAt:timestamp, verifiedAt?:timestamp |
| `hikeCompletionRateLimits` | windowStartedAtMillis:int, actionCount:int, updatedAt:timestamp |
| `hikeSessionRecoveryRateLimits` | windowStartedAtMillis:int, actionCount:int, updatedAt:timestamp |
| `live_location_shares` | shareId:string, ownerUserId:string, ownerUserDocumentPath:string, phoneNumber:string, shareUrl:string, latestLocation:map, isActive:boolean, expiresAt:timestamp, createdAt:timestamp, updatedAt:timestamp plus Local ISO mirrors |
| `mfaAuthenticationChallenges` | sessionDigest:string, userId:string, webAuthnChallenge:string, attemptsRemaining:int, consumed:boolean, expiresAtMillis:int, createdAt:timestamp |
| `mfaEnrollmentChallenges` | kind:string, contextKey:string, userId:string, phoneNumber:string, encryptedSecret?:map, webAuthnChallenge?:string, attemptsRemaining:int, consumed:boolean, expiresAtMillis:int, createdAt:timestamp |
| `mfaLoginSessions` | userId:string, phoneNumber:string, whatsappChallengeId:string, whatsappVerified:boolean, enrollmentRequired:boolean, methods:array<string>, attemptsRemaining:int, consumed:boolean, expiresAtMillis:int, createdAt:timestamp, createdAtLocal:string |
| `passwordResetChallenges` | phoneNumber:string, codeHash:string, attemptsRemaining:int, consumed:boolean, expiresAtMillis:int, sentAtMillis:int, createdAt:timestamp, verifiedAt?:timestamp |
| `passwordResetSessions` | phoneNumber:string, challengeId:string, verifiedAt:timestamp, used:boolean, expiresAtMillis:int, safetyQuestionField:string, skipQuestion:boolean, attemptsRemaining:int, createdAt:timestamp |
| `sosMessageRateLimits` | windowStartedAtMillis:int, sendCount:int, updatedAt:timestamp |
| `teamHikeActionRateLimits` | windowStartedAtMillis:int, actionCount:int, updatedAt:timestamp |
| `upcomingHikeJoinRequestRateLimits` | windowStartedAtMillis:int, actionCount:int, updatedAt:timestamp |
| `upcomingHikeRateLimits` | windowStartedAtMillis:int, actionCount:int, updatedAt:timestamp |
| `upcomingHikes` | hikeId:string, creatorUserId:string, creatorPhoneNumber:string, trailId:string, trailName:string, start/destination and coordinates, departure/estimated-return times, hikeType:string, joinPolicy:string, participants/invites:array, reminder counters/status, createdAt/updatedAt timestamps plus Local ISO mirrors |

## Detailed observed Firestore schemas

### `achievementEventReceipts/{documentId}`

Idempotency receipts for achievement event processing. Observed documents: **56**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `achievementId` | string | 56/56 |
| `applied` | boolean | 56/56 |
| `createdAt` | timestamp | 56/56 |
| `createdAtLocal` | string | 56/56 |
| `eventKey` | string | 56/56 |
| `userId` | string | 56/56 |

### `achievements/{documentId}`

Server-managed achievement catalogue and reward definitions. Observed documents: **24**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `accentColorValue` | integer | 24/24 |
| `achievementId` | string | 24/24 |
| `category` | string | 24/24 |
| `condition` | string | 24/24 |
| `createdAt` | timestamp | 18/24 |
| `createdAtLocal` | string | 18/24 |
| `iconName` | string | 24/24 |
| `isActive` | boolean | 24/24 |
| `metricKey` | string | 24/24 |
| `rewardPoints` | integer | 24/24 |
| `rewardsSafeBehaviour` | boolean | 24/24 |
| `rewardType` | string | 24/24 |
| `sortOrder` | integer | 24/24 |
| `targetCount` | integer | 24/24 |
| `title` | string | 24/24 |
| `updatedAt` | timestamp | 24/24 |
| `updatedAtLocal` | string | 20/24 |

### `activeHikeStartRateLimits/{documentId}`

Application data collection. Observed documents: **1**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `actionCount` | integer | 1/1 |
| `updatedAt` | timestamp | 1/1 |
| `windowStartedAtMillis` | integer | 1/1 |

### `appFeedback/{documentId}`

In-app feedback reports and optional screenshot references. Observed documents: **2**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `category` | string | 2/2 |
| `createdAt` | timestamp | 2/2 |
| `message` | string | 2/2 |
| `platform` | string | 2/2 |
| `screenshotPath` | string | 2/2 |
| `status` | string | 2/2 |
| `uid` | string | 2/2 |

### `assistantUsage/{documentId}`

Application data collection. Observed documents: **2**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `dayBucket` | string | 2/2 |
| `dayCount` | integer | 2/2 |
| `minuteBucket` | integer | 2/2 |
| `minuteCount` | integer | 2/2 |
| `updatedAt` | string | 2/2 |

### `checkIns/{documentId}`

Safety check-ins recorded during a hike session. Observed documents: **28**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `batteryLevel` | integer | 28/28 |
| `checkInId` | string | 7/28 |
| `createdAt` | timestamp | 28/28 |
| `createdAtLocal` | string | 28/28 |
| `location` | map | 27/28 |
| `sessionId` | string | 28/28 |
| `status` | string | 28/28 |
| `trailId` | string | 28/28 |
| `userId` | string | 28/28 |
| `userPhoneNumber` | string | 28/28 |

### `communityCounterEventReceipts/{documentId}`

Idempotency receipts for post comment counters. Observed documents: **1**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `applied` | boolean | 1/1 |
| `commentId` | string | 1/1 |
| `createdAt` | timestamp | 1/1 |
| `createdAtLocal` | string | 1/1 |
| `eventType` | string | 1/1 |
| `postId` | string | 1/1 |

### `communityPosts/{documentId}`

Community hike posts, route previews, images, and engagement counters. Observed documents: **3**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `authorAchievementPoints` | integer | 3/3 |
| `authorHandle` | string | 3/3 |
| `authorId` | string | 3/3 |
| `authorLevel` | integer | 3/3 |
| `authorLevelBadge` | string | 3/3 |
| `authorLevelName` | string | 3/3 |
| `authorName` | string | 3/3 |
| `authorPhoneNumber` | string | 3/3 |
| `authorPhotoURL` | string | 1/3 |
| `caption` | string | 3/3 |
| `checkIns` | integer | 2/3 |
| `commentCount` | integer | 3/3 |
| `createdAt` | timestamp | 3/3 |
| `createdAtLocal` | string | 3/3 |
| `distanceKm` | double | 2/3 |
| `durationMinutes` | integer | 2/3 |
| `highestAltitudeMeters` | null | 2/3 |
| `imageUrls` | array | 3/3 |
| `likeCount` | integer | 3/3 |
| `manualPins` | integer | 2/3 |
| `postId` | string | 3/3 |
| `postType` | string | 3/3 |
| `routeBounds` | map | 2/3 |
| `routeCaptureId` | string | 2/3 |
| `routeEnd` | map | 2/3 |
| `routePointCount` | integer | 2/3 |
| `routePreviewPoints` | array | 2/3 |
| `routeStart` | map | 2/3 |
| `sessionId` | string | 2/3 |
| `summaryReport` | map | 2/3 |
| `thumbnailType` | string | 2/3 |
| `trailId` | string | 2/3 |
| `trailName` | string | 2/3 |
| `visibility` | string | 3/3 |

### `downloadedMaps/{documentId}`

Per-user metadata for offline trail-map downloads. Observed documents: **2**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `downloadedAt` | timestamp | 2/2 |
| `downloadedAtLocal` | string | 2/2 |
| `downloadedMapId` | string | 2/2 |
| `localFilePath` | string | 2/2 |
| `trailId` | string | 2/2 |
| `trailName` | string | 2/2 |
| `userId` | string | 2/2 |
| `userPhoneNumber` | string | 2/2 |

### `fcmOutbox/{documentId}`

Short-lived queue and delivery result for team-hike push notifications. Observed documents: **14**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `attemptCount` | integer | 14/14 |
| `createdAt` | timestamp | 14/14 |
| `createdAtLocal` | string | 14/14 |
| `data` | map | 14/14 |
| `deliveryClaimedAt` | timestamp | 14/14 |
| `deliveryClaimedAtLocal` | string | 14/14 |
| `failureCount` | integer | 7/14 |
| `processedAt` | timestamp | 14/14 |
| `processedAtLocal` | string | 14/14 |
| `recipientPhoneNumber` | string | 14/14 |
| `senderPhoneNumber` | string | 14/14 |
| `status` | string | 14/14 |
| `successCount` | integer | 7/14 |
| `teamHikeSessionId` | string | 14/14 |
| `type` | string | 14/14 |
| `updatedAt` | timestamp | 14/14 |
| `updatedAtLocal` | string | 14/14 |

### `greenApiLoginChallenges/{documentId}`

Application data collection. Observed documents: **2**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `attemptsRemaining` | integer | 2/2 |
| `consumed` | boolean | 2/2 |
| `createdAt` | timestamp | 2/2 |
| `deliveredAt` | timestamp | 2/2 |
| `deliveryState` | string | 2/2 |
| `expiresAtMillis` | integer | 2/2 |
| `intent` | string | 2/2 |
| `passwordVerified` | boolean | 2/2 |
| `phoneNumber` | string | 2/2 |
| `providerMessageId` | string | 2/2 |
| `sentAtMillis` | integer | 2/2 |
| `verifiedAt` | timestamp | 2/2 |

### `groupChats/{documentId}`

Direct and hike-derived chat metadata and lifecycle state. Observed documents: **48**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `chatRemovesAtLocal` | string | 26/48 |
| `chatType` | string | 38/48 |
| `closureNoticeSentAt` | timestamp | 4/48 |
| `closureNoticeSentAtLocal` | string | 4/48 |
| `closureReason` | string | 26/48 |
| `createdAt` | timestamp | 27/48 |
| `createdAtLocal` | string | 48/48 |
| `creatorPhone` | string | 48/48 |
| `customName` | string | 3/48 |
| `deletedAt` | timestamp | 26/48 |
| `deletedAtLocal` | string | 26/48 |
| `departureTimeLocal` | string | 27/48 |
| `hikeEndedAt` | string | 2/48 |
| `hikeEndedAtLocal` | string | 26/48 |
| `hikeSessionId` | string | 48/48 |
| `hostNamingFinalizedAt` | timestamp | 1/48 |
| `hostNamingFinalizedAtLocal` | string | 1/48 |
| `isDeleted` | boolean | 26/48 |
| `lastMessage` | string | 33/48 |
| `lastMessageAtLocal` | string | 33/48 |
| `lastMessageSenderPhone` | string | 31/48 |
| `lastReadAt.{phoneKey}` | string | 8/48 |
| `latestJoinedName` | string | 4/48 |
| `namedAt` | timestamp | 2/48 |
| `namedAtLocal` | string | 2/48 |
| `nameSource` | string | 1/48 |
| `namingPromptActive` | boolean | 2/48 |
| `namingPromptShown` | boolean | 2/48 |
| `participantNames` | map | 35/48 |
| `participantPhones` | array | 48/48 |
| `participantPhotoURLs` | map | 28/48 |
| `requiresHostNaming` | boolean | 4/48 |
| `teamFormedAtLocal` | string | 4/48 |
| `teamHikeSessionId` | string | 28/48 |
| `trailName` | string | 48/48 |
| `unreadCount` | map | 4/48 |
| `unreadCount.{phoneKey}` | integer | 8/48 |
| `updatedAt` | timestamp | 28/48 |
| `updatedAtLocal` | string | 28/48 |

### `hazardReports/{documentId}`

User-submitted trail hazard reports and moderation status. Observed documents: **2**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `adminNote` | string | 2/2 |
| `description` | string | 2/2 |
| `hazardId` | string | 2/2 |
| `hazardType` | string | 2/2 |
| `latitude` | double | 2/2 |
| `location` | map | 2/2 |
| `longitude` | double | 2/2 |
| `reportedAt` | timestamp | 2/2 |
| `reportedAtLocal` | string | 2/2 |
| `reportedBy` | string | 2/2 |
| `reportedByPhoneNumber` | string | 2/2 |
| `reportLabel` | string | 2/2 |
| `reviewedAt` | timestamp | 2/2 |
| `reviewedAtLocal` | string | 2/2 |
| `reviewedByAdminId` | string | 2/2 |
| `reviewedByAdminPhoneNumber` | string | 2/2 |
| `severity` | string | 2/2 |
| `status` | string | 2/2 |
| `trailId` | string | 2/2 |
| `trailName` | string | 2/2 |

### `hikeCompletionRateLimits/{documentId}`

Application data collection. Observed documents: **1**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `actionCount` | integer | 1/1 |
| `updatedAt` | timestamp | 1/1 |
| `windowStartedAtMillis` | integer | 1/1 |

### `hikePrecautionDeliveries/{documentId}`

Application data collection. Observed documents: **4**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `leaseUntil` | integer | 4/4 |
| `sent` | map | 2/4 |
| `sentAt` | string | 2/4 |

### `hikeRouteCaptures/{documentId}`

Detailed recorded route geometry and completion summary. Observed documents: **51**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `anonymousRecommendationEligible` | boolean | 51/51 |
| `captureType` | string | 51/51 |
| `communityPostId` | string | 13/51 |
| `createdAt` | timestamp | 51/51 |
| `createdAtLocal` | string | 51/51 |
| `manualPinCount` | integer | 11/51 |
| `manualPins` | array | 51/51 |
| `manualPinsDownsampled` | boolean | 11/51 |
| `routeBounds` | map | 49/51 |
| `routeEnd` | map | 49/51 |
| `routePointCount` | integer | 50/51 |
| `routePoints` | array | 51/51 |
| `routePointsDownsampled` | boolean | 11/51 |
| `routeStart` | map | 49/51 |
| `sessionId` | string | 51/51 |
| `storedManualPinCount` | integer | 11/51 |
| `storedRoutePointCount` | integer | 11/51 |
| `summaryReport` | map | 51/51 |
| `trailId` | string | 51/51 |
| `trailName` | string | 51/51 |
| `updatedAt` | timestamp | 50/51 |
| `updatedAtLocal` | string | 50/51 |
| `userId` | string | 51/51 |
| `userPhoneNumber` | string | 51/51 |

### `hikeSessionTerminalStates/{documentId}`

Idempotent terminal-state markers for completion processing. Observed documents: **11**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `recordedAt` | timestamp | 11/11 |
| `recordedAtLocal` | string | 11/11 |
| `sessionId` | string | 11/11 |
| `status` | string | 11/11 |
| `userId` | string | 11/11 |
| `userPhoneNumber` | string | 11/11 |

### `hikeSessions/{documentId}`

Active and historical solo/group hike sessions. Observed documents: **96**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `checkIns` | integer | 57/96 |
| `checkpoints` | array | 66/96 |
| `completedChecklistItems` | array | 96/96 |
| `createdAt` | timestamp | 11/96 |
| `createdAtLocal` | string | 11/96 |
| `destinationName` | string | 96/96 |
| `distanceKm` | double \| integer | 57/96 |
| `durationMinutes` | integer | 57/96 |
| `duressEnabled` | boolean | 96/96 |
| `emergencyContactNames` | array | 96/96 |
| `endedAt` | timestamp | 67/96 |
| `endedAtLocal` | string | 67/96 |
| `expectedArrivalTimeLocal` | string | 96/96 |
| `expectedReturnTimeLocal` | string | 96/96 |
| `fallDetectionEnabled` | boolean | 96/96 |
| `fallDetectionLongestRestDurationSeconds` | integer | 32/96 |
| `fallDetectionResponseDurationSeconds` | integer | 32/96 |
| `fallDetectionSensorSensitivity` | double \| integer | 95/96 |
| `fallDetectionStillnessDurationSeconds` | integer | 95/96 |
| `hikeType` | string | 96/96 |
| `lastCheckInAt` | timestamp | 15/96 |
| `lastCheckInAtLocal` | string | 15/96 |
| `lastCheckInStatus` | string | 15/96 |
| `lastMonitoringReminderAt` | timestamp | 2/96 |
| `lastMonitoringReminderAtLocal` | string | 2/96 |
| `lastMonitoringReminderClaimedAt` | timestamp | 1/96 |
| `lastMonitoringReminderClaimedAtLocal` | string | 1/96 |
| `lastMonitoringReminderDeliveryStatus` | string | 1/96 |
| `lastMonitoringReminderReason` | string | 2/96 |
| `lastPathDeviation` | map | 3/96 |
| `lastPathDeviationAt` | timestamp | 3/96 |
| `lastPathDeviationAtLocal` | string | 3/96 |
| `lastScheduledCheckInReminderAt` | timestamp | 1/96 |
| `lastScheduledCheckInReminderAtLocal` | string | 1/96 |
| `lastScheduledCheckInReminderClaimedAt` | timestamp | 1/96 |
| `lastScheduledCheckInReminderClaimedAtLocal` | string | 1/96 |
| `lastScheduledCheckInReminderDeliveryStatus` | string | 1/96 |
| `latestLocation` | map | 93/96 |
| `latestLocationUpdatedAt` | timestamp | 93/96 |
| `latestLocationUpdatedAtLocal` | string | 93/96 |
| `latestMotion` | map | 7/96 |
| `latestMotionUpdatedAt` | timestamp | 7/96 |
| `latestMotionUpdatedAtLocal` | string | 7/96 |
| `liveLocationShareId` | string | 4/96 |
| `liveLocationShareLinkedAt` | timestamp | 4/96 |
| `liveLocationShareLinkedAtLocal` | string | 4/96 |
| `locationRecordingIntervalMinutes` | integer | 96/96 |
| `locationRecordingIntervalSeconds` | integer | 74/96 |
| `manualPins` | integer | 57/96 |
| `monitoringExpected` | boolean | 57/96 |
| `monitoringFcmToken` | string | 16/96 |
| `monitoringHeartbeatAt` | timestamp | 31/96 |
| `monitoringHeartbeatAtLocal` | string | 31/96 |
| `monitoringLifecycleState` | string | 57/96 |
| `offlinePhysicalAlertEnabled` | boolean | 96/96 |
| `pathDeviationAlertCount` | integer | 3/96 |
| `pathDeviationEnabled` | boolean | 96/96 |
| `plannedStartTimeLocal` | string | 96/96 |
| `routePointCount` | integer | 57/96 |
| `safetyCheckInIntervalMinutes` | integer | 96/96 |
| `safetyCheckInIntervalSeconds` | integer | 11/96 |
| `sessionId` | string | 96/96 |
| `shareLiveLocation` | boolean | 96/96 |
| `sourceUpcomingHikeId` | string | 6/96 |
| `startedAt` | timestamp | 96/96 |
| `startedAtLocal` | string | 96/96 |
| `startPointName` | string | 96/96 |
| `status` | string | 96/96 |
| `summaryReport` | map | 57/96 |
| `teamBuddies` | array | 70/96 |
| `teamHikeSessionId` | string | 12/96 |
| `trail` | map | 96/96 |
| `trailId` | string | 96/96 |
| `trailName` | string | 96/96 |
| `updatedAt` | timestamp | 96/96 |
| `updatedAtLocal` | string | 96/96 |
| `userId` | string | 96/96 |
| `userPhoneNumber` | string | 96/96 |

### `liveLocationContactDispatches/{documentId}`

At-most-once delivery ledger for live-location messages. Observed documents: **4**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `attemptCount` | integer | 4/4 |
| `attemptNonce` | string | 4/4 |
| `createdAt` | timestamp | 4/4 |
| `createdAtLocal` | string | 4/4 |
| `deliveryUncertain` | boolean | 4/4 |
| `leaseExpiresAtMillis` | integer | 4/4 |
| `messageType` | string | 4/4 |
| `outboundStartedAt` | timestamp | 4/4 |
| `outboundStartedAtLocal` | string | 4/4 |
| `ownerUid` | string | 4/4 |
| `providerMessageId` | string | 4/4 |
| `recipientPhoneNumber` | string | 4/4 |
| `retryable` | boolean | 4/4 |
| `senderPhoneNumber` | string | 4/4 |
| `sentAt` | timestamp | 4/4 |
| `sentAtLocal` | string | 4/4 |
| `sessionId` | string | 4/4 |
| `status` | string | 4/4 |
| `updatedAt` | timestamp | 4/4 |
| `updatedAtLocal` | string | 4/4 |

### `live_location_shares/{documentId}`

Application data collection. Observed documents: **1**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `createdAt` | timestamp | 1/1 |
| `createdAtLocal` | string | 1/1 |
| `expiresAt` | timestamp | 1/1 |
| `expiresAtLocal` | string | 1/1 |
| `isActive` | boolean | 1/1 |
| `latestLocation` | map | 1/1 |
| `ownerUserDocumentPath` | string | 1/1 |
| `ownerUserId` | string | 1/1 |
| `phoneNumber` | string | 1/1 |
| `shareId` | string | 1/1 |
| `shareUrl` | string | 1/1 |
| `updatedAt` | timestamp | 1/1 |
| `updatedAtLocal` | string | 1/1 |

### `localLocationPoints/{documentId}`

Synced raw route/location observations used by hike history. Observed documents: **559**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `accuracyMeters` | double | 559/559 |
| `batteryLevel` | integer | 559/559 |
| `isSynced` | boolean | 559/559 |
| `latitude` | double | 559/559 |
| `longitude` | double | 559/559 |
| `pointType` | string | 559/559 |
| `recordedAt` | timestamp | 245/559 |
| `recordedAtLocal` | string | 559/559 |
| `sessionId` | string | 559/559 |
| `trailId` | string | 559/559 |
| `userId` | string | 559/559 |
| `userPhoneNumber` | string | 559/559 |

### `maintenanceState/{documentId}`

Cursor and progress state for backend maintenance jobs. Observed documents: **1**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `lastRunDocumentWriteCount` | integer | 1/1 |
| `lastRunScannedCount` | integer | 1/1 |
| `migrationVersion` | integer | 1/1 |
| `teamComplete` | boolean | 1/1 |
| `teamCursor` | string | 1/1 |
| `upcomingComplete` | boolean | 1/1 |
| `upcomingCursor` | string | 1/1 |
| `updatedAt` | timestamp | 1/1 |
| `updatedAtLocal` | string | 1/1 |

### `mfaAuthenticationChallenges/{documentId}`

Application data collection. Observed documents: **1**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `attemptsRemaining` | integer | 1/1 |
| `consumed` | boolean | 1/1 |
| `consumedAt` | timestamp | 1/1 |
| `createdAt` | timestamp | 1/1 |
| `expiresAtMillis` | integer | 1/1 |
| `sessionDigest` | string | 1/1 |
| `userId` | string | 1/1 |

### `mfaLoginSessions/{documentId}`

Application data collection. Observed documents: **1**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `attemptsRemaining` | integer | 1/1 |
| `completedMethod` | string | 1/1 |
| `consumed` | boolean | 1/1 |
| `consumedAt` | timestamp | 1/1 |
| `createdAt` | timestamp | 1/1 |
| `createdAtLocal` | string | 1/1 |
| `enrollmentRequired` | boolean | 1/1 |
| `expiresAtMillis` | integer | 1/1 |
| `loginIntent` | string | 1/1 |
| `methods` | array | 1/1 |
| `passwordVerified` | boolean | 1/1 |
| `phoneNumber` | string | 1/1 |
| `userId` | string | 1/1 |
| `whatsappChallengeId` | string | 1/1 |
| `whatsappVerified` | boolean | 1/1 |

### `nearbySosIncidents/{documentId}`

Deduplicated nearby SOS incidents reported by button receivers. Observed documents: **6**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `accuracyMeters` | double \| integer | 6/6 |
| `counter` | integer | 6/6 |
| `deviceIdHash` | string | 6/6 |
| `firstReceivedAtLocal` | string | 6/6 |
| `incidentId` | string | 6/6 |
| `lastReceivedAtLocal` | string | 6/6 |
| `latitude` | double | 6/6 |
| `locationSource` | string | 6/6 |
| `longitude` | double | 6/6 |
| `reporterCount` | integer | 6/6 |
| `status` | string | 6/6 |
| `updatedAt` | timestamp | 6/6 |
| `updatedAtLocal` | string | 6/6 |
| `verificationState` | string | 6/6 |

### `networkObservations/{documentId}`

Route network-availability observations. Observed documents: **59**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `apiRequestSuccess` | boolean | 59/59 |
| `gpsAccuracy` | double | 59/59 |
| `latitude` | double | 59/59 |
| `longitude` | double | 59/59 |
| `networkType` | string | 59/59 |
| `recordedAt` | timestamp | 59/59 |
| `recordedAtLocal` | string | 59/59 |
| `sessionId` | string | 59/59 |
| `trailId` | string | 59/59 |
| `userId` | string | 59/59 |

### `passwordResetChallenges/{documentId}`

Application data collection. Observed documents: **1**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `attemptsRemaining` | integer | 1/1 |
| `consumed` | boolean | 1/1 |
| `createdAt` | timestamp | 1/1 |
| `deliveredAt` | timestamp | 1/1 |
| `deliveryState` | string | 1/1 |
| `expiresAtMillis` | integer | 1/1 |
| `phoneNumber` | string | 1/1 |
| `providerMessageId` | string | 1/1 |
| `sentAtMillis` | integer | 1/1 |
| `verifiedAt` | timestamp | 1/1 |

### `passwordResetPasskeyChallenges/{documentId}`

Application data collection. Observed documents: **6**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `attemptsRemaining` | integer | 6/6 |
| `consumed` | boolean | 6/6 |
| `consumedAt` | timestamp | 3/6 |
| `createdAt` | timestamp | 6/6 |
| `expiresAtMillis` | integer | 6/6 |
| `sessionDigest` | string | 6/6 |
| `userId` | string | 6/6 |
| `webAuthnChallenge` | string | 3/6 |

### `passwordResetSessions/{documentId}`

Application data collection. Observed documents: **5**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `attemptsRemaining` | integer | 5/5 |
| `challengeId` | string | 5/5 |
| `createdAt` | timestamp | 5/5 |
| `expiresAtMillis` | integer | 5/5 |
| `phoneNumber` | string | 5/5 |
| `recoveryMethod` | string | 3/5 |
| `recoveryMethods` | array | 4/5 |
| `recoveryVerified` | boolean | 4/5 |
| `recoveryVerifiedAt` | timestamp | 3/5 |
| `safetyQuestionField` | string | 5/5 |
| `skipQuestion` | boolean | 5/5 |
| `used` | boolean | 5/5 |
| `verifiedAt` | timestamp | 5/5 |

### `sosAlerts/{documentId}`

Canonical SOS events and their contact delivery summary. Observed documents: **141**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `cloudLogPath` | string | 141/141 |
| `contactCount` | integer | 141/141 |
| `dispatches` | array | 141/141 |
| `failedCount` | integer | 141/141 |
| `id` | string | 141/141 |
| `message` | string | 141/141 |
| `mode` | string | 141/141 |
| `phoneNumber` | string | 141/141 |
| `sentCount` | integer | 141/141 |
| `status` | string | 141/141 |
| `triggeredAtLocal` | string | 141/141 |
| `triggeredByPhoneNumber` | string | 141/141 |
| `triggerLocation` | map | 127/141 |
| `triggerSource` | string | 43/141 |
| `updatedAt` | timestamp | 141/141 |
| `userId` | string | 141/141 |

### `sosMessageRateLimits/{documentId}`

Application data collection. Observed documents: **1**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `sendCount` | integer | 1/1 |
| `updatedAt` | timestamp | 1/1 |
| `windowStartedAtMillis` | integer | 1/1 |

### `sosWhatsAppDispatches/{documentId}`

At-most-once WhatsApp delivery ledger for SOS messages. Observed documents: **61**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `attemptCount` | integer | 61/61 |
| `attemptNonce` | string | 61/61 |
| `createdAt` | timestamp | 61/61 |
| `createdAtLocal` | string | 61/61 |
| `deliveryUncertain` | boolean | 61/61 |
| `dispatchId` | string | 61/61 |
| `isTest` | boolean | 61/61 |
| `leaseExpiresAtMillis` | integer | 61/61 |
| `messageType` | string | 61/61 |
| `mode` | string | 61/61 |
| `outboundStartedAt` | timestamp | 61/61 |
| `outboundStartedAtLocal` | string | 61/61 |
| `ownerUid` | string | 61/61 |
| `payloadHash` | string | 61/61 |
| `preferredTimeZone` | string | 43/61 |
| `providerMessageId` | string | 61/61 |
| `recipientPhoneNumber` | string | 61/61 |
| `retryable` | boolean | 61/61 |
| `senderPhoneNumber` | string | 61/61 |
| `sentAt` | timestamp | 61/61 |
| `sentAtLocal` | string | 61/61 |
| `sourceId` | string | 61/61 |
| `status` | string | 61/61 |
| `triggeredAtMillis` | integer | 61/61 |
| `triggerSource` | string | 43/61 |
| `updatedAt` | timestamp | 61/61 |
| `updatedAtLocal` | string | 61/61 |
| `wasSent` | boolean | 61/61 |

### `teamHikeSessions/{documentId}`

Team readiness, participant state, shared plan, and active-session links. Observed documents: **29**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `activeHikeSessionId` | string | 29/29 |
| `activeHikeSessionIdsByPhone` | map | 7/29 |
| `completedAt` | timestamp | 3/29 |
| `completedAtLocal` | string | 3/29 |
| `completionReason` | string | 22/29 |
| `countdownSeconds` | integer | 29/29 |
| `countdownStartedAtLocal` | string | 7/29 |
| `createdAt` | timestamp | 29/29 |
| `createdAtLocal` | string | 29/29 |
| `creationKeyHash` | string | 2/29 |
| `destinationName` | string | 29/29 |
| `draft` | map | 2/29 |
| `endedAtLocal` | string | 22/29 |
| `expectedArrivalTimeLocal` | string | 29/29 |
| `expectedReturnTimeLocal` | string | 29/29 |
| `hostPhoneNumber` | string | 29/29 |
| `hostUserId` | string | 29/29 |
| `lastPathDeviation` | map | 1/29 |
| `lastPathDeviationAtLocal` | string | 1/29 |
| `participantPhoneNumbers` | array | 24/29 |
| `participants` | array | 29/29 |
| `phase` | string | 29/29 |
| `plannedStartTimeLocal` | string | 29/29 |
| `sharedHikePlanPrivacyVersion` | integer | 29/29 |
| `sharedHikePlanRedactedAt` | timestamp | 27/29 |
| `sharedHikePlanRedactedAtLocal` | string | 27/29 |
| `sourceUpcomingHikeId` | string | 2/29 |
| `startedAtLocal` | string | 7/29 |
| `startPointName` | string | 29/29 |
| `teamHikeSessionId` | string | 29/29 |
| `trailId` | string | 29/29 |
| `trailName` | string | 29/29 |
| `updatedAt` | timestamp | 29/29 |
| `updatedAtLocal` | string | 29/29 |

### `teams/{documentId}`

Saved team definition and member list. Observed documents: **1**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `createdAt` | timestamp | 1/1 |
| `createdAtLocal` | string | 1/1 |
| `expectedReturnTimeLocal` | string | 1/1 |
| `leaderId` | string | 1/1 |
| `leaderPhoneNumber` | string | 1/1 |
| `memberIds` | array | 1/1 |
| `plannedStartTimeLocal` | string | 1/1 |
| `safetyFeatures` | map | 1/1 |
| `status` | string | 1/1 |
| `teamId` | string | 1/1 |
| `teamName` | string | 1/1 |
| `trailId` | string | 1/1 |
| `trailName` | string | 1/1 |

### `trailWeatherCache/{documentId}`

Backend weather cache and refresh lease state. Observed documents: **35**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `leaseUntilMs` | integer | 35/35 |
| `retryAfterMs` | integer | 35/35 |
| `updatedAtMs` | integer | 35/35 |
| `weather` | map | 35/35 |

### `trails/{documentId}`

Trail catalogue, Mapbox route, elevation range, media, ratings, and hazards. Observed documents: **35**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `area` | string | 35/35 |
| `checkpoints` | array | 35/35 |
| `country` | string | 35/35 |
| `coverColorValue` | integer | 35/35 |
| `coverImageCredits` | array | 34/35 |
| `coverImageCurationVersion` | integer | 33/35 |
| `coverImageUpdatedAtLocal` | string | 33/35 |
| `coverImageUrl` | array | 35/35 |
| `createdAt` | timestamp | 15/35 |
| `createdAtLocal` | string | 35/35 |
| `createdByAdminId` | string | 15/35 |
| `createdByAdminPhoneNumber` | string | 15/35 |
| `dataSource` | string | 35/35 |
| `difficulty` | string | 24/35 |
| `difficultyRatingCount` | integer | 12/35 |
| `difficultyScoreAverage` | integer | 1/35 |
| `difficultyUpdatedAt` | timestamp | 1/35 |
| `difficultyUpdatedAtLocal` | string | 1/35 |
| `difficultyVoteCounts` | map | 12/35 |
| `distanceKm` | double \| integer | 35/35 |
| `elevationGainMeters` | integer | 35/35 |
| `estimatedDurationMinutes` | integer | 35/35 |
| `hazards` | array | 35/35 |
| `isVerifiedTrail` | boolean | 35/35 |
| `latitude` | double | 35/35 |
| `longitude` | double | 35/35 |
| `maxElevationMeters` | integer | 35/35 |
| `minElevationMeters` | integer | 35/35 |
| `name` | string | 35/35 |
| `offlineMapAvailable` | boolean | 35/35 |
| `offlineMapDownloaded` | boolean | 35/35 |
| `ratingAverage` | double \| integer | 35/35 |
| `ratingCount` | integer | 35/35 |
| `ratingSum` | double \| integer | 35/35 |
| `ratingUpdatedAt` | timestamp | 2/35 |
| `ratingUpdatedAtLocal` | string | 2/35 |
| `routeActivity` | string | 32/35 |
| `routeCheckpointsHash` | string | 4/35 |
| `routeEncodedPolyline` | string | 35/35 |
| `routeFilePath` | string | 35/35 |
| `routeGeometryMetadata` | map | 35/35 |
| `routeProvider` | string | 35/35 |
| `routeShape` | string | 32/35 |
| `seededAtLocal` | string | 20/35 |
| `state` | string | 35/35 |
| `trailId` | string | 35/35 |
| `updatedAt` | timestamp | 15/35 |
| `updatedAtLocal` | string | 35/35 |
| `updatedByAdminId` | string | 4/35 |
| `updatedByAdminPhoneNumber` | string | 4/35 |
| `weather` | map | 35/35 |

### `upcomingHikeJoinRequests/{documentId}`

Join-request workflow and host notification outcome. Observed documents: **2**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `createdAt` | timestamp | 2/2 |
| `createdAtLocal` | string | 2/2 |
| `departureTimeLocal` | string | 2/2 |
| `hikeId` | string | 2/2 |
| `hostFcmFailureCount` | integer | 2/2 |
| `hostFcmStatus` | string | 2/2 |
| `hostFcmSuccessCount` | integer | 2/2 |
| `hostNotificationDeliveryClaimedAt` | timestamp | 2/2 |
| `hostNotificationDeliveryClaimedAtLocal` | string | 2/2 |
| `hostNotificationProcessedAt` | timestamp | 2/2 |
| `hostNotificationProcessedAtLocal` | string | 2/2 |
| `hostNotificationStatus` | string | 2/2 |
| `hostPhone` | string | 2/2 |
| `hostWhatsAppMessageId` | string | 2/2 |
| `hostWhatsAppStatus` | string | 2/2 |
| `requesterName` | string | 2/2 |
| `requesterPhone` | string | 2/2 |
| `requesterPhotoURL` | string | 2/2 |
| `requesterUserId` | string | 2/2 |
| `requestId` | string | 2/2 |
| `resolvedAt` | timestamp | 2/2 |
| `resolvedAtLocal` | string | 2/2 |
| `resolvedByPhone` | string | 2/2 |
| `status` | string | 2/2 |
| `trailName` | string | 2/2 |
| `updatedAt` | timestamp | 2/2 |
| `updatedAtLocal` | string | 2/2 |

### `upcomingHikeRateLimits/{documentId}`

Application data collection. Observed documents: **2**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `actionCount` | integer | 2/2 |
| `updatedAt` | timestamp | 2/2 |
| `windowStartedAtMillis` | integer | 2/2 |

### `upcomingHikes/{documentId}`

Application data collection. Observed documents: **3**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `area` | string | 3/3 |
| `country` | string | 3/3 |
| `createdAt` | timestamp | 3/3 |
| `createdAtLocal` | string | 3/3 |
| `creationKeyHash` | string | 3/3 |
| `creatorName` | string | 3/3 |
| `creatorPhone` | string | 3/3 |
| `creatorUserId` | string | 3/3 |
| `deletedAt` | timestamp | 2/3 |
| `deletedAtLocal` | string | 2/3 |
| `deletedReason` | string | 2/3 |
| `departureTimeLocal` | string | 3/3 |
| `destinationName` | string | 3/3 |
| `difficulty` | string | 3/3 |
| `distanceKm` | double | 3/3 |
| `draft` | map | 3/3 |
| `durationMinutes` | integer | 3/3 |
| `expectedArrivalTimeLocal` | string | 3/3 |
| `expectedReturnTimeLocal` | string | 3/3 |
| `expired` | boolean | 2/3 |
| `expiredAt` | timestamp | 2/3 |
| `expiredAtLocal` | string | 2/3 |
| `hikeType` | string | 3/3 |
| `isDeleted` | boolean | 2/3 |
| `joinPolicy` | string | 3/3 |
| `latitude` | double | 3/3 |
| `longitude` | double | 3/3 |
| `nearbyNotificationDeliveryClaimedAt` | timestamp | 3/3 |
| `nearbyNotificationDeliveryClaimedAtLocal` | string | 3/3 |
| `nearbyNotificationDeliveryStatus` | string | 3/3 |
| `nearbyNotificationEligibleUsers` | integer | 3/3 |
| `nearbyNotificationFailureCount` | integer | 3/3 |
| `nearbyNotificationRadiusKm` | integer | 3/3 |
| `nearbyNotificationSentAt` | timestamp | 3/3 |
| `nearbyNotificationSentAtLocal` | string | 3/3 |
| `nearbyNotificationSuccessCount` | integer | 3/3 |
| `nearbyNotificationTokenCount` | integer | 3/3 |
| `notificationRadiusKm` | integer | 3/3 |
| `participantCount` | integer | 3/3 |
| `participantPhones` | array | 3/3 |
| `sessionId` | string | 3/3 |
| `sharedHikePlanPrivacyVersion` | integer | 3/3 |
| `startPointName` | string | 3/3 |
| `state` | string | 3/3 |
| `trailId` | string | 3/3 |
| `trailName` | string | 3/3 |
| `updatedAt` | timestamp | 3/3 |
| `updatedAtLocal` | string | 3/3 |

### `userAchievements/{documentId}`

Per-user progress and award state for each achievement. Observed documents: **38**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `achievementId` | string | 38/38 |
| `achievementTitle` | string | 38/38 |
| `awardedAt` | timestamp | 21/38 |
| `awardedAtLocal` | string | 21/38 |
| `condition` | string | 6/38 |
| `isUnlocked` | boolean | 38/38 |
| `metricKey` | string | 38/38 |
| `pointsAwarded` | integer | 17/38 |
| `progressCount` | integer | 38/38 |
| `rewardType` | string | 38/38 |
| `targetCount` | integer | 38/38 |
| `updatedAt` | timestamp | 38/38 |
| `updatedAtLocal` | string | 38/38 |
| `userAchievementId` | string | 38/38 |
| `userId` | string | 38/38 |

### `users/{documentId}`

Private account profile, safety settings, MFA summary, devices, and aggregates. Observed documents: **2**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `achievementCatalogSyncedAt` | timestamp | 2/2 |
| `achievementCatalogSyncedAtLocal` | string | 2/2 |
| `achievementCatalogSyncVersion` | integer | 2/2 |
| `achievementPoints` | integer | 2/2 |
| `achievementSummaryUpdatedAt` | timestamp | 2/2 |
| `achievementSummaryUpdatedAtLocal` | string | 2/2 |
| `activeFcmAppInstanceId` | string | 2/2 |
| `activeFcmToken` | string | 2/2 |
| `autoShareLiveLocationOnHikeStart` | boolean | 1/2 |
| `autoShareLiveLocationPreferenceUpdatedAt` | timestamp | 1/2 |
| `autoShareLiveLocationPreferenceUpdatedAtLocal` | string | 1/2 |
| `boundAppInstanceId` | string | 2/2 |
| `boundAppInstanceUpdatedAt` | timestamp | 2/2 |
| `boundAppInstanceUpdatedAtLocal` | string | 2/2 |
| `buddyRequestsIncoming` | map | 1/2 |
| `buddyRequestsOutgoing` | map | 1/2 |
| `buddyRequestsUpdatedAt` | timestamp | 2/2 |
| `createdAt` | timestamp | 2/2 |
| `createdAtLocal` | string | 2/2 |
| `currentAppId` | string | 2/2 |
| `deviceRebindVerifiedBy` | string | 2/2 |
| `deviceReboundAt` | timestamp | 2/2 |
| `deviceReboundAtLocal` | string | 2/2 |
| `fcmTokenByAppId` | map | 2/2 |
| `fcmTokens` | array | 2/2 |
| `firebaseUid` | string | 2/2 |
| `hikerLevel` | integer | 2/2 |
| `hikerLevelBadge` | string | 2/2 |
| `hikerLevelName` | string | 2/2 |
| `isAdmin` | boolean | 1/2 |
| `lastFcmToken` | string | 2/2 |
| `lastFcmTokenUpdatedAt` | timestamp | 2/2 |
| `lastFcmTokenUpdatedAtLocal` | string | 2/2 |
| `lastFirebaseAuthenticatedAt` | timestamp | 2/2 |
| `lastFirebaseAuthenticatedAtLocal` | string | 2/2 |
| `lastMfaAt` | timestamp | 2/2 |
| `lastMfaAtLocal` | string | 2/2 |
| `lastPasswordVerifiedAt` | timestamp | 2/2 |
| `lastPasswordVerifiedAtLocal` | string | 2/2 |
| `lastSignedInAppInstanceId` | string | 2/2 |
| `lastSignedInAt` | timestamp | 2/2 |
| `lastSignedInAtLocal` | string | 2/2 |
| `latest_sos_messaging_test` | map | 1/2 |
| `latestSosAlertPath` | string | 2/2 |
| `liveLocation` | map | 2/2 |
| `liveLocationEnabled` | boolean | 2/2 |
| `liveLocationExpiresAt` | timestamp | 2/2 |
| `liveLocationExpiresAtLocal` | string | 2/2 |
| `liveLocationShareId` | string | 2/2 |
| `liveLocationShareUrl` | string | 2/2 |
| `liveLocationUpdatedAt` | timestamp | 2/2 |
| `liveLocationUpdatedAtLocal` | string | 2/2 |
| `loginFailedAttempts` | integer | 2/2 |
| `mfaFactorCount` | integer | 2/2 |
| `mfaMethods` | array | 2/2 |
| `mfaRequired` | boolean | 2/2 |
| `mfaUpdatedAt` | timestamp | 2/2 |
| `mfaUpdatedAtLocal` | string | 2/2 |
| `onboardingCompletedAt` | timestamp | 2/2 |
| `onboardingCompletedAtLocal` | string | 2/2 |
| `onboardingVersion` | integer | 2/2 |
| `passwordHash` | string | 2/2 |
| `phoneNumber` | string | 2/2 |
| `photoURL` | string | 1/2 |
| `preferredTimeZone` | string | 2/2 |
| `preferredTimeZoneUpdatedAt` | timestamp | 2/2 |
| `preferredTimeZoneUpdatedAtLocal` | string | 2/2 |
| `previousBoundAppInstanceId` | string | 2/2 |
| `profile` | map | 2/2 |
| `profileSetupCompleted` | boolean | 2/2 |
| `profileUpdatedAt` | timestamp | 2/2 |
| `profileUpdatedAtLocal` | string | 2/2 |
| `recentSosAlertPaths` | array | 2/2 |
| `requiresOnboarding` | boolean | 2/2 |
| `safetyQuestions` | map | 2/2 |
| `sos_contacts` | array | 2/2 |
| `sosAlertReferencesMigratedAt` | timestamp | 2/2 |
| `sosAlertReferencesMigratedAtLocal` | string | 2/2 |
| `sosAlertReferenceVersion` | integer | 2/2 |
| `sosAlertsCount` | integer | 2/2 |
| `sosAlertsUpdatedAt` | timestamp | 2/2 |
| `sosAlertsUpdatedAtLocal` | string | 2/2 |
| `sosContactsCount` | integer | 2/2 |
| `sosContactsUpdatedAt` | timestamp | 2/2 |
| `sosContactsUpdatedAtLocal` | string | 2/2 |
| `sosMessagingTestUpdatedAt` | timestamp | 1/2 |
| `sosMessagingTestUpdatedAtLocal` | string | 1/2 |
| `teamSafetyPreferences` | map | 2/2 |
| `teamSafetyPreferencesUpdatedAt` | timestamp | 2/2 |
| `teamSafetyPreferencesUpdatedAtLocal` | string | 2/2 |
| `username` | string | 2/2 |

### `whatsAppMessageLogs/{documentId}`

User-facing WhatsApp send history for SOS messaging. Observed documents: **49**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `contactName` | string | 49/49 |
| `errorMessage` | string | 7/49 |
| `message` | string | 49/49 |
| `messageLogId` | string | 49/49 |
| `messageType` | string | 49/49 |
| `mode` | string | 49/49 |
| `recipientPhoneNumber` | string | 49/49 |
| `senderPhoneNumber` | string | 49/49 |
| `sentAt` | timestamp | 49/49 |
| `sentAtLocal` | string | 49/49 |
| `sourceId` | string | 49/49 |
| `userId` | string | 49/49 |
| `wasSent` | boolean | 49/49 |

## Subcollection schemas

### `users/{userId}/authFactors/{factorId}`

Observed documents: **3**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `aaguid` | string | 1/3 |
| `algorithm` | string | 2/3 |
| `counter` | integer | 1/3 |
| `createdAt` | timestamp | 3/3 |
| `createdAtLocal` | string | 3/3 |
| `credentialBackedUp` | boolean | 1/3 |
| `credentialDeviceType` | string | 1/3 |
| `credentialId` | string | 1/3 |
| `digits` | integer | 2/3 |
| `enabled` | boolean | 3/3 |
| `encryptedSecret` | map | 2/3 |
| `label` | string | 3/3 |
| `lastUsedAt` | timestamp | 3/3 |
| `lastUsedStep` | integer | 2/3 |
| `periodSeconds` | integer | 2/3 |
| `publicKey` | string | 1/3 |
| `transports` | array | 1/3 |
| `type` | string | 3/3 |
| `updatedAt` | timestamp | 3/3 |
| `updatedAtLocal` | string | 3/3 |

### `communityPosts/{postId}/comments/{commentId}`

Observed documents: **0**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| — | Defined but currently empty | 0/0 |

### `groupChats/{chatId}/messages/{messageId}`

Observed documents: **148**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `attachment` | map | 1/148 |
| `chatId` | string | 148/148 |
| `isSystemMessage` | boolean | 148/148 |
| `notificationDeliveryClaimedAt` | timestamp | 1/148 |
| `notificationDeliveryClaimedAtLocal` | string | 1/148 |
| `notificationDeliveryStatus` | string | 1/148 |
| `notificationEligibleUsers` | integer | 66/148 |
| `notificationFailureCount` | integer | 66/148 |
| `notificationProcessedAt` | timestamp | 66/148 |
| `notificationProcessedAtLocal` | string | 66/148 |
| `notificationSuccessCount` | integer | 66/148 |
| `notificationTokenCount` | integer | 66/148 |
| `seenBy` | array | 148/148 |
| `senderName` | string | 148/148 |
| `senderPhone` | string | 148/148 |
| `senderPhotoURL` | string | 1/148 |
| `sentAtLocal` | string | 148/148 |
| `text` | string | 148/148 |
| `unreadProcessedAt` | timestamp | 1/148 |
| `unreadProcessedAtLocal` | string | 1/148 |

### `trails/{trailId}/ratings/{sessionId}`

Observed documents: **2**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `comment` | string | 2/2 |
| `createdAt` | timestamp | 2/2 |
| `difficulty` | string | 1/2 |
| `rating` | integer | 2/2 |
| `sessionId` | string | 2/2 |
| `trailId` | string | 2/2 |
| `updatedAt` | timestamp | 2/2 |
| `updatedAtLocal` | string | 2/2 |
| `userId` | string | 2/2 |

### `upcomingHikes/{hikeId}/reminderPreferences/{userId}`

Observed documents: **5**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `deliveryClaimedAt` | timestamp | 3/5 |
| `deliveryClaimedAtLocal` | string | 3/5 |
| `deliveryClaimSequence` | integer | 3/5 |
| `departureTimeLocal` | string | 3/5 |
| `enabled` | boolean | 5/5 |
| `finalReminderMinutesBefore` | integer | 5/5 |
| `firstReminderMinutesBefore` | integer | 5/5 |
| `hikeId` | string | 5/5 |
| `lastDeliveryFailureCount` | integer | 3/5 |
| `lastDeliveryStatus` | string | 3/5 |
| `lastDeliverySuccessCount` | integer | 3/5 |
| `lastSentAt` | timestamp | 3/5 |
| `lastSentAtLocal` | string | 3/5 |
| `maximumReminders` | integer | 5/5 |
| `ownerPhoneNumber` | string | 5/5 |
| `ownerUserId` | string | 5/5 |
| `repeatIntervalMinutes` | integer | 5/5 |
| `sentCount` | integer | 3/5 |
| `updatedAt` | timestamp | 5/5 |
| `updatedAtLocal` | string | 5/5 |

### `nearbySosIncidents/{incidentId}/reports/{reporterHash}`

Observed documents: **6**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `detectorLocation` | map \| null | 6/6 |
| `receivedAtLocal` | string | 6/6 |
| `reportedLocation` | map \| null | 6/6 |
| `reporterHash` | string | 6/6 |
| `rssi` | integer | 6/6 |
| `updatedAt` | timestamp | 6/6 |
| `updatedAtLocal` | string | 6/6 |

## Canonical nested shapes

| Shape | Fields |
|---|---|
| Trail checkpoint | `name:string`, `latitude:number`, `longitude:number`, `order:int` |
| Trail weather | `summary:string`, `temperatureRange:string`, `rainProbability:int`, `cachedAtLocal:string`, optional `humidity:int`, `windSpeed:number`, `uvIndex:number`, `feelsLike:number`, `hourlyForecast:array`, `forecastData:map` |
| Hourly forecast | `timeLocal:string`, `temperature:number`, `precipitationProbability:int`, `weatherCode:int` |
| Trail hazard | `type:string`, `description:string`, `severity:string`, `locationLabel:string`, `reportedAtLocal:string`; enriched route hazards may also carry coordinates and provider evidence |
| Trail image credit | `sourceName`, `sourcePageUrl`, `author`, `licenseName`, `licenseUrl`, `description` (all strings) |
| Coordinate/location | `latitude:number`, `longitude:number`, optional `accuracyMeters:number`, `altitudeMeters:number`, and ISO capture time |
| User profile | `username`, `gender`, `hikerExperience`, `hikeFrequency`, `residentialLocation`, optional residential coordinates and `photoURL` |
| Emergency contact | `name:string`, `phoneNumber:string`, `relationship:string` |
| SOS dispatch | `contactName:string`, `phoneNumber:string`, `wasSent:boolean`, `retryable:boolean`, optional `errorMessage` and `providerMessageId` |
| Team buddy | `name`, `handle`, `phoneNumber`, `role`, optional `photoURL`, `avatarColorValue:int` |
| Team participant | `buddy:map`, `phoneNumber`, `status`, `isHost`, `isLeader`, `progressMeters`, optional location/timestamps/safety settings, `separationAlertActive` |
| Chat attachment | Storage URL/path plus attachment name, MIME type, byte size, and sender metadata; accepted formats are constrained by Storage Rules |
| Dynamic per-user maps | `lastReadAt.{phoneKey}`, `unreadCount.{phoneKey}`, `buddyRequestsIncoming.{phoneKey}`, `buddyRequestsOutgoing.{phoneKey}`, and `fcmTokenByAppId.{appInstanceId}` |

Server timestamps and `...Local` ISO-8601 mirrors intentionally coexist. Server timestamps provide authoritative ordering; Local mirrors make callable responses, offline persistence, and cross-platform parsing deterministic.

## Cloud Storage schema

| Object path | Current count | Purpose and constraint |
|---|---:|---|
| `app_feedback/` | 2 | `app_feedback/{uid}/{reportId}/screenshot.png` — owner/admin read, PNG only, maximum 5 MiB. |
| `community_hikes/` | 1 | `community_hikes/{uid}/{sessionId}/{file}` — owner-created hike images, supported image formats, maximum 10 MiB. |
| `group_chats/` | 1 | `group_chats/{chatId}/attachments/{file}` — chat-member media/documents, maximum 25 MiB. |
| `profile_photos/` | 1 | `profile_photos/{uid}/{file}` — owner/admin managed profile image, maximum 10 MiB. |
| `releases/` | 1 | `releases/android/beta/{apk}` — APK referenced by `web/site/beta-release.json`. |
| `trail_covers/` | 51 | `trail_covers/{trailId}/{image}` and deployment-curated variants — trail cover images. |

Total: **57 objects / 204.84 MiB**. All remaining objects are referenced by Firestore or a checked-in application/release manifest.

Three additional Google-managed Cloud Functions buckets were found (`gcf-v2-sources` in both deployed regions and the `gcf-v2-uploads` bucket). They are deployment infrastructure rather than app Storage and were intentionally preserved.

## Authentication schema boundary

- Firebase Authentication owns identity principals and tokens; the audit only counted accounts and did not export their records.
- The matching private app profile is `users/{uid}`. The app uses a canonical phone-based UID and validates the authenticated phone claim server-side.
- MFA factor secrets/credentials live only in `users/{uid}/authFactors/{factorId}` and are denied to normal Firestore clients. TOTP secrets are encrypted; passkeys store the public credential only.
- MFA/login/reset challenges are backend-only, expire in minutes, and are covered by the cleanup policy. Password hashes remain backend-only fields in the private user document.

## Composite indexes

| Collection group | Scope | Fields |
|---|---|---|
| `appFeedback` | COLLECTION | `uid` ASCENDING, `createdAt` DESCENDING |
| `trails` | COLLECTION | `isVerifiedTrail` DESCENDING, `ratingAverage` DESCENDING |
| `groupChats` | COLLECTION | `participantPhones` CONTAINS, `createdAtLocal` DESCENDING |
| `communityPosts` | COLLECTION | `visibility` ASCENDING, `createdAtLocal` DESCENDING |
| `hikeSessions` | COLLECTION | `status` ASCENDING, `checkIns` ASCENDING, `distanceKm` ASCENDING |
| `hikeSessions` | COLLECTION | `status` ASCENDING, `distanceKm` ASCENDING |
| `hikeSessions` | COLLECTION | `status` ASCENDING, `checkIns` ASCENDING |
| `hikeSessions` | COLLECTION | `status` ASCENDING, `hikeType` ASCENDING |
| `hikeSessions` | COLLECTION | `userId` ASCENDING, `status` ASCENDING, `endedAtLocal` DESCENDING |
| `userAchievements` | COLLECTION | `userId` ASCENDING, `isUnlocked` ASCENDING, `awardedAtLocal` DESCENDING |
| `userAchievements` | COLLECTION | `isUnlocked` ASCENDING, `awardedAtLocal` ASCENDING |
| `upcomingHikes` | COLLECTION | `creatorUserId` ASCENDING, `departureTimeLocal` DESCENDING, `__name__` DESCENDING |
| `upcomingHikes` | COLLECTION | `participantPhones` CONTAINS, `departureTimeLocal` DESCENDING, `__name__` DESCENDING |

## Deployed Cloud Functions

All functions below were ACTIVE during the audit and matched a source export. Deployment-managed source/archive buckets are intentionally excluded from application Storage cleanup.

| Function | Trigger | Region | Runtime |
|---|---|---|---|
| `authenticateAppSession` | Callable HTTPS | us-central1 | nodejs22 |
| `awardAchievementForApprovedHazard` | Firestore updated — hazardReports/{hazardId} | asia-southeast1 | nodejs22 |
| `awardAchievementForCheckIn` | Firestore created — checkIns/{checkInId} | asia-southeast1 | nodejs22 |
| `awardAchievementForCommunityPost` | Firestore created — communityPosts/{postId} | asia-southeast1 | nodejs22 |
| `awardAchievementForCompletedTeamHike` | Firestore updated — teamHikeSessions/{teamId} | asia-southeast1 | nodejs22 |
| `awardAchievementsForStartedHike` | Firestore created — hikeSessions/{sessionId} | asia-southeast1 | nodejs22 |
| `beginPasskeyEnrollment` | Callable HTTPS | us-central1 | nodejs22 |
| `beginPasskeyLogin` | Callable HTTPS | us-central1 | nodejs22 |
| `beginTotpEnrollment` | Callable HTTPS | us-central1 | nodejs22 |
| `checkActiveHikeMonitoringHeartbeats` | Scheduled | us-central1 | nodejs22 |
| `checkSafetyAnswer` | Callable HTTPS | us-central1 | nodejs22 |
| `cleanExpiredGroupChats` | Scheduled | us-central1 | nodejs22 |
| `cleanExpiredMfaArtifacts` | Scheduled | us-central1 | nodejs22 |
| `cleanExpiredTeamHikeInvitations` | Scheduled | us-central1 | nodejs22 |
| `cleanExpiredUpcomingHikes` | Scheduled | us-central1 | nodejs22 |
| `cleanStaleHikeSessions` | Scheduled | us-central1 | nodejs22 |
| `completeActiveHikeSession` | Callable HTTPS | us-central1 | nodejs22 |
| `createTeamHikeSession` | Callable HTTPS | us-central1 | nodejs22 |
| `decrementCommunityCommentCount` | Firestore deleted — communityPosts/{postId}/comments/{commentId} | asia-southeast1 | nodejs22 |
| `deleteChatForUser` | Callable HTTPS | us-central1 | nodejs22 |
| `deliverFcmOutboxMessage` | Firestore created — fcmOutbox/{messageId} | asia-southeast1 | nodejs22 |
| `ensureActiveHikeSessionInCloud` | Callable HTTPS | us-central1 | nodejs22 |
| `fetchWeatherForAllTrails` | Scheduled | us-central1 | nodejs22 |
| `fetchWeatherForTrail` | Callable HTTPS | us-central1 | nodejs22 |
| `finishPasskeyEnrollment` | Callable HTTPS | us-central1 | nodejs22 |
| `finishPasskeyLogin` | Callable HTTPS | us-central1 | nodejs22 |
| `finishTotpEnrollment` | Callable HTTPS | us-central1 | nodejs22 |
| `forwardNearbySosIncident` | Callable HTTPS | us-central1 | nodejs22 |
| `getMfaStatus` | Callable HTTPS | us-central1 | nodejs22 |
| `getMyAchievementProgressHash` | Callable HTTPS | us-central1 | nodejs22 |
| `getPublicHikerCircleStats` | HTTP request | us-central1 | nodejs22 |
| `getPublicProfiles` | Callable HTTPS | us-central1 | nodejs22 |
| `incrementCommunityCommentCount` | Firestore created — communityPosts/{postId}/comments/{commentId} | asia-southeast1 | nodejs22 |
| `joinUpcomingHike` | Callable HTTPS | us-central1 | nodejs22 |
| `linkPasswordToAccount` | Callable HTTPS | us-central1 | nodejs22 |
| `listMyHikeHistory` | Callable HTTPS | us-central1 | nodejs22 |
| `listUpcomingHikePreviews` | Callable HTTPS | us-central1 | nodejs22 |
| `loadAchievementLeaderboard` | Callable HTTPS | us-central1 | nodejs22 |
| `loadMyHikeHistoryDetail` | Callable HTTPS | us-central1 | nodejs22 |
| `loadPublicHikerProfile` | Callable HTTPS | us-central1 | nodejs22 |
| `loadUpcomingHikeJoinRequest` | Callable HTTPS | us-central1 | nodejs22 |
| `loginWithPassword` | Callable HTTPS | us-central1 | nodejs22 |
| `manageAchievementDefinition` | Callable HTTPS | us-central1 | nodejs22 |
| `manageBuddyRequest` | Callable HTTPS | us-central1 | nodejs22 |
| `manageTeamHikeSession` | Callable HTTPS | us-central1 | nodejs22 |
| `markFormedHikeGroupNamingPromptShown` | Callable HTTPS | us-central1 | nodejs22 |
| `mirrorActiveHikeLocationToLiveShare` | Firestore updated — hikeSessions/{sessionId} | asia-southeast1 | nodejs22 |
| `nameFormedHikeGroupChat` | Callable HTTPS | us-central1 | nodejs22 |
| `notifyEmergencyContactsOfLiveLocation` | Callable HTTPS | us-central1 | nodejs22 |
| `notifyGroupMembersAboutMessage` | Firestore created — groupChats/{chatId}/messages/{messageId} | asia-southeast1 | nodejs22 |
| `notifyHostAboutUpcomingHikeJoinRequest` | Firestore created — upcomingHikeJoinRequests/{requestId} | asia-southeast1 | nodejs22 |
| `notifyNearbyHikersAboutUpcomingHike` | Firestore created — upcomingHikes/{hikeId} | asia-southeast1 | nodejs22 |
| `openDirectChat` | Callable HTTPS | us-central1 | nodejs22 |
| `openUpcomingHikeJoinRequest` | HTTP request | us-central1 | nodejs22 |
| `preserveDeletedHikeTerminalState` | Firestore deleted — hikeSessions/{sessionId} | asia-southeast1 | nodejs22 |
| `processUpcomingHikeLifecycle` | Scheduled | us-central1 | nodejs22 |
| `recordActiveHikeCheckIn` | Callable HTTPS | us-central1 | nodejs22 |
| `recordHikeTerminalStateAndAchievements` | Firestore updated — hikeSessions/{sessionId} | asia-southeast1 | nodejs22 |
| `redactLegacySharedHikeDrafts` | Scheduled | us-central1 | nodejs22 |
| `registerSafetyQuestions` | Callable HTTPS | us-central1 | nodejs22 |
| `registerWithGreenApiAndPassword` | Callable HTTPS | us-central1 | nodejs22 |
| `remindUpcomingHikeHost` | Callable HTTPS | us-central1 | nodejs22 |
| `removeMfaFactor` | Callable HTTPS | us-central1 | nodejs22 |
| `requestToJoinUpcomingHike` | Callable HTTPS | us-central1 | nodejs22 |
| `resetPassword` | Callable HTTPS | us-central1 | nodejs22 |
| `resolveUpcomingHikeJoinRequest` | Callable HTTPS | us-central1 | nodejs22 |
| `scheduleUpcomingHike` | Callable HTTPS | us-central1 | nodejs22 |
| `sendGreenApiLoginCode` | Callable HTTPS | us-central1 | nodejs22 |
| `sendPasswordResetCode` | Callable HTTPS | us-central1 | nodejs22 |
| `sendReminderOnActiveHikeTerminationSignal` | Firestore updated — hikeSessions/{sessionId} | asia-southeast1 | nodejs22 |
| `sendScheduledActiveHikeCheckIns` | Scheduled | us-central1 | nodejs22 |
| `sendSosWhatsAppMessage` | Callable HTTPS | us-central1 | nodejs22 |
| `sendUpcomingHikePrecautions` | Scheduled | us-central1 | nodejs22 |
| `setUpcomingHikeJoinPolicy` | Callable HTTPS | us-central1 | nodejs22 |
| `startActiveHikeSession` | Callable HTTPS | us-central1 | nodejs22 |
| `submitCompletedHikeRating` | Callable HTTPS | us-central1 | nodejs22 |
| `syncMyAchievementProgress` | Callable HTTPS | us-central1 | nodejs22 |
| `verifyGreenApiLoginCode` | Callable HTTPS | us-central1 | nodejs22 |
| `verifyPasswordResetOtp` | Callable HTTPS | us-central1 | nodejs22 |
| `verifyTotpLogin` | Callable HTTPS | us-central1 | nodejs22 |

## Rules and lifecycle notes

- Firestore access is deny-by-default. Public/authenticated reads and user writes are granted only in the explicit collection matches in `firestore.rules`; backend-only collections rely on the Admin SDK.
- Storage is deny-by-default. File type, ownership/membership, and size constraints are enforced by `storage.rules`.
- `cleanExpiredMfaArtifacts`, `cleanExpiredUpcomingHikes`, `cleanExpiredGroupChats`, `cleanExpiredTeamHikeInvitations`, and `cleanStaleHikeSessions` are deployed scheduled lifecycle workers.
- The conservative maintenance script is `scripts/cleanup_firebase_data.js`. It is dry-run by default; `--apply` writes a local backup before exact-path deletion.
- The inventory script is `scripts/audit_firebase_inventory.js`. Re-run both after schema changes and before future cleanup.

## Recommended maintenance cadence

1. Run `node scripts/audit_firebase_inventory.js`.
2. Run `node scripts/cleanup_firebase_data.js` and review the dry-run counts.
3. If the candidates are expected, run `node scripts/cleanup_firebase_data.js --apply`.
4. Re-run the inventory and dry-run; the cleanup candidate counts must return to zero.
5. Keep safety/history data out of generic TTL policies. Apply automatic TTL only to explicit transient collections after confirming the application no longer needs a terminal response.

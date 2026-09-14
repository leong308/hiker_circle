# HikerCircle Firebase Schema and Cleanup Audit

Audit snapshot: **2026-09-13T07:14:08.045Z**  
Firebase project: **hiker-circle**  
Scope: Authentication, Cloud Firestore, Cloud Storage, Cloud Functions, Hosting, rules, indexes, and data lifecycle.

> This document records schema names and types only. User values, tokens, verification codes, messages, coordinates, and secrets are deliberately excluded. A field observed in fewer than all documents is optional, legacy, workflow-specific, or populated later by the backend.

## Audit result

- Cloud Functions: **80 ACTIVE deployments**, exactly matching the 80 exports in `functions/index.js`; no stale function was deleted.
- Firestore after cleanup: **28 non-empty root collections** plus documented subcollections.
- Cloud Storage after cleanup: **59 objects / 221.31 MiB**.
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

Hike sessions/history, raw route points, route captures, check-ins, SOS events and dispatch evidence, chats/messages, community posts, user/achievement records, trail ratings, current trail covers, the two KKM videos, feedback screenshots, the current profile photo, and the published Android beta APK were retained. These are active, user-facing, safety/audit-relevant, or still referenced.

## Firestore collection registry

| Collection | Documents | Purpose | Access | Lifecycle |
|---|---:|---|---|---|
| `achievementEventReceipts` | 18 | Idempotency receipts for achievement event processing. | Backend only | Keep while source event replay remains possible. |
| `achievements` | 24 | Server-managed achievement catalogue and reward definitions. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `appFeedback` | 2 | In-app feedback reports and optional screenshot references. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `checkIns` | 26 | Safety check-ins recorded during a hike session. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `communityCounterEventReceipts` | 1 | Idempotency receipts for post comment counters. | Backend only | Keep while source event replay remains possible. |
| `communityPosts` | 2 | Community hike posts, route previews, images, and engagement counters. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `downloadedMaps` | 2 | Per-user metadata for offline trail-map downloads. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `fcmOutbox` | 14 | Short-lived queue and delivery result for team-hike push notifications. | Backend only | Terminal entries: 30-day retention; pending entries retained. |
| `groupChats` | 48 | Direct and hike-derived chat metadata and lifecycle state. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `hazardReports` | 2 | User-submitted trail hazard reports and moderation status. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `hikeRouteCaptures` | 48 | Detailed recorded route geometry and completion summary. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `hikeSessionTerminalStates` | 8 | Idempotent terminal-state markers for completion processing. | Backend only | Retained while the feature/user history needs it. |
| `hikeSessions` | 93 | Active and historical solo/group hike sessions. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `liveLocationContactDispatches` | 1 | At-most-once delivery ledger for live-location messages. | Backend only | Operational delivery evidence; retain with SOS/live-share audit. |
| `localLocationPoints` | 548 | Synced raw route/location observations used by hike history. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `maintenanceState` | 1 | Cursor and progress state for backend maintenance jobs. | Backend only | Singleton operational state; never purge while jobs use it. |
| `nearbySosIncidents` | 2 | Deduplicated nearby SOS incidents reported by button receivers. | Backend only | Retained while the feature/user history needs it. |
| `networkObservations` | 55 | Route network-availability observations. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `sosAlerts` | 140 | Canonical SOS events and their contact delivery summary. | Rules-controlled app/backend | Safety history; retained. |
| `sosWhatsAppDispatches` | 60 | At-most-once WhatsApp delivery ledger for SOS messages. | Backend only | SOS delivery evidence; retained. |
| `teamHikeSessions` | 29 | Team readiness, participant state, shared plan, and active-session links. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `teams` | 1 | Saved team definition and member list. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `trailWeatherCache` | 34 | Backend weather cache and refresh lease state. | Backend only | Replace in place; safe to rebuild from provider. |
| `trails` | 35 | Trail catalogue, Mapbox route, elevation range, media, ratings, and hazards. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `upcomingHikeJoinRequests` | 2 | Join-request workflow and host notification outcome. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
| `userAchievements` | 34 | Per-user progress and award state for each achievement. | Rules-controlled app/backend | Retained while the feature/user history needs it. |
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

Idempotency receipts for achievement event processing. Observed documents: **18**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `achievementId` | string | 18/18 |
| `applied` | boolean | 18/18 |
| `createdAt` | timestamp | 18/18 |
| `createdAtLocal` | string | 18/18 |
| `eventKey` | string | 18/18 |
| `userId` | string | 18/18 |

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

### `checkIns/{documentId}`

Safety check-ins recorded during a hike session. Observed documents: **26**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `batteryLevel` | integer | 26/26 |
| `checkInId` | string | 5/26 |
| `createdAt` | timestamp | 26/26 |
| `createdAtLocal` | string | 26/26 |
| `location` | map | 25/26 |
| `sessionId` | string | 26/26 |
| `status` | string | 26/26 |
| `trailId` | string | 26/26 |
| `userId` | string | 26/26 |
| `userPhoneNumber` | string | 26/26 |

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

Community hike posts, route previews, images, and engagement counters. Observed documents: **2**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `authorAchievementPoints` | integer | 2/2 |
| `authorHandle` | string | 2/2 |
| `authorId` | string | 2/2 |
| `authorLevel` | integer | 2/2 |
| `authorLevelBadge` | string | 2/2 |
| `authorLevelName` | string | 2/2 |
| `authorName` | string | 2/2 |
| `authorPhoneNumber` | string | 2/2 |
| `caption` | string | 2/2 |
| `checkIns` | integer | 1/2 |
| `commentCount` | integer | 2/2 |
| `createdAt` | timestamp | 2/2 |
| `createdAtLocal` | string | 2/2 |
| `distanceKm` | double | 1/2 |
| `durationMinutes` | integer | 1/2 |
| `highestAltitudeMeters` | null | 1/2 |
| `imageUrls` | array | 2/2 |
| `likeCount` | integer | 2/2 |
| `manualPins` | integer | 1/2 |
| `postId` | string | 2/2 |
| `postType` | string | 2/2 |
| `routeBounds` | map | 1/2 |
| `routeCaptureId` | string | 1/2 |
| `routeEnd` | map | 1/2 |
| `routePointCount` | integer | 1/2 |
| `routePreviewPoints` | array | 1/2 |
| `routeStart` | map | 1/2 |
| `sessionId` | string | 1/2 |
| `summaryReport` | map | 1/2 |
| `thumbnailType` | string | 1/2 |
| `trailId` | string | 1/2 |
| `trailName` | string | 1/2 |
| `visibility` | string | 2/2 |

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

### `hikeRouteCaptures/{documentId}`

Detailed recorded route geometry and completion summary. Observed documents: **48**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `anonymousRecommendationEligible` | boolean | 48/48 |
| `captureType` | string | 48/48 |
| `communityPostId` | string | 12/48 |
| `createdAt` | timestamp | 48/48 |
| `createdAtLocal` | string | 48/48 |
| `manualPinCount` | integer | 8/48 |
| `manualPins` | array | 48/48 |
| `manualPinsDownsampled` | boolean | 8/48 |
| `routeBounds` | map | 46/48 |
| `routeEnd` | map | 46/48 |
| `routePointCount` | integer | 47/48 |
| `routePoints` | array | 48/48 |
| `routePointsDownsampled` | boolean | 8/48 |
| `routeStart` | map | 46/48 |
| `sessionId` | string | 48/48 |
| `storedManualPinCount` | integer | 8/48 |
| `storedRoutePointCount` | integer | 8/48 |
| `summaryReport` | map | 48/48 |
| `trailId` | string | 48/48 |
| `trailName` | string | 48/48 |
| `updatedAt` | timestamp | 47/48 |
| `updatedAtLocal` | string | 47/48 |
| `userId` | string | 48/48 |
| `userPhoneNumber` | string | 48/48 |

### `hikeSessionTerminalStates/{documentId}`

Idempotent terminal-state markers for completion processing. Observed documents: **8**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `recordedAt` | timestamp | 8/8 |
| `recordedAtLocal` | string | 8/8 |
| `sessionId` | string | 8/8 |
| `status` | string | 8/8 |
| `userId` | string | 8/8 |
| `userPhoneNumber` | string | 8/8 |

### `hikeSessions/{documentId}`

Active and historical solo/group hike sessions. Observed documents: **93**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `checkIns` | integer | 54/93 |
| `checkpoints` | array | 63/93 |
| `completedChecklistItems` | array | 93/93 |
| `createdAt` | timestamp | 8/93 |
| `createdAtLocal` | string | 8/93 |
| `destinationName` | string | 93/93 |
| `distanceKm` | double \| integer | 54/93 |
| `durationMinutes` | integer | 54/93 |
| `duressEnabled` | boolean | 93/93 |
| `emergencyContactNames` | array | 93/93 |
| `endedAt` | timestamp | 64/93 |
| `endedAtLocal` | string | 64/93 |
| `expectedArrivalTimeLocal` | string | 93/93 |
| `expectedReturnTimeLocal` | string | 93/93 |
| `fallDetectionEnabled` | boolean | 93/93 |
| `fallDetectionLongestRestDurationSeconds` | integer | 29/93 |
| `fallDetectionResponseDurationSeconds` | integer | 29/93 |
| `fallDetectionSensorSensitivity` | double \| integer | 92/93 |
| `fallDetectionStillnessDurationSeconds` | integer | 92/93 |
| `hikeType` | string | 93/93 |
| `lastCheckInAt` | timestamp | 13/93 |
| `lastCheckInAtLocal` | string | 13/93 |
| `lastCheckInStatus` | string | 13/93 |
| `lastMonitoringReminderAt` | timestamp | 2/93 |
| `lastMonitoringReminderAtLocal` | string | 2/93 |
| `lastMonitoringReminderClaimedAt` | timestamp | 1/93 |
| `lastMonitoringReminderClaimedAtLocal` | string | 1/93 |
| `lastMonitoringReminderDeliveryStatus` | string | 1/93 |
| `lastMonitoringReminderReason` | string | 2/93 |
| `lastPathDeviation` | map | 2/93 |
| `lastPathDeviationAt` | timestamp | 2/93 |
| `lastPathDeviationAtLocal` | string | 2/93 |
| `lastScheduledCheckInReminderAt` | timestamp | 1/93 |
| `lastScheduledCheckInReminderAtLocal` | string | 1/93 |
| `lastScheduledCheckInReminderClaimedAt` | timestamp | 1/93 |
| `lastScheduledCheckInReminderClaimedAtLocal` | string | 1/93 |
| `lastScheduledCheckInReminderDeliveryStatus` | string | 1/93 |
| `latestLocation` | map | 90/93 |
| `latestLocationUpdatedAt` | timestamp | 90/93 |
| `latestLocationUpdatedAtLocal` | string | 90/93 |
| `latestMotion` | map | 4/93 |
| `latestMotionUpdatedAt` | timestamp | 4/93 |
| `latestMotionUpdatedAtLocal` | string | 4/93 |
| `liveLocationShareId` | string | 1/93 |
| `liveLocationShareLinkedAt` | timestamp | 1/93 |
| `liveLocationShareLinkedAtLocal` | string | 1/93 |
| `locationRecordingIntervalMinutes` | integer | 93/93 |
| `locationRecordingIntervalSeconds` | integer | 71/93 |
| `manualPins` | integer | 54/93 |
| `monitoringExpected` | boolean | 54/93 |
| `monitoringFcmToken` | string | 16/93 |
| `monitoringHeartbeatAt` | timestamp | 28/93 |
| `monitoringHeartbeatAtLocal` | string | 28/93 |
| `monitoringLifecycleState` | string | 54/93 |
| `offlinePhysicalAlertEnabled` | boolean | 93/93 |
| `pathDeviationAlertCount` | integer | 2/93 |
| `pathDeviationEnabled` | boolean | 93/93 |
| `plannedStartTimeLocal` | string | 93/93 |
| `routePointCount` | integer | 54/93 |
| `safetyCheckInIntervalMinutes` | integer | 93/93 |
| `safetyCheckInIntervalSeconds` | integer | 8/93 |
| `sessionId` | string | 93/93 |
| `shareLiveLocation` | boolean | 93/93 |
| `sourceUpcomingHikeId` | string | 6/93 |
| `startedAt` | timestamp | 93/93 |
| `startedAtLocal` | string | 93/93 |
| `startPointName` | string | 93/93 |
| `status` | string | 93/93 |
| `summaryReport` | map | 54/93 |
| `teamBuddies` | array | 67/93 |
| `teamHikeSessionId` | string | 12/93 |
| `trail` | map | 93/93 |
| `trailId` | string | 93/93 |
| `trailName` | string | 93/93 |
| `updatedAt` | timestamp | 93/93 |
| `updatedAtLocal` | string | 93/93 |
| `userId` | string | 93/93 |
| `userPhoneNumber` | string | 93/93 |

### `liveLocationContactDispatches/{documentId}`

At-most-once delivery ledger for live-location messages. Observed documents: **1**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `attemptCount` | integer | 1/1 |
| `attemptNonce` | string | 1/1 |
| `createdAt` | timestamp | 1/1 |
| `createdAtLocal` | string | 1/1 |
| `deliveryUncertain` | boolean | 1/1 |
| `leaseExpiresAtMillis` | integer | 1/1 |
| `messageType` | string | 1/1 |
| `outboundStartedAt` | timestamp | 1/1 |
| `outboundStartedAtLocal` | string | 1/1 |
| `ownerUid` | string | 1/1 |
| `providerMessageId` | string | 1/1 |
| `recipientPhoneNumber` | string | 1/1 |
| `retryable` | boolean | 1/1 |
| `senderPhoneNumber` | string | 1/1 |
| `sentAt` | timestamp | 1/1 |
| `sentAtLocal` | string | 1/1 |
| `sessionId` | string | 1/1 |
| `status` | string | 1/1 |
| `updatedAt` | timestamp | 1/1 |
| `updatedAtLocal` | string | 1/1 |

### `localLocationPoints/{documentId}`

Synced raw route/location observations used by hike history. Observed documents: **548**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `accuracyMeters` | double | 548/548 |
| `batteryLevel` | integer | 548/548 |
| `isSynced` | boolean | 548/548 |
| `latitude` | double | 548/548 |
| `longitude` | double | 548/548 |
| `pointType` | string | 548/548 |
| `recordedAt` | timestamp | 245/548 |
| `recordedAtLocal` | string | 548/548 |
| `sessionId` | string | 548/548 |
| `trailId` | string | 548/548 |
| `userId` | string | 548/548 |
| `userPhoneNumber` | string | 548/548 |

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

### `nearbySosIncidents/{documentId}`

Deduplicated nearby SOS incidents reported by button receivers. Observed documents: **2**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `accuracyMeters` | double | 2/2 |
| `counter` | integer | 2/2 |
| `deviceIdHash` | string | 2/2 |
| `firstReceivedAtLocal` | string | 2/2 |
| `incidentId` | string | 2/2 |
| `lastReceivedAtLocal` | string | 2/2 |
| `latitude` | double | 2/2 |
| `locationSource` | string | 2/2 |
| `longitude` | double | 2/2 |
| `reporterCount` | integer | 2/2 |
| `status` | string | 2/2 |
| `updatedAt` | timestamp | 2/2 |
| `updatedAtLocal` | string | 2/2 |
| `verificationState` | string | 2/2 |

### `networkObservations/{documentId}`

Route network-availability observations. Observed documents: **55**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `apiRequestSuccess` | boolean | 55/55 |
| `gpsAccuracy` | double | 55/55 |
| `latitude` | double | 55/55 |
| `longitude` | double | 55/55 |
| `networkType` | string | 55/55 |
| `recordedAt` | timestamp | 55/55 |
| `recordedAtLocal` | string | 55/55 |
| `sessionId` | string | 55/55 |
| `trailId` | string | 55/55 |
| `userId` | string | 55/55 |

### `sosAlerts/{documentId}`

Canonical SOS events and their contact delivery summary. Observed documents: **140**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `cloudLogPath` | string | 140/140 |
| `contactCount` | integer | 140/140 |
| `dispatches` | array | 140/140 |
| `failedCount` | integer | 140/140 |
| `id` | string | 140/140 |
| `message` | string | 140/140 |
| `mode` | string | 140/140 |
| `phoneNumber` | string | 140/140 |
| `sentCount` | integer | 140/140 |
| `status` | string | 140/140 |
| `triggeredAtLocal` | string | 140/140 |
| `triggeredByPhoneNumber` | string | 140/140 |
| `triggerLocation` | map | 126/140 |
| `triggerSource` | string | 42/140 |
| `updatedAt` | timestamp | 140/140 |
| `userId` | string | 140/140 |

### `sosWhatsAppDispatches/{documentId}`

At-most-once WhatsApp delivery ledger for SOS messages. Observed documents: **60**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `attemptCount` | integer | 60/60 |
| `attemptNonce` | string | 60/60 |
| `createdAt` | timestamp | 60/60 |
| `createdAtLocal` | string | 60/60 |
| `deliveryUncertain` | boolean | 60/60 |
| `dispatchId` | string | 60/60 |
| `isTest` | boolean | 60/60 |
| `leaseExpiresAtMillis` | integer | 60/60 |
| `messageType` | string | 60/60 |
| `mode` | string | 60/60 |
| `outboundStartedAt` | timestamp | 60/60 |
| `outboundStartedAtLocal` | string | 60/60 |
| `ownerUid` | string | 60/60 |
| `payloadHash` | string | 60/60 |
| `preferredTimeZone` | string | 42/60 |
| `providerMessageId` | string | 60/60 |
| `recipientPhoneNumber` | string | 60/60 |
| `retryable` | boolean | 60/60 |
| `senderPhoneNumber` | string | 60/60 |
| `sentAt` | timestamp | 60/60 |
| `sentAtLocal` | string | 60/60 |
| `sourceId` | string | 60/60 |
| `status` | string | 60/60 |
| `triggeredAtMillis` | integer | 60/60 |
| `triggerSource` | string | 42/60 |
| `updatedAt` | timestamp | 60/60 |
| `updatedAtLocal` | string | 60/60 |
| `wasSent` | boolean | 60/60 |

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

Backend weather cache and refresh lease state. Observed documents: **34**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `leaseUntilMs` | integer | 34/34 |
| `retryAfterMs` | integer | 34/34 |
| `updatedAtMs` | integer | 34/34 |
| `weather` | map | 34/34 |

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
| `dataSource` | string | 31/35 |
| `dataSourceUrl` | string | 31/35 |
| `difficulty` | string | 24/35 |
| `difficultyRatingCount` | integer | 11/35 |
| `difficultyVoteCounts` | map | 11/35 |
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
| `osmRelationId` | string | 22/35 |
| `ratingAverage` | double \| integer | 35/35 |
| `ratingCount` | integer | 35/35 |
| `ratingSum` | double \| integer | 35/35 |
| `ratingUpdatedAt` | timestamp | 1/35 |
| `ratingUpdatedAtLocal` | string | 1/35 |
| `routeActivity` | string | 31/35 |
| `routeCheckpointsHash` | string | 4/35 |
| `routeEncodedPolyline` | string | 35/35 |
| `routeFilePath` | string | 35/35 |
| `routeProvider` | string | 31/35 |
| `routeReferenceName` | string | 31/35 |
| `routeReferenceNote` | string | 24/35 |
| `routeReferenceUrl` | string | 31/35 |
| `routeShape` | string | 31/35 |
| `routeVerifiedAtLocal` | string | 31/35 |
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

### `userAchievements/{documentId}`

Per-user progress and award state for each achievement. Observed documents: **34**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `achievementId` | string | 34/34 |
| `achievementTitle` | string | 34/34 |
| `awardedAt` | timestamp | 19/34 |
| `awardedAtLocal` | string | 19/34 |
| `condition` | string | 6/34 |
| `isUnlocked` | boolean | 34/34 |
| `metricKey` | string | 34/34 |
| `pointsAwarded` | integer | 15/34 |
| `progressCount` | integer | 34/34 |
| `rewardType` | string | 34/34 |
| `targetCount` | integer | 34/34 |
| `updatedAt` | timestamp | 34/34 |
| `updatedAtLocal` | string | 34/34 |
| `userAchievementId` | string | 34/34 |
| `userId` | string | 34/34 |

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
| `activeFcmAppInstanceId` | string | 1/2 |
| `activeFcmToken` | string | 1/2 |
| `boundAppInstanceId` | string | 2/2 |
| `boundAppInstanceUpdatedAt` | timestamp | 2/2 |
| `boundAppInstanceUpdatedAtLocal` | string | 2/2 |
| `buddyRequestsIncoming.{phoneKey}` | map | 1/2 |
| `buddyRequestsOutgoing.{phoneKey}` | map | 1/2 |
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
| `lastFcmToken` | string | 1/2 |
| `lastFcmTokenUpdatedAt` | timestamp | 2/2 |
| `lastFcmTokenUpdatedAtLocal` | string | 2/2 |
| `lastFirebaseAuthenticatedAt` | timestamp | 2/2 |
| `lastFirebaseAuthenticatedAtLocal` | string | 2/2 |
| `lastMfaAt` | timestamp | 2/2 |
| `lastMfaAtLocal` | string | 2/2 |
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

Observed documents: **1**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `comment` | string | 1/1 |
| `createdAt` | timestamp | 1/1 |
| `rating` | integer | 1/1 |
| `sessionId` | string | 1/1 |
| `trailId` | string | 1/1 |
| `updatedAt` | timestamp | 1/1 |
| `updatedAtLocal` | string | 1/1 |
| `userId` | string | 1/1 |

### `upcomingHikes/{hikeId}/reminderPreferences/{userId}`

Observed documents: **0**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| — | Defined but currently empty | 0/0 |

### `nearbySosIncidents/{incidentId}/reports/{reporterHash}`

Observed documents: **2**.

| Field | Firestore type(s) | Presence |
|---|---|---:|
| `detectorLocation` | map | 2/2 |
| `receivedAtLocal` | string | 2/2 |
| `reportedLocation` | null | 2/2 |
| `reporterHash` | string | 2/2 |
| `rssi` | integer | 2/2 |
| `updatedAt` | timestamp | 2/2 |
| `updatedAtLocal` | string | 2/2 |

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
| `first_aid/` | 2 | `first_aid/videos/{topic}_v{version}.mp4` — deployment-managed KKM tutorial media, authenticated read, app-cached. |
| `group_chats/` | 1 | `group_chats/{chatId}/attachments/{file}` — chat-member media/documents, maximum 25 MiB. |
| `profile_photos/` | 1 | `profile_photos/{uid}/{file}` — owner/admin managed profile image, maximum 10 MiB. |
| `releases/` | 1 | `releases/android/beta/{apk}` — APK referenced by `web/site/beta-release.json`. |
| `trail_covers/` | 51 | `trail_covers/{trailId}/{image}` and deployment-curated variants — trail cover images. |

Total: **59 objects / 221.31 MiB**. All remaining objects are referenced by Firestore or a checked-in application/release manifest.

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

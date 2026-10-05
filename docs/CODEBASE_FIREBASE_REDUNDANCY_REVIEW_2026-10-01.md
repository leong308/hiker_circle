# HikerCircle codebase and Firebase redundancy review

Review date: **1 October 2026, Asia/Kuala_Lumpur**. Project: **hiker-circle**.

**Original audit: review only.** The snapshot and recommendations below describe the state before cleanup. Following user approval, A was implemented on 1 October and B1–B9 on 2 October 2026 (Asia/Kuala_Lumpur), as recorded below. D1–D5 were implemented with compatibility safeguards on 2 October; see [the D execution record](STORAGE_NORMALIZATION_D1_D5_2026-10-02.md) for migration, deployment and validation details. C remains unexecuted. Existing unrelated uncommitted changes were preserved.

## Approved A cleanup execution

There was no A0 candidate in the original audit. A0 was treated as the baseline/caller/dependency verification step, without adding new cleanup scope.

| ID | Implemented outcome |
|---|---|
| A0 | Checked original dirty files, production callers, test/tool callers, and source-asset tooling dependencies. |
| A1 | Removed the disconnected legacy trail repository. |
| A2 | Removed the four disconnected home prototype files together. |
| A3 | Removed the empty deprecated `ensureTrailSeeds` API. |
| A4 | Removed all three empty achievement mutation APIs and the manual-pin call to the no-op. Manual-pin persistence/counting remains intact. No current server manual-pin achievement definition exists; this cleanup does not add or remove a real manual-pin award. Existing server achievement processing remains intact. |
| A5 | Removed `buildWeatherFromApi`, `WMO_MAP`, and `wmoSummary`. Both active weather functions still use the shared weather service; schedules, cache contracts and writes are unchanged. |
| A6 | Removed unreachable bodies from the three retired authentication callables. Retained their names and explicit rejection responses for old clients. Removed the unused secret attachment from the retired registration stub. Current password-before-OTP, MFA and reset flows are unchanged. |
| A7 | Removed the unused `processing_checkmark.json` and its asset declaration. Active primary/compact/Bluetooth loaders and the GIF remain. |
| A8 | Removed only the two unused Flutter PNG asset declarations. Both source PNG files remain for launcher/Hosting tooling. A7+A8 remove 1,593,304 bytes (about 1.52 MiB) of raw declared assets, not a measured compressed APK saving. |
| A9 | Archived the unused 910,252-byte italic font at `tmp/code-cleanup-a-2026-10-01/InterVariable-Italic.ttf`. It was never bundled, so this contributes no app-size reduction. |
| A10 | Removed 23 methods with neither production nor test/tool callers; with A4's called no-op, 24 APIs were removed overall. Kept all 10 test/tool-supported methods. Removed newly unused private getters/constants. |

Deleted tracked source/assets remain recoverable from Git history; the italic font additionally remains in the local archive above. No Firestore documents, Storage objects, Auth accounts, SQLite tables/data, rules or indexes were deleted or migrated. No function endpoint was deleted. Removing `deleteLegacyFirebaseDummyData` removes its unused API only; that destructive method was not executed.

Retained test/tool-supported APIs: `waitForCloudSync`, `downloadForTrails`, `optimizeWalkingRoute`, `saveCachedEntities`, `upsertOfflineMapRegion`, `loadOfflineMapRegions`, `loadOfflineMapRegion`, `deleteOfflineMapRegion`, `deleteSyncedLocationPoints`, and `discardHikeTrackingTelemetry`. Active cache/outbox handling, private completion telemetry cleanup, offline retries, SOS histories and team-hike functionality remain in place.

Validation so far: static analysis, `git diff --check`, and 130 backend tests passed. The source-based native-restoration regression test now normalizes Windows line endings before checking multiline code. The Android release APK built successfully (166.5 MB); inspection confirmed the retired JSON and two unnecessary PNGs are absent from the bundle while all four active animations and the Android logo remain. Existing liquid-glass SkSL fallback and plugin/Kotlin migration warnings remain; this cleanup does not address those dependencies.

The five affected backend functions were successfully redeployed to `hiker-circle` in `us-central1`: `registerWithGreenApiAndPassword`, `loginWithPassword`, `authenticateAppSession`, `fetchWeatherForAllTrails`, and `fetchWeatherForTrail`. The first discovery attempt exceeded the CLI's 10-second initialization limit while builds/tests were running; retrying with a longer discovery timeout succeeded. No other endpoint, rule, index, Hosting deployment, or scheduled frequency was changed. This does not certify deployment freshness for the other 80 functions.

The full Flutter suite exposed two unchanged website-test mismatches (13 expected evolution cards versus 14 actual; an obsolete dashed-border expectation). Another full run encountered a transient Windows file lock during live-location test teardown; its five tests passed on isolated rerun. The final application-only regression run passed all **516 tests**, excluding the separate website tests.

## Approved B1–B9 cleanup execution — 2 October 2026

Re-read live data before mutation; the original audit counts were not used as deletion targets. The scoped utility `scripts/cleanup_firebase_review_b.cjs` operates only on B1–B9 and never scans/deletes application Storage assets. Apply requires an explicit inspected plan generated within the preceding hour. Exact Firestore records were backed up before any deletion, with update-time preconditions to preserve concurrent changes. Reminder orphan deletion additionally used a transaction to confirm that the parent was still missing. Documents with child collections were protected.

| ID | Removed | Preserved behavior/data |
|---|---:|---|
| B1 | 2 expired WhatsApp login challenges | Valid login/OTP workflow; challenges within their validity window are retained even if consumed. |
| B2 | 1 expired password-reset challenge | Current reset verification workflow. |
| B3 | 5 expired reset sessions | Valid reset sessions and account credentials. |
| B4 | 6 expired passkey-reset challenges | Bound passkeys and Authenticator factors were not touched. The scoped maintenance selector now explicitly covers this collection. |
| B5 | 1 expired live-location share | Historical SOS events, user references and the other unexpired share. Missing historical links already display the existing unavailable-link response. |
| B6 | 14 terminal FCM delivery records older than 30 days | The 3 newer records, pending/sending/uncertain work, independent unfinished team-ready WhatsApp work, and local notification history. |
| B7 | 7 rate-limit counters older than 25 hours | The current upcoming-hike counter and rate-limit enforcement. Removed: 1 active-hike-start, 1 completion, 1 SOS-message, 3 team-action and 1 upcoming-hike counter. |
| B8 | 2 orphaned upcoming-hike reminder preferences | Preferences whose parent exists; no upcoming-hike document was deleted. |
| B9 | 27 non-active finalized Hosting versions older than 30 days | Every channel's current release and the newest two non-active finalized rollback versions. Three versions were protected in this run. |

Total: **38 Firestore documents and 27 old Hosting versions** removed. Hosting versions carried a summed reported `versionBytes` of **63,566,042 bytes (about 60.62 MiB)**; this is not a measured billing saving because Hosting can share content across versions. The counts differ from the original audit because the data and 30-day boundary changed. Expired auth/share records also use an additional one-hour safety margin.

Private recovery material is at `tmp/firebase-review-b-backup-2026-10-02T02-22-57-774Z/`: `manifest.json` contains full typed Firestore document representations, Hosting version/configuration metadata and file hashes; `results.json` records each successful exact-target deletion. The backup and before/after plan files are ignored by Git and may contain private data; do not publish them. Firestore records can be reconstructed from the backup, but expired security artifacts should not normally be restored. **Hosting metadata/file hashes are not a byte-for-byte site archive; the deleted versions are no longer available for rollback.** The live release and two recent rollback versions remain intact. See [Hosting version deletion API](https://firebase.google.com/docs/reference/hosting/rest/v1beta1/sites.versions/delete).

Verification completed:

- All 38 deleted Firestore paths returned 404 on independent read-back.
- All 27 selected Hosting versions were absent/deleted; all three protected versions remained finalized, and channel release pointers were unchanged.
- The scoped post-cleanup dry run reported **zero eligible B1–B9 candidates**.
- The public home and privacy-policy pages both returned HTTP 200.
- Ten maintenance regression tests passed, covering expiry boundaries, uncertain delivery protection, concurrent updates, descendant protection, and orphan-parent transactions.
- No application Storage object, account, bound factor, SOS event, trail, hike/session/chat record, SQLite data, function deployment, scheduler, rule or index was removed or changed by this run. No app rebuild is required for these cloud-data changes.

Repeat maintenance only after a new inspected dry run:

```powershell
node scripts/cleanup_firebase_review_b.cjs --plan-out tmp/NEW-private-plan.json
node scripts/cleanup_firebase_review_b.cjs --apply --plan tmp/NEW-private-plan.json
node scripts/cleanup_firebase_review_b.cjs
node --test scripts/test/cleanup_firebase_review_b.test.cjs
```

This is manual maintenance; no recurring purge, TTL policy or new scheduler was created. C/D findings remain review-only.

## Scope and evidence

The review combined application import reachability, symbol/caller searches, asset declarations, local SQL schema/API searches, backend module/export analysis, live Firestore reads, subcollection discovery, Storage reference tracing, deployed function and scheduler listings, and index comparison. `flutter analyze` passed with no issues.

| Inspected item | Live/source snapshot |
|---|---:|
| Dart files under `lib/` | 183 |
| Production backend JavaScript modules | 26 |
| Non-empty Firestore root collections | 41 |
| Root documents | 1,402 |
| Subcollection documents | 204 |
| Documents inspected for child collection discovery | 1,606 |
| Additional subcollection types discovered beyond the known schemas | 0 |
| Trail documents / detailed route-geometry documents | 35 / 35 |
| Firebase Authentication accounts | 2 |
| Deployed functions / matching source exports | 85 / 85 |
| Function regions | 68 in `us-central1`; 17 in `asia-southeast1` |
| Enabled scheduled jobs | 6 |
| Live composite indexes / checked-in definitions | 13 / 13, matching |
| Configured Firestore TTL policies | 0 |
| Application Storage objects | 57 |
| Application Storage bytes | 214,793,957 bytes, about 204.84 MiB |
| Storage objects without a found reference | 0 |

Private document values, phone numbers, credentials, message text and personal coordinates are excluded from this report. Document-size estimates below are the JSON representations returned by the Firestore REST API, **not billed Firestore storage measurements**. Counts are a snapshot; rerun the audit before any approved cleanup.

Runtime caller absence is strong evidence for internal Dart APIs, but does not prove that an external HTTP/callable client never uses a deployed endpoint. Tests, development tools, old app versions, offline persistence and historical records were considered separately. Rules/deployment inventories were inspected; this review does not certify that every deployed function's source bytes or live rule text match the working checkout.

## A. Confirmed code and packaging cleanup candidates

| ID | Candidate | Evidence | Suggested change after approval | Risk |
|---|---|---|---|---|
| A1 | `lib/trail/Data/trail_repository.dart` | No app entry point imports it. It explicitly identifies itself as a legacy local source and `loadTrails()` always returns an empty list. | Remove the obsolete repository. | Low |
| A2 | `lib/home/Data/home_feature_repository.dart`, `lib/home/ModelView/home_view_model.dart`, `lib/home/Model/safety_feature.dart`, `lib/home/View/feature_tile.dart` | These four files only form their own disconnected feature chain. No application entry point reaches them. `FeatureTile` still says the feature “will be built next.” | Remove the disconnected prototype chain together. | Low |
| A3 | `ensureTrailSeeds()` | Deprecated, empty method in the Firebase repository; no caller. | Remove the obsolete compatibility method. | Low |
| A4 | Empty achievement mutation methods | `awardAchievement()` and `recordAchievementMetricForUserId()` have no callers. `recordAchievementMetric()` is empty but is still awaited when adding a manual pin in `hiker_home_page.dart`. | Remove unused empty methods and the redundant manual-pin call. Verify that server completion still awards the intended manual-pin achievement. | Low–medium |
| A5 | Old weather parsing implementation in `functions/index.js` | `buildWeatherFromApi()` has no callers. `WMO_MAP` and `wmoSummary()` only support that dead implementation. Both active weather exports use `trail_weather.sharedTrailWeather()` and its newer parser. | Remove the old parser and its exclusive helpers. | Low |
| A6 | Unreachable bodies behind three retired authentication callables | `registerWithGreenApiAndPassword`, `loginWithPassword`, and `authenticateAppSession` immediately throw `failed-precondition`. Their lengthy old implementations can never execute. No current app call sites were found for these three endpoints. | Remove unreachable bodies first while retaining the rejection stubs. Consider deleting the deployments only after checking older-client use. | Low for dead bodies; medium for deleting endpoints |
| A7 | `assets/animations/processing_checkmark.json` | Listed in `pubspec.yaml`; no application/native runtime reference. The current compact animation is `loading_spinner.json`. Raw source size: 29,997 bytes. | Remove the unused bundled asset/declaration after visual confirmation. | Low |
| A8 | Flutter bundling of `HikerCircle-Loader-Transparent.png` and `AppIcon-Default-1024.png` | Neither PNG has a Flutter runtime caller. **Both files are still used by Hosting/build tooling**: the former becomes the favicon; the latter supplies a privacy-page icon and launcher-generation source. Combined raw size: 1,563,307 bytes. | Remove only unnecessary `flutter.assets` entries if confirmed; retain the source PNGs and tooling references. | Low–medium |
| A9 | `assets/fonts/InterVariable-Italic.ttf` | Not declared as a font or asset in `pubspec.yaml`; no source/tool reference found. Raw file size: 910,252 bytes. | Remove or archive the unused source font if custom italic styling is not planned. | Low; no current app-size saving because it is not bundled |
| A10 | Unused public repository/API methods | The detailed caller list in Appendix A identifies 33 methods with no production caller. Some are test/tool helpers, some are obsolete, and some are unfinished feature plumbing. | Review by method rather than deleting all 33 together. | Mixed |

Important exceptions: `lib/showcase_safety_main.dart` is a separate development/media-capture entry point documented in `INTERNAL_SHOWCASE_CAPTURE_GUIDE.md`; it is intentionally unreachable from `main.dart`. Keep it. `file_transfer.gif` is also active: tapping the main loader switches to this animation. Cupertino Icons are heavily used despite having no direct `package:cupertino_icons/` import, so that dependency is required.

A6 concerns retired endpoints and unreachable implementations only. The current password check before requesting a WhatsApp login code, password reset, and MFA remain active and are not cleanup candidates.

## B. Live Firebase data eligible for a conservative cleanup

Original 1 October audit snapshot: the existing cleanup script was executed **in dry-run mode only**. It found **33 documents** and **10 superseded Hosting versions**. Six more expired passkey-reset challenges were outside that script's selectors. The approved 2 October execution is recorded above and supersedes these historical counts.

| ID | Candidate | Current count | Why it is redundant now | Conditions before an approved removal |
|---|---|---:|---|---|
| B1 | `greenApiLoginChallenges` | 2 | Both expired and consumed. | Preserve active/unconsumed challenges; back up selected expired records. |
| B2 | `passwordResetChallenges` | 1 | Expired and consumed. | Select by expiry/consumption, not by deleting the whole collection. |
| B3 | `passwordResetSessions` | 5 | All expired; one is also marked used. | Keep valid reset sessions. |
| B4 | `passwordResetPasskeyChallenges` | 6 | All expired; three also consumed. Not covered by the existing cleanup script or the daily MFA worker. | Add this explicit collection to the reviewed expiry policy; do not touch bound passkeys in `users/{uid}/authFactors`. |
| B5 | `live_location_shares` | 1 | Its share has expired. | Preserve an appropriate expired-link response or tombstone if desired. Keep the historical SOS event. |
| B6 | `fcmOutbox` terminal delivery records | 14 of 17 | These terminal delivery records are older than the script's 30-day retention window. The other three are newer. | Preserve pending/sending/uncertain delivery work. These are delivery state, not the user's SQLite notification history. |
| B7 | Old rate-limit documents | 8 | One active-hike-start, one hike-completion, one SOS-message, three team-action and two upcoming-hike counters are beyond the 25-hour conservative window. | Remove expired counters only; retain rate-limit enforcement and collection definitions. |
| B8 | Orphaned `upcomingHikes/{id}/reminderPreferences` | 2 of 7 | Their parent upcoming-hike document no longer exists. | Remove only the two verified orphans. |
| B9 | Superseded Hosting versions | 10 | Older than 30 days and not referenced by the live channel in the dry-run inspection. | Preserve current releases and any intentionally retained rollback version. Reported version bytes: 12,238,824, about 11.67 MiB. This is separate from app Storage. |

The document total is **39 candidates** when B4 is included: 33 from the existing dry run + 6 separately verified expired passkey-reset challenges. Hosting versions are not counted as Firestore documents.

The daily `cleanExpiredMfaArtifacts` worker currently cleans only `mfaLoginSessions`, `mfaEnrollmentChallenges` and `mfaAuthenticationChallenges`. It does not automatically cover WhatsApp/reset challenges, reset sessions, or the passkey-reset collection. The existing maintenance script is manual; retention gaps will therefore recur without an explicit lifecycle policy. No TTL policy was found.

## C. Redundant or stale documents that require reconciliation first

| ID | Candidate | Live evidence | Recommendation | Why this is not a blind deletion |
|---|---|---|---|---|
| C1 | `maintenanceState` migration cursor | 1 document. Fields include `migrationVersion`, `teamCursor`, `upcomingCursor`, `teamComplete`, `upcomingComplete` and run counters. No current runtime code reads or writes this collection. | Archive the completed legacy redaction migration cursor after confirming migration completion. Correct the schema generator's “never purge while jobs use it” blanket statement. | It records an old migration, not the current scheduler state. Preserve audit provenance. |
| C2 | Old `teams` collection and Circle team-plan UI | 1 document. Its only app repository reader is unused `loadTeamSchedules()`. Circle's `_teams` is permanently `const []`; live team hikes use `teamHikeSessions` instead. | Retire/archive the old collection and unused reader, or explicitly wire the feature if saved team plans are still wanted. Remove/rework the unreachable `_TeamPlanCard` path accordingly. | This is a product choice, not an indication that live team sessions are disposable. |
| C3 | `downloadedMaps` and dormant offline-region plumbing | 2 cloud records. `recordOfflineMapDownloaded()` has no app caller; no current cloud reader was found. All four SQLite offline-region APIs have no production callers and only test coverage. | Decide whether to finish genuine offline-map downloading or retire its obsolete metadata APIs. Keep any previously downloaded user data until migration is agreed. | A stored map flag is not proof that Mapbox tiles are available offline. |
| C4 | Already hidden upcoming hikes | All 4 current upcoming-hike documents are soft-deleted/expired, but retain drafts totalling about 139,992 REST JSON bytes. | Define archive/retention for drafts and lightweight tombstones; make normal scheduling/preview queries skip tombstones where possible. | Join links, group chat links, idempotency and history may still refer to these IDs. |
| C5 | Soft-deleted group chats | 26 of 50 chats are `isDeleted:true`; all 26 also passed their removal time. Cleanup presently marks chats deleted and leaves their documents/messages. | Define archival retention and descendant/attachment handling. Exclude tombstones from unnecessary maintenance scans. | Firestore document deletion does not automatically delete child messages. Hike history can still need a chat link. |
| C6 | Three team sessions whose phase is stale | There are 30 team sessions: 27 completed and 3 labelled active. Of the three active teams, two link only to completed hikes; the third links to two abandoned hikes. There are **zero active `hikeSessions`** in this snapshot. | Reconcile team phase and participant state transactionally; inspect completion/recovery handlers and then archive stale plans if appropriate. | This is a lifecycle consistency defect, not simply unused data. Deleting the documents would conceal the defect. |
| C7 | Legacy chat read/unread fields | 13 chat documents contain 48 literal top-level fields named like `lastReadAt.{memberKey}` / `unreadCount.{memberKey}`, including old key variants. Current readers use nested maps and normalized member keys. | Merge recoverable read timestamps/counters into canonical nested maps, then remove literal legacy fields. Recalculate unread counts where source message/read time evidence is available. | Removing old values before reconciliation could change unread badges. |
| C8 | Legacy motion/scheduled-check-in metadata | Seven historical hike sessions contain old motion metadata. One contains `lastScheduledCheckInReminder...` fields from the removed scheduled-check-in worker. | Archive/strip retired operational fields only after confirming no old-client writer remains. Keep useful historical evidence if wanted. | An old timestamp can be intentionally retained for debugging even without an active reader. |
| C9 | Migration/provenance-only fields | `users.sosAlertReferencesMigratedAt*`, `teamHikeSessions.sharedHikePlanRedactedAt*`, and trail import/image-curation timestamps and versions are mostly maintenance provenance. | Keep by default, or move provenance to an archive if minimal live documents are desired. | They are not active UI inputs, but help migrations and future maintenance; savings are small. |
| C10 | Write-only latest SOS test summary | One user has `latest_sos_messaging_test` and associated timestamps. `sos_alert_repository.dart` still writes these; no reader was found. | Stop or relocate this diagnostic write if the latest test summary is not needed. | Deleting it alone would let the next test recreate it. |
| C11 | One weather-cache key outside the current trail coordinate set | 1 of 35 coordinate-keyed cache entries does not exactly match a current trail's rounded coordinates. | Check upcoming/active weather consumers and prior trail edits before deciding to expire it. | The cache is keyed by coordinates, **not trail ID**; other weather consumers may legitimately use the point. |

## D. Duplication worth redesigning for performance

### D1. Weather forecasts are duplicated and rewritten unnecessarily

All 35 trail documents carry full `weather` maps. These total approximately **1,849,165 REST JSON bytes**. The 35 `trailWeatherCache` documents store approximately **1,849,270 bytes** in their weather maps as well.

`functions/trail_weather.js` deliberately caches weather for three hours using a refresh lease. However, `fetchWeatherForAllTrails` runs hourly and unconditionally updates every trail after retrieving the cache result. When the cache returns the same forecast, that trail update is redundant. `fetchWeatherForTrail` also unconditionally writes the returned forecast.

With 35 valid trails and 24 successful hourly runs, the scheduler attempts roughly **840 trail-document updates per day**. If only eight three-hour forecast refreshes per day require new snapshots, avoiding identical writes could reduce that to roughly 280. This is an illustration from current trail count/cache lifetime, not a billing measurement or guarantee; on-demand refreshes, errors and timestamps affect actual totals.

Recommended order: first skip writes when the forecast version/cache timestamp has not changed. Then consider keeping a compact weather summary on the trail and loading detailed hourly/daily data on demand. Preserve offline forecasts, precaution rules, map forecasts and hike briefings during that migration.

Sources: `functions/index.js:9604`, `functions/index.js:9715`, `functions/trail_weather.js`, `lib/trail/Model/trail_models.dart`, `lib/trail/View/trail_page.dart`.

### D2. User token/profile fields duplicate values but have active consumers

Both current user documents contain a token map, token array, `activeFcmToken` and `lastFcmToken`; each currently refers to the same device token. Both also duplicate the username at the top level and in `profile.username`.

This is a normalization opportunity, **not safe immediate deletion**. `latestFcmTokensForUser()` still has fallbacks for the various token forms, and Flutter token registration/unregistration updates them. A migration could make `fcmTokenByAppId` the canonical device representation, project the active token when needed, and eventually remove compatibility fields after a supported-client transition. Keep notification delivery working throughout.

Sources: `functions/index.js:680`, `lib/app/Data/hiker_circle_firebase_repository.dart:606`, `lib/app/Data/firebase_user_repository.dart`.

The previously bulky `latest_sos_alert` / `sos_alerts` copies are **absent from both user documents**. The user-to-canonical-SOS reference migration is working and should not be reversed.

### D3. Hike snapshots and telemetry have overlapping data

The 96 hike-session documents contain about **633,305 REST JSON bytes** of `trail` snapshots; checkpoint snapshots contribute another 116,652 bytes. There are also 51 route captures and 559 raw location points.

Historical trail snapshots preserve what the hiker used at the time; simply replacing them with a live trail reference would make history change when a trail is edited. Recorded route captures can be downsampled, whereas raw location points retain individual observations. `hike_history_helpers.js` prefers captured routes and uses telemetry as a fallback. Both datasets are actively read.

A future compact historical projection could keep stable trail identity, geometry version/reference, necessary checkpoint definitions and summary fields while excluding large mutable forecast data. Raw route-point retention would need a separate archival policy that preserves checkpoint timing, pace, group simulations, map accuracy, offline completion and network history. This review found no missing parent session for any of the inspected 51 captures, 559 points, 59 network observations or 28 check-ins.

### D4. Terminal/tombstone documents remain in whole-collection scans

`processUpcomingHikeOperations` reads all upcoming hikes every five minutes; all four current documents are already tombstones. `cleanExpiredGroupChatsTask` queries group chats then skips `isDeleted` records in memory. Counts are small today, but retained tombstones make these scans grow over time.

Selective queries and a controlled archival policy would avoid repeated reads, but must handle legacy missing fields and preserve reminder, invalid-link and chat-history behavior. No scheduler combination/removal is recommended merely on the basis of this snapshot.

### D5. Two overlapping Firebase rules-test environments

`firebase_rules_tests/` and `test/firebase/` maintain separate Node manifests and Firebase/rules-testing versions. The former covers broader security rules; the latter has focused feedback tests. Consolidating their tooling/configuration could reduce repeated installs and version drift while **retaining both test sets**.

`functions/package.json` additionally declares `@firebase/app` and `@firebase/app-compat`, although no backend runtime import was found. These are candidates for dependency-tree review, not confirmed removals: the installed local tree did not expose them to `npm explain`, while the lockfile lists them. Inspect a clean locked install and peer/transitive constraints before changing the manifest. No unused Flutter package was confirmed after accounting for Cupertino's font package.

## E. Parts that should be kept

| Part | Reason |
|---|---|
| All 35 trails and 35 detailed `routeGeometry` documents | Current catalogue and exact route rendering; no geometry orphan found. Compact polylines and detailed points serve different consumers. |
| All currently referenced Storage objects | Every one of the 57 objects has a Firestore/Auth/manifest reference. There are no retired first-aid video objects remaining. |
| `sosAlerts` | Canonical safety history: 141 events. Successful, failed and no-contact events all explain past SOS behavior. |
| `sosWhatsAppDispatches` and `liveLocationContactDispatches` | Delivery ledgers guard against duplicate sending and preserve delivery evidence. They are not interchangeable with display logs. |
| `whatsAppMessageLogs` | User-visible messaging history. Similar information in a server ledger does not make this collection disposable. |
| Achievement and comment-counter receipts | Replay/idempotency evidence. The current comment counter uses reconciliation, but old receipts need an explicit replay/retention decision rather than generic deletion. |
| `hikeSessionTerminalStates` | Completion/deletion reconciliation and achievement idempotency. |
| `localLocationPoints`, route captures, check-ins, network observations | Actively used history/route data, with no verified parent-session orphans. |
| SQLite outboxes, pending hike ends, queued alerts and cached entities | Durable retries and offline behavior. A local copy alongside Firebase is intentional. |
| SQLite device notifications | Required locally retained notification history; independent of FCM delivery work-state. |
| SOS alarms, Bluetooth discovery animation, primary loader and GIF | Current app/native runtime references found. |
| Multi-provider route services | Referenced by route fallback/enrichment; the Mapbox renderer and external data providers have different jobs. |
| Server timestamps and `...Local` timestamp mirrors | Used for ordering, callable serialization and cross-platform/offline parsing. Not blanket duplicate-field cleanup candidates. |
| `isVerifiedTrail` | Still used by admin management, catalogue ordering/filtering and statistics even though a particular detail-page pill was removed. |
| First-aid cache retirement code | Removes files left by older builds; preserve during the upgrade window even though current guides have no videos. |
| The 6 current scheduled jobs and 13 composite indexes | Source/job inventories match and index definitions match. No stale deployed scheduler or index was confirmed. |

The two-region function layout is not proof of duplicate deployments: this snapshot has 85 unique function names with 85 source exports, rather than duplicate copies of the same named function across regions. Matching inventory is not a complete deployment freshness audit.

## Recommended review order

1. **A: confirmed dead code/packaging.** Five disconnected files, obsolete no-op APIs, dead weather code, unreachable auth bodies, and unnecessary bundling. Keep rejection stubs, launcher/Hosting source assets and tool-only helpers as appropriate.
2. **B: conservative transient cleanup.** Review the 39 expired/terminal/orphan candidates and 10 old Hosting versions. Back up exact selected targets before any future deletion.
3. **C6/C7: consistency repairs.** Reconcile stale active teams and legacy chat receipt fields before removing anything involved.
4. **D1: weather write deduplication.** This has the clearest performance/write-reduction benefit without initially changing the storage contract.
5. **C/D: broader archival and normalization.** Make a deliberate decision about saved teams, offline-map feature plumbing, chat/upcoming tombstones, bulky forecasts and device-token compatibility.

## Appendix A: methods with no production caller found

These are candidate methods, not an instruction to delete whole classes or tables. Names may appear in tests/tools. Methods reachable only through the disconnected files in A1/A2 are separately covered there.

| File | Method(s) | Review classification |
|---|---|---|
| `lib/assistant/Data/hiker_circle_assistant_history_store.dart` | `waitForCloudSync` | Test synchronization helper; keep unless the test design changes. |
| `lib/core/services/static_hazard_dataset_service.dart` | `loadSummary`, `downloadForTrails` | Bulk download is used by audit tooling/tests; retain that supported workflow. |
| `lib/core/services/mapbox_optimization_service.dart` | `optimizeWalkingRoute` | Old reorderable optimization path, test-only. App uses `walkingRouteInOrder`. Consider retiring just this method and its obsolete tests. |
| `lib/app/Data/local_session_database.dart` | `clearSession` | Legacy broad cleanup API; current sign-out uses `clearUserSessionOnly`. Review before removal. |
| same | `saveCachedEntities` | Test-covered bulk helper; not an unused cache table. |
| same | `upsertOfflineMapRegion`, `loadOfflineMapRegions`, `loadOfflineMapRegion`, `deleteOfflineMapRegion` | Dormant offline-map feature APIs; C3 applies. |
| same | `deleteSyncedLocationPoints`, `clearCompletedHikeTelemetry`, `discardHikeTrackingTelemetry` | Retention/cleanup helpers, some test-covered; an absent caller is not approval to delete telemetry. |
| same | `updatePendingFirestoreDocId`, `markPendingMessageSent`, `deletePendingMessage`, `countPendingMessages`, `deleteChatData` | Legacy chat/outbox helpers; active alternative status APIs exist. Keep pending-message storage. |
| same | `deleteRouteCacheForTrail`, `clearAllRouteCache` | Cache maintenance helpers; either expose a supported maintenance route or retire the unused APIs. |
| `lib/app/Data/hiker_circle_firebase_repository.dart` | `refreshTrailWeather` | Old wrapper/fallback; UI currently calls `refreshTrailWeatherViaCloud`. |
| same | `ensureTrailSeeds`, `deleteLegacyFirebaseDummyData` | Obsolete seeding/manual dummy cleanup. Never execute the destructive dummy-cleanup method as part of this review. |
| same | `attachActiveHikeToTeamSession` | Old attachment entry; inspect backend-managed team/session linkage before retiring. |
| same | `recordCheckIn` | Unused alternate callable/outbox writer; keep current active check-in path and persisted retries. |
| same | `recordOfflineMapDownloaded`, `loadTeamSchedules` | Dormant legacy features; C2/C3 apply. |
| same | `loadHazardReports`, `loadAdminWhatsAppMessageLogs` | Unused load variants; keep hazard moderation/SOS data and active admin loaders. |
| same | `awardAchievement`, `recordAchievementMetricForUserId` | Empty unused methods. |
| same | `queueSosPayload` | Alternate unused queue writer. Retain active SOS retry/dispatch implementations and queued records. |
| `lib/home/View/hiker_home_page.dart` | `openJoinTeamHike` | Obsolete navigation helper with no caller; current invitation navigation is separate. |

## Appendix B: complete live root collection inventory

| Collection | Documents | Classification in this review |
|---|---:|---|
| `achievementEventReceipts` | 56 | Keep idempotency receipts; explicit retention only. |
| `achievements` | 24 | Active catalogue. |
| `activeHikeStartRateLimits` | 1 | B7: stale counter. |
| `appFeedback` | 2 | Active feedback/history. |
| `assistantUsage` | 2 | Assistant quota counters; keep enforcement, consider rolling retention later. |
| `checkIns` | 28 | Active hike history. |
| `communityCounterEventReceipts` | 1 | Replay/provenance retention decision. |
| `communityPosts` | 3 | Active user content. |
| `downloadedMaps` | 2 | C3: dormant legacy metadata. |
| `fcmOutbox` | 17 | B6: 14 old terminal records; keep newer/durable work. |
| `greenApiLoginChallenges` | 2 | B1: expired/consumed. |
| `groupChats` | 50 | Active/history plus C5/C7. |
| `hazardReports` | 2 | Active moderated hazard data. |
| `hikeCompletionRateLimits` | 1 | B7: stale counter. |
| `hikePrecautionDeliveries` | 7 | Notification deduplication; design retention with hike lifecycle. |
| `hikeRouteCaptures` | 51 | Active recorded history/routes. |
| `hikeSessionTerminalStates` | 11 | Completion/idempotency records. |
| `hikeSessions` | 96 | 67 completed, 29 abandoned; history, not disposable. |
| `liveLocationContactDispatches` | 4 | Delivery ledger/history. |
| `live_location_shares` | 1 | B5: expired link. |
| `localLocationPoints` | 559 | Actual recorded locations; keep. |
| `maintenanceState` | 1 | C1: old migration cursor. |
| `nearbySosIncidents` | 6 | SOS history/evidence; do not infer that old `active` labels imply live emergencies. |
| `networkObservations` | 59 | Route/network history. |
| `passwordResetChallenges` | 1 | B2: expired/consumed. |
| `passwordResetPasskeyChallenges` | 6 | B4: expired. |
| `passwordResetSessions` | 5 | B3: expired. |
| `sosAlerts` | 141 | Canonical SOS history. |
| `sosMessageRateLimits` | 1 | B7: stale counter. |
| `sosWhatsAppDispatches` | 61 | Delivery ledger/history. |
| `teamHikeActionRateLimits` | 3 | B7: stale counters. |
| `teamHikeSessions` | 30 | Active/history plus C6 stale phase repair. |
| `teams` | 1 | C2: old unused saved-team model. |
| `trailWeatherCache` | 35 | Active cache/lease; D1/C11. |
| `trails` | 35 | Active catalogue. |
| `upcomingHikeJoinRequests` | 2 | Accepted request/history and link state. |
| `upcomingHikeRateLimits` | 2 | B7: stale counters. |
| `upcomingHikes` | 4 | C4: soft-deleted tombstones/plans. |
| `userAchievements` | 38 | Active achievement progress/history. |
| `users` | 2 | Active profiles/auth settings; D2 normalization candidates. |
| `whatsAppMessageLogs` | 49 | User-visible messaging history. |

Subcollections: `authFactors` 3; `comments` 0; `messages` 151; `ratings` 2; `reminderPreferences` 7; `reports` 6; `routeGeometry` 35. Only the two reminder preferences had missing parents in the inspected relationships.

## Reproducibility

- Read-only metadata utility: `node scripts/audit_redundancy_review.cjs --discover`.
- Conservative existing dry run: `node scripts/cleanup_firebase_data.js` **without `--apply`**.
- Detailed sanitized metadata: `tmp/redundancy-review-audit.json`.
- Existing basic inventory: `tmp/firebase_inventory.json`.
- Application static check performed: `flutter analyze` — passed.

The older `FIREBASE_SCHEMA_AND_CLEANUP.md` and its generator contain historic counts, removed scheduler names, and cleanup statements from earlier snapshots. Keep that file as historical evidence or rewrite it with current facts during the approved documentation cleanup. Re-running its generator blindly would preserve several hard-coded stale claims.

**A and B1–B9 have now been applied as recorded above. C/D remain unexecuted.** Review IDs allow approval of specific groups without treating every older record as unwanted.

# D1–D5 storage normalization and compatibility record

Project: `hiker-circle`. Execution date: 2 October 2026, Asia/Kuala_Lumpur.

This implements the approved D recommendations from `CODEBASE_FIREBASE_REDUNDANCY_REVIEW_2026-10-01.md`. It does not authorize or implement C cleanup, delete hike history, or change SOS retention.

## Implemented changes

| ID | Outcome | Compatibility safeguards |
|---|---|---|
| D1 | Both weather functions skip identical trail-forecast writes. Changed forecasts use a transaction that rejects stale forecasts, deleted trails, and coordinate changes. | Full live trail weather, provider cache, refresh leases, offline forecasts and precaution inputs remain unchanged. Detailed live forecasts have not been replaced by a summary-only contract. |
| D2 | `fcmTokenByAppId` is canonical, with `fcmTokenSchemaVersion: 2`. Registration and revocation are atomic. Backend delivery selects the bound/current device; revoked canonical entries cannot be resurrected by legacy aliases. Profile readers prefer `profile.username`. | Legacy token reads remain for unmigrated accounts. Ambiguous/unbound tokens are not blindly migrated. Top-level `username` remains a small compatibility projection, saved atomically with the profile. Credentials, MFA factors and SOS references are untouched. |
| D3 | Completed sessions keep a compact weather projection; their exact full forecast moves into an immutable private child document. Future online, offline and team completions do the same atomically. | Historical trail name, exact route, checkpoint definitions, summaries, location samples, route captures, check-in timings, pace and team simulation data are preserved. Active/preparation forecasts remain full. Abandoned sessions are not rewritten by this migration. |
| D4 | Upcoming-hike operations query `isDeleted == false`; group-chat cleanup queries `chatType == group` and `isDeleted == false`. Missing legacy flags were backfilled before deploying those queries. All new group-chat/upcoming-hike writers set the appropriate flag. | Tombstones and linked history remain stored. Existing tombstones are not revived just to initialize a flag. Schedules/frequencies and task-combination behavior are unchanged. |
| D5 | Both Firestore/Storage security suites share `firebase_rules_tests`, one pinned dependency tree, demo project and emulator configuration. Retired duplicate manifests were removed; feedback tests were moved, not discarded. | Production dependency versions were not opportunistically upgraded or removed. A fresh locked installation confirmed Firebase Admin's database-compat peer support for `@firebase/app` and `@firebase/app-compat`; both remain. |

## Live migration and evidence

Fresh inventory before migration: 2 users, 96 hike sessions, 6 upcoming hikes and 50 group chats. The migration selected only these field-level changes:

| Change | Count |
|---|---:|
| User token/profile normalization | 1 |
| Completed-session forecast archives and compact projections | 47 |
| Legacy upcoming-hike boolean flag | 1 |
| Legacy group-chat boolean flags | 23 |
| Total updated parent documents | 72 |
| New private forecast archive documents | 47 |
| Deleted documents | 0 |

The other user did not require a safe canonical-token migration. The script does not force a token when the active device cannot be identified safely.

Read-back verified all 72 updates against their inspected masks and original documents. All 47 archive payloads matched the original typed Firestore forecast exactly. No field outside an approved mask changed. A new post-migration dry run found zero remaining eligible D2–D4 candidates.

The moved series reduce parent-document REST JSON representations by 263,189 bytes in this snapshot. This is **not a billing saving or a reduction in total stored data**: the original series remain in archives, with additional archive metadata. The benefit is smaller completed-session payloads, while preserving recovery evidence.

### Private backup and tooling

Recovery manifest and per-record journal:

`tmp/storage-normalization-backup-2026-10-02T07-45-11-812Z/`

- `manifest.json`: exact original typed documents, planned field masks/projections, exact archives and plan SHA-256.
- `results.json`: successful exact-target mutation journal.

These ignored files contain private user data and must not be published. Retain them until validation and rollback needs are satisfied.

Tools:

- `scripts/migrate_storage_normalization.cjs`: read-only by default. Apply requires an explicit inspected plan no older than one hour. Updates have document-update-time preconditions; archive creation has an `exists: false` precondition. A parent and its archive are committed together. Concurrently changed parents are preserved, not overwritten.
- `scripts/verify_storage_normalization.cjs`: independent read-only comparison of migrated fields, exact archives, and all untouched fields against the private backup. Document path segments are encoded, including phone-number IDs.

Do not blindly restore an entire user/hike document from a backup over newer app activity. Any rollback must compare current update times and restore only the intended fields. An archive must be validated before rehydrating a forecast. Keep the archive rather than deleting it as a side effect of rollback.

## New and retained schema contracts

### `users/{userId}`

- `fcmTokenByAppId`: map of app-instance ID to device token.
- `fcmTokenSchemaVersion`: integer `2` for canonical-token semantics.
- Existing binding/active-app identity fields continue to select the correct device.
- `profile.username`: preferred display name.
- `username`: retained compatibility projection, not a second independent profile.
- Legacy `fcmTokens`, `activeFcmToken`, `lastFcmToken`: removed only when a safe canonical entry exists. Legacy readers remain for unmigrated accounts.

### `hikeSessions/{sessionId}`

- Existing history/telemetry fields retain their original meaning.
- `trail.weather`: current/summary weather fields and non-series forecast metadata. Completed projections omit `hourlyForecast`, `dailyForecast`, and `forecastData.hourly`/`forecastData.daily`.
- `trailSnapshotVersion`: integer `2` when a forecast has been archived.
- `trailForecastArchivePath`: relative Firestore path to the private sidecar.

### `hikeSessions/{sessionId}/snapshotArchives/trailForecast`

- `schemaVersion`: integer `1`.
- `weather`: original complete weather snapshot.
- `archivedAtLocal`: ISO timestamp of archival.

Mobile reads/writes/deletes are denied, including mobile admin accounts. Backend IAM-authorized maintenance can read the recovery archive. Existing authorized parent-history reads remain allowed. The app must never download this archive merely to render history.

### Maintenance flags and index

- `upcomingHikes.isDeleted`: explicit boolean; missing legacy flags were inferred from existing deletion/expiry markers without changing already-boolean flags.
- `groupChats.isDeleted`: explicit boolean on new chats, preserving existing tombstones.
- New composite index: collection `groupChats`, `chatType ASC`, `isDeleted ASC`. Confirmed `READY` before narrower queries were deployed. Existing indexes remain.

## Rollout order

1. Test normalization helpers and preserved history contracts.
2. Deploy archive-denial rules and the new index.
3. Deploy upcoming/join/completion writers.
4. Refresh and inspect the migration plan; back up exact targets; apply guarded mutations.
5. Verify every mutation and archive; confirm zero remaining candidates.
6. Deploy affected readers/delivery/weather functions and narrower maintenance queries.
7. Re-audit every chat creation path; ensure new active-team chats carry the flag and preserve existing tombstones.

Storage rules and Hosting were not changed by D. No endpoint was removed, no new scheduled job was added, and no emergency/test notification was deliberately sent to a real person for validation.

## Validation and limits

- All **144 backend regression tests** passed against Node.js 22 and a fresh locked dependency installation. They cover write deduplication/races, revoked-token behavior, legacy fallback, canonical names, history equivalence, online/offline/team completion archive idempotency, and chat creation flags.
- Unified emulators passed 30 general security groups and 5 feedback tests, including owner-only atomic token updates and backend-only archive access.
- Migration unit tests passed all 6 cases; independent live verification passed all 72 parents and 47 archives.
- Flutter analysis passed with no issues. Compact historical weather explicitly parses without fabricating unavailable hourly data; route/checkpoint fields remain intact.
- Android release compilation succeeded. Existing liquid-glass shader fallback/plugin warnings remain outside D scope.
- The broad parallel Flutter test run encountered the pre-existing Windows temporary-directory teardown race in `live_location_stop_test.dart`; that suite passed all 5 tests in isolation. The final serial application run passed **all 517 tests**, including every application test directory and both root test files. Separate unrelated website tests are not part of this application run.

These checks reduce regression risk; they are not a guarantee that no exception can ever occur on a real device. Physical Android/iOS multi-account login, notification delivery, offline hike completion and history smoke tests remain useful. An iOS release build cannot be verified on this Windows host.

### Final deployment and verification status

The rollout completed successfully: **27 distinct affected functions** were deployed, using Node.js 22 across their existing `us-central1` and `asia-southeast1` regions. Firestore rules and indexes were deployed successfully; the new index was confirmed ready. No blanket redeployment of unrelated functions was performed.

Independent Cloud Functions inventory confirmed all 27 targets present, `ACTIVE`, and using `nodejs22`. Read-only production executions of both new maintenance query shapes succeeded (1 non-deleted upcoming hike and 13 non-deleted group chats at verification time); counts naturally change with lifecycle activity.

Deployment groups:

- Initial writers: `scheduleUpcomingHike`, `joinUpcomingHike`, `resolveUpcomingHikeJoinRequest`, `completeActiveHikeSession`.
- Readers/delivery/maintenance: `notifyEmergencyContactsOfLiveLocation`, `manageBuddyRequest`, `requestToJoinUpcomingHike`, `loadUpcomingHikeJoinRequest`, `loadPublicHikerProfile`, `getPublicProfiles`, `openDirectChat`, `deleteChatForUser`, `createTeamHikeSession`, `manageTeamHikeSession`, `remindUpcomingHikeHost`, `notifyHostAboutUpcomingHikeJoinRequest`, `fetchWeatherForAllTrails`, `fetchWeatherForTrail`, `processUpcomingHikeOperations`, `cleanExpiredTeamAndGroupChats`, `notifyGroupMembersAboutMessage`, `deliverFcmOutboxMessage`, `recoverFcmOutboxDeliveries`, `notifyNearbyHikersAboutUpcomingHike`.
- Final team-writer guard rollout: `scheduleUpcomingHike`, `createTeamHikeSession`, `manageTeamHikeSession`, `cleanExpiredTeamAndGroupChats`, `awardAchievementsForStartedHike`, `recordHikeTerminalStateAndAchievements`, `monitorActiveHikes`. Four overlap earlier groups; three add the remaining callers of the shared team-chat writer.

Final evidence logs (ignored local files): `tmp/d-final-backend-tests.log`, `tmp/d-app-tests-serial.log`, `tmp/d-rules-resume-tests.log`, `tmp/d-final-analyze.log`, `tmp/d-final-release-build.log`, `tmp/d-writers-deploy.log`, `tmp/d-backend-deploy.log`, `tmp/d-team-writer-deploy.log`, `tmp/d-firestore-deploy.log`. Post-migration plan: `tmp/d-storage-normalization-post-plan.json`.

The final Android artifact is `build/app/outputs/flutter-apk/app-release.apk` (174,703,131 bytes). It was built, not installed on a device during this task.

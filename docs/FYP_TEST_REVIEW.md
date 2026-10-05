# HikerCircle code review for final-year-project testing

Reviewed 1 October 2026 (Malaysia time). Companion checklist: [FYP_TEST_PLAN.md](FYP_TEST_PLAN.md).

## Outcome and scope

The checklist contains **414 identified cases**: 154 P0, 249 P1 and 11 P2. There are 36 dedicated offline/reconciliation cases, plus offline variants in auth, routes, weather, contacts, SOS, BLE, live sharing, chat, guidance, assistant history, QR scanning and the notification inbox. Cases with multiple boundary values/platforms require separate executions; 414 is the count of case IDs, not the eventual number of test runs or a coverage percentage.

Static inspection covered Flutter entry points/view models/repositories/models, SQLite tables and migrations, Firebase callable/trigger/helper surfaces, security rules, native Android/iOS safety and BLE code, widget/platform declarations, hosted pages, existing regression tests and feature documents. The current working-tree code was the authority where older documents disagreed. No installed/deployed build, native hardware reliability, real provider delivery or production security behavior was verified by static inspection.

Baseline Git HEAD: `c8e291502fc3f2330aa0a759e778dff69ecec0bc`. The checkout was already dirty in assistant/profile files and contained an unrelated audit script. These were preserved. Other work can change the shared checkout; pin the final build and repeat verification before submission.

## Automated verification actually executed

| Suite | Command | Observed result | What this establishes |
|---|---|---|---|
| Flutter | `flutter test --reporter compact` | **516 passed, 4 failed** | Existing unit/widget/source-assertion suite on this Windows checkout; not device end-to-end coverage |
| Backend | `npm --prefix functions test` | **130 passed, 0 failed** | Current Node test suite, including helper/transaction regressions; not a deployment/provider test |
| Import/route scripts | `node --test scripts/test` | **18 passed, 0 failed** | Current local script tests |
| Targeted sharing retest | `flutter test test/me/live_location_stop_test.dart --reporter expanded` | **4 passed, 1 failed** | Same Windows cleanup failure reproduced; this is a subset rerun, not five additional independent full-suite cases |
| Firestore/Storage emulator rules | Not executed | **Unverified** | Broad rules package lacks installed dependencies; detected Java is17, while repository instructions require a Java21 JDK. Feedback-only package dependencies are present, but its emulator suite was not run. |
| Real-device/manual checklist | Not executed | **All checklist runs initially Not run** | Requires the actual phones, button firmware, test accounts/recipients and controlled backend fixtures |

The shell logging commands printed the tail after execution; use test-runner results above rather than the wrapper shell's final exit status. Raw logs were captured in the Windows temporary directory as `hiker-circle-flutter-test-20261001.log`, `hiker-circle-functions-test-20261001.log`, `hiker-circle-scripts-test-20261001.log`, and `hiker-circle-sharing-retest-20261001.log`. The findings below preserve the important results even if temporary logs are removed.

## Four full-suite failures

| Test | Evidence and interpretation | Required follow-up |
|---|---|---|
| `test/ios/active_hike_restore_startup_regression_test.dart` — Flutter reconciles and awaits stale native monitoring shutdown | Exact `contains` assertion expects LF in a multiline source fragment. Current home source uses CRLF. The expected fragment is absent raw and present after CRLF→LF normalization. Inspection also found the awaited native stop in the no-restored-hike branch. This particular failure does **not** demonstrate broken native shutdown. | Normalize line endings in the test or use a behavioral assertion; independently run END-12/HIKE-20/LIFE-12 on phones. |
| `test/me/live_location_stop_test.dart` — stop invalidates a busy load and keeps stale result inactive | `FileSystemException: Deletion failed ... (OS Error: The directory is not empty, errno =145)` in teardown at line27, after database close. Reproduced in targeted run. No failed inactivity assertion was reported for this case. The precise background-write/handle cause was not established. | Investigate outstanding async database work and teardown lifetime; do not dismiss repeated cleanup failure or call it a proven live-sharing privacy defect. Run SHARE-06/OFF-24/25 physically. |
| `test/web/landing_site_content_test.dart` — complete evolution timeline | Expected13 `data-evolution-card` occurrences; current source has14. This is a source-content contract failure. | Reconcile current intended timeline content with assertion; inspect UI through WEB-02. |
| `test/web/landing_site_content_test.dart` — pointer/keyboard/touch scrolling | Exact source assertion expects `border-style: dashed`; current stylesheet does not contain it. | Decide intended style/content contract and adjust implementation/test accordingly; verify actual pointer/keyboard/touch behavior separately. |

No source or test fixes were made as part of this analysis request. Avoid saying “all automated tests pass” in the report or examination until these failures are resolved and rerun.

## Findings that deserve attention before the examination

### 1. Offline map guarantee is not supported by the inspected flow

The source has `downloaded_maps`/`offline_map_regions`, model flags and `recordOfflineMapDownloaded`, plus older text pointing to a Malaysia download. A search of current Dart/native source found no current Mapbox tile/style download call or visible downloader implementation. Assistant code explicitly excludes the `offline_maps` action. An unused record/flag/MBTiles path is not proof of downloaded tiles.

Route geometry, hazard matches and a warm SDK map cache are separate resources. Opening a previously visible map without internet does not establish coverage at another zoom, style, region, or after process restart. Highest-value tests: ROUTE-12/13, OFF-07/08 and offline demo D. Record available behavior; repair or explain stale download guidance before presenting it as a supported feature.

Anchors: `lib/trail/View/trail_page.dart`, `lib/app/Data/local_session_database.dart`, `lib/app/Data/hiker_circle_firebase_repository.dart`, `lib/assistant/Data/hiker_circle_assistant_repository.dart`, `lib/core/widgets/route_preview_map.dart`.

### 2. Network status is weaker than service reachability

`NetworkReachabilityService` checks interface availability and resolves `firestore.googleapis.com`. DNS timeout is2 s and refresh is15 s. A captive portal, selectively blocked HTTPS, backend permission failure, unavailable callable or provider can exist while DNS resolves. UI/server acknowledgements and durable pending state must govern save/send confirmation.

Highest-value tests: OFF-03/04/05/06, SOS-12/13, END-03/04 and FEEDBACK-03. This is a limitation of the online heuristic, not evidence every write path mishandles it.

Anchor: `lib/core/services/network_reachability_service.dart`.

### 3. Background safety claims need current platform-specific evidence

Older README text says active-hike location and detection run only in Flutter. Current code includes Android `HikeSafetyMonitorService`, boot restoration, native location buffers and a headless Flutter SOS path. iOS `IOSHikeSafetyMonitor` has Core Motion/Core Location and persistent native buffers. Both current native paths target5 s location sampling, with upload cadence separately configured; an older SOS document says30 s on Android.

These implementations improve capability but do not prove all OS/vendor suspension behavior. iOS escalation reaches `ready_for_flutter_dispatch`; app availability is still relevant to the inspected messaging path. Force-stop/force-quit must remain distinct from backgrounding/swiping. Highest-value tests: LIFE-01–06/10/12/13, HIKE-20 and BLE-18. Document observed sample gaps/output/dispatch timings by actual platform and signing.

Anchors: Android `HikeSafetyMonitorService.kt`, `HikeSafetyMonitorBootReceiver.kt`, `NativeLocationSampleBuffer.kt`; iOS `AppDelegate.swift`, `NativeLocationSampleBuffer.swift`; `lib/home/ModelView/hike_safety_background_dispatcher.dart`.

### 4. A queued or sounding SOS is not accepted contact delivery

SOS persists retry intent before attempting dispatch, but local persistence can fail while immediate sending is still attempted. Per-contact successes/failures/uncertainty must remain separate. A client deadline can expire while the server/provider request continues. Server dispatch identity, payload binding, leases and provider classifier are intended to prevent duplicate/uncertain blind resends.

The queue can become terminal without every recipient accepting; removing pending work is not equivalent to delivered WhatsApp. A log-write failure after acceptance can require reconciliation without resending successful recipients. No automatic emergency-service connection was established. Highest-value tests: SOS-06/09–18, OFF-15/16/18 and SEC-05/09.

Anchors: `lib/sos/Data/sos_alert_repository.dart`, `lib/sos/ModelView/sos_view_model.dart`, `functions/sos_dispatch_helpers.js`, `functions/index.js` SOS callable.

### 5. Completion/start acknowledgement loss is a core demo risk

Start waits2 s before returning a local session on timeout. Completion uses45 s because the cloud may already commit before slower achievement work returns. Local/canonical IDs, sample identities, original end time and dependent records must reconcile; an unresolved ACK is not proof the operation was rejected or the device was offline.

Location uploads are bounded at200 samples and only acknowledged sample times may be marked synced. Repeated coordinates are valid distinct stationary samples. Highest-value tests: HIKE-03/08/11/12/19, END-02–04/13, OFF-10–14 and TEAM-12/16.

Anchors: repository active-hike create/restore/end/flush methods; `lib/app/Data/hike_completion_request.dart`; `functions/location_batch.js`; `docs/HIKE_COMPLETION_SYNC.md`.

### 6. Preparation rules are precise and dynamic

The guided gear gate is richer than a generic checklist. Required equipment depends on positive trail-local daytime overlap, <15°C fresh session sample, >50% rain/positive precipitation/rain code, and usable rough/muddy terrain analysis. Weather precaution thresholds differ (for example rain probability≥60%). Each participant's pack is independent; new forecast/route results arriving during a save can add requirements.

Equipment checkboxes express user's answers, not verified physical possession. The app gate is not an identical deployed server policy. Highest-value tests: PREP-01/04–13/16, PLAN-05/06 and WEATHER-07/08/09.

Anchors: `lib/home/Model/trail_gear_plan.dart`, `lib/home/View/final_preparation_review_page.dart`, `lib/home/Model/solo_hike_policy.dart`.

### 7. Owner isolation and offline stop intent need concurrency testing

SQLite scopes queues, preferences, contacts, history caches and messages by owner; several async operations capture account/generation guards. Signing out must not allow A's pending work to send under B. Live-share stop immediately disables local publication and persists a pending cloud stop; a recipient can still see the last cloud state until deactivation reaches the server. An older ACK must not clear a newer stop.

Highest-value tests: AUTH-18/19, OFF-18/19/24/25, SHARE-06/11 and AI-10/11. The helper tests are useful but cannot substitute for two-account, two-device evidence.

Anchors: `session_repository.dart`, `local_session_database.dart`, repository upload/message/outbox methods, `live_location_repository.dart`, `live_location_sharing_service.dart`, assistant history store.

### 8. Pairing and nearby observation have different trust boundaries

Owner-button events use pairing secret/authentication/counters. Secure firmware GATT is required for initial secret exchange. iOS lacks direct bond-state visibility, so firmware security flags matter. A nearby unpaired observer's type-5 location report is explicitly unverified. Legacy unauthenticated team-location advertisements cannot be treated as authoritative member locations.

Pairing, ownership switch, replay, maintenance logs, armed tests and force-stop are separate scenarios. Android BLE and hike-safety alert code use4213 notification paths, so simultaneous warning/press interactions need actual device checks. Highest-value tests: BLE-01–08/11/12/15/16/18/19 and LIFE-18.

Anchors: native BLE bridges/paired registries, `lib/core/services/hiker_ble_service.dart`, `docs/CUSTOM_SOS_BLE_PROTOCOL.md`.

### 9. Existing automation does not establish deployed security or hardware coverage

The repository has many valuable widget/helper tests and some exact-source assertions. No dedicated Flutter `integration_test` harness was found in the inspected project inventory. Rules tests exist but were not run in this review; pure Node helpers do not prove the actual deployed callable or provider configuration. Entitlements and manifests are not permission grants.

Personal Team iOS differs from Android/paid iOS for native passkeys, remote APNs notifications and Time Sensitive behavior. Evaluate the actual signing/version configuration. Highest-value tests: SEC-01–12, MFA-04/05/16, SETTINGS-04–06 and UX-07.

## Running the remaining automated suites

Run from the project root on a supported test setup; no deployment command is needed:

```powershell
flutter test --reporter expanded
npm --prefix functions test
node --test scripts/test
```

For the broad rule suite, follow `firebase_rules_tests/README.md`: install its pinned dependencies, select an actual Java21 JDK, and use an explicitly named **demo** project:

```powershell
npm --prefix firebase_rules_tests ci
$env:JAVA_HOME = '<absolute path to Java 21 JDK>'
firebase emulators:exec --config firebase.feedback-test.json --only firestore,storage --project demo-hiker-circle "npm --prefix firebase_rules_tests test"
```

The feedback rules suite shares the unified `firebase_rules_tests` dependencies and Firestore8181/Storage9199 configuration. To run only that suite inside the emulators:

```powershell
firebase emulators:exec --config firebase.feedback-test.json --only firestore,storage --project demo-hiker-circle "npm --prefix firebase_rules_tests run test:feedback"
```

Use emulator/provider-stub fixtures for invalid signatures, ambiguous writes, rate limits, expired triggers and sensor thresholds. Do not manually rewrite production data or send genuine emergency traffic to achieve checklist coverage.

## What to establish before presenting

1. Resolve/record the four automated failures and rerun the exact final checkout.
2. Execute core identity/preparation/start/end/SOS tests on the submitted release.
3. Complete the offline journeys, particularly restart+end+reconnect and account isolation.
4. Complete two-device team/share/chat cases and actual paired-button lifecycle cases.
5. Verify rules in the demo emulator and the intended deployment/configuration separately.
6. Keep a completed result record and short evidence clips, with actual observed limitations. A checked requirement, foreground service declaration, queue count or green mock test alone is not end-to-end evidence.

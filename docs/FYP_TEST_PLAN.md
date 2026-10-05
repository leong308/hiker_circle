# HikerCircle final-year-project test plan

Prepared 1 October 2026 (Malaysia time), from the current working tree.

**414 cases across 24 sections:** 154 critical P0, 249 P1 and 11 extended P2. Boundary/platform variants expand the number of actual runs.

This is a source-grounded test specification, not a claim that the manual cases passed. It covers the Flutter app, Android/iOS native services, Firebase functions and security rules, hosted pages, and physical-button integration. Existing uncommitted assistant/profile changes were included in the inspection. No production data was changed and no messages were sent during this review.

## How to use this plan

Each case has a stable ID, priority, execution method, setup/action, and observable expected result. Record each run in the result template at the end. Cases containing several boundary values require a separate result for each value. A single successful screenshot does not pass the other variants.

- **P0:** run before the examination; identity/privacy, hike lifecycle, offline recovery, SOS, and core demo gates.
- **P1:** run before final submission; major features, validation, failure handling, and multi-user interactions.
- **P2:** extended compatibility, presentation, load, and optional administration/website cases.
- **M:** manual UI test on a real device, including a second device/browser where stated.
- **H:** physical device/button/OS lifecycle test. An emulator or mocked widget test is insufficient.
- **I:** injected service response, clock, storage failure, or deterministic automated integration/unit test. Use a test build or emulator, never edit live user records to create these conditions.
- **S:** security rules/callable test with authenticated owner/member/outsider/admin contexts in a demo-project emulator.

Common defaults: signed-in completed profile A; stable internet; valid three-checkpoint trail T with known stored route; A has test-owned contact numbers. B is a second hiker; C is an outsider; D is an administrator with a server-issued claim. Override these defaults where a row says otherwise. Destructive reset/corruption tests use disposable test data. Message cases use controlled recipients or a provider stub; never call emergency numbers during a demo. The WhatsApp test function is explicitly labelled as a test, but production-mode behavior still needs stubbed or controlled-recipient tests.

**Suggested order:** P0 cases → the offline journeys → multi-user/team cases → all P1 cases → P2/device matrix. Start with AUTH, PREP, HIKE, OFF, SOS, LIFE and SEC. Inspect current automated failures in [FYP_TEST_REVIEW.md](FYP_TEST_REVIEW.md) before presenting a green-test claim.

## Test fixtures and evidence

Prepare A/B/C/D, a paired owner button and an unpaired observer phone. Have an Android phone and an iPhone; record Android version/vendor, iOS version, signing type, app version/build, Git commit and whether the checkout is dirty. Prefer the actual release build used at the examination. Run same-platform and Android↔iOS pairs for team/chat/BLE cases. Use a recipient browser with no app login for live-sharing cases.

Prepare trails with: no difficulty votes; mixed votes; short route; distance 10/20 km boundaries; missing geometry; malformed geometry; loop; out-and-back; repeated coordinates; rough/technical/muddy surfaces; water near the route versus a crossing; 499/500/1,000 m ascent; inaccessible starting point; Sabah/Sarawak and Peninsular Malaysia. Prepare forecast fixtures with fresh/stale/missing/partial hourly data and all WEATHER/PREP boundaries. GPS fixtures need stationary valid fixes with new timestamps, poor accuracy, stale fixes, out-of-order fixes, unavailable altitude, and actual movement.

Evidence should pair UI with durable state: local queue count/row identity, server session ID/status, acknowledged sample timestamps, provider-stub dispatch IDs, history/post IDs, recipient view, and elapsed times. Capture failures before resetting the app. Redact phone numbers, precise locations, OTPs, TOTP seeds, pairing secrets, share links and credentials in submitted screenshots.

## Source map and existing regression areas

Paths are relative to the project root. These mappings identify the implementation to investigate, not a coverage percentage.

| Case prefixes | Implementation anchors | Existing test areas |
|---|---|---|
| AUTH, MFA, PROFILE | `lib/authentication/`, `lib/onboarding/`, `lib/app/Data/session_repository.dart`, `firebase_user_repository.dart`; auth/MFA/reset callables in `functions/index.js` | `test/authentication/`, `test/onboarding/`, `test/app/`; `functions/test/*mfa*`, `*password_reset*` |
| TRAIL, ROUTE, WEATHER | `lib/trail/`, `lib/core/services/hiking_route_service.dart`, `trail_geometry_storage.dart`, weather and hazard services | `test/trail/`, `test/core/`; `scripts/test/`; `functions/test/trail_weather.test.js` |
| PLAN, PREP, TEAM | `lib/home/View/start_hike_wizard_page.dart`, `final_preparation_review_page.dart`, `lib/home/Model/trail_gear_plan.dart`, `hike_session_models.dart`; scheduling/team callables | `test/home/`, `functions/test/*upcoming*`, `*team_readiness*`, `*solo_hike*` |
| HIKE, END, OFF, LIFE | `lib/home/View/hiker_home_page.dart`, `lib/app/Data/hiker_circle_firebase_repository.dart`, `local_session_database.dart`, `functions/location_batch.js`; native safety monitors/buffers | `test/home/*active_hike*`, `test/app/`, `test/safety/`, `test/ios/`, `test/local_location_ack_test.dart` |
| SOS, CONTACT, BLE | `lib/sos/`, `lib/core/services/hiker_ble_service.dart`; Android `HikerBleBridge`, `BleSosMonitorService`, `HikeSafetyMonitorService`; iOS `HikerBleBridge.swift`, `AppDelegate.swift`; SOS callable/helpers | `test/sos/`, `test/core/hiker_ble_service_test.dart`, `functions/test/sos_dispatch_helpers.test.js` |
| SHARE | `lib/me/Data/live_location_repository.dart`, `live_location_sharing_service.dart`, `web/live-location.html`, `functions/live_location_share.js` | `test/me/*location*`, `functions/test/live_location_notification_helpers.test.js` |
| CIRCLE, CHAT, COMMUNITY | `lib/circle/`, repository buddy/chat/post/comment methods, `functions/community_comment_counter.js`, FCM outbox | `test/circle/`, `functions/test/transactional_audit_regression.test.js` |
| HISTORY, ACH, HELP, SETTINGS | `lib/me/`, `lib/home/View/first_aid_guide_page.dart`, `lib/app/Data/app_settings_controller.dart`, widget services | `test/me/`, `test/home/*first_aid*`, `*widget*`, `functions/test/achievement_helpers.test.js` |
| AI, FEEDBACK, ADMIN | `lib/assistant/`, `functions/hiker_circle_assistant.js`, `lib/feedback/`, `lib/admin/` | `test/assistant/`, `test/feedback/`, `test/admin/`, `firebase_rules_tests/feedback_rules.test.cjs` |
| SEC, WEB, UX | `firestore.rules`, `storage.rules`, callable authorization, `web/`, manifests/entitlements | `firebase_rules_tests/`, `test/web/`, UI tests |

## Implementation facts that change the expected results

1. **Offline capability is feature-specific.** SQLite caches sessions, contacts, planning state, entities, route data, queued SOS, messages, GPS points and pending hike ends. It cannot make login, provider calls, server-authorized team changes or public live updates work without connectivity. First-install offline use differs from returning to a warmed cache.
2. **Map downloads are not established.** The inspected `lib/` contains legacy map records/flags and text suggesting a download, but no current `OfflineManager`/`TileStore` download implementation was found. The assistant explicitly filters the `offline_maps` action. Cached route geometry and hazard records are separate from basemap tiles/style/fonts. Treat guaranteed downloaded-map coverage as an unsupported claim until a real flow is found and cold-start offline rendering is demonstrated.
3. **Online detection is a DNS heuristic.** `network_reachability_service.dart` resolves `firestore.googleapis.com` with a 2-second timeout and checks every 15 seconds. DNS success does not prove HTTPS, callable, Storage, weather, Mapbox or GreenAPI availability.
4. **Current native safety code supersedes older README wording.** Android has a native foreground safety/location service, persistent buffers and a headless Flutter SOS dispatcher. iOS has native motion/location monitoring and buffers; the inspected automatic SOS escalation still needs available/resumed Flutter. Background modes/receivers express intent, not measured reliability under suspension or force-stop.
5. **Exact business rules:** solo ≤10 km requires no distance acknowledgement; >10 to ≤20 km requires acknowledgement for that distance; >20 km requires a group. The start wizard requires 3–12 checkpoints; the generic route service accepts 2–12. Scheduled starts require at least 10 minutes from now.
6. **Preparation gate:** water, snack and first-aid always; positive overlap with trail-local 08:00–18:00 requires sun protection; fresh overlapping temperature <15°C requires blanket; usable rough/technical analysis requires poles; mud or fresh rain probability >50%, precipitation >0, or code 51–99 requires dry socks and pack rain cover. Weather precautions use different thresholds. The gear gate is an app check, not proof of physically carried items or equivalent server enforcement.
7. **SOS outcomes are separate:** local alarm, durable queue, provider acceptance, recipient receipt, and nearby observation. `sent` establishes provider acceptance, not read receipt/rescue. No automatic emergency-service dispatch was established. Stop alarm cannot recall a sent WhatsApp message.
8. **Timing is path-specific:** manual countdown 10 s; native mobile safety warning 15 s; Dart fallback default response 30 s. Active-hike start callable wait is 2 s; hike completion has a dedicated 45 s deadline. GPS sampling targets 5 s in current native code; upload cadence is separately configured. Test actual timings rather than older documentation values.
9. **Signing matters:** Personal Team iOS gates native passkeys and lacks APNs remote delivery/Time Sensitive capability in this configuration; TOTP and standard local notifications are separate paths. Mark unsupported signing cases N/A with evidence, not passed.

## 1. Startup, identity and authentication

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| AUTH-01 | P0 | M | Fresh install online; open app and complete sign-up with a new controlled phone. | Correct phone→OTP→required security/profile flow; one account; no home access before required steps. |
| AUTH-02 | P0 | M | Returning user; sign in with valid password/WhatsApp OTP and configured second factor. | Correct account and profile; one session; no intermediate unauthenticated data leak. |
| AUTH-03 | P0 | M | Close and reopen with a saved session and internet. | Saved identity loads promptly; bounded cloud refresh; no duplicate onboarding. |
| AUTH-04 | P0 | M | Save session, kill app normally, disconnect and cold launch. | Local session restores without an indefinite cloud wait; cached features usable; unavailable features honest. |
| AUTH-05 | P1 | M | Fresh install with no saved session and no internet; attempt registration/login. | Recoverable connection error; no invented login or cached identity. |
| AUTH-06 | P1 | I | Submit local `012…`, `60…`, `+60…`, spaced/hyphenated/bracketed numbers. | Equivalent valid numbers normalize consistently; same account/contact identity. |
| AUTH-07 | P1 | I | Submit empty, alphabetic, malformed plus, zero-prefix country code, too-short and >15-digit international numbers. | Invalid input blocked; no OTP/provider request for invalid identity. |
| AUTH-08 | P1 | M | Wrong password, unknown phone, existing phone in sign-up, rapid repeated attempts. | Appropriate bounded errors/rate control; no duplicate account or access. |
| AUTH-09 | P1 | I | Passwords length 7/8; omit uppercase/lowercase/digit/special individually. | Each implemented requirement enforced by client and relevant server path. |
| AUTH-10 | P1 | I | Passwords with three sequential digits, four repeated characters, keyboard patterns and banned common terms. | Rejected per current validator; a valid non-pattern password accepted. |
| AUTH-11 | P1 | M | OTP empty/partial/wrong; paste full code; backspace across cells; keyboard submit. | Correct focus/input behavior; malformed/wrong code never authenticates. |
| AUTH-12 | P0 | I | Verify valid OTP, then reuse it; use code from another phone/challenge. | One-time and identity-bound validation; replay/cross-account use denied. |
| AUTH-13 | P1 | I | Verify immediately before/at/after OTP expiry; change device clock. | Server expiry controls validity; client countdown does not bypass it. |
| AUTH-14 | P1 | M | Resend succeeds, then try old/new codes; repeat before allowed cooldown. | New challenge/code policy enforced; cooldown visible; no request storm. |
| AUTH-15 | P1 | I | Fail resend while original challenge is active. | Original challenge stays usable; user remains at OTP entry with error. |
| AUTH-16 | P0 | I | Provider unauthorized/offline, rejected response, successful HTTP without message ID, slow response. | No false claim of OTP delivery; recoverable provider/configuration error. |
| AUTH-17 | P1 | M | Double tap Send/Verify/Login and navigate Back during request. | No duplicate account/session transition; disposed UI not updated. |
| AUTH-18 | P0 | I | Delay saved-profile refresh; sign out before it finishes. | Late refresh cannot restore signed-out session. |
| AUTH-19 | P0 | M | Sign out offline; restart; sign in B online on the same phone. | No auto-return to A; B never inherits A's private queues/history/contacts. |
| AUTH-20 | P0 | I | Revoke/disable account or invalidate binding while session refresh runs. | Authorization failure requires sign-in; transport failure merely preserves local session. |
| AUTH-21 | P1 | M | Try B sign-in while device is still locally bound to A. | Explicit binding policy; no silent account overwrite. |
| AUTH-22 | P1 | I | Corrupt saved-session data or fail SQLite startup while active hike exists. | Recoverable startup; active hike not deleted merely because session loading fails. |

## 2. Security factors and password recovery

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| MFA-01 | P0 | M | Enroll TOTP; scan QR/enter secret in test authenticator; verify current code. | Enrollment completes only after correct proof; subsequent login requires bound factor. |
| MFA-02 | P1 | I | Wrong, expired, malformed and reused TOTP; boundary at period change. | Rejected according to server time/replay policy; no factor bypass. |
| MFA-03 | P1 | M | Cancel enrollment, restart and attempt login with incomplete factor. | No partially enrolled factor treated as active; enrollment can restart. |
| MFA-04 | P0 | H | Supported Android/paid-signed iOS build: enroll/sign in with passkey. | Correct relying-party/platform flow; possession proof required; cancellation recoverable. |
| MFA-05 | P0 | H | Personal Team iOS build: open security methods. | Passkey option gated with accurate reason; TOTP works independently. |
| MFA-06 | P0 | S | Replay factor challenge, change UID/session token, use expired challenge or altered relying-party/origin. | Enrollment/login rejected; no issued authenticated session. |
| MFA-07 | P0 | M | Remove factor without recent verification; then with successful recent verification. | Removal requires supported recent proof; login reflects remaining methods. |
| MFA-08 | P1 | I | Start factor removal twice; lose connection after server commits. | Retry converges to one valid factor state; no unintended removal of another factor. |
| MFA-09 | P0 | M | Full Forgot Password: phone→reset OTP→an already bound recovery method→new password. | Old password fails; new password works; reset proof consumed. |
| MFA-10 | P0 | I | Attempt reset before OTP, before recovery proof, for another account, or with expired/reset-reused token. | All bypasses denied; no password mutation. |
| MFA-11 | P1 | M | Safety questions with correct/incorrect/case/whitespace answer variants. | Current normalization policy consistent; no answer disclosure. |
| MFA-12 | P0 | M | Account has only TOTP, only questions, or passkey; open reset choices. | Only bound supported methods offered; no fabricated fallback. |
| MFA-13 | P1 | I | Wrong reset answers/codes repeatedly and simultaneous reset requests. | Rate/attempt limits enforced; no cross-challenge contamination. |
| MFA-14 | P1 | M | Resend reset OTP, provider failure, offline mid-reset, app restart mid-reset. | Clear retry/expiry state; no unearned verification or false success. |
| MFA-15 | P1 | I | New password invalid/mismatched; then valid at reset final step. | Invalid values rejected; secrets not logged or returned in UI. |
| MFA-16 | P0 | S | Read factor seeds/challenges/reset sessions as user, outsider and admin client. | Server-private artifacts denied per rules; public factor status excludes secrets. |

## 3. Onboarding and profile

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| PROFILE-01 | P0 | M | Complete all required onboarding fields and residential map selection. | Complete profile saves and survives restart; home becomes accessible. |
| PROFILE-02 | P1 | M | Leave each required field blank, whitespace-only name, city label without coordinates. | Incomplete form blocked; specific missing field identifiable. |
| PROFILE-03 | P1 | M | Back/revisit onboarding steps and restart before finishing. | Saved progress restored consistently; no accidental complete flag. |
| PROFILE-04 | P1 | I | Rapidly select different map coordinates; return geocoding responses out of order. | Latest selection wins; label and coordinates remain paired. |
| PROFILE-05 | P1 | M | Geocoding unavailable/invalid key/no city result; deny location. | Honest fallback/error; manual selection remains possible where supported. |
| PROFILE-06 | P1 | M | Edit username, experience, frequency, gender, residential city and photo. | Refresh/restart and another allowed profile view show consistent updates. |
| PROFILE-07 | P1 | H | Deny/cancel photo/camera picker; upload valid JPEG/PNG/HEIC. | Cancel harmless; supported image appears correctly; unsupported format handled. |
| PROFILE-08 | P1 | I | Upload image at 10 MiB and above; invalid MIME/extension; broken URL. | Limits/security enforced; fallback image; old profile not destroyed by failed upload. |
| PROFILE-09 | P1 | M | Edit offline, save and reconnect. | Actual local/cloud result disclosed; no success claim for unsaved fields; retry possible. |
| PROFILE-10 | P1 | M | Long Unicode/emoji name; empty values; huge text; rotate/open keyboard. | Validation/layout stable; saved text preserved according to current limits. |
| PROFILE-11 | P0 | S | Modify B's profile/photo or set A's admin/security-controlled fields. | Unauthorized changes denied regardless of hidden UI. |
| PROFILE-12 | P1 | M | View public profile as buddy and outsider. | Only intended public snapshot exposed; contacts, auth factors and private history excluded. |

## 4. Discovery and trail details

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| TRAIL-01 | P0 | M | Home discovery→trail list→detail→route/forecast→Back. | Selected trail retained; all primary navigation works without reset/crash. |
| TRAIL-02 | P1 | M | Search exact/partial/case/whitespace/Unicode/no-match names. | Correct filtering and explicit empty result; clear search restores data. |
| TRAIL-03 | P1 | M | Change Malaysia regions/states, combine available filters/sort, reset. | Results and state boundaries match choices; filters do not silently conflict. |
| TRAIL-04 | P1 | H | Allow/deny approximate/precise location for nearby discovery. | Correct distance ordering with fix; denial never fabricates proximity. |
| TRAIL-05 | P1 | I | Empty collection, bad coordinates, missing optional attributes and deleted trail. | Safe empty/error/default states; invalid trail cannot silently become a valid route. |
| TRAIL-06 | P1 | M | Load multiple images/credits; swipe; fail one image URL. | Correct attribution, stable placeholder and remaining images usable. |
| TRAIL-07 | P1 | M | Trail with zero votes, one vote, ties and mixed difficulty votes. | Current community difficulty or “Difficulty not rated”; counts/labels consistent across views. |
| TRAIL-08 | P1 | I | Community difficulty changes while a saved Next Hike is open. | Live/current value used when available; old scheduled difficulty not presented as current. |
| TRAIL-09 | P1 | M | Open checkpoints/start-point picker; choose different start and inspect map. | Names/order/coordinates consistent; return selection retained. |
| TRAIL-10 | P1 | M | Open previously viewed trail offline, then a never-viewed trail. | Cached versus unavailable data distinguished; no indefinite loading. |
| TRAIL-11 | P1 | I | Trail geometry stored natively, legacy metadata, missing document and changed checksum. | Correct route version/fallback/error; stale incompatible geometry not accepted silently. |
| TRAIL-12 | P2 | M | Rapid switches/search/refresh and long lists. | Latest selection wins; no old trail weather/hazards displayed on new trail. |

## 5. Routes, checkpoints and maps

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| ROUTE-01 | P0 | M | Preview stored route with start, intermediate and end checkpoints. | Route follows saved geometry; correct endpoints/order and camera bounds. |
| ROUTE-02 | P1 | I | Generic route service with 1/2/12/13 checkpoints. | 2–12 valid; outside range rejected. Wizard's separate 3–12 gate also tested. |
| ROUTE-03 | P1 | M | Add/remove/reorder/edit checkpoint and recalculate. | Changed route reflects intended order; stale result/cache not reused. |
| ROUTE-04 | P1 | I | Invalid latitude/longitude, NaN/infinity, duplicate coordinates, degenerate route. | Invalid data rejected or explicitly unavailable; no crash or fictitious distance. |
| ROUTE-05 | P1 | I | Primary route provider rejects/times out/malformed geometry; next provider succeeds. | Configured fallback attempted; returned source/route valid. |
| ROUTE-06 | P1 | I | All routing providers fail; elevation only fails. | Route failure recoverable; elevation loss does not create invented elevation values. |
| ROUTE-07 | P1 | I | Same checkpoints versus changed order/coordinates; load route cache offline. | Cache key respects route inputs; matching cached route usable, unrelated geometry not reused. |
| ROUTE-08 | P1 | M | Loop/out-and-back/repeated crossing route; animate and inspect progress. | Correct traversal and endpoint markers; no shortcut across repeated geometry. |
| ROUTE-09 | P1 | I | Geometry below/at/above 700,000 encoded-JSON bytes; malformed polyline. | Current geometry size/validity guards enforce safe save. |
| ROUTE-10 | P1 | M | Zoom/rotate/recenter/style switch while animation running; reopen. | Controls remain usable; style reload recreates overlays once. |
| ROUTE-11 | P1 | M | Weather overlay/boundary/hazard toggles and marker taps. | Correct legends/details; toggles do not remove route unexpectedly. |
| ROUTE-12 | P0 | H | Warm map online; offline restart; zoom beyond viewed area/change style. | Observe tile/style/font coverage honestly; missing basemap does not erase cached route data. |
| ROUTE-13 | P0 | H | Fresh install or clean map cache offline; open cached/imported route fixture. | No claim of full offline basemap; route/text fallback or explicit unavailable map. |
| ROUTE-14 | P1 | I | Water 49/50/51 m from corridor; ford crossing versus nearby parallel stream. | Crossing distinguished from proximity; water never declared potable/safe based on tags. |
| ROUTE-15 | P1 | I | Hazard cache refresh for T; open another trail U during response. | No cross-trail cache loss/markers; current generation applied. |
| ROUTE-16 | P1 | I | No hazards, stale/expired scan, service failure, duplicate clustered features. | Empty/stale/unavailable states truthful; no duplicate clutter or stale-algorithm flash. |
| ROUTE-17 | P1 | M | Community caution markers pending/approved/rejected and overlapping static cautions. | Approved/current status presented correctly; marker details distinguish source/unverified reports. |
| ROUTE-18 | P2 | H | Dense geometry/hazards on low-memory phone; recorded-history map. | Responsive bounded rendering; recorded route does not acquire unrelated planned-route markers. |

## 6. Weather and precaution boundaries

For WEATHER fixtures, inject hourly data with explicit UTC offset, cache timestamp, planned departure, duration, sunrise/sunset and all measurements. Compare trail page, pre-hike review, upcoming push and active speech separately; they intentionally have different time windows/channel eligibility. Values below/at/above each boundary require individual runs. These are app rules, not medical or official safety standards.

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| WEATHER-01 | P0 | M | Load current weather and session forecast; select departure/day; refresh. | Current readings separated from forecast; selected trail/date/time/units consistent. |
| WEATHER-02 | P1 | I | Cache ages 3 h 59 m/4 h/4 h 1 m; unavailable and invalid timestamps. | Four-hour staleness disclosed; missing values not treated as safe zeroes. |
| WEATHER-03 | P1 | I | Forecast timezone differs from phone; midnight and multi-day window. | Evaluated hours/daylight use intended trail/provider timezone consistently. |
| WEATHER-04 | P1 | I | Hazard hour just before/inside/after evaluated window. | Only channel-appropriate window triggers; gear uses session without precaution buffers. |
| WEATHER-05 | P1 | I | Temperature 31.9/32/32.1°C; feels-like 34.9/35/35.1°C. | Heat rule at ≥32 or feels-like ≥35; no false heat from unrelated missing field. |
| WEATHER-06 | P1 | I | Temperature 30°C/humidity 80% same hour, then separate hours. | Combined humid heat only when both coexist in one hour. |
| WEATHER-07 | P1 | I | Temperature 14.9/15/15.1°C with rain or wind 19.9/20/20.1 km/h. | Cold precaution at ≤15 with same-hour rain/wind; blanket has separate <15 rule. |
| WEATHER-08 | P1 | I | Rain probability 50/51/59/60%; precipitation zero. | Wet gear above 50; ordinary precaution at ≥60; probability never equated to intensity. |
| WEATHER-09 | P1 | I | Precipitation 0/0.005/0.01 mm and 9.9/10/10.1 mm/h. | In-app positive-rain vs server ≥0.01 distinction documented; heavy at ≥10 replaces ordinary rain. |
| WEATHER-10 | P1 | I | WMO 65/67/82 and storm 95/96/99, with zero numeric rain. | Appropriate heavy/storm cards from codes; storm plus heavy can both remain. |
| WEATHER-11 | P1 | I | Sustained wind 24.9/25; gust 39.9/40/59.9/60 km/h. | Wind caution and priority escalation at implemented boundaries. |
| WEATHER-12 | P1 | I | UV 2.9/3/7.9/8; missing UV. | Correct sun precaution/priority; absence acknowledged rather than invented zero. |
| WEATHER-13 | P1 | I | Fog WMO45/48; visibility 999/1,000/1,001 m. | Visibility caution for fog or <1,000 m; boundary exact. |
| WEATHER-14 | P1 | I | Gain 499/500/999/1,000 m; combine with heat. | Ascent caution/priority correct; combined heat avoids duplicate ascent advice. |
| WEATHER-15 | P1 | I | Start just before/at sunrise; finish 61/60/1 min before/at/after sunset. | Near-sunset/dark cards reflect actual estimated times and exact window. |
| WEATHER-16 | P1 | I | Duration 239/240 min; missing sunrise/sunset and missing hours. | Duration/daylight-data/incomplete-data rules correctly distinguished. |
| WEATHER-17 | P1 | M | Several high-priority cautions plus low-priority items; View all. | Highest first; all priority-3 cards visible; remaining cards accessible. |
| WEATHER-18 | P1 | I | Valid readings with no trigger, then empty forecast. | No-specific-advisory wording retains uncertainty; empty data shows data caution. |
| WEATHER-19 | P1 | I | Refresh fails, one API is blocked, stale fallback and repeated refresh taps. | Cached data labelled; last good readings retained; loading ends; no duplicate work. |
| WEATHER-20 | P1 | H | Active precaution repeats/changes; speech unavailable/muted; upcoming FCM denied. | Applicable deduplication/channel rules; no automatic SOS from weather; UI still informative. |

## 7. Planning and scheduling

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| PLAN-01 | P0 | M | Create Start Now solo draft through all wizard steps. | Trail/checkpoints/timing/safety choices retained; final preparation required before start. |
| PLAN-02 | P0 | M | Create scheduled hike online; restart and inspect Next Hike/chat. | One canonical schedule; saved time/trail/privacy/join policy/reminders correct. |
| PLAN-03 | P1 | I | Scheduled departure now+9:59/10:00/10:01; wait while wizard open. | At least 10-minute gate rechecked; formerly valid time can become invalid. |
| PLAN-04 | P1 | M | Departure after arrival/return, midnight, multi-day and maximum picker date. | Ordering/derived estimates valid; no negative duration; clear constraints. |
| PLAN-05 | P0 | I | Solo distances 9.999/10/10.001/19.999/20/20.001 km. | No acknowledgement ≤10; acknowledgement >10 to ≤20; group required >20. |
| PLAN-06 | P0 | M | Acknowledge solo distance, edit route to change distance, proceed. | Prior acknowledgement cannot authorize a different route distance. |
| PLAN-07 | P1 | M | Switch solo↔team and Now↔Scheduled; Back through steps. | Appropriate steps/defaults; no stale invitees or lost valid inputs. |
| PLAN-08 | P1 | M | Wizard checkpoints 2/3/12/13; repeated start/end and unsorted order. | Wizard 3–12 gate enforced; intended order validated; no unexpected route. |
| PLAN-09 | P1 | M | Set sharing off/on, upload interval, check-in/rest/sensitivity and shirt color. | Draft/next review/started session agree; sample cadence distinct from upload interval. |
| PLAN-10 | P1 | M | Save reminder combinations including disabled repeat, maximum counts and final reminder. | Preference persists; schedule does not create extra reminders beyond configured policy. |
| PLAN-11 | P0 | I | Double schedule; lose ACK after committed schedule; retry same creation request. | One hike/team/chat per stable creation identity; no duplicate invitation. |
| PLAN-12 | P1 | M | Schedule while offline or server rejects identity/permission. | No falsely confirmed schedule; explicit retry; no bypass of authoritative policy. |
| PLAN-13 | P0 | M | Cancel schedule as host, then open it from cached card/deep link. | Terminal state propagated; no new joins/start against cancelled source. |
| PLAN-14 | P1 | I | Pass departure+15-minute visibility grace; reopen pending request. | Expired/cancelled lifecycle shown; stale cached card cannot revive availability. |
| PLAN-15 | P1 | M | Multiple upcoming hikes; switch Next Hike; save per-hike checklist/settings. | Correct selected plan; state scoped to user+hike. |
| PLAN-16 | P1 | M | External navigation from selected start; no maps app installed; return. | Correct destination, safe fallback/error; draft preserved. |

## 8. Guided preparation and required equipment

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| PREP-01 | P0 | M | Immediate/scheduled/team-participant start with one required item missing. | Start blocked; missing item named; all three entry paths use required review. |
| PREP-02 | P0 | M | Complete guide with Yes packed for all required items and finish checks. | Start appears only at final step and becomes enabled when current requirements/saves complete. |
| PREP-03 | P1 | M | Choose Not yet, skip optional extras, revisit previous answers, reopen guide. | Deferred item stays missing; answers/history restore; optional skipping does not pack items. |
| PREP-04 | P0 | I | Every hike, including very short night route. | Water/snack/first-aid always required; obsolete saved tokens do not satisfy current requirements. |
| PREP-05 | P1 | I | Session ending exactly 08:00, starting exactly 18:00, 1-second positive overlap. | Sun protection only for positive local 08:00–18:00 overlap. |
| PREP-06 | P1 | I | Midnight/multi-day overlap with 08:00–18:00 and non-UTC+8 forecast. | Correct local-day computation across all overlapped days. |
| PREP-07 | P1 | I | Fresh overlapping temperatures 14.9/15/15.1°C; colder hour outside session. | Blanket required only by fresh relevant <15 sample. |
| PREP-08 | P1 | I | Rough/technical/muddy usable analysis, unusable/missing analysis. | Poles for usable rough/technical; wet extras for mud; missing terrain not labelled verified safe. |
| PREP-09 | P1 | I | Rain probability 50/50.1, rain >0 and codes50/51/99/100. | Exact wet-gear triggers; dry socks and cover appear once each. |
| PREP-10 | P1 | I | Stale/partial/missing weather; one known fresh cold/rain sample. | Uncertainty disclosed; known fresh sample can require gear despite incompleteness. |
| PREP-11 | P0 | I | New wet/cold/rough result arrives at final step or during save. | Requirements recalculated; new missing gear prevents start. |
| PREP-12 | P0 | I | Fail packed-answer save; retry; double tap answer. | Rollback and same question with retry; no false packed state. |
| PREP-13 | P0 | M | Host checklist complete; B joins with empty personal checklist. | Host pack does not satisfy B's required gear. |
| PREP-14 | P1 | M | Modify contacts from guide; add/remove; return via UI/system Back. | Same question restored; refreshed list including deletion; save-in-progress navigation guarded. |
| PREP-15 | P1 | H | Battery question entry, wait >30 s, background/resume; battery API unavailable. | Fresh reading/recheck or unavailable; no pretend battery-setting change. |
| PREP-16 | P1 | M | Modify sharing, Save; modify then Back; restart scheduled preparation. | Save retained, Back discards; no live share starts during preparation. |
| PREP-17 | P1 | M | Open full forecast/details and return repeatedly. | Question/back history/checklist retained; refresh can change requirements. |
| PREP-18 | P1 | M | Cancel hosted hike from menu at each preparation stage. | Cancellation accessible; no later Start from stale guide. |
| PREP-19 | P1 | I | Long day 10/10.1 km and 5:59/6 h; camping17:59/18 h; ascent499/500 m. | Correct recommendations; not all recommendations become mandatory; no remote-coverage inference. |
| PREP-20 | P1 | M | Large text/small screen/keyboard and pending team/cloud start. | Answers reachable; clear wait reason; no hidden start bypass. |

## 9. Joining hikes and team coordination

Run TEAM cases using A host, B participant, C outsider; keep both devices visible. Repeat role-changing and disconnect cases across Android/iOS when possible.

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| TEAM-01 | P0 | M | Discover public preview as C; join open hike as B. | Allowed preview excludes private details; B joins once and receives authorized membership. |
| TEAM-02 | P0 | M | Request approval-required hike; host accepts/rejects. | Pending does not grant membership; only accept joins; rejection truthful. |
| TEAM-03 | P0 | S | Outsider directly reads full upcoming document, request or private host/member details. | Access denied or authorized public snapshot only. |
| TEAM-04 | P1 | M | B requests twice; host accepts twice; simultaneous accept/reject. | Idempotent terminal decision; no duplicate participant/chat/counters. |
| TEAM-05 | P1 | M | Host changes join policy while B preview is open. | Authoritative latest policy governs; stale UI cannot bypass approval. |
| TEAM-06 | P1 | M | Host cancels/starts/expires hike while request dialog/deep link is open. | Request becomes unavailable/terminal; no revival or surprise membership. |
| TEAM-07 | P1 | M | Remind host repeatedly; host opens notification/link cold and warm. | Rate policy; correct request/hike route; no private data leaked via link. |
| TEAM-08 | P0 | M | Invite buddies; accept; begin readiness; each participant completes own preparation. | Correct invite→readiness→ready→active phases; each role's controls correct. |
| TEAM-09 | P0 | M | B not ready/offline; A tries team launch. | Enforced readiness policy; no false claim B is actively tracking. |
| TEAM-10 | P1 | M | Remove pending invitee, cancel team, or reject invite mid-readiness. | Membership/phase consistent on all clients; cancelled invitation unusable. |
| TEAM-11 | P0 | S | C attempts host actions; B sets A ready/removes A/changes leader. | Callable/rules deny role escalation. |
| TEAM-12 | P0 | I | Launch twice or timeout after server activation; retry/restore. | Same canonical team/active IDs; one launch event. |
| TEAM-13 | P1 | M | Formed team naming prompt; name, dismiss/reopen/retry. | Host-only naming; prompt persistence; consistent group name after reload. |
| TEAM-14 | P1 | H | A/B move; B loses internet; fix age at 2-minute freshness boundary. | Current vs stale/offline location distinct; no moving phantom participant. |
| TEAM-15 | P1 | M | Ping B and respond; duplicate ping, offline B, response after expiry/end. | Correct recipient/state; no unauthorized/late phase mutation. |
| TEAM-16 | P0 | H | B offline during team start/completion; reconnect after cloud terminal decision. | Terminal state wins; B cannot reopen completed/cancelled hike. |
| TEAM-17 | P1 | M | End/abandon participant session; host finishes; reopen group/history. | Individual/team statuses consistent with implemented policy; no accidental all-member completion. |
| TEAM-18 | P1 | I | Same invitee set in different order vs changed invitee set. | Stable creation identity independent of order, changes when membership intent changes. |

## 10. Active hike, GPS and navigation

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| HIKE-01 | P0 | H | Start prepared hike; walk known short path; watch time/distance/map. | One active session; sane elapsed/distance; local recording and map update. |
| HIKE-02 | P0 | M | Try another Start while an active hike exists; repeated taps. | No two unintended active sessions or duplicated safety monitors. |
| HIKE-03 | P0 | I | Start request times out after 2 s but later commits; reconnect. | Local session reconciles to canonical cloud ID; no duplicate hike. |
| HIKE-04 | P0 | I | Start transport error versus permission/validation rejection. | Offline fallback only for permitted transport-like errors; policy rejection cannot be bypassed. |
| HIKE-05 | P0 | H | Start offline from cached prepared route; acquire outdoor GPS. | Active hike durable locally; no network required for valid location sensing. |
| HIKE-06 | P1 | H | GPS off, denied, approximate, permanent denial, indoor no-fix. | Explicit unavailable/accuracy state; no route-center masquerading as user's position. |
| HIKE-07 | P1 | I | Latitude ±90/longitude ±180, beyond bounds, NaN/infinity, invalid accuracy/battery/altitude. | Invalid values rejected before persistence/server use; no crash. |
| HIKE-08 | P0 | I | Same coordinates with successive fresh fix/sample times. | Stationary points retain distinct time identity; newer fix can replace stale freshness. |
| HIKE-09 | P1 | I | Old fix repeated, old sample arrives late, future-skewed timestamps. | Freshness honest; latest position/time not regressed; invalid future values rejected. |
| HIKE-10 | P1 | H | Change upload intervals during preparation/active settings; measure local samples. | Sampling and upload cadence differ as designed; no falsely claimed battery savings. |
| HIKE-11 | P0 | I | Queue >200 GPS points offline; reconnect; lose one ACK. | Bounded batches drain; deduplication; only acknowledged timestamps marked synced. |
| HIKE-12 | P0 | I | Wrong session ACK, partial ACK, missing timestamp list, duplicate ACK. | No unrelated/unacknowledged points deleted; remaining data retried. |
| HIKE-13 | P1 | M | Manual pin/check-in with fix, duplicate pin, no fix; inspect route/check-in list. | Accurate timestamp/location or unavailable result; no accidental duplicate pin. |
| HIKE-14 | P1 | H | Leave route by below/at/above `max(75 m, 2×accuracy)`; stay 2 min; return. | Deviation requires sustained condition; return resets; uncertain GPS considered. |
| HIKE-15 | P1 | I | Repeat deviation within/after 15-minute cooldown; disable feature. | Correct cooldown/disable; advisory does not itself dispatch SOS. |
| HIKE-16 | P1 | H | Scheduled check-in due while locked/offline; respond on reopening. | Reminder/response state accurate; missed reminder not described as confirmed emergency. |
| HIKE-17 | P1 | M | Map preview/full-screen navigation; change tabs while tracking. | Tracking session continues; route/progress preserved; no monitor duplication. |
| HIKE-18 | P1 | H | Battery charges during hike; altitude unavailable; GPS jump. | Summary does not report negative battery use/nonsensical elevation/speed without handling. |
| HIKE-19 | P0 | I | Canonical ID remap while local points, pins, checks and end records exist. | Related records remap consistently; no stranded telemetry/history or duplicate state. |
| HIKE-20 | P0 | H | Reopen with restored hike before Firebase ready; native samples buffered. | Local restore proceeds; samples survive cloud delay; matching safety event consumed once. |

## 11. Completion, ratings and history

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| END-01 | P0 | M | Complete active hike online; inspect summary and history. | Original start/end/duration/distance retained; active services stop; one history record. |
| END-02 | P0 | H | End offline; restart offline; reconnect. | Durable pending end; original end time and route preserved; one canonical completion after sync. |
| END-03 | P0 | I | Completion responses after 12.553 s and 19.614 s, then >45 s. | First two within dedicated deadline; >45 s pending confirmation, not asserted rejection/offline fact. |
| END-04 | P0 | I | Server commits completion but response lost; retry multiple times. | Same terminal session/end time; no duplicate awards/history or restarted hike. |
| END-05 | P0 | M | Abandon/discard tracking; confirm/cancel dialog; existing queued SOS. | Intended terminal behavior; SOS queue survives telemetry discard. |
| END-06 | P1 | M | Empty/very short track, no altitude, single point, stationary-only track. | Summary safely displays available facts; no divide-by-zero or fabricated route. |
| END-07 | P1 | M | Rate completed hike, edit/retry same rating; no-vote trail updates. | One session-bound vote; aggregates consistent; uncompleted/other-owner rating denied. |
| END-08 | P0 | S | C completes/rates/loads A's hike; A rates wrong trail/session. | Ownership and lifecycle checks reject forgery. |
| END-09 | P1 | M | Share ended hike while completion pending; retry with original caption/photo. | Original hike identity/caption retained; no duplicate post after ACK loss. |
| END-10 | P1 | M | History list/detail/recorded map; filter/sort where available; reopen offline. | List/detail agree; cached detail distinguishable; planned route not substituted for actual track. |
| END-11 | P1 | M | Expired scheduled hike appears in expired history; active/completed/cancelled sources. | Correct classification; cannot start an expired record from history. |
| END-12 | P0 | H | Finish then restart phone/app; inspect native services/widgets/live share. | No stale hike watchdog, location sampling or alarm resurrected solely from obsolete native state. |
| END-13 | P1 | I | Late old GPS batch after completion/abandonment. | Valid owner telemetry may be retained; terminal lifecycle never reopens. |
| END-14 | P2 | I | History at limit with many entries and migrated malformed older records. | Stable ordering/bounded query; bad optional data does not break all history. |

## 12. Emergency contacts and SOS messages

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| CONTACT-01 | P0 | M | Save 1/2/3 contacts; restart online/offline. | Account-scoped durable list; names, relations and normalized numbers correct. |
| CONTACT-02 | P1 | M | Fourth contact, duplicate normalized phone, blank name/relation, invalid phone. | Max three and validation enforced; duplicates do not produce duplicate dispatch. |
| CONTACT-03 | P1 | I | Names/relations at80/81 chars; phone normalization variants. | Current length/format policy consistent across save/cloud sync. |
| CONTACT-04 | P0 | M | Edit/delete contacts offline; reconnect with dirty local changes and old cloud snapshot. | Unsynced local edits not overwritten by stale cloud; retry status accurate. |
| CONTACT-05 | P0 | I | Authoritative empty cloud list and clean cached contacts. | Clean local list cleared; no old recipients silently retained. |
| CONTACT-06 | P0 | M | Local cached contact removed on server; trigger controlled SOS. | Server allow-list rejection reported; local presence not sufficient authorization. |
| CONTACT-07 | P1 | M | Save while Back/system Back tapped; failure and retry. | No partial successful UI state; navigation guarded while saving. |
| CONTACT-08 | P1 | M | Custom manual/medical/duress note at240/241 chars; control characters/Unicode. | Current note limit/normalization; structured reason/identity never overridden. |

## 13. SOS dispatch, alarms and retry semantics

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| SOS-01 | P0 | H | Manual SOS; observe countdown; cancel before expiry. | 10-second cancellable flow; no provider dispatch after timely cancellation. |
| SOS-02 | P0 | H | Manual countdown completes with controlled contacts/provider. | Alarm and dispatch independently observable; correct mode/source/time/contact message. |
| SOS-03 | P0 | H | Medical mode; stop physical alarm after sending. | Medical alarm/content; stop clears local outputs and does not claim message recall. |
| SOS-04 | P0 | H | Duress hold below/at/above1,200 ms. | Threshold enforced; duress starts no loud pattern; wording avoids unsafe call instruction. |
| SOS-05 | P0 | H | Trusted immediate/button event while ordinary SOS dialog or volume prompt open. | Immediate path not stranded behind ordinary UI; intended event handled once. |
| SOS-06 | P0 | H | Airplane mode with GPS/Bluetooth separately enabled; trigger controlled SOS. | Local outputs can work; durable queued intent; no WhatsApp delivery claim offline. |
| SOS-07 | P0 | I | No contacts, fresh location, no location, and cached location >5 min. | `no_contacts` where appropriate; no authority substitution or invented position. |
| SOS-08 | P1 | I | No fresh fix arrives within ordinary initial600 ms wait. | Dispatch proceeds with available/null location; GPS does not block forever. |
| SOS-09 | P0 | I | Three recipients: accepted, retryable rejection, uncertain timeout. | Partial outcome preserved; retry only eligible work; accepted recipient not resent. |
| SOS-10 | P0 | I | Provider success with ID vs HTTP success without ID. | Accepted vs uncertain result distinguished; no false delivery assurance. |
| SOS-11 | P0 | I | Provider425/429,408/5xx, definitely-unsent transport and ambiguous transport. | Classifier-specific retry behavior; uncertainty suppresses blind resend. |
| SOS-12 | P0 | I | Client4 s ACK timeout while provider request remains active up to12 s. | Pending state; same dispatch identity reused; later acceptance retrieved safely. |
| SOS-13 | P0 | I | Lose network after provider accepts but before cloud summary/log save. | Log sync may remain queued; successful recipient not resent. |
| SOS-14 | P0 | I | Local queue insert fails, then cloud succeeds/fails. | Immediate delivery still attempted; durability failure disclosed and not disguised as saved queue. |
| SOS-15 | P0 | H | Queue SOS; kill/restart app; reconnect and flush. | Original trigger identity/time/location/recipient results survive; no duplicate dispatch. |
| SOS-16 | P0 | M | Stop alarm while queued SOS exists; change tabs/reopen queue. | Queue retained; terminal versus accepted status interpreted correctly. |
| SOS-17 | P0 | I | Same dispatch ID same payload concurrently; same ID different payload. | Idempotent one outbound acceptance; payload conflict rejected. |
| SOS-18 | P0 | I | Live claimed/sending lease, expired sending lease and retry count1/2/3/4. | Lease/attempt rules prevent concurrent or uncertain blind retries. |
| SOS-19 | P1 | I | Production trigger24h boundary, test10min boundary, future2min boundary. | Server age/skew validation; expired offline alert not marked delivered. |
| SOS-20 | P1 | I | Controlled production30 per5min and test6 perhour limits, plus next request. | Separate per-contact rate policies; truthful rejected/rate-limited result. |
| SOS-21 | P1 | H | iOS volume below/at0.55; cancel volume prompt; headphones/mute/DND. | Current readiness flow correct; alert outputs measured independently of cloud sending. |
| SOS-22 | P1 | H | No torch/camera busy, vibration unavailable, alarm asset/audio failure. | Independent local-output failure visible; dispatch still attempts. |
| SOS-23 | P1 | M | Test WhatsApp message with controlled recipients. | Clearly non-emergency content; separate test limits; no production SOS classification. |
| SOS-24 | P1 | I | >10 queued alerts; corrupt one payload; repeated simultaneous flush. | Bounded flush makes safe progress; bad row handled; no account crossover/duplicate sends. |

## 14. Fall/stillness detection and OS lifecycle

Use synthetic sensor input or protected device motion; do not perform an actual fall. Record the exact platform algorithm. Physical-device outcomes remain required even if synthetic tests pass.

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| LIFE-01 | P0 | H | Active hike foreground→locked/background for10–30min; walk. | Native samples/safety behavior measured; restored route contains actual retained points. |
| LIFE-02 | P0 | H | Android swipe away/UI process reclaimed; trigger synthetic native warning. | Foreground native monitor/handoff behavior verified; no assumption UI survival is required. |
| LIFE-03 | P0 | H | Android Settings force-stop; press button/wait sensor event; reopen. | Interruption limit accurately shown; no promise of restart before user opens app. |
| LIFE-04 | P0 | H | iOS background/suspension/force-quit; then reopen. | Distinguish native/local behavior from Flutter dispatch; no unsupported force-quit sending claim. |
| LIFE-05 | P0 | H | Reboot/app update during active hike and BLE monitor enabled. | Supported persisted service state restores safely; ended/stale sessions do not reactivate. |
| LIFE-06 | P1 | H | Battery saver/vendor optimization/low-power mode and permission revocation mid-hike. | Monitoring degradation visible; retained state safe; real reliability limits recorded. |
| LIFE-07 | P1 | I | Android free-fall then impact just inside/outside500 ms; direct impact. | Native threshold/entry behavior matches sensitivity; outside-window data not identical detection. |
| LIFE-08 | P1 | I | Android2 s bounce,10 s quiet; movement before quiet completes;60 s verification limit. | Phase/reset/timeout correct; no premature escalation. |
| LIFE-09 | P1 | H | Prolonged stillness at configured rest boundary, movement or fresh GPS relocation. | Platform-appropriate motion/reset; ordinary resting behavior documented. |
| LIFE-10 | P0 | H | Native warning; cancel at1 s/before15 s, then allow expiry. | Native15 s window; timely cancellation prevents dispatch; expiry produces one durable event. |
| LIFE-11 | P1 | H | Android warning touch response/unlock; iOS explicit dialog/notification response. | Actual platform response action accepted; no claim of observing every other-app touch. |
| LIFE-12 | P0 | I | Pending native event before active restore; wrong session/owner; already dispatched event. | Wait for restoration; mismatched events rejected; handled event not resent. |
| LIFE-13 | P0 | I | Android headless dispatcher no contacts/auth failure/timeout90 s; foreground recovery. | Persisted failure/retry state; no duplicate successful send; wrong identity never used. |
| LIFE-14 | P1 | H | Accelerometer/gyro absent or denied; missing barometer; sensitivity1/5/10. | Available capability disclosed; current native thresholds used, no clinical accuracy claim. |
| LIFE-15 | P1 | H | Backpack drop/phone drop/vehicle movement/walking/long seated rest. | Measure false positives and cancellation; report detector limits, not guaranteed discrimination. |
| LIFE-16 | P1 | H | Network loss stops cloud heartbeat but phone continues recording; reconnect. | Monitoring/offline reminder is not a confirmed accident; local points survive. |
| LIFE-17 | P1 | H | iOS local monitoring-stopped watchdog and server reminder after heartbeat expiry. | Correct reopen guidance; no duplicate/resurrected watchdog after completion. |
| LIFE-18 | P0 | H | BLE alert and native safety warning occur together (notification ID4213 paths). | Check overwrite/cancellation interactions; both events/outcomes remain recoverable. |

## 15. Physical button, BLE trust and nearby incidents

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| BLE-01 | P0 | H | Discover correct button in setup mode; complete physical confirmation and secure pairing. | Correct device/account binding; secret retained natively, never displayed/logged by Flutter. |
| BLE-02 | P0 | H | Android unbonded/insecure GATT; then OS-bonded secure characteristics. | Secret write refused before required secure bond; succeeds only under expected security. |
| BLE-03 | P0 | H | iOS firmware characteristic lacks authenticated encrypted protection. | Reject/test firmware security explicitly; app HMAC cannot compensate for exposed setup secret. |
| BLE-04 | P1 | H | Setup expires; incompatible firmware; wrong device; user cancels permissions/confirmation. | Clear compatibility/setup error; no half-paired trusted button. |
| BLE-05 | P0 | H | Paired production press foreground, locked, background and after reopening. | Authenticated event handled once; correct source/mode; lifecycle limits documented. |
| BLE-06 | P0 | I | Invalid HMAC, unknown device, replayed counter and malformed advertisement. | Not accepted as trusted owner's SOS. |
| BLE-07 | P0 | H | Burst/repeated advertisements from same press; press counter advances. | One event per genuine identity; new valid press separately recognized. |
| BLE-08 | P0 | H | Switch A→B; old A button broadcasts; unpair A then reconnect. | Account-scoped trust; no dispatch under B using A's secret/event. |
| BLE-09 | P1 | H | Bluetooth off/denied, scan/connect/advertise individually denied; turn back on. | Readiness and recovery truthful; not green simply because device is registered. |
| BLE-10 | P1 | H | Button out of range, low battery, sleeping/wakes, stale last-seen. | Stale readiness warning; connection discovery timeout recoverable. |
| BLE-11 | P0 | H | Owner press with fresh precise location, no precise fix and offline phone. | Authenticated handoff only with appropriate real fix; no fabricated exact location; cloud transport separate. |
| BLE-12 | P1 | H | Nearby unpaired phone observes location relay; repeated/stale relay. | Deduplicated local incident; explicitly unverified observation; no independent authenticity/rescue claim. |
| BLE-13 | P1 | M | Nearby incident popup→map→history; no coordinate/invalid coordinate/deleted record. | Honest location state; usable return navigation; no bogus marker. |
| BLE-14 | P1 | I | Forward nearby incident twice/multiple observers; malformed/spoofed payload. | Validation/rate/dedup rules; cloud incident remains unverified. |
| BLE-15 | P0 | H | Arm owner test window; authenticated mode0x02 inside/outside it. | Armed test is local result, not production contact dispatch/nearby emergency. |
| BLE-16 | P1 | H | Event-log Start; five presses within3 s, first wakes; incomplete sequence;30 s service window. | Complete maintenance sequence suppresses SOS; log retrieval authenticated/read-only; timeout safe. |
| BLE-17 | P1 | I | Fresh challenge failure, wrong secret, tampered/truncated log records; interrupt download. | Unauthorized log access rejected; malformed records safely handled; retry no SOS side effect. |
| BLE-18 | P1 | H | Android enabled monitor boot/app replacement/swipe vs Settings force-stop; iOS restoration/force-quit. | Measured platform behavior; no unsupported always-on promise. |
| BLE-19 | P1 | I | Legacy unauthenticated team-location packet during active team hike. | Cannot override cloud-authorized member locations. |
| BLE-20 | P2 | H | Admin button-debug trace/filter/export; native channel unavailable. | Errors/fields truthful; secret material excluded; troubleshooting usable. |

## 16. Offline, interrupted work and reconciliation

These cases deliberately test different failure points. **Warm** means the needed feature was loaded online first. **Cold** means no app-level cache for it. “Offline” includes airplane mode, Wi-Fi with no internet, captive portal, DNS failure, selectively blocked HTTPS/services, high latency, packet loss and rapid network flapping. Airplane mode may disable Bluetooth/Wi-Fi; re-enable Bluetooth for BLE-only tests and document that setting. GPS and mobile internet are different capabilities.

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| OFF-01 | P0 | H | Cold install, no internet, launch every main entry. | No fabricated account/data; bounded errors; no crash or endless splash. |
| OFF-02 | P0 | H | Warm saved session; offline cold launch; visit every main tab. | Local restoration; cached/empty/unavailable states distinct; navigation usable. |
| OFF-03 | P0 | H | Wi-Fi connected but router internet disconnected; repeat key actions. | Operations fail/queue appropriately even if Wi-Fi icon exists. |
| OFF-04 | P0 | H | DNS resolves but Firebase HTTPS/callables blocked. | DNS-derived online badge does not cause false saved/sent claims; durable retries retained. |
| OFF-05 | P1 | H | Captive portal, DNS timeout and selective Mapbox/weather/Storage block. | Each feature reports its own failure; working local features remain accessible. |
| OFF-06 | P1 | I | Slow internet/packet loss and Wi-Fi↔mobile flapping during write. | Timeout/pending states; stable retry identity; no duplicate cloud result. |
| OFF-07 | P0 | H | Warm trail/route/hazards then offline; open never-cached trail too. | Matching cached data usable; absent geometry/tiles/weather not claimed present. |
| OFF-08 | P0 | H | Kill offline app and relaunch map; switch style, zoom and move outside cached region. | Persistent versus incidental tile coverage recorded; clear limitations/fallback. |
| OFF-09 | P1 | M | Offline preparation answers and per-hike sharing settings; reopen. | Saved local answers/settings restore; pending failure not mistaken for success. |
| OFF-10 | P0 | H | Start offline; walk; pin/check-in; restart; continue; end offline. | Local durable lifecycle/route/end intent coherent; no lost completed work. |
| OFF-11 | P0 | H | Reconnect OFF-10; inspect server and history. | One canonical hike; full acknowledged route/check-ins/end time; queue drains safely. |
| OFF-12 | P0 | I | Server commits start, ACK lost; later end locally before canonical ID response. | Reconcile all dependent data to correct canonical ID; one completion. |
| OFF-13 | P0 | I | Partial location batch ACK then reconnect/restart. | Only committed timestamps marked synced; remaining samples retained. |
| OFF-14 | P0 | H | Offline end waits; restart/reconnect several times. | Stable original end time; no duplicate completion/achievement/community post. |
| OFF-15 | P0 | H | Offline SOS; local alarm; stop; restart; reconnect. | Durable dispatch intent independent of alarm; eligible recipients sent once. |
| OFF-16 | P0 | I | Offline SOS ages beyond24h before reconnection. | Validation failure/terminal reason exposed; not falsely sent or silently re-timestamped. |
| OFF-17 | P0 | M | Offline contact edit vs concurrent server contact removal. | Dirty/clean reconciliation verified; recipient authorization remains server-enforced. |
| OFF-18 | P0 | H | Queue work as A; sign out; log in B; reconnect. | A's SOS/points/check-ins/ends/messages/preferences never sent as B. |
| OFF-19 | P0 | I | Sign out/account switch during active upload or late ACK. | Captured owner checked after await; no deletion/mutation of B's rows. |
| OFF-20 | P1 | M | Cached chat offline: send several text messages; restart; reconnect. | Local pending bubbles persist; original order/identity; one server message each. |
| OFF-21 | P1 | I | Chat write committed but ACK/read fails; retry. | Deterministic message document prevents duplicate body/notifications. |
| OFF-22 | P1 | M | Offline attachment selection/upload versus text send. | Unsupported attachment queueing not assumed; retained/error UI honest; text still works. |
| OFF-23 | P1 | M | Offline read receipts/mute/pin changes; reconnect with old cloud preference. | Local dirty preference/receipt merge behaves as implemented; no lost latest choice. |
| OFF-24 | P0 | H | Stop live share offline; restart; recipient browser still open; reconnect. | Local publishing stops immediately; cloud deactivation pending disclosed; later retry deactivates. |
| OFF-25 | P0 | I | Older share-stop ACK arrives after a newer stop/activation attempt. | Generation guards prevent resurrecting a stopped share or clearing newer pending intent. |
| OFF-26 | P1 | M | Offline assistant: view history, ask new question, clear history; reconnect. | Cached history works; new answer requires callable; clear not resurrected by old cloud history. |
| OFF-27 | P1 | M | Offline feedback submission with screenshot; reconnect/retry. | Draft/error retained as implemented; immutable draft ID prevents duplicate report. |
| OFF-28 | P1 | M | Offline warm history/achievements/first aid/help; uncached detail. | Cached/packaged content useful; unavailable remote media/detail clearly differentiated. |
| OFF-29 | P0 | I | Server completed/cancelled scheduled/team hike while phone offline; reopen/reconnect. | Server terminal status authoritative; no unauthorized offline revival. |
| OFF-30 | P1 | I | Disk full/DB locked/read-write failure during GPS, SOS, checklist and end persistence. | Durability loss explicit; fail-safe UI; immediate emergency attempt independent where implemented. |
| OFF-31 | P0 | I | Reopen DB from supported prior schema with unsent rows; interrupt migration. | Migration preserves owner identity/queue data; failure recoverable without silent destructive reset. |
| OFF-32 | P1 | I | Corrupt one entity/queue payload/route-cache row; leave others valid. | Bad data contained; other feature/queue entries remain available. |
| OFF-33 | P1 | I | Queue thousands of GPS samples/messages; restart and reconnect. | Bounded processing/UI responsive; no unacknowledged data pruned. |
| OFF-34 | P1 | H | Reconnect while UI terminated, then reopen and trigger flush. | Document actual flush trigger; do not claim continuous daemon for every queue. |
| OFF-35 | P1 | I | Manual/periodic flush overlap, reconnect event and active tick all run. | In-flight guards/idempotency; no double dispatch or queue corruption. |
| OFF-36 | P1 | H | App upgrade with warm caches/active hike/queued messages and SOS. | Persistent data readable; owner binding retained; no duplicate restoration. |

## 17. Live location and recipient page

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| SHARE-01 | P0 | H | Activate sharing online; open link in logged-out browser; walk. | Supported capability link shows intended coordinates/time/expiry; updates at actual cadence. |
| SHARE-02 | P0 | M | Stop share; recipient stays on page then refreshes. | Link becomes inactive; no new location from stopped local publisher. |
| SHARE-03 | P1 | I | Expiry before/at/after server expiration; client clock skew. | Recipient page expires appropriately; expired share cannot be extended by unauthorized client. |
| SHARE-04 | P0 | S | Guess other IDs/read inactive or expired share/write foreign share. | Intended active-link read policy only; unauthorized modifications denied. |
| SHARE-05 | P0 | I | Activate without valid fresh location/auth; malformed server response. | No usable invented share; errors clear; no partial active UI. |
| SHARE-06 | P0 | I | Busy load returns stale active share after user stops. | Service stays inactive; result cannot resurrect publishing. |
| SHARE-07 | P1 | H | Enable auto-share for hike; start prepared hike; stop manually mid-hike. | Only intended start activates; manual stop respected by subsequent ticks. |
| SHARE-08 | P1 | M | Rotate/copy/open/share link; no browser/map API; blocked static map. | Coordinates/status usable when map unavailable; no private contact data included. |
| SHARE-09 | P1 | I | Fresh native/cloud mirrored fix then older batch. | Recipient latest location does not regress; timestamp/accuracy remain truthful. |
| SHARE-10 | P1 | M | Contact notifications accepted/partial/uncertain; retry same share. | Per-contact results and dedup; link notification not a delivery/read guarantee. |
| SHARE-11 | P0 | H | Account switch or hike completion during pending publication. | Old owner's publication stopped/invalidated; no B location under A's link. |
| SHARE-12 | P1 | M | Offline recipient browser after previously active link. | Stale cached display labelled/handled; cannot be presented as real-time reception. |

## 18. Buddies, chat and community

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| CIRCLE-01 | P1 | M | Discover hiker; send buddy request; accept/decline as B. | Reciprocal state consistent; pending request differs from confirmed buddy. |
| CIRCLE-02 | P1 | M | Self-request, duplicate/crossed simultaneous requests, removed/deleted account. | Invalid/duplicate requests handled; no contradictory relationship. |
| CIRCLE-03 | P0 | S | C accepts A↔B request or edits another user's buddy list. | Server authorization denies. |
| CIRCLE-04 | P1 | M | Open direct chat twice and from different entry points. | Same intended conversation; no repeated group creation. |
| CHAT-01 | P1 | M | Send A↔B text; inspect preview/unread/read receipt on both. | Sender/name/time/body correct; own receipt only; counters settle consistently. |
| CHAT-02 | P1 | M | Empty/whitespace text, Unicode/emoji/multiline, maximum allowed and oversized input. | Valid text preserved; invalid/oversized content rejected without crash. |
| CHAT-03 | P1 | M | Many messages; scroll/load; arrive while scrolled up; tap retry failed bubble. | Stable ordering/scroll/retry; no duplicate bubbles or missing new messages. |
| CHAT-04 | P1 | M | Image/video/document attachments; cancel picker and denied permission. | Supported media opens; cancellation harmless; failed upload not represented as sent. |
| CHAT-05 | P1 | I | Files25 MiB/over25 MiB, unsupported MIME/extension, zero bytes, forged URL from another chat. | Client/rules enforce attachment contract; foreign attachment denied. |
| CHAT-06 | P0 | S | C reads/writes group messages/Storage; removed B tries again. | Current membership enforced for new authorized requests. |
| CHAT-07 | P1 | M | Mute/unmute/pin/delete-for-self and return after new message. | Per-user behavior; other member's chat not deleted; current notification preference respected. |
| CHAT-08 | P0 | S | A overwrites B's read/unread fields, sender identity, group creator or membership. | Protected metadata and ownership remain immutable to unauthorized edits. |
| CHAT-09 | P1 | I | Replay message trigger/FCM outbox worker; token rotated/invalid. | No duplicate counter/notification side effects; retries/invalid-token handling recorded. |
| CHAT-10 | P1 | M | Team chat expires/cancels while open or text pending. | Terminal membership/lifecycle honored; queued text not sent to invalid destination silently. |
| COMMUNITY-01 | P1 | M | Create post/comment; refresh on B; own edit/delete where offered. | Correct author/time/counts; ownership controls; text/media preserved. |
| COMMUNITY-02 | P1 | M | Submit hazard report with trail/type/location/detail; admin approves/rejects. | Correct lifecycle; visible markers match approval/publication policy. |
| COMMUNITY-03 | P0 | S | Forge post author, completion source, report status, comment count or moderator identity. | Privileged/ownership fields protected. |
| COMMUNITY-04 | P1 | I | Create/delete comment triggers delivered twice/out of order. | Receipt/transaction logic prevents double count/negative count. |
| COMMUNITY-05 | P1 | M | Remove/restrict post while B reads/comments; offline cached post. | Current moderation respected on refresh/new writes; stale cache handled honestly. |
| COMMUNITY-06 | P1 | M | Malicious HTML/script-like text and very long emoji content. | Displayed as text; no execution/layout failure. |

## 19. Achievements, guidance and settings

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| ACH-01 | P1 | M | Complete qualifying start/check-in/hike/post/approved-hazard fixtures. | Only defined eligible awards/progress; correct user and source event. |
| ACH-02 | P0 | I | Replay completion/achievement trigger and retry pending completion. | One award/event receipt; points not inflated. |
| ACH-03 | P0 | S | Directly write own score/award/level or another user's progress. | Client forgery denied; server-defined criteria authoritative. |
| ACH-04 | P1 | M | Leaderboard ties/no users/disabled achievement; cached progress offline. | Stable ranking/labels; cached state distinguished from latest server results. |
| ACH-05 | P1 | I | Legacy/missing progress fields, hash unchanged/changed and corrupted local cache. | Correct refresh/defaults; no shared account cache. |
| HELP-01 | P0 | H | Open packaged first-aid guide offline; categories/search/all steps. | Bundled guide usable; media requiring internet not silently claimed available. |
| HELP-02 | P1 | M | Help conditions/filter/detail/back; first-aid image/video invalid URL. | Selection preserved; readable steps and explicit unavailable media. |
| HELP-03 | P0 | I | Emergency-call action for supported region, invalid number, no dialer. | Correct launch/fallback behavior; test intercepts launcher and makes no real call. |
| HELP-04 | P1 | M | Privacy/help entry points from auth/profile/settings/site. | Correct destination; offline availability/error clear; return navigation intact. |
| SETTINGS-01 | P1 | M | Switch light/dark/system and restart across key screens. | Theme persisted; contrast and map/dialog state consistent. |
| SETTINGS-02 | P1 | M | Change preferred timezone; reopen Next Hike, SOS log and history. | Consistent timezone labels/timestamps; original UTC identity unaffected. |
| SETTINGS-03 | P1 | I | Unsupported timezone or stale cloud preference after dirty local change. | Valid fallback; local latest choice not accidentally overwritten. |
| SETTINGS-04 | P1 | H | Enable/deny notifications; foreground/background/terminated notification tap. | Authorized route opened once after session restore; denied state accurately reported. |
| SETTINGS-05 | P1 | H | Android upcoming/next-hike/weather/SOS widgets; cold launch deep link. | Correct action/card data; no duplicate SOS; finished hike widget stale state cleared. |
| SETTINGS-06 | P1 | H | iOS widget/Live Activity supported versions/signing; stop hike. | Supported local update/action works; unsupported feature N/A; activity ends appropriately. |

## 20. Assistant and feedback

The assistant files were already modified when inspected. Pin the exact build before running these cases so UI/history expectations match the submitted version.

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| AI-01 | P1 | M | Ask supported feature question and follow-up referencing previous answer. | Relevant answer; intended last-eight-message context; source/notice presentation. |
| AI-02 | P1 | I | Question length0/2/3/480/481 and repeated send while busy. | Minimum/maximum enforced; no duplicate concurrent request. |
| AI-03 | P0 | I | Emergency-now question vs “how to configure emergency contacts.” | Emergency response mode for immediate danger; configuration question not mistaken for event. |
| AI-04 | P1 | H | Ask nearby trails with permitted/denied/no location; ask ordinary question. | Location only sought when relevant; valid trail cards/order or honest lack of proximity. |
| AI-05 | P1 | M | Tap recommended trail/action, malformed/deleted trail ID and obsolete offline-map action. | Valid destination only; no broken obsolete map-download navigation. |
| AI-06 | P1 | I | AI unavailable/no key/provider timeout/empty or malformed answer. | Curated server fallback/error as implemented; offline client cannot manufacture callable response. |
| AI-07 | P0 | I | Question/history includes phone/email/coordinates/OTP or prompt injection. | Sensitive-content handling and grounding; no secrets or unauthorized data/tools exposed. |
| AI-08 | P1 | I | Controlled limits6/minute and40/day, then next request. | Rate-limited response handled; history/loading remains usable. |
| AI-09 | P1 | M | Ask question then leave screen/reopen; offline saved history. | No disposed-state error; local entries persist and failed answers distinguishable. |
| AI-10 | P0 | I | Clear history offline; cloud later supplies older messages; simultaneous sync/clear. | Clear watermark prevents resurrection; newer eligible messages not incorrectly removed. |
| AI-11 | P0 | M | A history→sign out→B assistant→A sign in. | Private owner-scoped history; no cross-user leakage. |
| AI-12 | P1 | I | Malformed cached messages/card values and >400 history entries during cloud sync. | Invalid rows handled; batch limits honored; no crash/duplicate history. |
| FEEDBACK-01 | P1 | M | Submit Problem/Suggestion/Other with optional screenshot; view own report. | Correct category/message/identity; confirmation only for acknowledged report. |
| FEEDBACK-02 | P1 | I | Trimmed text9/10/4,000/4,001 chars; screenshot5 MiB/over5 MiB. | Exact validation limits; no invalid report/upload. |
| FEEDBACK-03 | P1 | I | Server commits then timeout; retry same draft. | Same immutable report ID; no duplicate; wording “cannot confirm” rather than “not sent.” |
| FEEDBACK-04 | P0 | S | C reads A's feedback, A edits admin status, uploads screenshot to B's path. | Denied; admin can change only authorized status fields. |
| FEEDBACK-05 | P1 | M | Admin marks New→In review→Resolved; permission denied/offline during submission. | Correct status propagation; draft retained and error distinguished from connectivity failure. |

## 21. Administrator and backend maintenance

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| ADMIN-01 | P0 | S | Non-admin opens/calls dashboard and privileged APIs; forged local isAdmin field. | No privileged data/actions; server-issued claim required. |
| ADMIN-02 | P1 | M | Admin dashboard success/empty/load failure and filters. | Actual counts/logs; failed query not displayed as healthy empty queue. |
| ADMIN-03 | P1 | M | Create/edit trail with valid checkpoints, geometry, images and metadata. | Atomic/coherent trail and geometry version; hiker sees correct updated route. |
| ADMIN-04 | P1 | I | Invalid checkpoints/oversized geometry/failed cover upload; retry save. | Validation and recoverable error; no half-valid public trail or unintended duplicates. |
| ADMIN-05 | P1 | M | Delete trail referenced by cached/scheduled/history hike. | Reference policy/error handled; existing history not silently corrupted. |
| ADMIN-06 | P1 | M | Review hazard/moderate post with approve/reject/hide/delete; refresh B. | Authorized status/data changes; consistent marker/feed visibility. |
| ADMIN-07 | P1 | M | Create/update/disable achievement definition; hiker refreshes. | Validation; disabled definitions do not grant new unearned awards. |
| ADMIN-08 | P1 | I | Scheduled operations run twice/delayed: reminders, check-ins, expiries, cleanup. | Idempotent eligible work; active/pending durable work not prematurely deleted. |
| ADMIN-09 | P1 | I | FCM outbox worker crashes after send/before ACK; recovery next schedule. | Current lease/retry policy respected; no endless claimed state or uncontrolled duplicates. |
| ADMIN-10 | P1 | I | Weather refresh provider down; malformed one trail; maintenance cursor rerun. | Bounded progress; valid trails retained; stale forecasts not called fresh. |
| ADMIN-11 | P1 | S | Read authoritative SOS/provider audit as admin vs owner; inspect status meanings. | Access per rules; provider acceptance/uncertainty separate from client summary. |
| ADMIN-12 | P2 | M | Button-debug unavailable native channel; long trace/filter/disposal. | Error rather than fictitious healthy status; no secret logging. |

## 22. Security and integrity tests beyond the UI

Run these in the demo emulator or a purpose-built test backend. Hidden buttons do not demonstrate authorization. Use genuine user-role test tokens, not an admin SDK pretending to be a client.

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| SEC-01 | P0 | S | Anonymous reads/writes every private collection and calls authenticated endpoint. | Default deny; only intentional public endpoints/link capability readable. |
| SEC-02 | P0 | S | A supplies B UID/phone/owner/session/trail/contact in each mutation. | Auth identity authoritative; foreign data inaccessible/unmodified. |
| SEC-03 | P0 | S | Directly create/update lifecycle docs, team membership, awards and server audit/rate artifacts. | Server-only writes denied by rules. |
| SEC-04 | P0 | S | Alter existing hike identity/status, owner path or creation key. | Identity immutable; callable lifecycle/idempotency checks remain. |
| SEC-05 | P0 | S | Modify SOS recipients to an arbitrary phone not saved on server. | No unrestricted WhatsApp relay. |
| SEC-06 | P0 | S | Read another user's contacts/location queue/history/assistant/feedback/private request. | Owner/member/admin policies enforced; no broad list leakage. |
| SEC-07 | P0 | S | Upload/read/delete cross-user profile, chat, feedback and community-hike files. | Path/metadata/membership/MIME/size policy enforced. |
| SEC-08 | P1 | S | Fake extensions, wrong content type, huge/zero-length objects, forged attachment URLs. | Supported type/size constraints; no UI-only validation reliance. |
| SEC-09 | P0 | S | Replay OTP/MFA/reset/SOS/creation/completion/notification events with same vs altered payload. | Appropriate one-time or idempotent policy; no duplicated awards/messages. |
| SEC-10 | P1 | S | Call with null/string/list instead of object, missing fields, overlong IDs, NaN/skewed values. | Bounded invalid-argument errors; no partial writes or stack/secret disclosure. |
| SEC-11 | P0 | H | Release APK/app backup/logs/debug exports inspected for provider/pairing/auth secrets. | GreenAPI secret absent from mobile; pairing secret protected natively; sensitive traces redacted. |
| SEC-12 | P1 | S | Token revoked/claim removed/member removed while operation is in flight. | New server request obeys authorization; client cache never treated as proof of current privilege. |
| SEC-13 | P1 | I | Rules queries use expected constraints; missing index/permission failure. | Real failure surfaced; not treated as successful empty dataset. |
| SEC-14 | P1 | S | Client injects share link/script markup into display text or requests unrelated assistant resource. | No script execution or unauthorized resource action. |

## 23. Website, accessibility and device quality

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| WEB-01 | P2 | M | Landing/get-app/privacy/live-location on phone and desktop browsers. | Correct routes/content/download links; no unintended Flutter routing collision. |
| WEB-02 | P2 | M | Evolution timeline mouse/keyboard/touch; open media/dialog; Escape/Back. | Current intended content and accessible navigation; investigate failing content assertions. |
| WEB-03 | P1 | I | Public stats endpoint unavailable/malformed/empty and successful. | Graceful display; response exposes no private user/contact/active location details. |
| WEB-04 | P2 | M | No internet/slow assets/missing screenshot/video and beta-download metadata. | No fake release availability; fallback useful; links don't silently download wrong build. |
| UX-01 | P1 | M | Small screen, large text200%, landscape/keyboard across auth/prep/SOS/history. | Main controls readable/reachable; no clipping/overflow hiding required action. |
| UX-02 | P1 | H | TalkBack/VoiceOver traverse core forms, countdown, map alternatives and errors. | Named controls/logical focus; safety actions operable without visual-only cues. |
| UX-03 | P1 | M | All main screens light/dark/system; contrast/errors/disabled controls. | Text/icons/state distinguishable; not relying only on color. |
| UX-04 | P1 | H | Device Back, predictive Back, fast tab changes and repeated dialogs. | Correct stack; no stuck overlay/disposed-state crash; active hike preserved. |
| UX-05 | P1 | H | Interrupt with incoming call/audio/camera, lock/unlock and app resume. | Local-output conflicts handled; pending operation/session safe. |
| UX-06 | P2 | H | Low-end Android, current Android/iOS, older supported OS, different vendors. | Supported capability/performance recorded; unsupported OS/signing N/A with reason. |
| UX-07 | P1 | H | Real release build, restricted keys, backend config failures and absent optional API key. | Launch works with correct config; missing provider isolated; no debug-only success assumption. |
| UX-08 | P2 | H | Long hike30–120min, repeated navigation/refresh, large cache; observe heat/battery/memory. | No crash/runaway timers; quantify battery/memory and sampling gaps, not merely “fast.” |
| UX-09 | P1 | I | Date/timezone changes, month/year rollover and clock moved backwards during hike. | Stable lifecycle/sample identities; no negative times/unearned expiry extension. |
| UX-10 | P2 | H | Uninstall/reinstall versus app update; backup restore on another phone. | Data-loss and binding/secret-restoration policy understood; no unsafe implicit paired ownership. |

## 24. Profile QR scanning and notification inbox

Implementation anchors: `lib/me/View/qr_scanner_page.dart`, the profile QR and device-notification pages in `lib/me/View/me_page.dart`, `lib/core/services/device_notification_log_service.dart`, `fcm_notification_router.dart`, native QR platform views, and `test/core/fcm_notification_router_test.dart`. These are separate from authenticator-enrollment QR codes.

| ID | P | How | Setup and action | Expected result |
|---|---|---|---|---|
| QR-01 | P1 | H | Display A's profile QR; scan as B on same and mixed-platform phones. | Intended buddy identity/link decoded; add-buddy prompt; correct request after confirmation. |
| QR-02 | P1 | H | Long Unicode/emoji name/handle and international phone in profile QR. | Fixed local encoder capacity handled; valid normalized phone preserved; readable/scannable code. |
| QR-03 | P1 | H | Scan own QR, repeated frames of B QR, then Cancel/re-scan. | Self ignored with explanation; one prompt/request; scanner recovers after cancel. |
| QR-04 | P0 | I | QR claims B's name but contains C's number; missing/invalid phone; existing buddy. | Backend identity validation; display name not proof of ownership; no unauthorized request or wrong trusted membership. |
| QR-05 | P1 | H | Camera denied/permanently denied, unavailable native channel, low light/out-of-focus. | Useful error/exit; no frozen loading; later permission grant/reopen recovers. |
| QR-06 | P0 | I | Scan HTTPS/arbitrary schemes, malformed URI and unrelated `hikercircle` action payloads. | No script/external unsafe action or SOS dispatch caused by profile scan; only supported profile flow or harmless rejection. |
| QR-07 | P1 | H | Scan offline, leave during profile lookup/request, restart scanner. | Honest lookup/request failure; no false buddy success; no stale prompt after disposal. |
| NOTIF-01 | P1 | M | Receive chat/hike/team notifications; open inbox and individual item. | Correct title/body/time/category; intended destination; opened state persists. |
| NOTIF-02 | P1 | M | Star/unstar, mark-all-read, delete one and clear supported inbox items; restart. | Only selected local log state changes; unrelated server/SOS queues not removed. |
| NOTIF-03 | P1 | I | Same notification delivered twice with same ID; different event with same text. | Deduplicate identity correctly; distinct events retained. |
| NOTIF-04 | P1 | M | Cached inbox offline; missing/deleted/expired target; no entries. | Local list usable; target lifecycle honored; honest empty/unavailable state. |
| NOTIF-05 | P0 | H | A notification pending, sign out/in B, tap old notification. | No A private route/data opened under B; ownership/session check applied. |
| NOTIF-06 | P0 | I | FCM payload includes SOS-action deep link or forged/malformed destination. | SOS notification routes to safe active/view path; arbitrary payload cannot trigger production SOS automatically. |
| NOTIF-07 | P1 | H | Tap notification with app foreground/background/terminated before saved-session restoration. | Correct navigation once after readiness; no duplicate dialogs or lost active hike. |
| NOTIF-08 | P1 | I | Type-specific routing missing ID, ID over240 chars and unknown type. | Safe null/error handling; no navigation to unintended resource. |
| NOTIF-09 | P1 | H | Notification permissions denied/channel disabled, token refresh and device replacement. | Local log versus delivered push distinguished; current token/permission state used. |

## Offline examiner demonstrations

Do each journey once with screen recording and once without relying on a prepared recording. Capture queue/cloud evidence after reconnect. The label below is a demo scenario, not an assertion that it already passes.

### A. Returning hiker with no internet

1. Online, sign in A, load T, route, forecast, contacts, history and guide; complete saved preparation.
2. Disconnect internet; confirm a real HTTPS operation fails. Keep GPS on; separately enable Bluetooth if needed.
3. Kill and cold launch the app. Open cached trail, route, first aid and preparation.
4. Start permitted offline hike; walk a short known path; pin/check in.
5. Close/reopen offline; verify same hike and local track. End offline.
6. Reconnect and flush/reopen as implemented. Show one server hike, original end time, correct acknowledged track and one history entry.
7. Explain map tile coverage actually observed; never infer a downloaded basemap from route geometry or from a map previously left open.

### B. SOS without internet

1. Controlled provider/recipients only. Start with locally saved contacts and known queue count.
2. Disconnect, trigger one test-controlled production-mode scenario; show alarm output and queued status separately.
3. Stop alarm, restart offline, confirm queue persists.
4. Reconnect; verify eligible recipients accepted once and result/queue settles.
5. Show provider acceptance evidence separately from recipient receipt. Explain no automatic authority dispatch and no remote recall from Stop.

### C. Offline privacy and conflicts

1. A queues one text/GPS/end/SOS item and stops a live share while offline.
2. Sign out A; sign in B online. Show no A private data or A dispatch under B.
3. Return A; verify only A work retries; recipient link deactivates when cloud stop syncs.
4. Repeat with server cancellation/completion while A offline; terminal status wins on reconnect.

### D. Cold-cache honesty

1. Use disposable fresh install or intentionally empty feature/map caches.
2. Disconnect; show startup requirements and never-cached route/map/forecast/assistant behavior.
3. Contrast with warmed data using precise observed capabilities. Show bundled first-aid text independently of online media.

## Examiner demo route (approximately 15–20 minutes)

| Sequence | What to demonstrate | Cases to prepare | Evidence ready if challenged |
|---|---|---|---|
| 1 | Login/TOTP and brief invalid input | AUTH-02/11, MFA-01/02 | Correct identity; rejected proof |
| 2 | Trail→route→forecast→hazards | TRAIL-01/07, ROUTE-01/14, WEATHER-01/08 | Known fixture and readable source/age |
| 3 | Required gear blocks start; complete gear | PREP-01/02/11 | Missing item, recalculated requirements |
| 4 | Host/participant join and readiness | TEAM-02/08/09/11 | Both phone screens; outsider denial |
| 5 | Active tracking/pin/check-in/deviation | HIKE-01/13/14 | Physical path or deterministic injected trace clearly labelled |
| 6 | Offline restart/end/reconnect | OFF-10/11/14 | Local queue and canonical server/history identity |
| 7 | Manual cancellation, duress, paired test | SOS-01/04, BLE-15 | Controlled outputs; no actual emergency calls |
| 8 | Share/stop and history/rating | SHARE-01/02, END-07/10 | Logged-out recipient browser; original end time |
| 9 | Assistant/feedback/admin if time permits | AI-01/03/10, FEEDBACK-01, ADMIN-02 | Existing regression results and role boundaries |

Keep a secondary prepared account/device, charged button, network hotspot, QR/passkey/TOTP setup, authorized test recipients/stub, and cached route. Time-dependent/sensor/provider failure fixtures should be prepared in a clearly identified test build; do not present simulated detection as observed clinical accuracy or live provider delivery. Recordings are backup evidence, not proof an arbitrary examiner interaction will pass.

## Cross-cutting variants to expand each important case

Avoid blindly multiplying every case by every device. Apply pairwise combinations broadly, then deliberately test high-risk combinations together: offline+restart+end; offline+SOS+account switch; pending upload+canonical remap; readiness+host cancellation; live-share stop+late ACK; locked phone+BLE+safety warning.

| Dimension | Minimum variants |
|---|---|
| Identity | fresh user, returning user, partial onboarding, owner, member, outsider, admin, revoked account |
| Network | normal, airplane mode, Wi-Fi/no internet, DNS succeeds/HTTPS fails, latency, packet loss, service-specific failure, reconnect |
| Cache | cold, warm, stale, partial, wrong-owner, corrupted, old schema |
| Lifecycle | foreground, background, locked, swipe-away, process termination, force-stop/force-quit, reboot, upgrade, restore |
| Permission | granted, first denial, permanent denial, precise/approximate, revoked mid-operation |
| Data | empty, single, many, just below/at/above boundary, malformed, Unicode, duplicate, out-of-order |
| Concurrency | double tap, two devices, overlapping flush, delayed response after navigation/sign-out, commit before ACK |
| Hardware | GPS no-fix/poor fix, absent gyro/barometer/torch, Bluetooth disabled/out-of-range, low battery, muted/headphones |
| Platform | actual release Android/iOS; same and mixed platform pairs; iOS signing type; real button firmware version |

Completion criteria: all P0 cases relevant to the submitted scope passed or documented as blocked/unsupported with examiner explanation; no unresolved identity/privacy, duplicate-dispatch, false-success or lost-durable-work failures; P1 major flows completed; known P2 limits recorded; repeat the final full demo on the exact submitted release and test backend. No finite list proves “all scenarios”; this provides feature, boundary, state-transition, fault, concurrency and platform coverage without asserting an unmeasured percentage.

## Result template

Copy a row for every run, including separate boundary/platform variants:

| Case + variant | Build/commit | Device/OS/signing | Preconditions + fixture | Actual result | Status | Evidence | Defect/notes | Retest date |
|---|---|---|---|---|---|---|---|---|
| e.g. OFF-11 / Android / 250 samples | | | | | Not run | | | |

Statuses: Not run, Pass, Fail, Blocked, N/A. N/A must state the excluded feature/platform/signing reason. A mock test pass and a real-device pass are separate evidence. For offline writes, record before/after queue counts and IDs, pending versus terminal outcome, original timestamps, cloud canonical IDs and duplicate counts. For safety cases, record warning/dispatch/output timings and each independent output failure.

# HikerCircle SOS mechanism — end-to-end technical reference

Reviewed against repository source on **10 September 2026**.

This document describes implemented behaviour, not a proposed design, certification, clinical fall-detection validation or guarantee of rescue. It consolidates the mobile, native, BLE, local-storage and Firebase paths. Existing firmware-specific documents remain relevant; see the source map at the end.

**Scope of this review:** static inspection of Flutter, Android Kotlin, iOS Swift, Firebase functions/rules and existing test coverage. No real SOS was triggered, no emergency contact was messaged, and no physical button or native background reliability test was performed to prepare this document. Source code does not prove that every installed app or deployed function matches this checkout.

## 1. What SOS means in this app

SOS has separate outputs which can succeed or fail independently:

1. **Local attention:** phone siren, vibration, flashlight or warning speech, depending on mode and phase.
2. **Contact messaging:** authenticated Firebase callable → GreenAPI → WhatsApp to saved emergency contacts.
3. **Persistence:** local retry queue, owner-facing SOS records and server-side dispatch audit.
4. **Nearby BLE observation:** owner-button authentication, location handoff/relay, nearby-phone display and optional cloud incident reporting.

There is no demonstrated automatic police/ambulance dispatch integration in these paths. WhatsApp goes to configured contacts, not automatically to Malaysian emergency services. A nearby report is not proof that somebody is helping. Weather precautions, route-deviation notices and monitoring-stopped reminders are **not** themselves SOS dispatches.

## 2. Architecture and ownership

```text
User gesture / widget / trusted paired-button event
  -> Flutter SOS request queue
  -> local alarm where appropriate
  -> location snapshot
  -> SosAlertRepository: persist retry intent, then submit contacts
       -> Firebase sendSosWhatsAppMessage (one dispatch per contact)
          -> authenticate + validate saved contact + deduplicate/rate-limit
          -> GreenAPI sendMessage
          -> authoritative provider-acceptance result
       -> owner SOS log + local queue checkpoint/removal

Active hike automatic detection
  Android: HikeSafetyMonitorService -> 15 s warning -> headless Flutter dispatch
  iOS: IOSHikeSafetyMonitor -> 15 s warning -> ready_for_flutter_dispatch
       -> running/resumed Flutter consumes native event -> same repository
  Dart fallback: FallStillnessMonitor -> configurable response -> same repository

Paired physical button
  authenticated type-4 advertisement -> owner phone dispatch + GPS handoff
  phone -> authenticated GATT location write -> firmware type-5 location relay
  nearby phone -> local incident/map -> optional unverified cloud incident report
```

### Detection owner

`_syncFallStillnessMonitor` in `hiker_home_page.dart` deliberately disables the Dart sensor monitor on Android and iOS. Native services own mobile detection. Running both would create two independent countdowns and duplicate escalation.

The Dart fallback algorithm must therefore **not** be described as the exact Android/iOS production algorithm. The platform comparisons below are intentional and important.

## 3. Trigger modes and user-entry scenarios

| Mode / entry | Trigger | Immediate behaviour | Contact dispatch |
|---|---|---|---|
| Manual SOS from main control | Ordinary manual action | Cancellable **10-second** dialog, then optional iOS output-volume readiness check | Submitted after confirmation/countdown completes |
| Immediate manual / trusted physical button path | Accepted immediate request | Bypasses the ordinary manual countdown; queued independently of an open volume dialog | Manual SOS with appropriate trigger source |
| Medical help | Medical mode request | Loud pattern uses medical alarm asset | Medical reason sent to contacts |
| Duress | Long-hold control, **1,200 ms**, or accepted duress request | No loud emergency pattern; medium haptic feedback may still occur | Discreet duress wording; advises against calling if it increases danger |
| Fall + stillness | Native or fallback detector reaches escalation | Warning phase first; physical alarm after escalation | `fall_stillness`, source `automatic_detection` |
| Prolonged stillness | Configured rest/motion condition reaches escalation | Warning phase first; physical alarm after escalation | `prolonged_stillness`, source `automatic_detection` |
| WhatsApp messaging test | Explicit contact-message test | Separate test content | Clearly says it is not an emergency; server test rules apply |
| Armed paired-button test | Authenticated button mode `0x02` in a live owner arm window | Local test result only | Must not be treated as production SOS or forwarded as a nearby emergency |
| Phone-generated BLE help-beacon test | Developer/test UI broadcasts this phone's GPS help beacon for **5 seconds** | Nearby phones can show a help popup | Separate from authenticated mode-`0x02` testing; may enter observer incident display/logging paths |

Persisted production modes: `manual`, `medical`, `fall_stillness`, `prolonged_stillness`, `duress`. Trigger sources: `mobile_phone`, `emergency_button`, `automatic_detection`. Server also supports the separately validated `test` mode.

“Silent duress” means this path does not start its own loud alarm. It does **not** guarantee an invisible phone: UI, haptics, notifications, recipient replies, an already-running alarm, screen recording or another application may expose activity.

### Deep links and widgets

Android widget providers include manual and three-button SOS variants. Deep links are entry points, not proof that a hardware packet was authenticated. External SOS links have their own confirmation handling in the home page. Trusted paired-button presses must come through the native account-scoped BLE event inbox; `hikercircle://sos/paired` is not a substitute for authenticated delivery.

`FcmNotificationRouter` deliberately rewrites SOS notification action links (`/manual`, `/instant`, `/medical`, `/duress`) to the existing SOS state. **Tapping an old notification must not create a new SOS.**

## 4. Shared mobile dispatch lifecycle

### 4.1 Request and UI queue

`sos_page.dart` captures the mode, source and trigger time when the request enters its in-memory queue. A serialized drain prevents a second request from being stranded while a previous worker finishes. The view model also guards concurrent submissions.

For loud modes, local alarm startup is launched without waiting for cloud acknowledgement. Alarm failure is shown separately and does not prove contact sending failed. Conversely, a sounding alarm does not establish that any contact message left the phone.

The UI shows submission progress and then the returned outcome. It does not intentionally treat initial local queue creation as successful contact delivery. The in-memory request queue itself is not durable: leaving/disposal before a request reaches repository persistence is a limitation.

### 4.2 Location capture

`LocationSnapshotService` holds an **in-memory** location snapshot:

| Setting | Current value / behaviour |
|---|---|
| Passive refresh | 2 minutes |
| Live refresh | 30 seconds; requested intervals are not allowed below this |
| Maximum emergency snapshot age | 5 minutes |
| Persistence | Cleared when service stops/process exits |
| Background | Timer remains installed, but OS suspension can throttle it |
| Ordinary SOS initial wait | Use fresh cached snapshot immediately; otherwise wait at most **600 ms** for refresh, then continue with available/null location |

A null location must remain “Location unavailable”; it is not replaced with an invented route position. Message formatting can include coordinates, a Google Maps link and reported accuracy. Accuracy is an estimate, not a guarantee of an exact casualty position.

The ordinary contact-dispatch path prioritizes dispatch latency over waiting indefinitely for a new GPS fix. The physical-button location handoff separately requests a fresh precise fix and has different timing; see §9.

### 4.3 Durable intent before provider submission

`SosAlertRepository.submitAlert` attempts to create a `queued_alerts` SQLite row before contacting the server. If local persistence fails, it still attempts emergency delivery; durability is then not guaranteed.

Each alert ID is derived from mode and trigger microsecond timestamp. Each contact dispatch ID combines that alert ID with the normalized recipient number. Retries preserve the original event identity, trigger time, message inputs and location.

Contacts are submitted concurrently through `Future.wait`. Current immediate client attempt count is **1** per contact. The callable acknowledgement wait is **4 seconds**; cloud log writing is separately bounded at **4 seconds**. A client timeout does not cancel an already-running server/provider request.

The queue is checkpointed with known dispatch outcomes and only retryable recipients. If contact sends succeed but the cloud-log write fails, a row may remain for log synchronization without resending successful contacts.

During queue flushing, the code also calls `markQueuedAlertSent` when **no retryable contacts remain**, even if the aggregate alert is not `sent`. That database operation means queue work is complete/terminal, not proof of successful delivery. Retain the alert/dispatch result when interpreting a queue row that has left the pending list.

### 4.4 Outcomes and what they actually prove

| Owner-facing status | Meaning | Does not prove |
|---|---|---|
| `queued` | Work remains locally pending/retryable; may also represent in-flight intent | Network transmission, recipient receipt or rescue |
| `sent` | All attempted contacts returned accepted provider results | WhatsApp delivery/read receipt or human response |
| `partial` | Some contacts accepted, others failed/unconfirmed | That failed contacts know of the emergency |
| `failed` | No successful accepted contact result for this attempt | That an ambiguous provider request definitely sent nothing |
| `no_contacts` | Contact list empty | Any automatic fallback to authorities |

The server has a richer `delivery_uncertain` state. Do not reduce that operationally to “definitely not sent.” The authoritative server record is `sosWhatsAppDispatches`, not the client-editable summary record.

## 5. Emergency contacts and message content

- Contacts are account-scoped; repository and Firestore validation support **up to three** contacts.
- Numbers are normalized and validated; duplicates are filtered by the repository. Local cached contacts allow an offline start, but the server authorizes only contacts currently saved in the user's cloud `sos_contacts` list.
- A locally cached contact that is absent from the server can therefore be rejected, even if visible on the device.
- Custom WhatsApp notes are supported for manual, medical and duress modes, with a **240-character** limit. Notes do not replace trusted server-generated reason/identity fields.
- The backend composes the outgoing message from structured validated inputs; it does not act as an unrestricted client-supplied WhatsApp relay.
- The message includes hiker identity, trigger time, reason, location if available, note and suggested recipient action. Duress has different action wording.
- Preferred timezone is validated. The backend fallback identifier is currently **`Asia/Singapore`**, which has the same UTC+8 offset as Malaysia; this is not a timezone named `Asia/Malaysia`.

## 6. Firebase and GreenAPI delivery contract

Entrypoint: `sendSosWhatsAppMessage`, callable function with GreenAPI secrets and a **30-second** function timeout.

### 6.1 Authorization and input checks

The callable requires an authenticated UID matching the normalized authenticated phone identity, a valid enabled owner account, and a recipient in that owner's saved emergency contacts. Client-supplied sender identity is not authoritative.

Validation includes:

- E.164-like recipient format, allowed modes/sources and test-mode consistency.
- Dispatch ID restricted to 8–180 allowed characters.
- Production trigger time no older than **24 hours**; test trigger time no older than **10 minutes**; maximum future skew **2 minutes**.
- Coordinates must be supplied as a pair and within geographic bounds; supplied accuracy must be 0–10,000 m.
- Custom note length and control-character normalization.

### 6.2 Idempotency, lease and rate control

Server record key: SHA-256 of owner UID, dispatch ID and recipient. A separate canonical payload hash binds the content. Reusing the same ID for different content is rejected.

```text
new -> claimed -> sending -> sent
                    |----> failed (some failures retryable, maximum 3 attempts)
                    `----> delivery_uncertain (automatic resend suppressed)
```

The transaction uses a random attempt nonce and **30-second lease**. A previously sent dispatch returns its stored result without another outbound send. A still-valid claimed/sending lease prevents normal concurrent sending. An expired `sending` lease is treated as uncertain, not automatically resent.

Rate limits count per-contact requests, not whole emergencies:

| Traffic | Current owner limit |
|---|---|
| Production SOS | 30 dispatch requests per 5-minute window |
| Test messages | 6 per hour, separate rate document |
| Retryable failed dispatch | At most 3 server attempts for that dispatch |

These safeguards can block/reject traffic; they are not an unlimited emergency-delivery guarantee.

### 6.3 Provider handling

The latency-critical path sends directly with configured GreenAPI credentials rather than making a separate readiness ping before every SOS. The outbound HTTP timeout is **12 seconds**.

| Provider result | Server interpretation |
|---|---|
| Successful response with provider message ID | `sent` / accepted by provider |
| Successful HTTP but missing message ID | `delivery_uncertain` |
| Transport failure known to be definitely unsent | Retryable failure |
| Ambiguous transport timeout/failure | `delivery_uncertain`; do not blindly resend |
| HTTP 408 or 5xx | `delivery_uncertain` |
| HTTP 425 or 429 | Retryable failure |
| Other rejected HTTP response | Non-retryable failure according to classifier |

The client may time out at four seconds while the server is still processing its twelve-second provider request. A later retry with the same identity can retrieve the result safely. This intentional mismatch must not be diagnosed as proof of duplicate dispatch or guaranteed non-delivery.

## 7. Automatic detection: platform-specific state machines

### 7.1 Android native monitor

Owner: `HikeSafetyMonitorService`, a location foreground service with sensors, persistent configuration/event state, notifications, wake-lock handling and a boot receiver.

- Sensor sampling target: **100 ms / 10 Hz**; location interval/telemetry target **30 seconds**.
- Sensitivity is clamped 1–10. With normalized sensitivity `s=(value−1)/9`, thresholds interpolate from low to high sensitivity:
  - Free-fall magnitude: **0.25g → 0.40g**.
  - Impact after free-fall: **5.0g → 4.0g**, within **500 ms**.
  - Direct impact: **3.6g → 2.8g**, independent entry path.
- Impact enters **2-second** bounce grace, then fall verification. Quiet verification requires **10 seconds**. Gyroscope movement resets quiet tracking; fall verification logic includes a **60-second** limit.
- Prolonged-rest expiry in the native NORMAL state directly begins the warning. Do not add the Dart fallback's extra location/gyro verification sequence to this native path.
- Motion bookkeeping includes acceleration deviation from gravity and gyroscope activity. GPS movement uses `max(5 m, min(100 m, 1.5 × max(reference accuracy, current accuracy)))`; accepted native location accuracy is 0–500 m. Motion can postpone rest expiry without a large GPS position change.
- Rest duration defaults to **180 seconds**, clamped natively to **30 seconds–24 hours**.
- Native response window is fixed at **15 seconds**, regardless of the Dart settings object's default response duration.

```text
normal -> direct impact OR free-fall/impact -> bounce -> fall quiet verification
      `-> prolonged no-motion interval -----------------------------------+
                                                                         v
                                       awaiting response (15 s) -> escalation
                                             | response
                                             v
                                        monitoring resumes
```

During warning, Android posts an alert, vibrates, speaks “Are you okay?” and attempts its lock-screen response activity. `SafetyAlertActivity` accepts a touch-down during the warning as a response; back is disabled. The service also recognizes a locked-to-unlocked transition during that warning. This does not mean the app can globally observe every touch in every other app.

At expiry, native code persists the event, starts physical alarm outputs and a **headless Flutter engine**. The background dispatcher restores the signed-in session, requires a matching active hike and local emergency contacts, initializes Firebase and calls the same SOS repository. Native dispatch watchdog: **90 seconds**. Failure remains available for foreground recovery; native dispatch outcome is persisted.

### 7.2 iOS native monitor

Owner: `IOSHikeSafetyMonitor` inside `AppDelegate.swift`, using Core Motion, Core Location, local notifications and persisted event state.

- Device-motion target **0.1 seconds**; timer **1 second**; Firebase telemetry target **30 seconds**.
- Fall impact threshold interpolates **5g → 4g**. The reviewed iOS path does not implement Android's separate lower direct-impact/free-fall branches.
- After impact, wait at least **2 seconds**, then require **10 seconds** with rotation magnitude ≤0.08 and user-acceleration magnitude ≤0.22 m/s²; candidate expires after **60 seconds**.
- Meaningful motion: rotation magnitude >0.08 or user acceleration above the sensitivity-dependent **0.55 → 1.25 m/s²** threshold. This refreshes the rest clock in monitoring phase.
- Rest expiry begins warning; fixed response window **15 seconds**.
- Warning has an “I'm Safe” notification action. Foreground Flutter displays its own explicit countdown UI because there is no Android-style overlay activity.
- Expiry persists **`ready_for_flutter_dispatch`** and starts escalation notification/output callbacks. Flutter must consume the event and perform cloud submission. There is no equivalent independent iOS headless-dispatch engine demonstrated here.
- Native location enables background updates only with appropriate Always authorization. Significant-location-change support and background modes do not remove force-quit/suspension restrictions.
- A local monitoring-stopped watchdog is scheduled for **120 seconds**, refreshed no more often than every **45 seconds**. Its notification asks the user to reopen; it is not itself an emergency-contact SOS.

### 7.3 Dart fallback monitor

`FallStillnessMonitor` is retained for non-native ownership. It samples accelerometer/gyro at **100 ms** and optional barometer at **500 ms**. It has free-fall, impact, bounce, quiet verification and response phases.

Gyroscope quiet uses each axis ≤0.05, with a **10-second** quiet interval. Its response uses `FallDetectionSettings.fallResponseDuration` (default **30 seconds**), unlike mobile native's fixed 15 seconds. Prolonged-location-watch handling is also different: it can continue waiting for quiet until location changes.

Barometer history (5 seconds, examining the preceding 3 seconds) estimates drop using a standard pressure formula and sets a backpack-trap diagnostic flag. The existence of `backpackTrapStillnessDuration=20 seconds` in settings does **not** prove the reviewed fallback selects that duration: the examined verification path uses the 10-second constant. Do not advertise unused constants as deployed protection.

All detector thresholds are heuristics. Phone placement, device sensors, bags, drops, vehicle movement, GPS uncertainty and unavailable sensors can cause false positives or missed events. This review does not establish sensitivity/specificity or clinical performance.

## 8. Native/Flutter handoff and cancellation semantics

Native events include event ID, session ID, kind, phase and relevant timestamps. The home page waits for active-hike restoration and rejects mismatched session events.

| Native state / situation | Flutter action |
|---|---|
| Already dispatched | Display persisted outcome; no duplicate submit for handled event |
| Dispatching / triggering | Recheck after about 2 seconds rather than create a parallel send |
| Dispatch failed / ready for Flutter | Load contacts and use common automatic-SOS path |
| iOS warning before deadline | Show explicit cancellation dialog |
| Android warning | Native activity owns UI; avoid a second Flutter dialog underneath |
| Warning dialog expires | Re-read native state rather than regard “dialog shown” as handled |

**Cancellation before dispatch:** cancels the countdown/reset path; no new SOS should be initiated by that countdown.

**Stopping the physical alarm after escalation:** stops local outputs and resets/acknowledges native state as applicable. It does **not** retract WhatsApp messages, delete an authoritative provider receipt, or guarantee cancellation of an outbound request already accepted by the provider. A durable queued dispatch is also separate from the alarm toggle; do not describe “I'm Safe” as a universal remote-message recall.

Ending the hike stops native monitoring through the active-hike cleanup path. App backgrounding is not logically equivalent to ending a hike; native lifecycle and persisted-event restoration exist specifically to distinguish those cases.

## 9. Physical SOS button and nearby help

### 9.1 Pairing and trust

Current paired protocol uses manufacturer ID **0x02E5** and authenticated **version 2/type 4** advertisements. Packet fields include device ID, mode, uint32 event counter and an **8-byte truncated HMAC-SHA256** tag. Owner verification uses the paired secret and replay state.

- Mode `0x01`: production manual SOS.
- Mode `0x02`: armed local test only.
- Counter wrap uses uint32 serial arithmetic; a firmware reset to a lower counter can require physical re-pairing.
- The native owner inbox is account-scoped. Pending owner presses older than **5 minutes** or implausibly future-dated are discarded.
- Owner inbox persistence is committed before advancing replay state, reducing crash-loss between acceptance and delivery.
- Legacy type-1 behaviour is disabled by default except explicit migration; counterless legacy signals use **10-second** debounce.

Pairing writes 42 bytes: protocol header, six-byte device ID and a **32-byte long-lived secret**. The application payload is not itself encrypted. Production firmware must require an encrypted, authenticated, MITM-resistant BLE connection for secret transfer. An Android bond alone does not establish the firmware's association security; iOS relies on protected GATT attributes to invoke pairing. Physical confirmation is not protection against an unencrypted radio transfer.

Use the firmware documents for complete UUIDs, byte order, payload lengths, status handling and physical-confirmation requirements. Do not replace those details with an invented protocol.

### 9.2 Phone-to-button location handoff

The owner requests `allowLastKnown:false, requirePrecise:true`. If no fresh precise result is returned, the Flutter path can fall back to snapshot refresh/latest usable snapshot; therefore “exact” in the UI/protocol is not proof of a fresh survey-grade fix.

The phone sends a **30-byte authenticated GATT location write** with event ID, E7 coordinates, decimetre accuracy, timestamp and 8-byte HMAC. Firmware must validate event association, freshness, coordinates and authentication, then advertise the **24-byte type-5 location relay**. Firmware missing this implementation cannot be fixed by merely relabelling the app's approximate location.

The type-5 advertising layout does not carry the owner-secret HMAC from the GATT write. Nearby unpaired observers cannot establish owner-secret authenticity from that advertised location alone. Keep the relay's trust level distinct from the authenticated owner trigger.

### 9.3 Nearby phone scenarios

| Observation | Behaviour |
|---|---|
| Valid owner-authenticated press | Owner may initiate its SOS; phone separately attempts handoff |
| Unknown/unpaired device advertises SOS | Nearby-help observation; must not initiate the observer's own emergency-contact SOS |
| Nearby press received before location relay | Store incident and wait **12 seconds** for matching device/counter location |
| Matching location arrives in time | Cancel fallback timer and show relayed coordinates |
| No matching location arrives | Show approximate/detector context; no invented exact position |
| Location arrives after approximate popup | Preserve/update record and allow subsequent exact-location presentation |
| Armed test packet seen by unpaired phone | Ignore as emergency/forwarding event |

RSSI is radio signal strength, not reliable victim distance or a geographic fix. The retained legacy range helper is not proof of an exact nearby location.

Nearby events are saved in account-scoped SQLite `nearby_sos_events`, deduplicated by event key and retained up to **200 per owner**. Best-effort cloud forwarding uses `forwardNearbySosIncident` and can be replayed from local records on reconnect.

The callable validates received time within **10 minutes**, IDs, counter and coordinates. It hashes device/reporter identity and aggregates reports under `nearbySosIncidents/{incidentId}/reports`. It labels the incident **`unverified_nearby_ble`**. Forwarding is incident storage/aggregation; the inspected callable does **not** automatically dispatch WhatsApp to authorities or fan out an emergency FCM to all users.

## 10. Offline, failure and retry scenarios

| Failure / state | Implemented response | Remaining limitation |
|---|---|---|
| No internet | Local outputs can still work; queue remains for retry | No WhatsApp without network/provider connectivity |
| No current location | Continue with available fresh snapshot or null | Contact may receive “Location unavailable” |
| No local storage | Try immediate delivery despite queue-write failure | App termination can lose work |
| No contacts | `no_contacts`; Android headless dispatcher explicitly fails without cached contacts | No automatic authority substitution |
| Cloud contacts differ from local cache | Server rejects unauthorized recipient | Offline contact configuration is not sufficient server authority |
| One recipient fails | Keep successful outcomes; retry only retryable recipient work | Not every contact is notified |
| Provider uncertainty | Server suppresses blind resend | Someone must assess uncertainty rather than assume not sent |
| Cloud log write fails after sending | Keep synchronization work | Summary counters/history can differ from accepted provider dispatch |
| Reconnect | UI/repository retry flow checks reachability and flushes queued rows, default batch limit **10** | Not a guaranteed continuously running queue daemon on a terminated phone |
| Queue event becomes >24 h old | Production callable validation rejects its old trigger time | Local retention is not an unlimited server retry window |
| Account unavailable or active session mismatch in headless dispatch | Fail handoff rather than send under wrong identity | Foreground/account recovery may be necessary |
| Native engine exceeds 90 s on Android | Persist failure and ask user to reopen/retry | Not proof that any already-submitted request was recalled |
| App force-stopped/OS suspends work | Platform-dependent interruption; watchdog/reopen reminders may help | No guarantee of sensor monitoring, TTS, BLE scanning or contact dispatch |

The queue UI describes records as protected from manual removal; alarm stop is not a queue-delete operation. Logs may contain personal identity, contact numbers and precise locations. Do not assume ordinary SQLite tables are independently encrypted just because pairing secrets use protected storage.

## 11. Permissions, local alarms and platform prerequisites

| Area | Android | iOS |
|---|---|---|
| BLE | Scan/connect/advertise permissions, Bluetooth enabled, connected-device foreground service | Bluetooth authorization; central/peripheral background modes; service UUID important for background discovery |
| Location | Fine/coarse as available; separate background-location grant for expected background handoff | When In Use / Always as appropriate, precise location where available; background location mode |
| Motion | Native sensor availability and foreground-service execution | Core Motion permission/device-motion availability |
| Warning UI | Notification/full-screen/overlay capabilities vary by OS and user setting | Local notification authorization; foreground dialog / notification action |
| Audible/physical output | Native audio, vibration, camera torch hardware/settings | Audio session/media volume, vibration and torch availability |
| Restart support | Persisted service configuration and boot receivers | Persisted native state, location/watchdog mechanisms; no blanket force-quit guarantee |

Alarm assets: `assets/audios/sos_alarm.mp3` and medical variant `assets/audios/med_alarm.mp3`. Output-volume readiness uses a minimum normalized threshold **0.55**. A user-initiated iOS volume prompt can delay that UI action; immediate/hardware requests are kept out of the ordinary manual volume-dialog queue to avoid that blockage.

Android's activity-independent `NativeSosAlarmController` loops the alarm asset with alarm audio attributes and runs a repeating short–short–short / long–long–long / short–short–short torch sequence. Its short pulses are 220 ms, long pulses 650 ms, with programmed gaps and a 1,400 ms final gap. Actual torch operation remains hardware/permission-dependent; these timings describe this controller, not a guarantee that all platform output paths are identical.

Manifest/background declarations show configured capabilities, not granted permissions or guaranteed execution. Battery management, locked-screen policy, muted output, headphones and unavailable hardware can independently affect local attention.

## 12. Adjacent safety features — not automatic SOS

- **Monitoring heartbeat watchdog:** Firebase `checkActiveHikeMonitoringHeartbeats` runs every minute. For active hikes expecting monitoring, a heartbeat older than **5 minutes** triggers revalidation, participant offline update and a reopen-reminder path. This is not a confirmed accident.
- **iOS local termination watchdog:** approximately 120 seconds without refresh can produce “Hike monitoring stopped,” asking the user to reopen.
- **Scheduled check-ins:** `sendScheduledActiveHikeCheckIns` is backend-driven so a reminder does not depend solely on Flutter timers. Do not equate a reminder to dispatched SOS.
- **Route deviation:** distance beyond `max(75 m, 2 × accuracy)` for **2 minutes**, with a **15-minute** notification cooldown, produces map/retrace advice and a local notification. The inspected handler does not send a contact SOS.
- **Weather precautions:** see [trail-precaution-rules.md](trail-precaution-rules.md). Upcoming FCM and active spoken cautions are advisory and do not automatically escalate into SOS.
- **Legacy BLE team-location exchange:** disabled/ignored in the home integration because that packet path lacks per-session authentication; cloud-authorized participant updates remain authoritative. It must not be confused with the paired SOS protocol.

## 13. Storage and access boundaries

| Store | Purpose / authority |
|---|---|
| `users/{uid}.sos_contacts` | Saved emergency contacts; server recipient allow-list |
| User custom-note/timezone fields | Message preferences; server validates/normalizes inputs |
| Local `queued_alerts` | Durable retry payloads, status, contact outcomes, coordinates and failure information |
| `sosAlerts/{alertId}` | Owner-facing event history; owner/admin reads, owner-scoped create/update, client delete denied |
| User `latest_sos_alert`, `sos_alerts`, `sosAlertsCount` | Client-written summaries; not authoritative proof of provider acceptance |
| `sosWhatsAppDispatches` | Server dispatch lease, payload hash, nonce, provider result and retry audit; admin read, client writes denied |
| `sosMessageRateLimits` | Server-only counters; client read/write denied |
| Legacy `whatsAppMessageLogs` | Admin-read legacy records, client write denied; not authoritative new dispatch ledger |
| Local `nearby_sos_events` | Observer-owned deduplicated incident history, max 200 |
| `nearbySosIncidents` and `reports` | Server-mediated, explicitly unverified BLE incident aggregation |
| Android preferences / iOS defaults | Native active session, motion clock, pending event state |
| Native paired-button registry | Account-scoped secret/counter state; secure storage and backup constraints apply |

The client summary `_saveAlert` merges the alert but also increments a user count and appends an array entry. Retrying a partially completed cloud write can affect summary counts/history. Use server dispatch IDs/results for delivery auditing, not a raw summary counter.

## 14. Known limitations and review observations

1. Native Android, native iOS and Dart fallback algorithms are different. Documentation or UI that implies identical thresholds/countdowns is misleading.
2. Native warnings are fixed at 15 seconds; the Dart model still exposes a default 30-second response duration. Changing that model alone does not change native warning behaviour.
3. iOS escalation requires available/running/resumed Flutter for the reviewed WhatsApp path. No guarantee of cloud sending after force-quit is established.
4. Sensor loss, stale native location and saved native event recovery need hardware tests. The Android headless payload uses stored coordinates and associates them with the trigger time; this is not proof a new GPS fix was captured at that instant.
5. Type-5 nearby position data is not independently authenticated to an unpaired observer; cloud explicitly treats observations as unverified.
6. The pairing secret requires secure firmware GATT access; application-level HMAC after pairing does not repair a secret exposed during insecure pairing.
7. Stop-alarm/cancel semantics are local and phase-dependent, not remote message recall.
8. Android BLE detected-alert and hike-safety alert code both currently use notification ID **4213**. Channel names alone do not establish independent notification identities; collision/overwriting needs device verification.
9. Some SOS repository dashboard strings are static presentation defaults. They must not be treated as health checks of provider, authority connectivity or delivery readiness.
10. No automatic emergency-services integration, delivery/read receipt confirmation, clinical accuracy certification or guaranteed rescue was established by this review.

These are documentation observations, not fixes performed during this task.

## 15. Verification matrix for developers and testers

Use test accounts/consenting test recipients and explicitly labelled test mode wherever possible. Do not generate production emergencies merely to validate a screen.

| Test family | Scenarios to verify |
|---|---|
| Manual controls | Cancel 10-second countdown; complete it; repeat requests; hardware request while manual volume dialog open |
| Duress | Hold shorter/longer than 1,200 ms; no new loud pattern; inspect visible/haptic side effects |
| Location | Fresh cache, no cache, GPS denied, inaccurate fix, stale >5 min, 600 ms fallback |
| Contacts | Zero/one/three contacts, duplicates, invalid number, local/cloud mismatch |
| Provider | Accepted ID, no ID, 429, 500, transport timeout, definitely-unsent failure, client timeout before server completes |
| Retry identity | Same payload returns stored result; modified payload rejected; partial success; app restart after queue persistence |
| Native fall | Each platform's actual threshold path, motion during quiet phase, no gyro/device-motion, phone-in-bag/drop false-positive cases |
| Native stillness | Safe rest expiry, GPS jitter, rotation without GPS displacement, warning response, no response |
| Cancellation | Before escalation, while headless dispatch starts, after provider accepted; check messages are not described as recalled |
| Lifecycle | Foreground/background/locked/force-stop/reboot; matching vs ended session; Android dispatch watchdog; iOS reopen |
| BLE security | Valid/wrong HMAC, replay, counter wrap/reset, wrong account, stale queued press, armed/unarmed test |
| Location relay | Fresh handoff accepted/rejected, wrong event, no relay, within/after 12-second wait, approximate-to-relayed upgrade |
| Nearby reporting | Same event from multiple observers, no network then reconnect, invalid coordinates/time, unverified label retained |
| Permissions/output | Denied notification/BT/location, background-location missing, battery restrictions, low volume/headphones, no torch |
| Data/logging | Owner isolation, client denial on authoritative dispatch/rate stores, summary count vs dispatch count, queue retention |

Existing automated test areas include `test/sos/`, `test/core/hiker_ble_service_test.dart`, `test/core/fcm_notification_router_test.dart`, `test/home/stationary_location_policy_test.dart`, and `functions/test/{sos_dispatch_helpers,nearby_sos_helpers}.test.js`. Automated model/helper tests do not replace native sensor, hardware, provider-delivery or lock-screen tests.

For this documentation review, **25 isolated automated tests passed**: 15 server helper tests (SOS validation/message/idempotency/failure classification and nearby incident normalization), plus 10 Flutter mode/model/movement-policy tests. These tests did not send WhatsApp messages, run live SOS, establish sensor performance or verify deployment state. Markdown whitespace validation also passed.

## 16. Source map and related documents

| Component | Repository source |
|---|---|
| Modes, statuses, message model | `lib/sos/Model/sos_models.dart` |
| Manual/duress controls and request drain | `lib/sos/View/sos_page.dart` |
| View-model submission/result handling | `lib/sos/ModelView/sos_view_model.dart` |
| Queue, retry, per-contact send and summary log | `lib/sos/Data/sos_alert_repository.dart` |
| Contact storage | `lib/sos/Data/emergency_contacts_repository.dart` |
| Snapshot / native output bridge | `lib/sos/Data/location_snapshot_service.dart`, `sos_device_alert_service.dart` |
| Session detection settings | `lib/home/Model/hike_session_models.dart` |
| Native event consumption, automatic dispatch, button handoff | `lib/home/View/hiker_home_page.dart` |
| Dart fallback / movement policy | `lib/home/ModelView/fall_stillness_monitor.dart`, `stationary_location_policy.dart` |
| Android headless bridge | `lib/home/ModelView/hike_safety_background_dispatcher.dart` |
| Native Android | `android/app/src/main/kotlin/com/example/hiker_circle/`: `HikeSafetyMonitorService.kt`, `SafetyAlertActivity.kt`, `NativeSosAlarmController.kt`, `BleSosMonitorService.kt`, `PairedSosButtonRegistry.kt`, `MainActivity.kt`, widget/boot receivers |
| Native iOS | `ios/Runner/AppDelegate.swift` including `IOSHikeSafetyMonitor`; `ios/Runner/Info.plist` |
| BLE Flutter bridge | `lib/core/services/hiker_ble_service.dart` |
| Local persistence | `lib/app/Data/local_session_database.dart` |
| Provider callable / watchdog / forwarding | `functions/index.js` |
| Trusted message validation / idempotency helpers | `functions/sos_dispatch_helpers.js` |
| Nearby incident normalization | `functions/nearby_sos_helpers.js` |
| Access control | `firestore.rules`; native manifests/entitlements for platform capabilities |

Related references:

- [BLE SOS protocol and pairing contract](CUSTOM_SOS_BLE_PROTOCOL.md)
- [Exact-location handoff firmware contract](SOS_BUTTON_EXACT_LOCATION_HANDOFF.md)
- [Button firmware update requirements](SOS_BUTTON_FIRMWARE_UPDATE_FOR_APP.md)
- [Smartwatch safety integration](SMARTWATCH_SAFETY_INTEGRATION.md) — a separate integration document; existence alone does not prove a deployed watch trigger.
- [Precaution triggers and lifecycle delivery](trail-precaution-rules.md)

Update this reference whenever detection ownership, thresholds, warning timing, server validation, queue semantics, firmware authentication or platform lifecycle behaviour changes. Keep proposed capabilities explicitly separate from implemented paths.

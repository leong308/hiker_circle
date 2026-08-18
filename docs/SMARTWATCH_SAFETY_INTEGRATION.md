# HikerCircle Smartwatch Safety Integration Plan

Status: design only. Apple Watch and other watch features are intentionally not implemented yet.

## Goal

Use a paired, capable smartwatch as a second safety sensor and response surface during an active hike. The phone remains the source of truth for the hike, contacts, Firebase records, and SOS delivery. A watch must improve detection and recovery without becoming a single point of failure.

The system should support premium watches through vendor-specific companion apps behind one capability-based protocol. It must never assume that every model exposes the same sensors, background runtime, haptics, cellular connection, or health data.

## Supported platform tiers

| Tier | Watch families | Phone pairing | Native transport | Intended support |
|---|---|---|---|---|
| A | Apple Watch | iPhone | WatchConnectivity | Full companion: workout session, motion/vitals where authorized, alerts, safe response, SOS, route/check-ins |
| A | Wear OS, including current Samsung Galaxy Watch and Pixel Watch | Android | Wear OS Data Layer | Full companion: Health Services exercise, motion/vitals where available, alerts, safe response, SOS, route/check-ins |
| B | Garmin Connect IQ models | iPhone or Android | Connect IQ Mobile SDK and a Monkey C watch app | Safety events, supported motion/vitals, haptics, response, SOS, check-ins, compact route guidance |
| B | Huawei watches that support third-party Wear Engine apps | Compatible Huawei/Android phone | Huawei Wear Engine P2P | Safety events, available sensors, haptics, response, SOS, check-ins |
| C | Other paired watches with notification mirroring only | Vendor-supported phone | OS/vendor notification bridge | Display warning/SOS notifications and expose supported notification actions only |
| Unsupported | Basic bands or proprietary watches with no app SDK, response action, or data channel | Any | None usable | Do not claim monitoring; show as notification-only or unsupported after a capability probe |

Wear OS Data Layer is only for a Wear OS watch paired to Android. A Wear OS watch paired to iPhone needs a watch-to-cloud design and therefore does not meet this plan's required paired-phone channel. It starts as unsupported unless a particular vendor provides a verified SDK.

## What the watch adds

1. **Better human-response detection**
   - Large `I'M SAFE` button, hardware-button shortcut where permitted, wrist gesture, and haptic acknowledgement.
   - Warning countdown is shown on both phone and watch. A valid response on either device cancels both and re-arms monitoring.

2. **Stronger fall and stillness evidence**
   - Wrist accelerometer/gyroscope is fused with phone motion and GPS.
   - A watch impact followed by orientation change, low wrist motion, and low phone movement raises confidence.
   - Phone-in-backpack motion without wrist motion is treated differently from true whole-person stillness.

3. **Physiological context, where explicitly authorized**
   - Heart rate trend and signal availability can raise or lower confidence.
   - SpO2, skin temperature, ECG, or irregular-rhythm results are optional context only when the vendor exposes them to third-party apps.
   - HikerCircle must not diagnose fainting, cardiac events, or other medical conditions. Missing or implausible consumer sensor data must never suppress an otherwise valid SOS.

4. **Independent safety controls**
   - Hold-to-SOS on the watch.
   - `I'M SAFE`, check-in, add waypoint/pin, request phone sound, and show emergency status.
   - If the phone link fails, queue the signed event locally. A cellular/Wi-Fi watch may send through HikerCircle's authenticated cloud endpoint only after a platform-specific security review.

5. **Useful hike surface**
   - Elapsed time, expected return time, distance, battery on both devices, GPS/link freshness, team status, next route cue, off-route warning, weather hazard summary, and emergency contact delivery state.
   - Periodic haptic check-ins and a return-time reminder reduce the chance that the first watch interaction is an emergency.

## Shared architecture

```text
Watch sensors + watch UI
        |
Vendor adapter (WatchConnectivity / Data Layer / Connect IQ / Wear Engine)
        |
Signed Hiker Safety Protocol
        |
Phone native safety coordinator
        |
Flutter active-hike state + SOS repository
        |
Firebase hike telemetry, alerts, contacts, and team state
```

The phone coordinator must expose the same state machine already used by native Android and iOS monitoring:

```text
MONITORING
  -> WARNING (15-second response window; no SOS)
  -> ESCALATED (send SOS, physical alarms)
  -> DISPATCHED (alarm remains until safe response)
  -> MONITORING (after I'M SAFE/reset)
```

Watch evidence may start `WARNING`, but the watch must not implement a second unrelated countdown. The phone assigns the canonical `eventId`, deadline, escalation status, and reset generation. If the phone is unreachable, the watch uses a locally generated UUID and monotonic timestamp; the phone reconciles it idempotently on reconnect.

## Capability handshake

At pairing and before every hike, the watch sends a signed capability record:

```json
{
  "protocolVersion": 1,
  "platform": "watchos|wearos|garmin|huawei",
  "deviceModel": "vendor model",
  "appVersion": "watch companion version",
  "sensors": ["accelerometer", "gyroscope", "heart_rate", "location"],
  "actions": ["safe", "sos", "check_in", "haptic", "audio"],
  "backgroundMode": "workout|exercise|vendor_background|foreground_only",
  "network": ["paired_phone", "wifi", "cellular"],
  "batteryPercent": 82,
  "permissionsReady": true
}
```

The pre-hike screen reports exactly what is active. A watch is never labelled `Monitoring` merely because Bluetooth pairing exists. Required checks are: companion installed, correct account/device binding, current protocol version, reachable or queued transport verified, needed sensor permissions, adequate watch battery, and a successful test haptic/round trip.

## Event protocol

All messages include `protocolVersion`, `messageId`, `sessionId`, `deviceId`, `sequence`, wall-clock time, monotonic time, payload, and an authentication tag. Persist the last accepted sequence per device to reject replay.

Core message types:

- `hike.start`, `hike.update`, `hike.stop`
- `telemetry.motion_summary`, `telemetry.vitals_summary`, `telemetry.location`, `telemetry.battery`
- `safety.warning`, `safety.warning_ack`, `safety.escalated`, `safety.dispatched`, `safety.safe`, `safety.reset`
- `action.sos`, `action.check_in`, `action.pin`, `action.find_phone`
- `link.heartbeat`, `link.capabilities`, `link.degraded`

Raw high-rate sensor streams stay on the watch. Send compact windows such as peak acceleration, orientation delta, motion variance, sample coverage, heart-rate range, confidence, and timestamps. This reduces battery, bandwidth, health-data exposure, and Firebase cost.

## Detection fusion

Use an explainable evidence score, calibrated separately for each device family:

- Phone impact plus watch impact in the same short window: strong fall evidence.
- Watch impact plus orientation change and 10 seconds of low motion: strong evidence.
- Phone still, watch moving normally: reset stillness; likely the phone was put down.
- Phone moving in a backpack but wrist still for the configured rest duration: warn, because watch evidence better represents the person.
- Abnormal or missing heart-rate samples: supporting evidence only; never a diagnosis and never the sole trigger.
- Watch removed/not worn, charging, low battery, stale samples, or poor sensor contact: mark watch evidence unavailable and continue phone-only monitoring.

Every decision persisted to Firebase should include the evidence sources, freshness, thresholds, watch model, algorithm version, and reason. Do not upload continuous raw health/motion data by default.

## Platform implementation notes

### Apple Watch

- Build a watchOS companion target and use `WCSession` for immediate messages, queued user-info transfers, and current application context.
- Run an `HKWorkoutSession` for the active hike, with clear start/stop UI and the required HealthKit and workout-processing capabilities. Apple permits sensor updates and haptic/audio alerts in the background during an active workout, subject to resource limits.
- Use WatchConnectivity delivery queues; test only on physical iPhone/Apple Watch hardware.
- Request only the HealthKit data needed for the selected feature. Do not imply that Apple Watch health readings are continuously available on every model.

### Wear OS

- Build a Wear OS module with the same application ID and signing identity as Android.
- Use Health Services `ExerciseClient` during an active hike. Use the Data Layer `MessageClient` for immediate commands and urgent `DataItem`/`DataClient` updates for recoverable state.
- Account for Doze and reconnection delay. The watch can use its own network for an optional future cloud fallback, but Data Layer itself remains the paired-device channel.
- Handle Wear OS 6 health permissions separately from earlier `BODY_SENSORS` permissions.

### Garmin Connect IQ

- Build a Connect IQ watch app in Monkey C and use mailbox-style messages through the iOS/Android Mobile SDK.
- Gate sensor use by per-model API support. Connect IQ can expose accelerometer, gyroscope on supported models, heart rate, altitude, pressure, and optional pulse oximetry.
- Garmin Connect Mobile is involved in discovery and/or transport depending on phone platform. Support must be tested against an explicit model list rather than advertised for all Garmin watches.

### Huawei

- Build matching phone/watch applications and use Wear Engine P2P messaging, `ping`, and file/data transfer where supported.
- Treat sensor and background availability as device- and region-specific capabilities. Start with response/SOS/haptics, then enable motion or health evidence only for documented and tested models.

## Safety, security, and privacy requirements

- Explicit opt-in for watch monitoring and separate consent for health metrics.
- Encrypt transport using the platform channel and additionally authenticate HikerCircle event envelopes.
- Bind one watch installation to one authenticated user and phone installation; rotate keys after re-pair, sign-out, or device removal.
- Store minimal summaries, apply retention limits, and let users delete watch/health telemetry.
- Never send health data to emergency contacts unless the user explicitly enables a clearly described field.
- A lost link, dead watch, revoked permission, or watch-app termination must visibly downgrade to phone-only mode; it must not stop the phone monitor.
- Rate-limit watch SOS while preserving immediate first delivery and idempotent retry.

## Delivery phases

1. **Shared protocol and simulator** — Define schemas, signatures, sequence/replay handling, fake-watch test harness, and phone coordinator API.
2. **Apple Watch pilot** — Hike session, haptics, `I'M SAFE`, watch SOS, check-in, link health; then add workout motion/heart-rate summaries.
3. **Wear OS pilot** — Match the Apple feature contract through Health Services and Data Layer, including Samsung/Pixel physical-device tests.
4. **Garmin pilot** — Select a small supported-device matrix and validate background/mailbox delivery and battery use.
5. **Huawei pilot** — Response/control surface first; add sensor fusion only after model-specific validation.
6. **Notification-only adapter** — Honest limited mode for other paired watches.
7. **Controlled field trial** — Opt-in test users, scripted falls/stillness, no-contact/network-loss cases, battery profiling, false-positive review, and rollback switches per platform/model.

## Acceptance criteria

- A response on watch or phone stops all alarms, records the responder/device, and re-arms one canonical monitor.
- Duplicate/out-of-order messages cannot send duplicate SOS alerts.
- Phone-only monitoring continues when watch data becomes stale.
- The UI identifies `full`, `limited`, `disconnected`, and `unsupported` states accurately.
- Warning/escalation timing stays within the defined tolerance on locked/background devices.
- Each supported model passes battery, permission-revocation, phone/watch restart, Bluetooth loss, offline queue, and session-recovery tests.
- No platform/model is enabled remotely until its validation matrix passes.

## Primary platform references

- Apple: [Watch Connectivity](https://developer.apple.com/documentation/WatchConnectivity), [transferring data](https://developer.apple.com/documentation/WatchConnectivity/transferring-data-with-watch-connectivity), [workout sessions](https://developer.apple.com/documentation/HealthKit/running-workout-sessions), and [watch background sessions](https://developer.apple.com/documentation/watchkit/enabling-background-sessions)
- Google: [Wear OS Data Layer](https://developer.android.com/training/wearables/data/overview), [Data Items](https://developer.android.com/training/wearables/data/data-items), and [Health Services permissions](https://developer.android.com/health-and-fitness/health-services/permissions)
- Garmin: [Connect IQ iOS Mobile SDK](https://developer.garmin.com/connect-iq/core-topics/mobile-sdk-for-ios/), [Android Mobile SDK](https://developer.garmin.com/connect-iq/core-topics/mobile-sdk-for-android/), and [sensor APIs](https://developer.garmin.com/connect-iq/core-topics/sensors/)
- Huawei: [Wear Engine overview](https://developer.huawei.com/consumer/en/codelab/WearEngine/) and [P2P app messaging](https://developer.huawei.com/consumer/en/doc/connectivity-Guides/send-message-0000001052460491)

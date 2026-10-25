# hiker_circle

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Google Maps Platform

The onboarding city picker uses the Google Geocoding API to convert the map
coordinate selected by the user into a city. Enable the Geocoding API for the
project and provide a restricted key when building:

```powershell
flutter run --dart-define=GOOGLE_GEOCODING_API_KEY=your_key
```

If this value is omitted, the app falls back to `GOOGLE_ROUTES_API_KEY`.

## Mobile API configuration

The mobile app loads the ignored `.env.public` asset in debug, profile, and
release builds. Set your public `MAPBOX_ACCESS_TOKEN` in the environment or an
ignored `.env` file, then generate the asset before building:

```sh
python3 scripts/prepare_mobile_public_config.py
flutter pub get
flutter run
```

The generator packages only allowlisted public configuration. GreenAPI
credentials must be configured only as Firebase Functions secrets; they must
never be passed to or embedded in the mobile app.

## Firebase mobile security deployment

Before deploying the mobile backend:

1. Configure the `GREEN_API_INSTANCE_ID` and `GREEN_API_TOKEN` Firebase
   Functions secrets.
2. Deploy Firestore rules/indexes, Storage rules, and Functions together. The
   Functions project uses the supported Node.js 22 runtime.
3. Grant the Firebase Rules service agent
   `roles/firebaserules.firestoreServiceAgent`; Storage attachment rules use
   Firestore membership lookups.

GreenAPI sends now call `getStateInstance` before every login-code,
password-reset, or SOS dispatch. The instance must report `authorized`, and a
successful `sendMessage` response must contain `idMessage`; otherwise the app
reports the real provider/configuration failure instead of claiming delivery.

## iOS passkeys and personal signing

Free Apple-account (Personal Team) provisioning does not authorize the
Associated Domains entitlement required by native iOS passkeys. Personal-signed
iOS builds therefore offer Authenticator as the supported second factor and do
not start a passkey request that iOS will reject.

Android and web passkeys remain enabled. If the app is later signed through the
paid Apple Developer Program, select `ios/Runner/Runner.entitlements` for the
iOS target and opt in when building with:

```powershell
flutter build ios --release --dart-define=IOS_NATIVE_PASSKEYS_ENABLED=true
```

Do not use that flag with Personal Team signing; the matching entitlement
cannot be authorized by its provisioning profile.

## BLE SOS monitor lifecycle

On Android, the BLE monitor runs as a `connectedDevice` foreground service and
is restarted after device boot or app replacement when the user has enabled the
monitor. It continues scanning when the Flutter UI is backgrounded, swiped
away, or its process is reclaimed by Android. Android notifications must be
allowed and battery-optimization restrictions may need to be disabled for
reliable delivery on vendor-modified devices.

A user force-stop from Android Settings deliberately prevents all services and
receivers from restarting; the user must open HikerCircle and enable the
monitor again. iOS uses CoreBluetooth state restoration, but iOS may throttle
background scans and does not relaunch a force-quit application for BLE events.

Pairing credentials must only be written to firmware characteristics that
require an encrypted, authenticated, MITM-protected BLE link. Android refuses
to write the pairing secret until the peripheral is OS-bonded. CoreBluetooth
does not expose bond state to iOS apps, so the firmware characteristic security
flags are mandatory there. Physical setup confirmation alone does not encrypt
the GATT exchange.

## Active-hike mobile lifecycle

Solo/team GPS sampling, fall/stillness detection, live sharing, and cloud
heartbeats currently run in the Flutter process. They work while the app is
active, but Android/iOS suspension or process termination can pause new samples
and safety checks. Reopening the app restores the last durable hike snapshot;
it cannot reconstruct points missed while the process was stopped. A true
background implementation requires native continuous-location and motion
services with durable native buffers. User force-stop/force-quit remains an OS
limit even with that architecture.

An authenticated paired-button press can be detected and queued natively, but
cloud contact dispatch and GPS-to-button handoff still require the Flutter app
to activate. Treat the button as phone/app-dependent; life-critical independent
coverage requires hardware with its own cellular or satellite transport.

## SOS button event logs

Log retrieval does not require pairing setup or RST. On the paired-button page,
tap the history icon and choose Start, then press the external button five times
within three seconds. The first press wakes a sleeping button. A completed
sequence suppresses SOS and exposes the read-only log service for 30 seconds.
Android and iOS authenticate with a fresh BLE challenge and the pairing secret
held in encrypted native storage. The secret is never exposed to Flutter.

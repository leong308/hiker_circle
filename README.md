# HikerCircle

HikerCircle is a Flutter app for planning hikes, hiking with a group, and keeping
emergency contacts informed. It brings trail previews, weather, activity
tracking, and SOS tools into one app for Android and iOS.

Firebase handles account services and cloud data. Local storage keeps saved
information and pending work on the phone, so supported features can still be
used without a connection and sync when the network returns.

## What you can do

- Browse trails, check the weather, and preview a route before setting off.
- Plan solo or team hikes, prepare equipment, and set reminders.
- Join a group hike and coordinate through its chat and shared launch flow.
- Record GPS footprints and receive route-deviation or motion-based warnings.
- Send SOS messages to saved contacts, with a local queue for retryable failures.
- Pair a Bluetooth SOS button, share a live-location link, and read first-aid
  guides offline.
- Share hiking updates and caution reports with other hikers.

## Running the app

You need Flutter with a Dart SDK compatible with `^3.10.4`, Python for the
configuration script, and an Android or iOS development environment. The backend
uses Node.js 22 and the Firebase CLI. iOS builds need macOS and Xcode.

This checkout also uses a local package at
`packages/hiker_circle_security_bridge`. Make sure it is present before running
`flutter pub get`.

Add your public Mapbox token to an ignored `.env` file, or set it in your shell:

```dotenv
MAPBOX_ACCESS_TOKEN=pk.your_public_mapbox_token
```

Then run these commands from the project root:

```powershell
python scripts/prepare_mobile_public_config.py
flutter pub get
flutter run
```

The script creates `.env.public`, which the app reads in debug, profile, and
release builds. It includes only the allowed public settings. Regenerate it
after changing those settings.

## Backend configuration

Private provider credentials belong in Firebase Functions secrets, not in the
mobile app. WhatsApp messages use `GREEN_API_INSTANCE_ID` and `GREEN_API_TOKEN`.
The location and routing proxy, `requestPrivateProvider`, uses
`GOOGLE_GEOCODING_API_KEY`, `GOOGLE_ROUTES_API_KEY`, `GEOAPIFY_API_KEY`, and
`OPENROUTESERVICE_API_KEY`. Configure the relevant provider services and their
keys on the backend rather than passing private keys through `--dart-define`.

For a backend setup or release that changes access rules, deploy the Functions,
Firestore rules and indexes, and Storage rules together. Storage attachment
rules look up Firestore membership, so the Firebase Rules service agent needs
the `roles/firebaserules.firestoreServiceAgent` role.

Before sending a login code, password-reset code, or SOS message, the backend
checks the GREEN-API instance with `getStateInstance`. The instance must report
`authorized`, and a successful `sendMessage` response must include `idMessage`.
That confirms provider acceptance; it does not mean the contact has read the
message.

## Account security

Account access uses passwords, WhatsApp OTP, MFA, Firebase Authentication,
server-owned mobile sessions, account-role checks, and database rules.

Firebase App Check and Play Integrity are intentionally not used in this
project. Do not add providers, debug-token registration, token-refresh retries,
or callable attestation enforcement. Keep the existing account checks and
database rules in place.

Before a sign-up phone number is submitted, a consent notice explains the
information used by the app and links to the Privacy Policy. Acceptance is
saved locally first and synced after authentication. Login does not show this
popup, and setup does not ask for consent again.

Account deletion is under Profile → Help Center → Delete HikerCircle account.
After two confirmations, it deletes the main `users/{uid}` document and Firebase
Authentication user, then signs out. Location records, trail history,
subcollections and uploads remain. Registering again creates fresh sign-in
settings; credentials and verification sessions from the previous account
cannot be used for the new registration.

## iOS signing and passkeys

Personal Team builds use Authenticator instead of native iOS passkeys. The free
signing profile does not authorize the Associated Domains entitlement that
passkeys need, so these builds leave the native passkey option disabled.

For a paid Apple Developer Program build, select
`ios/Runner/Runner.entitlements` for the iOS target and enable the option when
building:

```sh
flutter build ios --release --dart-define=IOS_NATIVE_PASSKEYS_ENABLED=true
```

Use this flag only with a provisioning profile that supports the entitlement.
Android and web passkey support is separate from this iOS build setting.

## Background monitoring

Active hikes use native Android and iOS monitors for location, fall detection,
and prolonged stillness. Android runs the safety checks in a foreground service
and can start a background Flutter engine for contact dispatch. iOS uses Core
Motion and location updates, and retains pending safety events for Flutter to
process. Live sharing and cloud updates also depend on network access and the
app's ability to run.

The Bluetooth monitor has its own lifecycle. On Android it uses a
`connectedDevice` foreground service, with restart handling for device boot and
app updates when monitoring is enabled. On iOS it uses CoreBluetooth state
restoration, though background scans may be throttled.

Permissions, battery restrictions, and the operating system can interrupt
monitoring. An Android force-stop blocks service restarts until the user opens
the app again, and iOS does not relaunch a force-quit app for BLE events.
Reopening HikerCircle restores saved hike state, but cannot recreate GPS points
that were never recorded.

The SOS button still depends on the phone and app for location and contact
dispatch. It does not have its own cellular or satellite connection.

## Pairing and reading SOS button logs

Pairing writes must use firmware characteristics that require an encrypted,
authenticated BLE link with protection against man-in-the-middle attacks.
Android waits for an OS bond before writing the pairing secret. iOS does not
expose bond state to the app, so the firmware must enforce those protections.
Pressing the physical setup button alone does not secure the data exchange.

To read logs from a paired button, open its page, tap the history icon, and
choose Start. Press the external button five times within three seconds; the
first press wakes it if it is asleep. Completing the sequence suppresses SOS
and opens the read-only log service for 30 seconds. There is no need to reset
the button or enter pairing setup.

Both platforms authenticate log access with a fresh BLE challenge and the saved
pairing secret. The secret stays in encrypted native storage and is not exposed
to Flutter.

## Finding your way around the code

```text
lib/          Flutter features, shared services, and local data handling
android/      Android services and platform integration
ios/          iOS motion, location, Bluetooth, and platform integration
functions/    Firebase Cloud Functions and backend policies
assets/       First-aid guides, maps, fonts, icons, and audio
web/          Hosting pages, including privacy and live-location views
```

Most feature folders under `lib/` use `View`, `ModelView`, `Model`, and `Data`
subfolders. Start with `View` for a screen, `ModelView` for its behaviour, and
`Data` for storage or service calls. Shared widgets and services are in
`lib/core`; app startup, sessions, and the local database are in `lib/app`.

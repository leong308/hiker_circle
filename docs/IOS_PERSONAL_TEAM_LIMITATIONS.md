# HikerCircle iOS Personal Team Limitations

Last audited: 2026-08-29

This is the release reference for iPhone builds signed with a free Apple
Account, shown by Xcode as a **Personal Team**. In this document, "release
build" means Flutter/Xcode's optimized Release configuration installed for
development on the owner's registered iPhone. It does **not** mean an App Store,
TestFlight, Ad Hoc, or public release; those distribution methods require Apple
Developer Program membership.

The current Runner target uses `ios/Runner/Runner-Debug.entitlements` for
Debug, Profile, and Release. That file is deliberately empty so Personal Team
signing succeeds. `ios/Runner/Runner.entitlements` is the paid-team template and
must not be selected while using Personal Team signing.

## Executive summary

| App capability or behavior | Android | Personal-signed iOS | Cause | Current handling |
| --- | --- | --- | --- | --- |
| Native passkey enrollment and sign-in | Available | Unavailable | Apple does not grant Associated Domains to a free Apple Account | Passkeys are hidden/blocked; Authenticator (TOTP) remains available |
| Firebase remote notifications | Available when the user grants notification permission | Unavailable | FCM delivers iOS messages through APNs; Personal Team cannot enable Push Notifications | The app still works while open, but no background/terminated remote alerts |
| Time Sensitive safety alerts | Android high-priority/full-screen paths are available subject to OS/user permission | Standard iOS local notifications can work, but Time Sensitive interruption is unavailable | Personal Team cannot enable Time Sensitive Notifications | Safety alerts cannot bypass Focus or Notification Summary as Time Sensitive |
| Firebase App Check with App Attest | Can be added with an Android provider | App Attest unavailable | Personal Team cannot enable App Attest | Not currently initialized or enforced in this app; no present feature loss |
| Local Live Activity updates | Not applicable; Android uses a foreground-service notification | Available, subject to iOS version/settings | No paid capability is required for the current local-only implementation | Current code uses `pushType: nil`, so it does not depend on APNs |
| Home-screen SOS widgets | Available | Available on the extension's supported iOS versions | Widget/App Groups are not blocked by Personal Team | Current widgets use deep links and no shared App Group container |
| Background location, motion, and BLE modes | Available through Android services/permissions | Available, but governed by iOS scheduling and force-quit rules | Background Modes are available to a free Apple Account | Keep the existing `UIBackgroundModes`; do not remove them for Personal Team |

The paid-team template contains exactly four restricted capability areas:
Associated Domains, APNs, App Attest, and Time Sensitive Notifications. All
four are covered below. The Runner `Info.plist`, WidgetKit extension, Android
manifest/services, native iOS bridge, Flutter platform gates, and Firebase
notification producers were also scanned. No other currently implemented user
feature was found to be disabled solely because the app uses a Personal Team.

## Features currently lost because of Personal Team signing

### 1. Native passkeys

Affected user flows:

- Enroll a passkey from **Security Methods**.
- Use a passkey during sign-in/security verification.
- Use an existing passkey-only account on a personal-signed iPhone when that
  account does not also have Authenticator enrolled.

Apple requires a `webcredentials` Associated Domains entitlement for native
passkey registration and assertion. The project has the correct relying-party
domain (`hiker-circle.web.app`) and deployed AASA file, but the entitlement must
also be authorized by the provisioning profile. A Personal Team profile cannot
authorize it, which is why iOS returned **“The security request could not be
completed. Please try again.”** before the build guard was added.

Current Personal Team policy:

- `IOS_NATIVE_PASSKEYS_ENABLED` defaults to `false` on iOS.
- The service rejects a native passkey request before opening Apple's sheet.
- Security screens explain that Authenticator is the supported iOS method.
- Android and web passkeys remain enabled.

Do not set the following flag for a Personal Team build:

```text
--dart-define=IOS_NATIVE_PASSKEYS_ENABLED=true
```

If an account has only a passkey, use Android or the web to sign in and add
Authenticator before relying on the personal-signed iPhone build.

### 2. Firebase Cloud Messaging / APNs remote notifications

The app requests an FCM token and the backend already sends an APNs payload for
iOS. However, every FCM message to an Apple app is transported through APNs.
The active Personal Team entitlements contain no `aps-environment`, and a free
Apple Account cannot enable the Push Notifications capability or create the
normal distribution setup required by Firebase.

These app events therefore do not arrive as remote notifications while the
personal-signed iOS app is backgrounded or terminated:

- Direct and group chat messages.
- Nearby upcoming-hike notices.
- Upcoming-hike reminders, host-ready reminders, and join requests.
- Team-hike invitations, acceptance/start/completion updates, teammate pings
  and OK responses, separation alerts, and path-deviation warnings.
- Scheduled active-hike check-in reminders sent by the backend.
- The backend warning that active-hike monitoring stopped and the app should be
  reopened.

This does not disable the underlying chat, hike, team, or Firestore features.
When the app is open and connected it can still read current state. Custom
`hikercircle://` deep links also remain usable. Only APNs-backed delivery and
notification-open routing are absent.

Do not treat `FirebaseMessaging.requestPermission()` succeeding as proof that
remote notifications work. iOS permission controls presentation; an
APNs-enabled provisioning profile and Firebase APNs credential are separate
requirements. `getToken()` may fail or produce no usable iOS delivery path in
this build.

### 3. Time Sensitive safety notification priority

The paid-team entitlement template includes
`com.apple.developer.usernotifications.time-sensitive`, but the active Personal
Team file cannot include it. This affects the native iOS notifications used for:

- The fall/stillness **Are you okay?** warning.
- The **SOS escalation started** warning.
- The **active-hike monitoring stopped** watchdog warning.

Ordinary local notifications are still supported and may show, sound, and open
the app when the user has granted notification permission. What is missing is
the Time Sensitive behavior that can break through Focus and Notification
Summary. The user can also disable Time Sensitive interruptions even in a
properly entitled paid build, so it must never be the only safety path.

The three current native requests set `.timeSensitive` unconditionally. Their
delivery must be tested on the personal-signed physical device; if iOS rejects
rather than downgrades an unentitled request, the Personal Team path should set
the default/active interruption level instead. Standard local notifications
that do not request Time Sensitive priority are unaffected by APNs signing.

Critical Alerts are not a drop-in replacement: they require a separate
Apple-approved entitlement and are not implemented in this project.

### 4. App Attest for Firebase App Check (dormant, not a current loss)

`ios/Runner/Runner.entitlements` contains an App Attest environment entry, but
the Personal Team profile cannot authorize App Attest. The app currently has no
direct `firebase_app_check` dependency and does not initialize an App Check
provider, so removing this entitlement from Personal Team builds does not
remove a working user feature today.

Do not enable Firebase App Check enforcement for this personal-signed iOS app
assuming App Attest tokens will be available. Before future enforcement, choose
and test an attestation/debug strategy for every supported build, then monitor
Firebase App Check metrics before enforcing it.

## Scanned differences that are iOS platform limits, not Personal Team limits

Paying for Apple Developer Program membership would **not** make these behave
like Android:

| Android behavior in this repository | Closest iOS behavior | Practical limitation |
| --- | --- | --- |
| `BleSosMonitorService` runs as a connected-device foreground service and has a boot/app-update receiver | CoreBluetooth background mode and state restoration | iOS may throttle scanning and does not relaunch an app the user force-quits |
| `HikeSafetyMonitorService` is a process-independent foreground location service and has a boot/app-update receiver | Core Location + Core Motion native monitor with significant-location-change recovery | There is no Android-style always-visible foreground service or boot receiver; iOS controls suspension and relaunch opportunities |
| `SafetyAlertActivity` can show when locked, turn on the screen, request full-screen intent, and use an overlay | Local notification, sound/vibration, and Live Activity | iOS has no general overlay/full-screen-intent equivalent for this app; Focus may suppress ordinary alerts |
| Android exposes whether the BLE peripheral is OS-bonded before writing the pairing secret | CoreBluetooth plus firmware-enforced encrypted/authenticated GATT characteristics | iOS does not expose an Android-style bond-state check to the app |
| Android services can be restarted after boot or application replacement | Restore state when iOS launches/relaunches the app for an allowed event | There is no general iOS boot-completed callback for third-party apps |

Both platforms intentionally stop providing these guarantees after the user
explicitly force-stops/force-quits the app. The Android implementation can
recover after ordinary process reclamation and reboot; the iOS implementation
depends on allowed Bluetooth/location restoration events and remains less
deterministic.

## Capabilities that remain available with Personal Team

Do not remove or disable the following merely because the paid entitlement
template is not selected:

- Background Modes, including this app's `audio`, `bluetooth-central`,
  `bluetooth-peripheral`, and `location` entries in `Info.plist`.
- Standard local notifications.
- Camera/QR scanning, Contacts, Motion & Fitness, precise/Always location, photo
  access, Bluetooth central/peripheral use, vibration, speech, torch, and custom
  URL schemes, subject to device support and user permission.
- Keychain storage local to the application.
- App Groups: Apple's capability table currently lists App Groups as available
  to a free Apple Account. This app does not currently use an App Group.
- The SOS WidgetKit extension and its custom-scheme deep links, subject to its
  deployment target and normal extension signing.
- The current Live Activity. It is started and updated locally using
  `pushType: nil`; remote ActivityKit push updates would require APNs and are
  therefore unavailable in a Personal Team build.

The `ManualSOSExtension` deployment target is currently iOS 18.5. Consequently,
the SOS widgets and Live Activity extension will not be installable on iOS
16.0-18.4 even though the main app targets older iOS. That is a project
configuration choice, not a Personal Team restriction.

## Personal Team installation and release constraints

A Personal Team is for on-device development testing. Apple currently applies
all of these limits:

- Up to 10 App IDs, expiring after 7 days.
- Up to 3 registered devices, expiring after 7 days.
- Up to 3 installed apps per device.
- Installed provisioning profiles expire after 7 days, so the app must be
  rebuilt and reinstalled.
- No App Store Connect, TestFlight, App Store, or normal registered-device
  distribution.

Because HikerCircle contains both the Runner app ID and the
`ManualSOSExtension` app ID, it consumes at least two Personal Team App IDs.
Treat an optimized Release build as a seven-day development install, not as a
durable field deployment—especially for a safety app.

## Build policy

### Personal Team build

Keep all Runner configurations pointed at:

```text
ios/Runner/Runner-Debug.entitlements
```

That file must remain free of Associated Domains, APNs, App Attest, and Time
Sensitive Notifications entitlements. Keep iOS native passkeys disabled.

### Paid Apple Developer Program build, if adopted later

After configuring the App ID, APNs key in Firebase, and all capabilities in the
Apple developer account:

1. Point the intended paid-team configurations at
   `ios/Runner/Runner.entitlements`.
2. Confirm the provisioning profile authorizes every requested entitlement.
3. Upload the APNs authentication key to the Firebase iOS app configuration.
4. Build with `--dart-define=IOS_NATIVE_PASSKEYS_ENABLED=true`.
5. Test passkey enrollment and assertion on a physical device.
6. Test every FCM event above in foreground, background, and terminated states.
7. Verify Time Sensitive permission/status separately from ordinary notification
   authorization.
8. Keep App Check enforcement off until an initialized production provider has
   valid metrics for the release build.

## Repository evidence

- Personal Team entitlements: `ios/Runner/Runner-Debug.entitlements`
- Paid-team template: `ios/Runner/Runner.entitlements`
- Runner build configuration: `ios/Runner.xcodeproj/project.pbxproj`
- Passkey build guard: `lib/authentication/Data/passkey_build_support.dart`
- Passkey calls: `lib/authentication/Data/multi_factor_auth_service.dart`
- FCM registration/presentation: `lib/home/View/hiker_home_page.dart`
- FCM deep-link routing: `lib/core/services/fcm_notification_router.dart`
- Backend notification producers: `functions/index.js`
- iOS local safety notifications and Live Activity: `ios/Runner/AppDelegate.swift`
- iOS BLE restoration: `ios/Runner/HikerBleBridge.swift`
- Android services/receivers/lock-screen activity:
  `android/app/src/main/AndroidManifest.xml` and
  `android/app/src/main/kotlin/com/example/hiker_circle/`
- iOS widget extension: `ios/ManualSOS/`

## Primary references

- [Apple: Developer account overview and Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [Apple: Supported capabilities for iOS by membership](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)
- [Apple: Supporting passkeys](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys)
- [Apple: Supporting associated domains](https://developer.apple.com/documentation/Xcode/supporting-associated-domains)
- [Apple: Time Sensitive notification behavior](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive)
- [Apple: Local-only versus push-updated Live Activities](https://developer.apple.com/documentation/activitykit/activity/request%28attributes%3Acontent%3Apushtype%3A%29)
- [Firebase: Add Firebase to an Apple project / Cloud Messaging prerequisites](https://firebase.google.com/docs/ios/setup)
- [Firebase: FCM on Apple platforms uses APNs](https://firebase.google.com/docs/cloud-messaging/ios/receive-messages)
- [Firebase: App Check with App Attest setup](https://firebase.google.com/docs/app-check/ios/app-attest-provider)

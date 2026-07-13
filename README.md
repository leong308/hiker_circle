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

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

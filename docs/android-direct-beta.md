# Android direct beta

This is a direct-download beta, not a Google Play release. The existing upload
certificate is retained for compatibility with the current signed Android APK.
The existing signing configuration remains marked development-only; store bundle
guards are unchanged. Back up the keystore and passwords privately. A different
future Play signing certificate may require a separate installation.

## Public configuration

The developer `.env` must never be packaged for public download. The isolated
build uses only a public Mapbox token and the `hikercircle-android-beta` Google
key, restricted to the Android package/certificate and required Google APIs.
The original Geoapify, OpenRouteService, Google Routes and Geocoding keys are
excluded. Mapbox and Google remain configured alongside saved route data.
These client restrictions reduce exposure; they are not a substitute for
backend authorization, quotas, billing monitoring or abuse prevention.

## Build and verify

1. `node scripts/prepare_beta_key.cjs` verifies valid/invalid client requests.
2. `node scripts/stage_public_beta.cjs` creates `build/public-beta-source` from
   HEAD and the four security-related working-tree source files. Other unrelated
   uncommitted app changes are not included.
3. In that directory, run `flutter build apk --release
   --build-name=1.1.0-beta.1 --build-number=3 --dart-define=HC_PUBLIC_BETA=true`.
4. From the repository root, run `scripts/verify_beta_apk.ps1`. It verifies the
   certificate, build version and absence of original provider credentials.
5. Smoke-test the release on Android without triggering a real SOS.
6. `node scripts/publish_beta_apk.cjs` uploads the exact verified APK to a
   content-addressed beta object, verifies its public SHA-256 and generates
   `web/site/beta-release.json`.
7. Test the landing-site content and deploy Firebase Hosting only.

Do not upload the isolated source, signing files or `output/beta` reports.
The public APK uses an object-specific download token. Storage rules are not
opened globally. Remove/revoke the token if the release needs to be withdrawn.
For a later beta, update the version/build in the build, verification, publishing
scripts and website together. Never overwrite a released version's object.

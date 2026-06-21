# HikerCircle Play Internal Testing Release

## Upload artifact

Build and upload:

`build/app/outputs/bundle/release/app-release.aab`

Package name: `com.leongziqi.hikercircle`

Version: `1.0.0 (1)`

Target API: `36`

Upload-key certificate:

- SHA-1: `4E:84:B7:B3:74:06:76:8A:07:15:59:59:8F:FE:80:0C:61:98:7B:3A`
- SHA-256: `7E:53:A6:38:96:66:0A:05:BA:77:B1:16:36:AE:7F:CB:6F:42:A2:60:09:ED:B6:C1:4C:28:4D:01:D5:26:69:82`

## Play Console

1. Create the app as **HikerCircle**, choose **App**, and choose **Free**.
2. Enroll in **Play App Signing** and let Google generate the app-signing key.
3. Open **Testing > Internal testing** and create a release draft.
4. Upload `app-release.aab`.
5. Before starting rollout, complete the Firebase certificate steps below.
6. Use these release notes:

   `Initial internal test for Firebase Phone Authentication, GreenAPI WhatsApp fallback, hiking sessions, maps, community, and chat attachments.`

7. Save, review, and start the internal rollout.
8. Add tester email addresses or a Google Group, then install from the Play opt-in link.

## Firebase Phone Auth after first upload

1. In Play Console, open **Setup > App integrity > App signing**.
2. Copy the **SHA-1** and **SHA-256** fingerprints from the **App signing key certificate** section, not the upload certificate.
3. In Firebase Console, open **Project settings > Your apps > Android app**.
4. Add both Play app-signing fingerprints to `com.leongziqi.hikercircle`.
5. Return to the Play release draft and start the rollout.

The upload-key certificate and Play app-signing certificate are intentionally different.

The currently registered debug fingerprints do not make a Play-installed release valid. Firebase Phone Auth must have the Play **app-signing** SHA-256.

## Files that must be backed up and never committed

- `android/app/hiker-circle-upload.jks`
- `android/key.properties`

The public certificate is:

- `android/upload-key-certificate.pem`

## Production-access note

Internal testing has no tester-count requirement and supports up to 100 testers.
If this is a personal Play developer account created after November 13, 2023,
public production access requires a closed test with at least 12 testers opted
in continuously for 14 days.

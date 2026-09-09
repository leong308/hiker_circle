# HikerCircle in-app feedback

## Selection (9 September 2026)

Compared the official Flutter packages and documentation:

- [BetterFeedback / feedback 3.2.0](https://pub.dev/packages/feedback): open-source screenshot annotation, custom themes, and a submission callback that can use our Firebase backend. Android and iOS supported.
- [Wiredash](https://pub.dev/packages/wiredash): richer hosted feedback dashboard, labels and surveys; requires a Wiredash project ID and secret from a separate account.
- [Shake](https://pub.dev/packages/shake_flutter): richer hosted bug-reporting tooling; requires its own service integration. [Flutter screenshot limitations](https://help.shakebugs.com/en/articles/5191101-black-screenshots-in-flutter-blank-bug-reports-double-tap-recording-fix) also need device validation.

Selected BetterFeedback plus a custom Firebase workflow because the app already uses Firebase and no hosted-feedback credentials were provided. This adds categories, review/removal of screenshots, submission history and admin triage beyond a basic screenshot callback. It does not claim BetterFeedback is more feature-rich than hosted alternatives.

The local SenzoCG/senzo_3nt_sbox copy was inspected. Its pubspec and Dart sources do not contain the feedback dependency or BetterFeedback implementation, so no Senzo feedback source was copied.

## Usage

- Profile → Send feedback → Write feedback, or Capture and mark a screen.
- In capture mode, Navigate lets the user move through the app; Draw marks the problem. The captured text and image open a final review page, not an immediate upload.
- Select Problem, Suggestion or Other. Review/remove the screenshot and press Send feedback.
- My feedback shows the most recent 100 reports, with New / In review / Resolved status.
- Admin dashboard → Hiker feedback inbox reviews all reports and updates status. The admin inbox is also available from an administrator's feedback page.

Uses the app's Material theme and light/dark colors. BetterFeedback's capture chrome is themed green. Submission uses the primary HikerCircle loading popup and a 30-second timeout. A timed-out operation may still finish remotely; retries reuse an immutable ID and Firestore transaction to prevent duplicates. Fields remain unchanged during retry. Drafts remain in memory only while that review page is open.

## Data and privacy

- Firestore: appFeedback/{id}; account UID, category, message, platform, server timestamp, review status and optional private screenshot path.
- Storage: app_feedback/{uid}/{id}/screenshot.png; PNG metadata only, maximum 5 MB. No public download URL is generated.
- No automatic location collection, logs, passwords, background recording or third-party feedback service. Screenshots may contain whatever the user captures; review before sending.
- Authenticated owners read their own reports; admins read all. Only admins change status, and cannot rewrite the original report through client rules. Attachments cannot be overwritten after submission.
- Submissions are for product feedback, not emergency response. No email/FCM escalation is implemented; administrators review the inbox.
- Existing Firebase billing applies. There is no per-user submission rate limiter or automatic retention cleanup in this implementation; administrators should monitor volume and configure a retention policy if needed. A screenshot uploaded before a failed report write can remain as an orphaned private object.

## Verification and deployment

### Production cross-service permission prerequisite

On 9 September, the connected Android device's screenshot upload returned Storage HTTP 403 even though rule compilation and emulator tests passed. The production Storage service agent was missing `roles/firebaserules.firestoreServiceAgent`, required for the rule's `firestore.exists` check. The installed Firebase CLI skips its IAM check in non-interactive mode; a successful rules deployment did not establish this permission. Emulators do not reproduce production IAM.

Fixed the project binding for `service-41069899337@gcp-sa-firebasestorage.iam.gserviceaccount.com` with that specific role, preserving all other IAM bindings. Do not replace this with public Storage access. Future project provisioning must check this role explicitly. See [Firebase cross-service rule permissions](https://firebase.google.com/docs/rules/manage-deploy#manage_permissions_for_cross-service_cloud_storage_security_rules).

The app now distinguishes permission denial from network failures and logs only the Firebase plugin/error code (no report contents or credentials).

After IAM propagation, retried the existing screenshot report on the connected RMX3834 Android device at 11:23 MYT. It reached the server-acknowledged Thank you screen without reinstalling the app. The error-message regression suite passed all eight tests and targeted analysis reported no issues.

Firestore and Storage rules and the owner/createdAt history index deployed successfully to hiker-circle. No Cloud Function or hosting deployment is needed for this feature.

Validation completed: 17 Flutter tests passed across feedback, achievements and theme regression suites. Five emulator security tests passed, covering report ownership, forged fields, admin status permissions, scoped history queries and private/immutable screenshot uploads. Physical-device capture remains a release smoke-test item.

Run Flutter validation:

```powershell
flutter test test/feedback/feedback_page_test.dart test/me/achievements_page_test.dart test/home/theme_consistency_test.dart
flutter analyze lib/feedback lib/app/View/hiker_circle_app.dart lib/me/Data/me_repository.dart lib/me/View/me_page.dart lib/admin/View/admin_page.dart
```

Run isolated rules tests (never targets production; Java 21+ may be required by the emulator):

```powershell
Push-Location test/firebase
npm ci
Pop-Location
firebase emulators:exec --config firebase.feedback-test.json --project demo-hikercircle-feedback --only firestore,storage "node --test test/firebase/feedback-rules.test.cjs"
```

Before distributing, rebuild and smoke-test on physical Android and iOS: text submission, capture/annotation, screenshot removal, offline timeout/retry, personal history, and admin status update. Flutter-rendered screenshots may omit native Mapbox/video surfaces. Device screenshot fidelity has not been verified by desktop widget tests.

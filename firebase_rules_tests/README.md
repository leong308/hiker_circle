# Firebase security-rule tests

These tests run entirely against Firebase demo-project emulators; they do not
read or mutate production data.

Install the pinned test dependencies once:

```powershell
npm --prefix firebase_rules_tests ci
```

Then run Firestore and Storage rules together:

```powershell
$env:JAVA_HOME = '<path-to-a-Java-21-JDK>'
$env:Path = "$env:JAVA_HOME\bin;" + $env:Path
firebase emulators:exec --config firebase.feedback-test.json --only firestore,storage --project demo-hiker-circle "npm --prefix firebase_rules_tests test"
```

The Storage rules use `firestore.get()` to authorize group-chat attachments.
Both the general security suite and feedback suite now share this pinned
dependency tree, demo project, and emulator configuration (Firestore 8181,
Storage 9199). `npm run test:security` and `npm run test:feedback` select one
suite inside the same emulator session. The former `test/firebase` dependency
environment was removed; no test coverage was removed.
Before deploying them, ensure the Firebase Rules service agent
`service-PROJECT_NUMBER@firebase-rules.iam.gserviceaccount.com` has the
`roles/firebaserules.firestoreServiceAgent` IAM role on the project.

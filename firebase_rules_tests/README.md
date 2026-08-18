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
firebase emulators:exec --only firestore,storage --project demo-hiker-circle "npm --prefix firebase_rules_tests test"
```

The Storage rules use `firestore.get()` to authorize group-chat attachments.
Before deploying them, ensure the Firebase Rules service agent
`service-PROJECT_NUMBER@firebase-rules.iam.gserviceaccount.com` has the
`roles/firebaserules.firestoreServiceAgent` IAM role on the project.

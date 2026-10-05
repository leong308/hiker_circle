# Upcoming hike operations: demand-driven scheduling

Implementation: 4 October 2026, Malaysia time. Firebase project: `hiker-circle`.

## Behavior

One shared job is retained:

`projects/hiker-circle/locations/us-central1/jobs/firebase-schedule-processUpcomingHikeOperations-us-central1`

| Live Firestore state | Behavior |
|---|---|
| First upcoming listing is created or restored | Resume the existing job; retain its five-minute interval. |
| Additional listings exist | Keep enabled, with no additional job or repeated resume action. |
| A listing is removed but another remains | Keep enabled. |
| Last listing is cancelled, soft-deleted, physically deleted, or expired by maintenance | Pause the existing job. |
| Participant, reminder, nearby-notification or other metadata changes | Ignore for scheduler control when listing membership is unchanged. |
| An old/duplicate removal event arrives after a new listing exists | Query current data; keep or resume the job. |
| An invocation was already dispatched when paused | It cannot be recalled; it checks live data and safely exits if empty. |

Membership matches the existing maintenance query: `upcomingHikes` documents with `isDeleted == false`. It does not count historical or soft-deleted documents. The departure grace period remains: listings are soft-hidden after departure plus 15 minutes, on the next scheduled check. The scheduler stays enabled through this grace period so expiry still happens. No additional time-based scheduler is created. A distant-future listing also counts, as requested.

## Existing functionality retained

The combined job still sends due FCM departure reminders according to saved preferences, checks hikes departing within 24 hours for new/escalated environmental precautions, and soft-hides expired listings. It does not start/end an active session, send SOS, delete history, or modify WhatsApp delivery. Reminder and precaution deduplication remains intact.

The expiry guard also handles a legacy `expired: true, isDeleted: false` record: it must still be soft-hidden rather than keeping this job enabled forever. No new physical deletions are performed.

## Controller and safeguards

`reconcileUpcomingHikeOperationsOnWrite` is one retry-enabled Firestore written trigger in `asia-southeast1`, covering create/update/delete. It only reconciles membership transitions. Nearby-notification delivery remains in its separate existing handler and is not replayed by this controller.

The controller reuses the active monitor's tested implementation, with separate control documents and membership query. A transactional 120-second lease serializes control; busy owners cause retry rather than losing a wake-up event. Controller timeout is 60 seconds. A current `limit(1)` query with an empty projection avoids a counter or full-collection scan. Before pause/resume, lease ownership is verified; live membership is rechecked after the Scheduler action. Up to three race-recovery passes converge before a retryable failure.

Scheduler requests use modular Firebase Admin `getApp()` credentials and ten-second HTTP timeouts. Runtime code only gets/pauses/resumes allowlisted fixed jobs; it never creates another job. Missing jobs and IAM/transport failures surface rather than silently disabling functionality.

`processUpcomingHikeOperations` has one maximum instance, concurrency one, its existing 540-second deadline and a separate 600-second run lease. Completed schedule timestamps suppress duplicate/older deliveries; failed work remains retryable. Scheduler retries are bounded to three with 30–120-second backoff. Its tasks remain concurrent. After maintenance, including a task failure, reconciliation re-reads listings so last-listing expiry pauses the job. An empty snapshot also reconciles and exits immediately.

## Backend-only schema additions

Mobile accounts (including app administrators) cannot read/write/delete these records under the existing catch-all rules:

- `maintenanceState/upcomingHikeOperationsSchedule`: `leaseOwner`, `leaseExpiresAtMillis`, fixed `jobName`, confirmed `jobState`, `hasUpcomingListing`, `lastReconciledAtMillis`, bounded `lastErrorCode`/`lastErrorAtMillis`.
- `maintenanceState/upcomingHikeOperationsRun`: independent `leaseOwner`/`leaseExpiresAtMillis` and `lastCompletedTickMillis` for completed-delivery deduplication.

No app rebuild, new index, client rule permission, credential, or IAM grant is required. Existing runtime IAM requires Scheduler job get/pause/enable permissions, just as the active monitor does. Pause preserves the job and stops future dispatches; it does not guarantee zero platform charges.

## Deployment and checks

Deploy only `processUpcomingHikeOperations` and `reconcileUpcomingHikeOperationsOnWrite`. New triggers do not replay old listings; reconcile once after deployment because Firebase/manual job changes can leave an initially enabled job.

```powershell
node scripts/inspect_upcoming_hike_schedule.cjs --reconcile
node scripts/inspect_upcoming_hike_schedule.cjs
```

Default is read-only. `--reconcile` invokes the existing worker once through Scheduler, allowing deployed runtime credentials to control it; it creates no fake listing or new job. Inventory, live membership, scheduler state and both functions are independently read back. If live listings exist, the ordinary worker may perform due real maintenance during this invocation.

Tests cover first/additional listings, last removal, remaining listings, restoration, stale events, concurrent creation/removal races, failure/retry, expired leases, overlap protection, separate active/upcoming state, tick replay, fixed-job transport, write-trigger filtering, empty execution and reconciliation despite task failure. Security rule tests include denial for both new operational documents.

References: [Firebase scheduled functions](https://firebase.google.com/docs/functions/schedule-functions), [Firestore event delivery](https://firebase.google.com/docs/functions/firestore-events).

## Verified rollout — 4 October 2026

- Both affected exports deployed successfully and independently confirm `ACTIVE` on Node.js 22. The worker confirms maximum instances one/concurrency one; the new write trigger confirms retry-enabled delivery.
- Live inventory confirms exactly one upcoming-operations Scheduler job, still configured `every 5 minutes`.
- Before rollout the job was enabled despite no non-deleted upcoming listings. After invoking the existing worker once, its deployed controller paused it. Independent read-back confirms `hasUpcomingListing: false`, `jobState: PAUSED`, no controller error and released controller/run leases, at approximately **21:21:45 Malaysia time** (13:21:45 UTC).
- All **170 backend tests** passed, including the unchanged active-monitor suite and new upcoming controller/worker regressions. Unified rule emulators passed **31 general security groups and 5 feedback tests**, including protection of the new operational documents.
- Independent active-monitor read-back confirms it remains a single paused two-minute job with no active hikes; its four deployed functions remain active. They were not redeployed in this rollout.
- No fake hike/listing was created, no existing history was deleted, and no IAM, client rules, indexes, app code or assets were changed for this feature. Real-device first-listing/last-removal smoke testing was not performed; these transitions and races were covered in backend tests.
- Initial deployment analysis encountered the machine's Node.js 20 CommonJS/ESM compatibility error. Running the Firebase CLI under Node.js 22, matching the deployed runtime, resolved it without altering package dependencies.

Local ignored evidence: `tmp/upcoming-schedule-tests-2026-10-04.log`, `tmp/upcoming-schedule-rules-2026-10-04.log`, `tmp/upcoming-schedule-deploy-2026-10-04-node22.log`, `tmp/upcoming-schedule-live-2026-10-04.log`.

# Active hike monitor: demand-driven scheduling

Implementation date: 4 October 2026, Asia/Kuala_Lumpur. Project: `hiker-circle`.

## Expected behavior

There is one Cloud Scheduler job for the whole system:

`projects/hiker-circle/locations/us-central1/jobs/firebase-schedule-monitorActiveHikes-us-central1`

| Current live hike state | Scheduler behavior |
|---|---|
| No document has `status: active` | Pause the existing job. No periodic monitor invocations are requested while paused. |
| First active hike starts | Resume the existing job; checks run every 2 minutes. No per-hiker job is created. |
| More active hikes start | Leave the already-enabled job enabled; do not repeat the resume action. |
| One hike ends while another remains active | Keep the shared job enabled. |
| Last active hike completes, is abandoned/cancelled, changes away from active, or is deleted | Pause the shared job. |
| GPS/heartbeat changes without an active/non-active transition | No scheduler reconciliation or Scheduler API request. |
| A session is created already completed after an offline hike | Do not resume the job for that historical session. |
| A scheduled invocation was already in flight when the job paused | It cannot be recalled; it checks current sessions, avoids duplicate work and safely exits if none remain. |

The two-minute interval is retained; resuming does not create a separate immediate monitoring loop. Firestore lifecycle events are asynchronous, so enable/pause follows event delivery rather than blocking the hiker's start/end button.

## Existing triggers used

No extra Firestore trigger or polling scheduler was added. These existing handlers reconcile active membership before their usual work:

- `awardAchievementsForStartedHike`: creation of an active hike.
- `recordHikeTerminalStateAndAchievements`: transition into/out of `active`, including terminal statuses not used for achievement awards.
- `preserveDeletedHikeTerminalState`: deletion of an active hike; now explicitly retries transient failures.

Each uses retry-enabled event delivery. The controller queries current `hikeSessions` with `status == active`, `limit(1)` and an empty field projection, rather than incrementing a fragile counter or trusting an old event payload. Duplicated/out-of-order events therefore converge on live truth. Existing achievement, terminal-state, live-sharing and team-status handling remains.

## Singleton and race safeguards

- Runtime code can GET, pause or resume only the fixed job. It never calls create/delete/list to provision per-hiker jobs.
- A Firestore transaction claims a two-minute controller lease. A competing controller throws a retryable event failure rather than accepting and losing the event. A crashed controller's lease expires and can be reclaimed.
- Before a Scheduler mutation, the owner validates its lease. Actual controller runtime deadlines are 60 seconds, shorter than lease expiry.
- After observing/applying Scheduler state, the controller rechecks current active hikes. A start during a pause, or an end during a resume, causes another reconciliation pass. If activity continually changes, the event retries.
- A transition arriving just after the final recheck still runs its own retry-enabled lifecycle handler. It cannot be permanently swallowed by the preceding owner.
- `monitorActiveHikes` uses one runtime instance, concurrency one, and a separate distributed run lease. Overlapping deliveries skip duplicate work. Completed schedule timestamps are retained so duplicate/older deliveries do not run again; failed work does not mark the tick completed.
- The monitor also reconciles if it finds no active sessions, or has just abandoned stale sessions. This is a fallback after deployment or last-session cleanup, not an additional idle polling loop.

## Backend-only control records

Both records live under the existing `maintenanceState` collection. Mobile clients, including mobile admin users, cannot access them under the catch-all rules. Only backend IAM-authorized code manages them.

### `maintenanceState/activeHikeMonitorSchedule`

- `leaseOwner`: opaque unique owner, or null when released.
- `leaseExpiresAtMillis`: lease deadline, or zero when released.
- `jobName`: fixed Scheduler resource path.
- `jobState`: last confirmed `ENABLED` or `PAUSED` state.
- `hasActiveHike`: live membership result at reconciliation.
- `lastReconciledAtMillis`: successful reconciliation time.
- `lastErrorCode`, `lastErrorAtMillis`: bounded operational error metadata; no tokens or user identities.

### `maintenanceState/activeHikeMonitorRun`

- `leaseOwner`, `leaseExpiresAtMillis`: independent monitor execution lease.
- `lastCompletedTickMillis`: successfully processed schedule time for replay/out-of-order suppression.

## Permissions and failure behavior

The runtime uses Firebase Admin's existing Application Default Credential and project ID; no credential/key is embedded in source. Required Scheduler permissions are `cloudscheduler.jobs.get`, `cloudscheduler.jobs.pause`, and `cloudscheduler.jobs.enable` (resume uses **enable**, not a permission named resume). The existing runtime service account already has the project Editor role; this change does not grant additional IAM roles or broaden access.

Scheduler requests have 10-second HTTP timeouts. Missing jobs, permission errors, unexpected job states, uncertain transport results and persistent start/end races surface as event failures for retry; they are not hidden and do not cause a duplicate job to be created. Claims are released on normal/error completion; process crashes recover via lease expiry. A missing job must be restored by deploying the existing `monitorActiveHikes` export, not by a second runtime scheduler.

Pause stops future scheduled executions, not already-dispatched requests. It preserves the job, schedule, OIDC target and monitoring logic. It is not job deletion or a guarantee of zero platform charges.

## Monitoring behavior retained

Existing stale reporting detection, 10-minute FCM reminder cooldown, team offline/ended updates, and stale-session abandonment thresholds are unchanged. This function does not perform on-phone fall/stillness detection or automatically send emergency SOS messages.

## Deployment and validation

Deploy only the four affected functions. After deployment, reconcile against live data: Firebase redeployment or manual Scheduler edits can leave a job enabled even when no hike is active. An initial invocation of the existing monitor safely reconciles the current system state without making a fake hike or sending a fake emergency.

Regression coverage includes first start, additional hikers, last end, one remaining hiker, stale events, start-during-pause/end-during-resume races, duplicate delivery, controller failure/retry, expired/crashed leases, overlap suppression, tick replay and the fixed-job HTTP contract. All **158 backend tests** pass under Node.js 22, including a regression for the modular Firebase Admin v14 `getApp()` credential path. Unified rule emulators pass **31 general security groups and 5 feedback tests**, including denial of both operational records to mobile owner/member/admin/anonymous accounts.

Post-deployment verification tool:

```powershell
node scripts/inspect_active_hike_monitor.cjs
```

It checks the single-job inventory, current active membership, job state and the four affected functions without changing data. After deploying this scheduler, use `--reconcile` when an initial reconciliation is needed:

```powershell
node scripts/inspect_active_hike_monitor.cjs --reconcile
```

This invokes the existing monitor through Cloud Scheduler once, then verifies convergence. It never creates a hike or another Scheduler job and does not directly rewrite Scheduler state using administrator credentials. The actual deployed runtime performs the pause/resume decision.

### Verified rollout — 4 October 2026

- All four affected exports were successfully updated and independently confirmed `ACTIVE` on Node.js 22. Existing function names and regions were retained. `monitorActiveHikes` confirms one maximum instance and concurrency one; all three lifecycle handlers confirm retry-enabled delivery.
- Inventory across `us-central1` and `asia-southeast1` confirms exactly **one** monitor Scheduler job, still configured for `every 2 minutes`.
- The live system had **zero active hikes** at verification. The deployed runtime successfully returned HTTP 200, logged `Active hike monitor schedule reconciled` with `state: PAUSED`, and confirmed `hasActiveHike: false` at **13:14:07 Malaysia time** (05:14:07 UTC).
- Independent read-back confirms the job is `PAUSED`, both operational leases are released, the successful tick timestamp is recorded, and the controller's `lastErrorCode` is null.
- Initial live verification exposed an Admin v14 legacy-accessor error. It was corrected to modular `getApp()`, covered by a new regression test, and all four callers were redeployed before final verification. Earlier failed verification logs remain as evidence; they were not deleted.
- Start/resume, other active hikers, last-end pause and concurrency/race cases were regression-tested without creating counterfeit live hike records or sending emergency traffic. A real-device first-start/last-end smoke test is still useful; it was not claimed as performed here.
- No Flutter/native code, app assets, IAM grants, Firestore/Storage rules, indexes, other schedulers or unrelated function exports were changed by this rollout. No app rebuild is needed for this backend-only feature. The existing rules already deny the control records; their protection was tested in the emulators.

Evidence: `tmp/active-monitor-tests-2026-10-04.log`, `tmp/active-monitor-rules-2026-10-04.log`, `tmp/active-monitor-deploy-fixed-2026-10-04.log`, and `tmp/active-monitor-live-read-2026-10-04.log` (ignored local logs).

## Primary API references

- [Google Cloud Scheduler pause](https://docs.cloud.google.com/scheduler/docs/reference/rest/v1/projects.locations.jobs/pause).
- [Google Cloud Scheduler resume](https://docs.cloud.google.com/scheduler/docs/reference/rest/v1/projects.locations.jobs/resume).
- [Firebase Firestore events: ordering and duplicate delivery](https://firebase.google.com/docs/functions/firestore-events).

# Navigation when a hike starts

A successful start returns to the existing Home shell, selects Home, and displays the active hike. Trail details, the start wizard, preparation, and team readiness must not remain above that screen or reappear on Back.

Previously, starting from trail details only popped the wizard. Home had already switched to the active hike underneath, but the trail page stayed visible.

## Code ownership

| Code | Responsibility |
| --- | --- |
| `lib/home/View/hiker_home_page.dart` — `_revealActiveHike` | Select Home and unwind to the actual Home route after setting `activeHike`. |
| `_startInstantHikeFromWizard` | Return to the active hike after a successful immediate start, including permitted offline fallback. |
| `_startUpcomingHikeNow` | Return after a successful scheduled start and dismiss its own progress dialog. |
| `_openTeamHikeInvite` | Return after participant session creation, or when opening an invitation for the already-active team. |
| `_showUpcomingHikeDetails` | A stale notification for the current active hike opens that hike instead of reopening its preparation. |
| `_TeamHikeLaunchPageState._finishTeamNavigation` | Complete readiness once, unwinding any nested safety page and returning the team result to the waiting caller. |
| `lib/home/View/hike_start_navigation.dart` | Shared route ownership helpers. Preserve history below Home; ignore already-removed routes; remove only the owned dialog when another page covers it. |
| `lib/home/View/start_hike_wizard_page.dart` — `_startNowAndFinish` | Close only its own route if the owner has not already removed it. A late success callback must not pop Home. |

The transition happens after session creation succeeds (or an allowed offline session is accepted), not when the user first taps Start. A failed start or cancelled preparation leaves the setup available. Background restoration and ordinary session updates do not force navigation.

Progress cleanup is tied to the actual dialog route, so a delayed callback cannot accidentally pop a new page. Team completion is scheduled after the current frame to avoid changing the route stack during a stream-driven build.

## Verification

- `test/home/hike_start_navigation_test.dart`: immediate, scheduled, and team stack shapes; preservation of history below Home; repeated cleanup; covered-dialog cleanup; nested team result delivery; cancelled preparation.
- `test/home/start_hike_wizard_navigation_test.dart`: actual wizard success callback unwinds through trail details without popping Home; blocked start retains the draft.
- Existing preparation, planned-state, and active-session persistence tests cover the surrounding state contracts.

Widget tests simulate route transitions. They do not create real Firebase sessions or exercise two physical phones joining a team.

# Internal app showcase capture guide

Prepared 18 September 2026.

Showcase URL: https://hiker-circle.web.app/internal/app-showcase/

This page lives on the existing website. It is unlisted, omitted from public navigation and marked noindex. It does not require sign-in; anyone with the URL can view it. The page presents the catalog one feature at a time, grouped by chapter, with a short description and media or an in-place capture brief. The full inventory and detailed capture instructions remain in `web/internal-showcase/catalog.json` and this guide. No new phone captures are claimed by the presentation.

## What is already wired

The catalog contains **48 flows** in **10 chapters**. **22 flows reuse existing website screenshots or recordings**, **4 have rendered interface previews**, and **22 flows still need their first capture**. The manager-facing page makes all 48 available without showing a large grid at once. The unrelated route-preview screenshot is deliberately suppressed, adding one replacement to the capture priority. Other partial or staged media is labelled, and missing or provisional media gets a capture brief on the page. The catalog remains authoritative for wiring new media.

Existing media was matched against the image descriptions in `web/index.html` and the milestone metadata in `web/site/app.js`. Existing September 7–8 recordings are earlier captures, not newly obtained phone footage. Older milestone dates describe the product story; they are not necessarily the media capture date. Original/staged material is labelled in each catalog item's `notes`.

The current preparation experience is **Get ready to hike**, a guided sequence of required gear, optional extras, individual safety prompts and a final review. `docs/PREPARATION_REQUIREMENTS.md` supersedes older tabbed preparation screenshots. Do not present the older `output/final-preparation/` or `output/home-redesign/preparation-*.png` as the current guided flow.

## What to provide

Provide the original portrait PNG screenshots and MP4 screen recordings in a folder named `internal-showcase-captures`. Use the exact filenames below. A full flow recording is useful even if some of its screenshots already exist; a matching still image acts as its poster.

- Keep the entire app screen visible at native resolution. Avoid camera photos, chat-compressed copies, added device frames or baked-in explanatory captions.
- Use one consistent theme for the main set. Optional light/dark counterparts can add `-light` or `-dark` before the extension.
- Record most flows for 10–30 seconds, pausing 1–2 seconds at each important state. Portrait H.264 MP4 at 30 fps is preferred; provide original MOV files if conversion is needed.
- Start with content loaded, close unrelated notifications and use a fictional/consented demonstration account. Check every visible phone number, name, conversation, profile QR, live-location link and map location.
- Provide a small `capture-notes.txt` with the app build/version, iOS or Android version, capture date, device model, demonstration account label, and any steps that could not be completed. State whether data is real, seeded or a no-dispatch demonstration.
- Do not include sign-in passwords, verification codes, Authenticator setup secrets or raw pairing credentials. For settings and admin captures, use already sanitized fixture data where possible.

## New phone captures: exact shot list

This list covers the 22 missing visuals plus the preparation and administration features currently illustrated with interface previews. Each section gives the screenshot filename, suggested recording filename, entry path and requested interaction. Additional filenames mentioned in the shot instructions are useful supplementary images. Screenshots can be delivered first; the ordered flows remain available while recordings are pending.

### Join & set up

**Phone sign-in** — `sign-in.png`; optional `sign-in.mp4`.

Path: Open HikerCircle → Enter phone number → Complete sign-in → Arrive at Home.

Capture the sign-in screen with a fictional phone number. Record 10–15 seconds from the prepared form to Home using a demo account; omit passwords and verification codes.

Capture constraint: Sign-in may send a real WhatsApp verification message; use a controlled demo account.

**Create your hiker profile** — `onboarding.png`; optional `onboarding.mp4`.

Path: Verify demo account → Complete profile → Choose city on map → Continue to contacts.

Capture the profile form and city-level map picker as onboarding.png and onboarding-city.png. Record scrolling through the fields without revealing a password or exact home address.

**Account recovery** — `account-recovery.png`; optional `account-recovery.mp4`.

Path: Open Forgot password → Choose recovery method → Verify account → Set new password.

Capture the recovery entry and method selection in a test account. A short recording may show navigation only; stop before requesting codes or changing credentials.

**Trusted contacts** — `emergency-contacts.png`; optional `emergency-contacts.mp4`.

Path: Open Emergency contacts → Review demo contacts → Open contact editor → Save controlled demo data.

Capture three fictional contacts with relationships and an open editor. Use a demo repository or controlled test account; do not show real numbers or change production contacts.

### Explore a trail

**Weather on the map** — `weather-map.png`; optional `weather-map.mp4`.

Path: Open normal route map → Tap cloud control → Choose weather layer → Inspect legend and opacity.

Capture rain, wind and temperature overlays after loading, named weather-map.png, weather-map-wind.png and weather-map-temperature.png. Record 15 seconds changing layer and opacity.

Capture constraint: Requires configured weather service. Regional layers are not measurements at every point on the trail.

### Prepare & plan

**Build the itinerary** — `checkpoints.png`; optional `checkpoints.mp4`.

Path: Choose route → Open Checkpoints → Add or select a stop → Review itinerary.

Capture the current checkpoint timeline and map picker. Record highlighting a stop and returning to its place in the route.

Capture constraint: Use a demo draft; do not save modifications to shared production trails.

**One packing question at a time** — `required-gear.png`; optional `required-gear.mp4`.

Path: Open Final preparation review → Read required item → Choose Yes, packed or Not yet → Continue guide.

Capture the current Get ready to hike required-item question showing its reason and response buttons. Record 15 seconds answering two items in a demo plan.

Capture constraint: Current guided flow supersedes older preparation tabs. A saved tick records the answer, not physical verification.

**Extras, safety & final review** — `preparation-review.png`; optional `preparation-review.mp4`.

Path: Review optional extras → Review safety prompts → Read final review → Resolve missing required items.

Provide preparation-review.png at final review plus preparation-extras.png and preparation-safety.png. Record 20–30 seconds through extras, a safety prompt and a blocked/ready final state in a demo plan.

### On the trail

**Check in & save a place** — `check-ins-pins.png`; optional `check-ins-pins.mp4`.

Path: Open active hike → Choose Check In → Choose Pin → Review saved status.

Record one check-in and one pin in an isolated demo hike; capture confirmation with a non-sensitive location.

**Stay aware of your team** — `team-tools.png`; optional `team-tools.mp4`.

Path: Open team hike → Open Team Tools → Review roster status → Inspect teammate on map.

Capture Team Tools with at least two test participants and a timestamped map. Record switching between roster/check-ins and the map.

Capture constraint: Use controlled participants. Stale updates and route warnings do not prove an emergency.

**Conditions & optional live sharing** — `active-weather-sharing.png`; optional `active-weather-sharing.mp4`.

Path: Open active weather → Review route conditions → Open Location sharing → Review link controls.

Capture active weather and Location sharing as active-weather-sharing.png and location-sharing.png. Record only demo link controls; use a test location and stop sharing afterward.

Capture constraint: Creating a live link exposes its location to people holding that link; use a demo session.

### Safety & support

**Time to cancel a manual alert** — `sos-countdown.png`; optional `sos-countdown.mp4`.

Path: Open isolated safety demo → Tap Manual SOS → Review countdown → Cancel SOS.

Record a 10–15 second manual countdown and cancellation using lib/showcase_safety_main.dart or another isolated no-dispatch harness. Capture countdown at five seconds.

Capture constraint: Do not demonstrate against live emergency contacts. Cancelling before dispatch differs from stopping a local alarm afterward.

**Clear alert status & notes** — `sos-queue-notes.png`; optional `sos-queue-notes.mp4`.

Path: Open SOS status → Inspect queued detail → Review contact outcomes → Open message-note settings.

Provide sos-queue-notes.png showing a seeded queued/partial alert and sos-notes.png showing fictional text. Record inspecting details in an isolated demo; never enqueue a real SOS for media.

**Safe button tests & event history** — `button-test-logs.png`; optional `button-test-logs.mp4`.

Path: Open paired button → Enter explicit test mode → Press test button → Review test result or log.

Capture the Test mode active and Button press detected states, then event history with identifiers removed. Record only an authenticated mode-0x02 test inside its active arm window.

Capture constraint: Ordinary physical presses can trigger production SOS. Do not use an unarmed button press as a demo.

**Nearby SOS context** — `nearby-help.png`; optional `nearby-help.mp4`.

Path: Open Nearby SOS → Select demo incident → Open map → Review timestamp and context.

Capture a seeded incident list and map as nearby-help.png and nearby-help-map.png. Use repository fixtures; do not broadcast a fake live emergency.

Capture constraint: Nearby observations are not verified rescue responses. Test phone broadcasts can reach other devices.

### Your hiking circle

**Discover & join a group** — `join-group.png`; optional `join-group.mp4`.

Path: Open Find a Hike → Inspect group details → Review join policy → Join demo or request approval.

Capture one open group and one approval-required group using test hosts. Record request and acceptance only with controlled consenting demo accounts.

**Stories & buddies** — `stories-buddies.png`; optional `stories-buddies.mp4`.

Path: Open Stories → Read demo hike post → Open buddy requests → Review a demo request.

Provide stories-buddies.png with sample stories and buddy-requests.png. Record scrolling and request review; do not publish posts or send requests to real users for the capture.

**Conversations around the hike** — `chat.png`; optional `chat.mp4`.

Path: Open a demo conversation → Review sample messages → Open attachment options → Review mute or pin controls.

Capture a consented demo chat and attachment picker. Record navigation through image/video/document options and mute settings without transmitting a real message.

### After the hike

**Replay & share the journey** — `team-replay-share.png`; optional `team-replay-share.mp4`.

Path: Open team history → Play route replay → Open Share Hike → Review share preview.

Capture team replay and the recap preview, then record 15–20 seconds of playback. Stop at the system share chooser; no external posting is required.

### Your app

**Your profile & preferences** — `profile-settings.png`; optional `profile-settings.mp4`.

Path: Open Me → Review profile or QR → Open App Settings → Review notification history.

Provide profile-settings.png, profile-qr.png and app-settings.png with a fictional account. Record theme/language controls and notification history without private messages.

**Prepare for limited coverage** — `offline-resources.png`; optional `offline-resources.mp4`.

Path: Open App Settings → Review offline map → Inspect cache status → Open downloaded guidance.

Capture offline download/status and storage usage. Record opening already downloaded guidance without connectivity; downloading may use network data.

Capture constraint: Offline resources do not imply offline contact-message delivery. Verify availability on the captured build.

**Feedback with context** — `feedback.png`; optional `feedback.mp4`.

Path: Open Send feedback → Capture and mark a screen → Review message and image → View My feedback.

Capture annotation mode and final review with harmless demo text. Record drawing and reviewing; use seeded My feedback for status examples instead of submitting a live report.

### Internal operations

**Administration workspace** — `admin-overview.png`; optional `admin-overview.mp4`.

Path: Open Admin → Review overview → Choose collection → Inspect a demo record.

Capture the current mobile admin overview and one collection. Use a demo administrator dataset; crop all real user data and do not approve, remove or edit live records.

**Maintain trail & community quality** — `admin-trails-moderation.png`; optional `admin-trails-moderation.mp4`.

Path: Open Trail library → Inspect trail editor → Review safety report → Review community queue.

Provide admin-trails-moderation.png for a trail draft and admin-review-queue.png for seeded moderation. Record editor/navigation without saving, deleting, approving or hiding live content.

**Support & button diagnostics** — `admin-diagnostics.png`; optional `admin-diagnostics.mp4`.

Path: Open Support and diagnostics → Inspect feedback status → Open Button Debugging → Review sanitized session.

Capture sanitized feedback inbox and Button Debugging screens, named admin-feedback.png and admin-diagnostics.png. Record a safe armed button test using test hardware; exclude payload secrets and personal records.

Capture constraint: Diagnostics may contain raw packets, account data or identifiers; inspect every exported frame.

## Refreshing existing media

These entries are already reviewable. A fresh capture should replace an earlier screen only after confirming it matches the current build.

| Flow | Replacement file | Current reference |
| --- | --- | --- |
| Login security | `login-security.png` / `login-security.mp4` | Existing website media; recorded before this showcase. Interface may differ from the current build. Native iOS passkeys require supported signing; Personal Team builds use Authenticator. |
| Find your next trail | `trail-discovery.png` / `trail-discovery.mp4` | Existing website media; recorded before this showcase. Interface may differ from the current build. |
| A trail at a glance | `trail-detail.png` / `trail-detail.mp4` | Existing website media; recorded before this showcase. Interface may differ from the current build. |
| Follow the route before departure | `route-preview.png` / `route-preview.mp4` | Existing website screenshot. A new recording is needed for the current first-person controls. |
| Choose a weather window | `trail-forecast.png` / `trail-forecast.mp4` | Existing website media; recorded before this showcase. Interface may differ from the current build. |
| Community trail cautions | `hazard-report.png` / `hazard-report.mp4` | Existing website capture. Submitting a report writes community data. |
| Your next hike | `upcoming-home.png` / `upcoming-home.mp4` | Rendered preview of the Next Hike card; capture the full Home carousel. |
| Solo or team | `create-hike.png` / `create-hike.mp4` | Existing website capture. Longer routes apply HikerCircle-specific solo distance rules. |
| Timing & reminders | `schedule-reminders.png` / `schedule-reminders.mp4` | Existing website capture. |
| Safety before departure | `hike-safety-settings.png` / `hike-safety-settings.mp4` | Existing website media; recorded before this showcase. Interface may differ from the current build. Warning behavior is platform-specific; the screenshot does not validate detection reliability. |
| Get everyone ready | `team-launch.png` / `team-launch.mp4` | Existing website media; recorded before this showcase. Interface may differ from the current build. Starting creates an active session and may notify invited participants. |
| Your active hike | `active-tracking.png` / `active-tracking.mp4` | Existing website capture. GPS and background behavior depend on platform, permissions and app state. |
| Emergency controls | `sos-center.png` / `sos-center.mp4` | Existing website capture. Production SOS can message contacts and activate sound, vibration or flashlight. |
| A discreet duress demonstration | `duress-demo.png` / `duress-demo.mp4` | Existing staged demonstration with sample contacts. It does not establish real WhatsApp delivery or invisible operation. |
| Pair a physical SOS button | `physical-button.png` / `physical-button.mp4` | Existing website media; recorded before this showcase. Interface may differ from the current build. Button operation depends on the phone/app and supported firmware. |
| Prepared guidance | `first-aid-gear.png` / `first-aid-gear.mp4` | Existing website capture. Use app guidance as presented; emergency dialing and Open SOS are real actions. |
| Meet your hiking circle | `find-hikers.png` / `find-hikers.mp4` | Existing website media; recorded before this showcase. Interface may differ from the current build. |
| Close the hike & rate the route | `finish-rating.png` / `finish-rating.mp4` | Existing website capture. Completing or rating a live hike writes account/community records. |
| Your hike history | `hike-history.png` / `hike-history.mp4` | Existing website media; recorded before this showcase. Interface may differ from the current build. |
| The details of your day | `hike-analysis.png` / `hike-analysis.mp4` | Existing website media; recorded before this showcase. Interface may differ from the current build. |
| Progress worth revisiting | `achievements.png` / `achievements.mp4` | Existing website media; recorded before this showcase. Interface may differ from the current build. |
| Widgets & Live Activity | `native-widgets.png` / `native-widgets.mp4` | Historical/staged presentation. Platform behavior and background reliability must be validated separately. |
| The original safety interface | `original-sos.png` / `original-sos.mp4` | Historical interface, labeled 28 May 2026 in existing website metadata; not the current product screen. |

Each existing-media item also contains a specific `capture` instruction in the catalog. The most valuable refreshes are the current Next Hike card, the guided preparation journey, the active Home map, current safety settings, forecast interaction and team readiness.

## Interface previews already wired

Four inspected renders are currently shown with an **Interface preview** label: the Next Hike card, required-gear question, final preparation review and admin overview. These use demo data and are not fresh phone screenshots. Replace them with the filenames specified above when ready.

The incomplete weather-layer test image and earlier checkpoint component render were deliberately omitted because they do not show the requested full feature screen.

## Connected-phone capture

No further phone access is requested in this task. When you choose to supply captures, use the phone’s screenshot or screen-recording controls and save originals with the filenames above. Begin with read-only pages: Home, trails, forecasts, profile, history, achievements and settings. A phone being attached does not prove that this host can read its screen; record the actual tool result before claiming a successful capture.

Do not replace an installed production app, sign out an existing account or modify its records solely to get a cleaner shot without considering the user's active session. If capture is unavailable, these filenames and instructions are sufficient for the user to provide the missing media.

For SOS animation, `lib/showcase_safety_main.dart` is an existing separate media-capture entry point with no Firebase initialization and fake contact/alert repositories. Review its implementation before running it. Its contact-success state is **staged**; label it accordingly. A real installed build's manual, medical or duress controls may send WhatsApp messages, activate alarms and write incident records.

Use seeded repositories for queued/partial/failed alert states and nearby incidents. An armed physical-button mode-0x02 test is distinct from an ordinary production press. Phone-generated BLE help-beacon tests may be visible to other devices. Do not trigger real contacts, call emergency services, broadcast false incidents, or send community/chat messages just to produce media. Team, chat and sharing flows should use controlled demo participants.

## Wiring a supplied capture

1. Inspect the image or every meaningful recording state and confirm its catalog flow. Verify the capture date/build and whether its state is real or staged.
2. Place approved files in `web/internal-showcase/media/`. Keep lowercase hyphenated filenames. Do not commit original private capture folders.
3. Find the matching `id` in `web/internal-showcase/catalog.json`. Set `image` to `/internal/app-showcase/media/<id>.png` and, if provided, `video` to `/internal/app-showcase/media/<id>.mp4`.
4. Set `source` to `device` only for an actual phone screenshot/recording; use `preview` for rendered UI or other non-device demonstration media. Keep a precise `notes` label for seeded/staged data, older builds or platform limits.
5. Update `updated` when the catalog changes. Keep `description` at 20 words or fewer and `flow` at 3–6 short steps. Keep the capture instruction even after media is added so future refreshes have a shot brief.
6. Load the showcase locally. Check that images resolve, posters match their video, videos play with controls and the narrow mobile layout remains readable. Check browser network responses for missing files.
7. Include only approved showcase files in the normal website deployment. A hidden URL and no-index tags reduce discoverability; they do not make the page or its image/video URLs confidential. Use actual access control if authenticated internal-only access is required.

Example catalog update:

```json
{
  "id": "required-gear",
  "chapter": "prepare",
  "title": "One packing question at a time",
  "description": "Pack the required items for the route and understand why each item matters.",
  "flow": ["Open Final preparation review", "Read required item", "Choose Yes, packed or Not yet", "Continue guide"],
  "source": "device",
  "image": "/internal/app-showcase/media/required-gear.png",
  "video": "/internal/app-showcase/media/required-gear.mp4",
  "capture": "Capture the current required-item question, reason and response buttons.",
  "captureFile": "required-gear.png",
  "notes": "Captured on [date], [device/build], using a controlled demonstration plan."
}
```

## Feature confidence and exclusions

The inventory was inspected in Flutter source and local project documentation. It documents available UI and intended code paths; it does not certify deployed backend behavior or an installed phone's build.

- Guided preparation: `lib/home/View/final_preparation_review_page.dart` and `docs/PREPARATION_REQUIREMENTS.md` describe the current one-question flow and required-item gate.
- Routes, forecasts, weather layers and cautions: `lib/trail/View/trail_page.dart`, `lib/core/widgets/route_preview_map.dart` and `docs/WEATHER_MAPS.md`. Regional weather layers and estimated first-person rain values are distinct.
- Active hike: `lib/home/View/hiker_home_page.dart` uses `ActiveHikeHomePage`; the older standalone active-dashboard branch is not the normal production shell.
- SOS, queue status and paired button: `docs/SOS_MECHANISM.md` distinguishes platform behavior, provider acceptance from recipient receipt, and local alarms from contact dispatch. Do not promise automatic emergency-service dispatch or guaranteed rescue.
- Community/chat: `lib/circle/View/circle_page.dart` and `group_chat_detail_page.dart`. Nearby-trail-post personalization and profile-history privacy switches are visibly unavailable placeholders; do not show them as delivered features.
- History and achievements: `lib/me/View/hike_history_page.dart` and `me_page.dart`; use real fixture-backed tabs instead of inventing populated data.
- Admin: `lib/admin/View/admin_page.dart` and `button_debugging_page.dart`. These are authorized staff workflows; examples should use demo data.
- Smartwatch, LoRa and mesh concepts remain excluded from the implemented-flow inventory. `docs/SMARTWATCH_SAFETY_INTEGRATION.md` is a plan, and the public website marks those ideas as future concepts.
- Native background safety and widget capabilities vary by platform, permissions and signing. Repository documents contain historical lifecycle descriptions; a demonstration recording alone cannot establish reliability.


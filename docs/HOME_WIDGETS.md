# Home screen widgets

Updated: 17 September 2026.

This document covers both the **phone Home Screen widgets** and the cards inside HikerCircle. The initial implementation added only in-app cards; that did not register anything in the phone’s widget picker. The native implementation now adds **Next Hike**, **Hike Weather**, and **Upcoming Hikes** alongside the existing SOS widgets.

## Add the phone Home Screen widgets

A full native build/install is required after this change. Flutter hot reload and hot restart cannot register a new WidgetKit configuration or Android widget provider.

- **iPhone:** install the updated app, open HikerCircle once, then long-press an empty area of the Home Screen → Edit → Add Widget → search HikerCircle → select **Next Hike** or **Hike Weather** (small/medium), or **Upcoming Hikes** (large) → Add Widget. The hiking configurations are listed before SOS in the existing widget extension.
- **Android:** install the updated app, open it once, long-press the launcher Home Screen → Widgets → HikerCircle → drag **Next Hike**, **Hike Weather**, or **Upcoming Hikes** onto the screen. Launcher wording varies.
- You can add either widget before creating a hike. It displays “Plan your next hike” until a schedule is available. Save a scheduled hike in the app to populate it.
- If only SOS is listed, the phone still has an older native extension/provider registration. Install the rebuilt native app, open it once and reopen the widget gallery. A Dart-only reload is insufficient.

## Installing a version that reopens normally

For routine use on a physical iPhone, install a **release** build. The user’s current preference is **install only; do not automatically launch the app**. Use the separate build/install commands below. For intentional interactive debugging only:

```sh
flutter run --release -d <iphone-device-id>
```

For a separate build and install:

```sh
flutter build ios --release
xcrun devicectl device install app --device <coredevice-id> build/ios/iphoneos/Runner.app
```

Flutter debug builds on physical iOS devices require Flutter/Xcode debugging support when launching. Closing that session and reopening from the Home Screen can fail before the Flutter UI appears. Use release/profile for standalone launch; use debug through `flutter run` or Xcode for development. See [Flutter’s iOS launch limitation](https://api.flutter.dev/flutter/services/RestorationManager-class.html).

During device validation on 15 September, the debug install crashed at `FirebaseFunctionsPlugin.register(with:)` during startup. A signed release build replaced it and was tested with standalone process launches. Both builds include the widget registrations, but release is the appropriate installed version for opening the app and testing widgets without a debugger.

## Phone widget inventory

| Phone widget | Display | Tap action |
|---|---|---|
| Next Hike (new) | Next eligible saved trail, departure countdown/date, route distance/difficulty where space permits, gear checklist progress; medium iOS and Android also show return time | Opens HikerCircle Home to review preparation; never starts a hike or SOS |
| Hike Weather (new) | Scheduled-window temperature and peak rain probability, update time, outdated/missing forecast state; larger layouts include daylight context | Opens HikerCircle Home with the hike weather briefing |
| Upcoming Hikes (large) | Next four eligible schedules with date, departure time and distance; Android reduces to three for smaller height or larger text | Each row opens that hike’s preparation; empty space opens Home |
| HikerCircle SOS (existing) | SOS shortcut | Existing SOS deep-link flow |
| HikerCircle SOS Actions (existing) | Existing separate SOS actions | Existing action-specific deep-link flows |
| Hike Live Activity (existing iOS) | Active hiking status on supported system surfaces | Existing live activity behavior; this is not a separately addable Home Screen widget |

### Weather context and countdown layout

Hike Weather retains its existing colors and layout, with a small context label: **Upcoming hike** before departure, **Scheduled hike window** between departure and planned return, and **Past hike window** during the brief post-return eligibility period. This widget is based on saved schedules; the label does not claim that live tracking is running. The displayed forecast always covers that hike's planned departure-to-return interval.

The rain metric is labeled **Peak chance** and means the highest rain probability in that interval. Both sizes show temperature range, rain probability and forecast update time. The wide widget additionally shows daylight guidance. The sun/cloud header icon identifies weather; it is not a sunny/cloudy forecast. Wind speed, UV, and condition-specific sunny/cloudy icons are not currently included in the native forecast snapshot.

On iOS, the small Next Hike countdown uses a live numeric hours/minutes/seconds timer so minutes fit; “to go” is smaller and fixed-width. The time icon uses SF Symbol `timer`; the hiking header icon stays unchanged. The wide layout keeps its written hours/minutes countdown. Scheduled departure entries stop the countdown at departure.

### Native registration and shared data

1. `lib/home/Data/home_screen_widget_service.dart` converts up to eight eligible schedules into a compact JSON snapshot. It uses only the matching plan’s gear counts/contact-selection flag/sharing flag/battery; it never exports auth tokens, phone numbers or emergency contact identities.
2. `HikerHomePage._rebuildPlannedHike` and `_updatePlannedHike` publish schedule/preparation changes, independent of whether a Flutter Home card is visible. The existing planned-state refresh/expiry logic continues to drive these updates.
3. The service obtains the next hike’s forecast from the same four-hour Open-Meteo cache and uses `HikeWeatherBriefing` for the same scheduled interval calculations. A hike snapshot is published immediately, so a failed forecast does not hide the widget.
4. The Flutter method channel is `hiker_circle/home_widgets`, method `update`, with a JSON string argument containing `{version: 1, hikes: [...]}`.
5. On iOS, `AppDelegate.configureHomeWidgetsChannel` writes `hikeWidgetSnapshot` into `UserDefaults(suiteName: "group.com.leongziqi.hikercircle.widgets")` and reloads `NextHikeHomeWidget` and `HikeWeatherHomeWidget` timelines. The app and extension both declare the same App Group entitlement. App Group capability must also be included in their signing profiles.
6. `ios/ManualSOS/HikeHomeWidgets.swift` defines both WidgetKit configurations and a shared timeline provider. `ManualSOSBundle.swift` registers them alongside SOS. Both support small and medium families. The provider selects the first unexpired schedule, supplies entries every 15 minutes for four hours plus exact departure, return and expiry entries, then requests a new timeline. Actual reload scheduling is controlled by iOS.
7. On Android, `MainActivity` sends the snapshot to `HikeHomeWidgetProvider.publish`, which stores it in private `home_widgets` SharedPreferences and updates both registered providers. Provider XML requests 30-minute updates; countdown uses the platform Chronometer. Widgets re-read persistent snapshots after process restart.
8. `AppViewModel` clears native snapshots at sign-out, Firebase-auth session loss, before a new account signs in, and when startup finds no signed-in session. Revision guards prevent an old forecast request from repopulating cleared data.
9. `hikercircle://hike/briefing` and `hikercircle://hike/weather` select Home through the existing authenticated deep-link handler. They perform no start-session or SOS action.

Native weather uses the last forecast published by the app; the widget extension does not make background weather requests. Its cached timestamp remains visible and data becomes explicitly outdated after four hours. Open HikerCircle to refresh. OS scheduling does not guarantee an immediate widget reload. Future cancellation/rescheduling from another device becomes visible after the app syncs those changes.

### Native code map

| File | Responsibility |
|---|---|
| `lib/home/Data/home_screen_widget_service.dart` | Snapshot serialization, matching preparation, cached forecast, channel publication and account clearing |
| `lib/home/View/hiker_home_page.dart` | Schedule/checklist hooks and safe widget deep links |
| `lib/app/ModelView/app_view_model.dart` | Clear widgets at account transitions |
| `ios/ManualSOS/ManualSOSBundle.swift` | Add both new configurations to the iOS widget gallery |
| `ios/ManualSOS/HikeHomeWidgets.swift` | SwiftUI layouts, placeholders, shared snapshot reader, expiry/freshness timeline |
| `ios/Runner/AppDelegate.swift` | Flutter-to-App-Group bridge and WidgetCenter reloads |
| `ios/Runner/Runner.entitlements`, `Runner-Debug.entitlements`, `ios/ManualSOS/ManualSOS.entitlements` | Matching App Group access |
| `ios/Runner.xcodeproj/project.pbxproj` | Extension entitlement setting in every configuration |
| `android/app/src/main/kotlin/com/example/hiker_circle/HikeHomeWidgetProvider.kt` | Both launcher widget providers, persisted snapshot reader and rendering |
| `android/app/src/main/kotlin/com/example/hiker_circle/MainActivity.kt` | Android method-channel handler |
| `android/app/src/main/AndroidManifest.xml` | Register Next Hike and Hike Weather providers |
| `android/app/src/main/res/xml/next_hike_widget_info.xml`, `hike_weather_widget_info.xml` | Launcher size, resizing, preview and update metadata |
| `android/app/src/main/res/layout/hike_home_widget.xml` | Android widget layout |
| `test/home/home_screen_widget_service_test.dart` | Payload/forecast/preparation publication, deduplication, expiry, failure and sign-out race coverage |

Platform references: [Apple widget timeline updates](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date), [Android widget updates](https://developer.android.com/develop/ui/views/appwidgets/advanced).

The rest of this document describes the in-app Home cards. Those remain available above trail discovery.

## Screen states and order

`lib/home/View/hiker_home_page.dart` owns sessions, scheduled hikes, live trails and navigation. Its Home branch chooses:

| State | Visible content, in order |
|---|---|
| No active session and no resolved plan | Plan Your Hike header → Create Hike / Find a Hike → next-hike briefing when an eligible scheduled hike exists → any remaining upcoming hikes → Hiking Trails |
| Resolved upcoming plan | Hike Plan Ready header → Create Hike / Find a Hike → next-hike briefing with preparation values → remaining upcoming hikes → Hiking Trails → recent hazards for the planned trail |
| Active session | Active hike header and elapsed time → GPS / safety health strip → live tracking map → hiking actions. Planning cards are replaced by this screen. |

`HomeDashboardPage` uses a scrollable column, an 18 px horizontal margin, a maximum width of 640 px and space for bottom navigation. Shared header typography comes from `PageHeaderStyle`.

## Planning Home inventory

| Widget / section | Data and meaning | Interaction and conditions | Related code |
|---|---|---|---|
| Home header | Plan Your Hike, or Hike Plan Ready when a plan is resolved | Informational | `home_dashboard_page.dart`: `_HomeDashboardHeader`, `_TrailDiscoveryDashboard`, `_PreparationDashboard` |
| Create Hike | Starts the flow for a new hike | Calls `onStartHike(null)`; it must not silently start the scheduled hike displayed below | `home_dashboard_page.dart`: `_StartHikeActions`, `_startHikeFromDashboard` |
| Find a Hike | Discover available scheduled hikes | Opens the existing Find Hike screen | `hiker_home_page.dart`: `_openFindHike`; `find_hike_page.dart` |
| Next hike briefing | Earliest eligible scheduled hike, its route, trailhead, distance, difficulty, creator/joined label, departure and expected return | Review preparation opens a scrollable preparation sheet with editable gear, contact access, expandable route details and fixed launch/cancel actions. A standalone dashboard without that callback falls back to its preparation summary when a matching plan exists | `next_hike_briefing.dart`; `home_dashboard_page.dart`: `_MyUpcomingHikesSection`; `hiker_home_page.dart`: `_showUpcomingHikeDetails` |
| Countdown | Time remaining until the persisted departure instant | Recalculates every minute while Home is visible and app is foreground; displays Departure time reached after the instant passes | `next_hike_briefing.dart`: `_tick`, `build` |
| Gear progress | Compact completed/total gear count; full checklist in the preparation sheet | Only shown for the `PlannedHike` matching the scheduled hike ID. This is **gear checklist completion**, not an overall safety score | `PlannedHike`; `GearChecklistCatalog`; `next_hike_briefing.dart` |
| Preparation sheet | Editable gear checklist, emergency contacts and phone battery; route details expand on demand | Saved checklist updates local planning and phone widgets. Manage contacts opens the SOS tab without triggering SOS | `final_preparation_review_page.dart`; `hiker_home_page.dart` |
| Weather for your hike | One-line temperature and peak chance summary, with stale/unavailable state | Tap the weather strip for hourly forecast, update timestamp and daylight guidance; refresh retries the forecast | `next_hike_briefing.dart`, `hike_weather_briefing.dart`, `hike_briefing_weather_service.dart` |
| More upcoming hikes | Every remaining eligible schedule after the featured hike | Existing compact cards open their respective details. The featured schedule is not repeated | `home_dashboard_page.dart`: `_MyUpcomingHikesSection` |
| Hiking Trails filters | All, Nearest radius, Malaysian state | Nearest defaults to 50 km; the user can change radius. State opens the region selector | `home_dashboard_page.dart`: `_BestMatchesSection` |
| Hiking Trail cards | Trail name/image, route length, routed distance from user where available, difficulty and typical duration | Opens trail details. Admin add/edit/delete actions appear only when the corresponding callbacks are supplied | `home_dashboard_page.dart`: `_BestMatchesHeader`, trail card helpers |
| Loading / empty discovery | Loading, unavailable trails, or no filter matches | Reflects actual loading/filter/location state | `home_dashboard_page.dart`: `_BestMatchesSection`, `_EmptyState` |
| Preparation reminder fallback | Outstanding preparation for a resolved plan when there is no upcoming card | Opens the preparation summary; not duplicated below the normal briefing | `home_dashboard_page.dart`: `_PreparationWarning`, `_PreparationReminderPage` |
| Recent Hazards on This Trail | Hazards attached to the resolved planned trail, or an explicit empty state | Tap a hazard for severity, location, time and recommended action | `home_dashboard_page.dart`: `_HazardRow`, `_HazardDetailPage` |

All paths in the table without a prefix are under `lib/home/View/`, except the model/data/service paths detailed below.

## Scheduled hike and preparation mechanism

1. The parent loads scheduled hikes from the repository and local session database.
2. `PlannedHikeStateResolver` merges eligible cached and remote schedules, handles consumed/deleted schedules, and selects the next schedule. The current preparation branch also uses the parent's existing eligibility rules.
3. `_MyUpcomingHikesSection` defensively excludes expired/deleted schedules using `UpcomingHike.isUpcomingAt(now)` and sorts by departure. `UpcomingHike` currently has a 15-minute visibility grace after departure. The parent separately stops exposing a preparation plan after its current 10-minute cutoff; the card can then show a schedule without preparation statuses.
4. The nearest schedule becomes `NextHikeBriefing`; remaining schedules retain compact cards. The preparation object is used only when `upcomingHikeId` matches the featured schedule.
5. The parent supplies current gear progress, emergency-contact selection, phone battery and sharing configuration. The new widget does not create another Firebase preparation record or change any start-session rules.
6. Review preparation uses `_showUpcomingHikeDetails` and `FinalPreparationReviewPage`. That sheet retains the existing host/joined restrictions and solo/team readiness/start behavior. Merely opening the briefing or its weather details never starts tracking.

Relevant files:

- `lib/home/Model/hike_session_models.dart`: `UpcomingHike`, `PlannedHike`, session/draft models.
- `lib/home/Data/planned_hike_state_service.dart`: schedule merge/selection and preparation resolution.
- `lib/home/View/hiker_home_page.dart`: parent state, `_updatePlannedHike`, `_showUpcomingHikeDetails`, `_startUpcomingHikeNow` and existing preparation flows.
- `lib/app/Data/hiker_circle_firebase_repository.dart`: scheduled hike and related repository operations.
- `lib/app/Data/local_session_database.dart`: existing local persistence and pending sync.

Schedule timestamps and forecast update timestamps are displayed in the phone's local timezone, consistently with the surrounding app. Solar times and hourly weather detail rows explicitly use the forecast's trail timezone. Expected return includes its date so an overnight return is not mistaken for the same morning.

## Cancelling an upcoming hike

Open **Review preparation → Cancel upcoming hike**, then confirm. The cancellation button stays beside the persistent action area, outside the scrolling detail list. Only the host sees it. The sheet disables duplicate submissions and keeps errors visible for retry.

`HikerCircleFirebaseRepository.cancelUpcomingHike` calls the authenticated `cancelUpcomingHike` Cloud Function (`functions/index.js`, transaction in `functions/cancel_upcoming_hike.js`). The transaction validates the host UID and phone, rejects any schedule already linked to team launch or started tracking, then sets `isDeleted: true` and cancellation audit fields. Repeating a successful cancellation is harmless. Existing discovery, participant lists, joins, launch checks and reminder filters respect the deleted schedule. Chat/history records are not deleted.

After the server succeeds, `_cancelUpcomingHike` in `hiker_home_page.dart` marks the cached plan consumed, removes it from Home and republishes phone-widget data. A provisional local ID is first resolved against the confirmed matching schedule. Cancellation needs connectivity; failed server calls leave the hike available rather than claiming it was cancelled offline. This does not cancel an active hike, which keeps its existing end-session flow.

Tests: `functions/test/cancel_upcoming_hike.test.js`, `test/home/final_preparation_review_page_test.dart`, and the compact-card/layout checks in `test/home/next_hike_briefing_test.dart`.

## Scheduled weather mechanism

### Fetching and caching

`lib/home/Data/hike_briefing_weather_service.dart` requests Open-Meteo `/v1/forecast` at the scheduled hike's latitude/longitude. It does not use the phone's location or a map viewport.

Parameters:

| Parameter | Value |
|---|---|
| `hourly` | `temperature_2m,precipitation_probability` |
| `daily` | `sunrise,sunset` |
| `timezone` | `auto` |
| `timeformat` | `unixtime` |
| `temperature_unit` | `celsius` |
| `forecast_days` | `7` |

- No additional API key is needed by this integration; the widget credits Open-Meteo.
- A shared in-memory cache reuses forecasts for four hours, keyed by coordinates rounded to four decimal places. Up to 12 locations are retained.
- Concurrent requests for the same location share one in-flight request.
- Failed requests have a five-minute service backoff. The mounted card waits 15 minutes before automatic retry; a manual refresh bypasses the backoff/cache and can retry immediately.
- Requests time out after 12 seconds. An owned HTTP client is closed after completion.
- An existing trail forecast can seed the card only if it contains structured hourly data and timezone offset. A summary-only cache is insufficient to describe a future hike.
- Automatic refresh/countdown work is skipped while Home is hidden or the app is backgrounded. It resumes when visible/foreground. There are no per-minute API requests when a fresh result is available.
- Changing hike ID, coordinates or scheduled window invalidates the card's result. Generation checks ignore responses belonging to an old hike or a disposed card.
- Departures at least seven days away do not trigger requests; the card says that weather is available closer to departure. The actual returned timestamps, rather than this preliminary cutoff, determine forecast coverage.
- This new forecast cache is **memory only**. It does not write Firebase, alter the existing saved trail weather, or promise offline availability after restarting the app.

### Calculating the hiking-window values

`lib/home/Model/hike_weather_briefing.dart` parses numeric Unix timestamps and evaluates the interval from scheduled departure to expected return.

- An hourly sample covers `[hour, hour + 1 hour)`. Include every sample overlapping the hiking window. A 05:30–08:30 hike uses the 05:00, 06:00, 07:00 and 08:00 samples; an exact 08:00 return excludes the 08:00 sample.
- Temperature shows the minimum and maximum of those overlapping samples.
- Peak rain chance is their maximum probability, not the whole-day maximum, current-hour probability, accumulated rainfall or a fabricated ten-minute measurement.
- Every hour of the scheduled window must be covered continuously before aggregate values are displayed. Outside-range dates, gaps and invalid/reversed windows show an unavailable state.
- Missing/nonfinite temperature or rain entries leave that metric unavailable. Missing rain is never replaced with 0%.
- Sunrise belongs to the departure date; sunset belongs to the return date. Dates are matched using the provider's timezone offset and comparisons use absolute timestamps.
- Departure before sunrise and return after sunset have distinct messages. A 05:00 departure / 08:30 finish can therefore explain the pre-dawn start without claiming an evening finish. Cross-date trips indicate overnight travel.
- Solar values unavailable from the provider remain labelled unavailable. A multi-day hike is not compressed into an assumed single daylight interval.
- The update timestamp remains visible. A retained forecast older than four hours is explicitly labelled outdated; refresh failure is labelled when applicable.

The hourly details sheet shows the same selected samples and timestamps as the summary. Its list scrolls and supports large text. This is a point forecast for the trail area, not an elevation-adjusted forecast sampled along every route coordinate.

## Session forecast detail sheet

Tapping the compact weather strip opens `lib/home/View/hiking_forecast_sheet.dart`. The fixed header has refresh and close actions; all detail content scrolls. `SessionWeatherForecast` in `lib/home/Model/session_weather_forecast.dart` separates the exact planned session from two hours before departure and two hours after return. All display times use the trail's UTC offset, and overnight headers retain dates.

- The selected metric shows one hourly reading prominently, with a smaller hike range/peak covering **only the planned session**. Temperature, rain chance, wind, humidity and rainfall can be selected using the arrows or a horizontal swipe.
- The graph spans the exact buffered interval, shades the planned hike using the app theme, and supports temperature (default), rain probability, humidity, wind speed and hourly rainfall. It connects hourly samples with the same filled line style as the trail weather page, clips fractional-hour boundaries, and breaks lines at missing measurements/timestamps. Tap to inspect the relevant hourly conditions. Departure/return hours are labelled explicitly when they overlap a schedule boundary.
- The top area is a single forecast explorer, replacing separate summary blocks, metric chips and hourly-reading cards. It combines the selected metric, hour, graph, time slider and playback controls. It keeps the theme-coloured 2.5px filled line from `lib/trail/View/weather_presentation.dart` and a 160px graph. Lines between hourly samples show a trend, not a higher-frequency forecast.
- Touching the graph or dragging the time slider updates the same selected-hour reading. Start/Return jump to those schedule times. Play moves a continuous timeline from the buffered start to the buffered end at 1.2 seconds per forecast hour. The slider and graph cursor share a frame-synchronised animation controller; only the small cursor/slider rebuild every frame, while the chart is isolated in a repaint boundary and the sheet refreshes its readings at hourly boundaries. Readings remain actual hourly samples; missing hours are labelled unavailable, not interpolated. Reduced-motion mode retains stepped playback. Manual time selection, refresh, backgrounding and disposal stop playback. No network requests are made by exploration or playback. There are no floating graph tooltips.
- More session conditions expands on the same sheet to show peak feels-like temperature, gusts, UV, humidity and rainfall, plus the selected hour’s condition, feels-like temperature, rain chance/rainfall, wind/gusts, humidity and visibility. Sunrise/sunset remain below the caution card.
- A brief entrance fade, graph metric transitions, changed-value crossfades, rotating disclosure arrow and expanding details use 280 ms animations. Unchanged readings no longer reanimate at every hour, and tabular digits keep number widths stable. Reduced-motion settings disable them. These interactions use the already loaded forecast and make no additional API requests.
- Before you set off retains its original `weatherDetailSection` presentation: rounded expandable card, precaution count, original messages and running border; it starts expanded when cautions exist. It reuses `trailPrecautions` from the trail page. Optional `assessmentStart`/`assessmentEnd` scope the shared weather thresholds to exact intervals; existing trail-page callers retain their one-hour delay buffer. Solar cautions use the planned departure/return, not the enlarged graph window. Elevation comes from the selected trail.
- Buffer-only risks are separately prefixed Before departure / After expected return. Rain before departure can indicate a potentially wet trail, but forecast rain is not an observation of ground wetness. Existing wet-trail probability threshold remains strictly greater than 50%. Storm, heavy-rain, wind, heat, fog, UV, duration and ascent rules retain the shared thresholds.
- Missing hours/metrics and stale data remain explicit; the UI does not turn unknown values into zero. Refreshing updates the open sheet and the compact Home summary. A legacy two-variable cache is refreshed when the sheet opens.

The existing Open-Meteo request now includes temperature, apparent temperature, humidity, rain probability, precipitation, weather code, wind speed/gusts, visibility and UV, plus daily sunrise/sunset. It requests one past day so a session near midnight still has its preceding buffer, retains seven forecast days, and uses Celsius, km/h and millimetres. It continues to use the same four-hour per-location cache. See [Open-Meteo forecast documentation](https://open-meteo.com/en/docs).

Validation: `test/home/session_weather_forecast_test.dart` covers fractional hours, buffer isolation, missing data and overnight sessions; `test/home/hiking_forecast_sheet_test.dart` covers graph limits, selection, cautions and narrow-screen scrolling. Existing trail-precaution tests protect unchanged trail-page rules. Visual renders are in `output/session-forecast/`.

## Home and preparation redesign (17 September)

The Home page consistently uses **Home** as its title. `next_hike_briefing.dart` has dedicated weather and preparation action cards, with packed-gear progress. `hike_departure_countdown.dart` rebuilds just the day/hour/minute/second tiles once per second; `split_flap_number.dart` gives each changed number a 560 ms two-stage hinged flip: old top folds away, new bottom settles, with a fixed centre seam, hinge details and shading. The number panels are at least 72 logical pixels tall with 32 px digits and separate unit labels. The row is centred and capped at 260 logical pixels with 12 px gaps, giving each tile a slimmer 56 px width on typical phones; it shrinks for narrow screens. Weather and preparation use the same action-row component: matching surface, 14 px padding, 38 px circular icons, title/subtitle styling and trailing chevrons, with a 78 px minimum row height that expands for larger text. It pauses offscreen/in background, disposes its timer, clamps at zero, and respects reduced motion. This timer does not fetch weather.

`final_preparation_review_page.dart` uses the shared page-header style and theme surfaces. Its body scrolls; start/cancel actions remain accessible in the footer. Route details has been removed. View trail and Directions remain explicit actions. Cancellation retains host checks, confirmation, inline errors and duplicate-submit prevention.

### Trail-specific packing

`lib/home/Model/trail_gear_plan.dart` builds the list. `lib/home/View/trail_gear_checklist.dart` is shared between the preparation popup and `gear_checklist_page.dart`. It shows packing progress, expandable sections, a reason for each addition, and a read-only **Selected for your route** explanation. There are no manual terrain switches.

| Condition | Packing additions |
|---|---|
| Every hike, including short paved routes | 10 compact essentials: navigation, contacts, water, snack, first aid, whistle, headlamp, rain protection, sun protection, emergency blanket |
| Distance >10 km or planned duration ≥6 hours | Power bank, extra food/water and blister care |
| Mapped ford or possible unbridged water crossing on the route | Dry bag, secure crossing footwear, dry socks, poles |
| Mapped uneven/unpaved terrain within 50 m | Grippy footwear, poles and blister care |
| Planned duration ≥18 hours | Shelter, sleeping system, meals, water treatment, stove where permitted, permits, layers and waste bags |
| Mapped mud/wetland within 50 m or fresh, covered session forecast with peak chance >50% | Waterproof storage, dry socks, pack cover |
| Water within 50 m without a crossing | Waterproof storage; proximity alone does not imply a crossing |
| Ascent ≥500 m | Poles and blister care |

A route over 10 km is not automatically an overnight trip. A waterfall name alone does not establish a river crossing. Recommendations now come from actual map geometry rather than trail-name keywords or user-selected conditions. Map data can be incomplete, and the UI labels unavailable, partial, old or missing-surface data. Phone signal coverage is not inferred from map features. Items are deduplicated across sections. Charged phone has been removed from the pack because battery readiness is already shown below.

Packing ticks use the existing account/hike-scoped SQLite `planned_hike_state.completed_checklist_json`. Legacy `gear:scenario:<key>:on/off` strings remain readable for compatibility, but are ignored by automatic recommendations and never counted as packed. Unknown tokens are rejected by `GearChecklistCatalog.sanitize`. Hidden gear ticks are preserved if conditions later change back. `PlannedHike.withGearProgress()` and `PlannedHikeStateResolver` calculate totals from the current recommendation, and the existing native snapshot receives those totals.

Packing guidance draws on [NPS Ten Essentials](https://www.nps.gov/articles/10essentials.htm), [Hike Smart](https://www.nps.gov/articles/hiking-safety.htm), and [Safe River Crossings](https://home.nps.gov/articles/safe-river-crossings.htm). Equipment is not a clearance to cross unsafe water. These lists support preparation; local conditions and route requirements still matter.

### Automatic 50 m map corridor

`lib/core/services/route_gear_analysis_service.dart` resolves the saved or cached hiking route using `HikingRouteService`; it never substitutes straight checkpoint connectors. Custom scheduled checkpoints invalidate the canonical path before route resolution. `RouteGearAssessment` stores the resulting findings; Home preloads the next hike and the preparation sheet loads/retries other hikes.

The query uses OpenStreetMap/Overpass waterways, fords, bridges, walking paths, surface tags, rough ground and technical aids. A ≤5 m simplified polyline with a 56 m query radius avoids missing features because of simplification/rounding. Returned geometries are then filtered against the **original route segments at 50 m**, including segment intersections (not just vertex distances). Simplification does not alter the stored hiking route.

Water within 50 m adds waterproof storage. River crossings require a mapped ford within 10 m or waterway geometry within 2 m of the path, with mapped walking bridges considered. Each route segment is checked so one bridge cannot hide a later unbridged crossing of the same river. The wording remains “possible” where geometry is the evidence; this does not establish depth, flow or safe passage. Rough/technical/mud findings drive their gear additions. Surface tags on some segments never prove full coverage of the route.

Successful analyses are cached for seven days in SQLite `local_preferences` under `gear50-v1:<SHA-256 of actual encoded route>`, with blank owner because these are public map findings, not account data. In-memory keys also include the trail/checkpoints/stored route so route edits invalidate the result. Concurrent requests coalesce; failures have a five-minute memory backoff. Old findings remain dated if refresh fails. Partial/failed responses are never saved as a successful empty scan. Geometry classification runs off the UI isolate. There are no zoom-triggered calls.

See the [Overpass polyline proximity documentation](https://dev.overpass-api.de/overpass-doc/en/full_data/polygon.html). A live Penang Hill request returned 97 mapped objects; exact-corridor filtering retained 96 and identified unpaved terrain, without inventing a river crossing. Tests cover the 50 m boundary, segment intersections, bridges, repeated crossings, caching, changed routes and provider failure. Updated visual captures are under `output/automatic-gear/`.

### Solo-distance rule

This is a HikerCircle product rule, not a universal safety cutoff. `solo_hike_policy.dart` and `solo_hike_distance_dialog.dart` apply these boundaries:

- ≤10 km: no distance acknowledgement.
- >10 km through 20 km: explicit solo acknowledgement, saved as `soloDistanceAcknowledgedKm` in the draft. A different trail or distance invalidates it.
- >20 km: group setup required. Starting a group route of this length also requires a hiking partner.

The setup wizard checks mode, route changes and final submission. Existing scheduled hikes are checked on start. `functions/solo_hike_policy.js` validates scheduling against the server’s canonical trail distance, including acknowledgement. `scheduleUpcomingHike` is the deployed callable. Neither workflow starts tracking merely by acknowledging a dialog.

### Large upcoming-hikes widget

The existing account-cleared snapshot already contains up to eight sorted eligible hikes. The new list uses it without additional API requests. iOS `UpcomingHikesHomeWidget` uses `.systemLarge`, the existing timeline provider and a new bundle registration; the native bridge reloads its timeline on updates/clears. Android `UpcomingHikesWidgetProvider` uses a 4×4 default size, day/night resource colours, and three or four rows depending on height/text scale. Providers refresh after snapshot changes; Android also handles resizing and the standard 30-minute update cadence. Expired/cancelled schedules follow the same filtering as the existing widgets.

Each row links to `hikercircle://upcoming-hike/view?upcomingHikeId=…`, using the existing authenticated hike-detail flow. No background launch or tracking is started. Widget gallery entries include preview content. Android launcher behaviour and final native rendering still require validation on an Android device; no Android SDK is available on this Mac.

Validation includes gear scenarios and deduplication, SQLite reopen with saved scenario metadata, exact distance boundaries, acknowledgement persistence/dialogs, countdown ticks, cancellation, scheduling navigation, large-text layouts and native snapshot tests. Visual renders are under `output/home-redesign/`.

## Active hike Home inventory (existing behavior)

The normal app uses `ActiveHikeHomePage` in `hiker_home_page.dart` while a session is active. The new scheduled cards do not replace or modify its functionality.

| Widget | Contents / action | Code |
|---|---|---|
| Active header | Trail title, elapsed time, estimated return and recorded GPS point count | `_ActiveHikeTopBar`, `_ElapsedTimeDisplay` |
| Weather action | Opens Weather along your hike with current/ahead-of-route samples, update time and failure state; existing five-minute refresh | `_ActiveHikeWeatherSheet`, `_ActiveHikeWeatherCard`; existing active weather service |
| Safety health strip | Location freshness and fall/stillness monitor state | `_ActiveHikeSafetyHealthBar`; `FallStillnessMonitorSnapshot` |
| Tracking map | Session positions, route, team context and weather samples; existing map style controls | `lib/home/View/active_tracking_map_view.dart`: `ActiveTrackingMapView` |
| Check In | Existing check-in and sync flow | `_ActiveHikeBottomBar`, parent callback |
| Pin Location | Save a manual location pin | `_ActiveHikeBottomBar`, parent callback |
| Report Hazard | Existing route hazard reporting | `_ActiveHikeBottomBar`, parent callback |
| Team Tools | Team-specific tools; only present for a team session | `_ActiveHikeBottomBar`, `_openTeamTools` |
| End Hike Session | Existing stop/finish flow | `_ActiveHikeBottomBar`, parent callback |

`home_dashboard_page.dart` also retains `_ActiveHikeDashboard`, a legacy/standalone rendering branch with session/connectivity information, a map, elapsed/distance/GPS/pin metrics, check-in and pin controls, safety monitoring/cancel-SOS information, sharing and team snapshots. The production parent's active-session branch uses the separate full-map `ActiveHikeHomePage` instead. Account settings, Circle, SOS and Admin are separate destinations rather than additional planning Home widgets.

## Native validation

The new widget SwiftUI implementation passes `swiftc -typecheck` against the iPhoneOS SDK. The signed iOS application and embedded extension build successfully with matching App Group entitlements. The Dart widget and Home tests total 32 passing checks. Android manifest/layout/provider XML validates; a full Android build requires an Android SDK and Gradle installation, which are not present on this Mac.

## Validation and extension points

Tests:

- `test/home/hike_weather_briefing_test.dart`: window overlap, exact return boundary, forecast gaps/horizon, missing rain, timezone/daylight comparison, invalid interval, request parameters/cache/deduplication and retry.
- `test/home/next_hike_briefing_test.dart`: countdown/preparation display and navigation, hourly details, hidden Home, far-future departure, request failure/retry, disposal and narrow layouts with enlarged text in both themes.
- `test/home/home_trail_discovery_test.dart`: existing Home discovery/filter behavior, independent Create Hike action and single display of a scheduled hike.
- `test/home/planned_hike_state_service_test.dart`: existing schedule/preparation state resolution.

Run:

```sh
flutter test test/home/home_screen_widget_service_test.dart test/home/hike_weather_briefing_test.dart test/home/next_hike_briefing_test.dart test/home/home_trail_discovery_test.dart test/home/planned_hike_state_service_test.dart
flutter analyze lib/home/Data/hike_briefing_weather_service.dart lib/home/Model/hike_weather_briefing.dart lib/home/View/next_hike_briefing.dart lib/home/View/home_dashboard_page.dart
```

To change the weather cache lifetime, edit `HikeBriefingWeatherService.freshness`. To change included weather hours or aggregation, edit `HikeWeatherBriefing.fromWeather` and its boundary tests. To change the visual layout or details sheet, edit `NextHikeBriefing`. To change which hike is featured, coordinate `_MyUpcomingHikesSection` with `PlannedHikeStateResolver`; never attach another hike's checklist to the featured card.


## Forecast and packing interaction refinement (18 September 2026)

`HikingForecastSheet` places the existing **Before you set off** section immediately below the trail and session date. Caution icons are supplied by the shared `precautionIcon` helper in `lib/trail/View/weather_presentation.dart`, also used by the trail weather view. In `trail_precautions.dart`, a pre-sunrise start recommends a headlamp and spare power; an earlier departure/shorter itinerary is suggested only when estimated finish is strictly after sunset. The bottom footer contains only the update timestamp and Open-Meteo.

The forecast timeline autoplays once the initial forecast is ready. The existing continuous animation controller moves the cursor without rebuilding the chart on every frame. Touch down, drag, tap or mouse hover anywhere on the plot selects that time and pauses playback; the play control resumes it. Departure and **Estimated finish** cards sit above the readings and chart, with matching dated times and chart boundary labels. The data remains hourly: smooth cursor motion does not invent higher-frequency forecast values. Missing forecast hours remain unavailable. Reduced-motion preference retains discrete playback.

**More session conditions** is a rounded expandable panel with **Hike summary** and **Selected hour** controls. Responsive metric cards show the relevant units and missing-data states, including gusts, UV, humidity and apparent temperature. Summary values cover the planned hike rather than its two-hour context buffers.

`TrailGearChecklist` and the standalone checklist use `GearPackingTile`: whole-card tap targets, category icons, animated packed states, haptic feedback and accessible toggle semantics. Narrow layouts and larger text use single-column rows. The preparation sheet updates packing immediately, disables repeat submission while saving, and restores the previous selection on failure while preserving newly loaded route analysis. Existing item names, persistence format and route-derived gear rules are retained.

The separate research deliverable is `output/pdf/HikerCircle_Hiking_Scenario_Matrix.pdf`: 84 scenarios across 14 domains, 43 primary references, decision points and limitations of map/forecast inference. Its proposed scenario rules have **not** been implemented. UI renders for this refinement are in `output/forecast-refinements/`.


## Final preparation review page and required pack (18 September 2026)

The latest preparation flow is a full page named **Final preparation review**. Pack categories and Safety readiness use horizontal tabs; required items gate scheduled and immediate starts plus participant entry to team readiness. GPS-device/app and saved-emergency-contact packing entries are removed. Next Hike has larger date/time fields, no redundant countdown caption or Hosting suffix, and a difficulty label consistent with the trail detail hero. See [PREPARATION_REQUIREMENTS.md](PREPARATION_REQUIREMENTS.md) for exact rules, unapproved scenario candidates, persistence and code ownership. This supersedes earlier preparation-sheet descriptions above.

# Trail precautions — Before you set off

## Delivery across the hiking lifecycle (10 September 2026)

- **Upcoming hikes:** `sendUpcomingHikePrecautions` checks every five minutes for departures in the next 24 hours. Weather refresh uses a 15-minute shared cache limit. Active/deleted/ended hikes are excluded. Host and current participant device tokens receive environmental-risk FCM notifications; tapping opens that upcoming hike. Routine ascent/equipment reminders are reserved for the app. Notification TTL ends at departure.
- Server delivery ledger `hikePrecautionDeliveries` is keyed by hike, departure and recipient hash. Claims use a transaction/10-minute lease. Each risk is sent once per severity; escalation can send again. No device token is treated as a successful delivery. Partial success records delivery to avoid repeatedly notifying successful devices; FCM is not exactly-once and cannot guarantee that a device displayed the message. This server-only collection is covered by the default client deny rule.
- **Pre-hike:** fresh weather is checked before native safety readiness and before a team participant marks Ready (using the shared draft). The primary HikerCircle loading animation covers the bounded 15-second request. An explicit review dialog offers Go back or acknowledgement; failure shows an unavailable-data caution, not a safe status.
- **During a hike:** the home session owner checks for a new session every ten seconds and refreshes weather at most every five minutes, using latest valid coordinates or the trail position and estimated remaining time. Newly detected/escalated precautions are immediately passed to the existing Android/iOS native speech channel and also shown as a toast. Existing SOS/stillness activity suppresses precaution speech. Session identity is rechecked after the request, so an ended/replaced session cannot issue a late result. Timers are disposed with their owner.
- Spoken deduplication is per app process/session, not persistent across restarts. Restarting may repeat a safety caution. Silent mode, audio routing, speech availability, network connectivity and OS background suspension can prevent/delay speech. This is **not** a terminated-app/background continuous monitoring guarantee; a new native background integration would be needed for that. FCM delivery is also best-effort, not instantaneous detection of an actual weather event.
- Current limitations for unverified water/terrain/API/official-alert inputs below still apply to all delivery channels. Forecast warnings do not establish on-site conditions. Backend notification rules are maintained alongside the Dart evaluator and covered by separate rule tests.

Initial rules implemented: 9 September 2026. Lifecycle delivery implemented: 10 September 2026. Documentation reconciled with the current code: 10 September 2026. Scope: Malaysian trail planning.

## Safety contract

These are planning advisories, not a safety clearance, clinical assessment, flood prediction or official warning system. Numeric thresholds below are product heuristics unless explicitly attributed. Values below a threshold do not establish safety. Actual conditions, park instructions and official closures take precedence.

The current release implements weather, elevation-gain, duration and daylight rules. Water, verified terrain altitude/steepness, Malaysian API and official alerts remain **unassessed**, explicitly disclosed in the UI. They require verified data integrations; this document must not be read as claiming those integrations exist.

## Inputs and evaluation

- Existing `TrailWeather.forecastData`: Open-Meteo hourly temperature (°C), apparent temperature (°C), humidity (%), precipitation (mm for the forecast hour), rain probability (%), WMO weather codes, sustained wind and gusts (km/h), visibility (m), UV; daily sunrise/sunset and time-zone offset.
- Existing trail elevation gain (m) and estimated duration (minutes). Elevation gain is NOT summit altitude; provider grid elevation is NOT maximum route altitude.
- Without a departure selection: selected day's hourly outlook, explicitly labelled Daily outlook.
- With departure: selected date/time in the trail timezone through estimated completion plus a 60-minute delay buffer. Intersecting hourly slots are included, including next-day slots when available. No phone-timezone substitution.
- Sunset comparisons use estimated completion; the separate buffer is reflected by the within-60-minutes warning. Departure before sunrise also triggers darkness.
- Re-evaluate on selected date, departure time, weather or trail rebuild; refresh freshness status each minute. The selector is a local planning control, not a change to a scheduled hike.
- No departure selector is enabled when duration is unknown. Missing/short/null/non-finite series, missing beginning/end hours, gaps, and forecasts at least four hours old trigger a data warning. Never substitute current weather for a future date.

## Active rules

| ID | Trigger in evaluated hours | Display/action | Priority |
|---|---|---|---|
| heat | Temperature ≥32°C OR feels-like ≥35°C | Heat stress: earlier start, slower pace, shade breaks, drinking water; stop if dizzy/unusually fatigued | 2 |
| heat (combined) | Temperature ≥30°C AND humidity ≥80% in the SAME hour | Hot/humid strain; same precautions. If gain ≥500 m, include ascent in this card rather than duplicate ascent advice | 2 |
| cold | Temperature ≤15°C AND rain >0 OR wind ≥20 km/h in same hour (temperature condition applies to both) | Waterproof layer, dry clothing, avoid prolonged exposed stops | 2 |
| rain | Rain >0 OR probability ≥60% | Slippery roots/rocks, protect essentials. Probability is not intensity | 1 |
| rain (heavy) | ≥10 mm/hour OR WMO 65, 67, 82 | Consider postponing; avoid streams/gullies/unstable slopes; check closures. Replaces ordinary rain card | 3 |
| storm | WMO 95, 96, 99 | Consider postponing; avoid exposed ridges/summits/water; substantial building or enclosed vehicle, not isolated tree | 3 |
| wind | Sustained ≥25 km/h OR gust ≥40 km/h | Balance/branch concerns; avoid exposed terrain and damaged trees | 2; 3 at gust ≥60 |
| ascent | Gain ≥500 m, unless combined into heat | Pace ascent, breaks, save energy for descent; report actual gain | 1; 2 at ≥1,000 m |
| uv | UV ≥3 | Sun protection and shade; report peak UV | 1; 2 at ≥8 |
| visibility | WMO 45/48 OR visibility <1,000 m | Download route, keep group together; markers/edges may be obscured | 2 |
| sunset | Finish within 60 minutes before sunset | Actual estimated finish/sunset; start earlier or shorten route; headlamp | 2 |
| dark | Start before sunrise OR finish at/after sunset | Headlamp/spare power; consider changing time | 3 |
| duration | Estimated duration ≥240 minutes | Food, water, backup power; share return time, allow delays | 1 |
| data | Incomplete hours/measurements or cache age ≥4 h | Cannot fully assess; refresh/check official warnings | 3 |
| daylight-data | Planned time exists but sunrise/sunset missing | Check daylight before departure | 2 |

## Presentation

Highest priority first, stable ordering within priority. Show first three cards plus ALL priority-3 cards; View all reveals remaining cards. Priority-3 icons use theme error colour; other icons use the app primary colour. Cards contain a title, actual available measurements and practical action. Peak values are independent maxima, not claimed to occur simultaneously; humid-heat and cold combinations are evaluated per hour.

If no rule fires: “No specific advisories identified from the available data. Conditions can change.” The unassessed-data disclaimer remains. Empty forecast data still presents a precautions section and data warning. Weather advice never disables the app's SOS or replaces on-site judgment.

## Channel coverage — what actually triggers where

“Yes” means eligible for that channel, subject to the timing, data and repeat rules below. It does NOT mean delivery or audible playback is guaranteed. Priority 1 is a planning consideration, 2 is elevated caution, and 3 is high-priority advice or an assessment failure; these are app priorities, not official warning categories.

| Precaution | Trail page | Pre-hike review | Upcoming FCM | Active-hike toast + speech |
|---|---|---|---|---|
| Heat / hot and humid | Yes | Yes | Yes, shortened message | Yes |
| Cold with rain/wind | Yes | Yes | Yes | Yes |
| Rain / heavy rain | Yes | Yes | Yes | Yes |
| Thunderstorm | Yes | Yes | Yes | Yes |
| Strong wind | Yes | Yes | Yes | Yes |
| UV | Yes | Yes | Yes | Yes |
| Fog / low visibility | Yes | Yes | Yes | Yes |
| Near sunset / darkness | Only with selected departure and known duration | Yes | Yes, with available sunrise/sunset | Yes, evaluated from now and remaining duration |
| Ascent | Yes; merged into heat if applicable | Yes | No: routine terrain advice is not pushed | Yes; uses total recorded trail gain, not remaining ascent |
| Long duration | Yes | Yes | No: routine preparation advice is not pushed | Yes if estimated remaining time is ≥4 h |
| Incomplete/stale/unavailable weather | Data caution | Data caution | No standalone unavailable-data push | Data caution eligible for speech once per session |
| Missing sunrise/sunset | With planned departure | Yes | Daylight rules skipped, no data push | Yes |
| Unverified water, steepness, altitude, API or official notices | Not assessed | Not assessed | Not assessed | Not assessed |

### Important current differences between channels

- Trail-page thresholds use rainfall **>0 mm** for ordinary rain/cold-wet detection. The server currently uses **≥0.01 mm**. Thus a supplied positive value below 0.01 could trigger an in-app caution but not a rain-volume-based FCM. Rain probability ≥60% independently triggers both ordinary-rain rules.
- The app checks hourly completeness and shows a data warning. The server skips missing individual measurements rather than sending a data warning; it can still send a risk supported by another available measurement. No push is not evidence of complete data or safe conditions.
- The server suppresses a forecast with an invalid cache timestamp or age ≥4 h. Its 15-minute cache refresh target is not a hard freshness guarantee: provider failures can return cached data that is older than 15 minutes but younger than four hours.
- Upcoming duration uses the trail estimate; the current server falls back to **120 minutes** when that numeric value is missing/zero. The FCM text does not disclose this fallback. It is an estimate, not an observed completion time.
- Live/pre-hike checks explicitly request Malaysia time and fresh provider data. They do not reuse the trail-page departure selector. Active checks use remaining duration clamped to 1–1,440 minutes, then add the 60-minute weather buffer.
- The pre-hike dialog lists all returned precautions. Only the trail page uses the first-three-plus-priority-3 / View all presentation. Active speech/toast combines all newly eligible cautions. FCM combines newly eligible messages and truncates the body to 900 characters; opening the hike is needed for further review.

## Condition scenarios: when and why a caution appears

The examples below are rule examples, not forecasts for a real hike. Each trigger must occur in the channel's evaluated hiking window unless Daily outlook is selected.

| Scenario | Result | Why / practical meaning |
|---|---|---|
| Temperature 32°C, feels-like 33°C | Heat, priority 2 | Actual-temperature threshold reached; reduce exertion and heat exposure |
| Temperature 29°C, feels-like 35°C | Heat, priority 2 | Apparent-temperature threshold independently reached |
| Temperature 30°C and humidity 80% in the same hour | Combined humid heat, priority 2 | Heat and humidity coincide; cooling may be harder |
| Temperature 30°C at 10 AM, humidity 80% only at 3 PM when temperature is 25°C | No combined humid-heat rule from these facts alone | Independent daily maxima must not be combined as though simultaneous |
| Humidity 95%, temperature 25°C, feels-like below 35°C | No heat alert from humidity alone | High humidity is not independently treated as heat stress |
| Heat rule plus 700 m elevation gain | One heat card including ascent in app; no separate ascent card | Avoid duplicate advice while noting extra exertion; FCM remains a shortened heat message |
| Temperature 15°C and rain in the same hour | Cold/wet, priority 2 | Wet clothing can increase cooling; pack dry/waterproof layers |
| Temperature 15°C and wind 20 km/h in the same hour, no rain | Cold/wind, priority 2 | Exposure to cool wind is relevant even without rain |
| Temperature 15°C with neither rain nor wind ≥20 km/h | No combined cold rule | Temperature alone does not meet this implemented rule |
| Rain probability exactly 60%, forecast volume zero | Ordinary rain, priority 1 | Probability threshold is met; this is not a claim of heavy rainfall |
| Rain probability 100%, no heavy-rain code or ≥10 mm/hour | Ordinary rain, not automatically heavy rain | Probability is not intensity |
| Positive forecast rainfall, probability below 60% | Ordinary rain in app; server requires ≥0.01 mm | Rain amount can trigger independently |
| Hourly rainfall exactly 10 mm, or WMO 65/67/82 | Heavy rain, priority 3, replaces ordinary rain | Potential access/drainage concerns; consider postponing |
| WMO 95, 96 or 99 | Storm, priority 3 | Thunderstorm forecast; exposed hiking should be reconsidered |
| Thunderstorm and heavy rain both forecast | Two distinct priority-3 cautions | Lightning exposure and heavy-rain hazards are different; neither is hidden |
| Sustained wind exactly 25 km/h, low gusts | Wind, priority 2 | Sustained-wind threshold independently reached |
| Gust exactly 40 km/h, low sustained wind | Wind, priority 2 | Gust threshold independently reached |
| Gust rises from 40 to 60 km/h | Wind escalates from priority 2 to 3 | Escalation is eligible for another FCM/spoken alert |
| Gust rises from 40 to 55 km/h | Same wind priority 2 | Updated values can display; no repeated delivery solely for value change |
| Gain 499 m / 500 m / 1,000 m, without heat | No ascent / priority 1 / priority 2 | Product exertion thresholds; not altitude sickness assessment |
| UV 2.9 / 3 / 8 | No UV / priority 1 / priority 2 | Protection threshold and elevated exposure threshold |
| Visibility exactly 1,000 m, no fog code | No visibility rule | Numeric trigger is strictly below 1,000 m |
| Visibility 999 m OR WMO 45/48 | Visibility, priority 2 | Markers and edges may be obscured |
| Sunset 19:00, estimated finish 17:59 | No limited-daylight rule | More than 60 minutes remain before sunset |
| Sunset 19:00, finish 18:00–18:59 | Sunset, priority 2 | At most one hour of daylight buffer remains |
| Sunset 19:00, finish exactly 19:00 or later | Darkness, priority 3; not a duplicate sunset card | Estimated hike overlaps darkness |
| Departure before sunrise, finish comfortably before sunset | Darkness, priority 3 | The start of the hike is in low light |
| Departure exactly at sunrise, finish more than an hour before sunset | No daylight warning from those facts | The before-sunrise comparison is strict |
| Estimated duration 239 / 240 minutes | No long-outing / duration priority 1 in app | Four-hour preparation threshold |
| No applicable condition and complete forecast | Neutral in-app message; no FCM or new active speech | No specific rule fired, not a safety clearance |

## Upcoming-hike FCM scenarios

| Situation | When / action | Reason or limitation |
|---|---|---|
| Departure more than 24 h away | No precaution push yet | Outside the monitored upcoming window |
| Departure exactly 24 h away through just before departure | Eligible at the next five-minute scheduler run | Forecast is checked for the hiking window, including a 60-minute delay buffer |
| Hike created inside this window | First eligible scheduler pass evaluates it | Creation itself does not synchronously send this precaution FCM |
| New eligible risk found | Host and current participant phones are resolved to registered device tokens | Risk is relevant to people currently associated with the hike |
| User is only a pending join requester, not a participant | No participant precaution push | Recipient list is creator plus `participantPhones` |
| User joins later, after others were notified | New recipient can receive current qualifying cautions | Delivery history is per recipient, not a single hike-wide flag |
| Participant leaves before the delivery claim | Claim is suppressed | Current membership is rechecked transactionally |
| Same hazard and severity on later scheduler runs | No repeat after successful FCM acceptance | Persistent per-recipient severity ledger suppresses duplicates |
| New hazard appears, e.g. rain after an earlier heat push | Send only newly eligible hazard(s) | New ID is independent of previously sent risks |
| Rain changes from ordinary (1) to heavy (3) | Eligible to send again | Severity exceeds the recorded severity for `rain` |
| Severity falls, then returns to the same previously sent maximum | No repeat | Highest delivered severity is retained; resolving a hazard does not reset it |
| Near-sunset changes to darkness | Darkness can send | `sunset` and `dark` are separate IDs |
| Departure is rescheduled | New departure-specific ledger; current risks may send again | The time window has materially changed |
| Two workers process the same recipient | Transactional ten-minute lease prevents normal simultaneous claims | Crash/retry and FCM cannot provide strict exactly-once delivery |
| No user document or no registered tokens | Nothing sent; lease released | Not treated as delivery success; later runs can retry |
| FCM returns zero successes | No delivered severity recorded; later run retries | All devices failed acceptance |
| At least one device succeeds but another fails | Record delivered severities | Avoid repeatedly notifying successful devices; failed devices are not individually retried by this ledger |
| Worker throws after claiming | Lease expires after ten minutes before retry | Error is logged; a send-then-write failure can cause a duplicate on retry |
| Departure is now/past, hike deleted/started or terminal status recorded | Skip during eligibility filtering | Upcoming alerts should not be used as active-hike delivery |
| Linked team phase active/completed/ended/cancelled | Skip during team lookup | Team hike has moved beyond upcoming preparation |
| Missing trail ID/document/finite coordinates or unreadable departure | Skip | Cannot calculate an applicable forecast safely |
| Forecast refresh fails, cached data remains <4 h old | Available cached risks may still send | Fifteen minutes is the refresh target, not guaranteed freshness |
| Forecast missing or timestamp invalid/≥4 h old | No weather-claim push | Do not push stale/unverifiable weather as a new forecast |
| Departure/participant changes during claim | Rechecked departure, deletion/start flag and membership can reject the claim | A state change after the claim can still race delivery; there is no atomic transaction with FCM |
| User taps the notification | Open `hikercircle://upcoming-hike/view?upcomingHikeId=…` | Opens the relevant hike; tap does not start a hike or trigger SOS |
| Notification reaches expiry at departure | Android TTL / APNs expiration set to departure | Does not retract a notification already displayed or guarantee instant OS expiry |

These precaution pushes currently use a separate delivery flow and **do not consult the configurable ordinary upcoming-reminder preferences**. OS notification permissions/settings still apply. Normal scheduled reminder messages are a different feature. This distinction describes the implementation, not a claim that every user has enabled notifications.

## Pre-hike preparation scenarios

| Situation | Result / why |
|---|---|
| User starts a hike now or starts a scheduled hike through the home start flow | Check immediately before native background-safety readiness; use current time, not an old selected start time |
| Team participant presses Ready and shared draft exists | Check the shared draft's trail before marking Ready; each participant reviews locally |
| Team shared draft is missing | This particular weather review is skipped; do not claim the team path assessed a trail it did not receive |
| Already-ready host presses the activation button | The Ready handler does not perform another review on that branch; an earlier review is not continuous revalidation |
| Weather request is pending | Primary HikerCircle loading dialog; request timeout is 15 seconds |
| Request fails/times out | Show “Conditions could not be checked” and advice to check official sources; acknowledgement remains possible |
| Fresh forecast has cautions | Show all returned titles/actions and require acknowledgement to continue through this review |
| Fresh forecast has no cautions | Show neutral assessment text and acknowledgement; do not say “safe” |
| User selects Go back or uses system back | Return false; this start/Ready attempt does not proceed |
| User acknowledges | Review returns true; other readiness, permissions and start checks still run |
| User leaves screen while request finishes | No late continuation on an unmounted caller |
| User retries the start/Ready flow | Another fresh review may appear | 

No FCM is sent simply because this dialog opens. Acknowledgement does not authorise a closure violation and is not medical/safety certification.

## During-hike speech scenarios

| Situation | Result / why |
|---|---|
| New/restored active session becomes available while the home owner is running | Next ten-second timer tick can start the initial check; this is not a guarantee of speech exactly at the start instant |
| Same active session after a check | Skip until five minutes have elapsed; repeated timer ticks do not repeatedly fetch |
| New check completes with a new hazard or higher priority | Immediately submit combined eligible text to native speech and show a toast; actual speech depends on platform/audio availability |
| Same ID and same/lower priority remains | Do not repeat in this process/session; changed temperature alone is insufficient |
| Hazard disappears and later recurs at already-spoken priority | No repeat; the remembered maximum is not cleared by recovery |
| New hike/session ID | Clear spoken history and last-check time; new hike is assessed independently |
| App process restarts and restores the same hike | Memory-only history is lost; caution may be read again |
| Latest position is valid | Query weather at that coordinate |
| No valid latest position | Use the trail coordinate, not a fabricated live position |
| Planned duration is already exceeded | Remaining estimate is clamped to at least one minute, plus weather buffer; not a new full-route estimate |
| Remaining duration falls below four hours | Long-duration rule may no longer apply; no “all clear” speech is emitted |
| Ascent condition is evaluated mid-hike | Uses full recorded trail gain, not ascent still ahead; this limitation is not a measured remaining-terrain assessment |
| Stillness response pending, local stillness alarm active, or fall/stillness SOS sending before check | Skip check; existing safety response takes priority |
| One of those states begins while weather is being fetched | Suppress result speech/toast; the check timestamp has been updated, so reconsideration may wait until the next five-minute refresh |
| SOS starts after precaution speech was submitted | The guards are not an atomic native speech-priority queue; existing emergency speech can replace speech, but complete race-free prioritisation is not proven |
| Hike ends or session changes during fetch | Discard late results by checking current session ID |
| Home owner is disposed | Timer is cancelled; no new checks from it |
| Network/provider failure | A data-unavailable precaution is eligible for speech/toast once; not a fabricated weather condition |
| Speech plugin/platform throws a handled availability error | Toast remains; the current implementation still marks the caution as handled, so no immediate automatic retry at the same priority |
| Device muted, routed to headphones, speech engine unavailable or volume too low | Audible output cannot be guaranteed; app does not override these settings |
| App is backgrounded/suspended or terminated | Dart timer/speech is not guaranteed; there is no new native continuous weather monitor or terminated-app TTS implementation |

“Immediately read out” means **submit speech after a scheduled check detects a newly eligible caution**. It does not mean instant detection of real-world weather changes, continuous sensing, a push-triggered active-hike speech path, or guaranteed sound while the app is terminated. The upcoming FCM scheduler does not monitor active hikes.

## Approved rules awaiting verified inputs

| Rule | Required input | Planned behaviour |
|---|---|---|
| Nearby water | Verified route geometry and mapped river/waterfall proximity | Banks/edges slippery; do not infer crossing or drinking safety |
| River crossing | Confirmed crossing on actual route | Avoid fast/rising water; turn back if uncertain |
| Water + rain | Verified water hazard plus recent/upstream rain or applicable flood warning | Avoid crossings/waterfalls; local dry weather cannot establish upstream safety |
| Steep + rain | Verified route slope profile | Slippery descent; footwear and extra time; no inference from total gain |
| High altitude | Verified maximum route altitude ≥2,500 m | Acclimatisation/guide advice; no ascent while unwell |
| Haze | Current Malaysian API, station/location and timestamp | >100 reduce/postpone strenuous activity; >200 stronger advisory; never substitute foreign AQI categories |
| Official alerts/closure | Authoritative notice, trail/geographic applicability, issued/expiry time and source | Prominent actual notice, never hidden behind View all or overridden by favourable forecast |

Do not populate these from trail names, unverified free text, forecast grid elevation, fabricated API values, or a generic countrywide warning. Current `TrailHazard` records have no verification/expiry contract and are displayed separately, not upgraded into official notices.

## Sources

- [KKM heat guidance](https://infosihat.moh.gov.my/cuaca-panas.html): health precautions, not the app's numeric heat thresholds.
- [METMalaysia weather phenomena and storm precautions](https://www.met.gov.my/en/pendidikan/fenomena-cuaca/): thunderstorm safety; app thresholds are not MET warning issuance criteria.
- [WHO UV guidance](https://www.who.int/news-room/fact-sheets/detail/ultraviolet-radiation): protection at UV ≥3.
- [DOE Malaysian API](https://www.doe.gov.my/2021/10/04/english-air-pollutant-index-api/): reference for future air-quality integration.
- [Open-Meteo API](https://open-meteo.com/en/docs): forecast variables, units, WMO codes and timestamps. Forecasts cannot resolve every trail microclimate.

## Code and verification

- Pure rules: `lib/trail/Model/trail_precautions.dart`.
- UI: `lib/trail/View/trail_weather_panel.dart`; duration supplied by both trail page weather entry points.
- Tests: `test/trail/trail_precautions_test.dart`; existing panel tests in `test/trail/trail_weather_panel_test.dart`.
- The original trail-page rules consume existing forecast data without a backend deployment. Lifecycle FCM delivery adds `functions/hike_precaution_reminders.js` and the deployed `sendUpcomingHikePrecautions` function (us-central1, hiker-circle). Its server-only ledger uses existing default-deny client rules; no client schema/rules deployment was added for it.
- Live/pre-hike fetch: `lib/trail/Model/precaution_check_service.dart`; review dialog: `lib/trail/View/precaution_confirmation.dart`; start/Ready/active-timer hooks: `lib/home/View/hiker_home_page.dart`; notification routing: `lib/core/services/fcm_notification_router.dart`.
- Lifecycle tests: `functions/test/hike_precaution_reminders.test.js`, `functions/test/trail_weather.test.js`, `test/core/fcm_notification_router_test.dart`. The last implementation verification ran 25 targeted rule/widget/router/cache tests with clean targeted Dart analysis. These are not end-to-end device-delivery or native audio tests.
- A new app build is required for local review and speech. Successful Firebase deployment verifies provisioning, not actual device receipt, audibility or background reliability. This documentation update does not redeploy or change app behaviour.

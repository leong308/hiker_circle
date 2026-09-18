# Final preparation review

Updated 18 September 2026. This page replaces the preparation bottom sheet. Open it from **Next Hike → Final preparation review**. The same review is required for immediate starts, scheduled hikes started through the dashboard, and participants proceeding to team readiness. Participants use their own checked items; the host's shared checklist never satisfies another hiker's requirements.

## Required items implemented

These are the requested HikerCircle product rules, not universal outdoor-safety thresholds.

| Condition | Required items | Exact implementation |
|---|---|---|
| Every hike | Drinking water; Energy snack; First-aid kit | Always required, including short hikes |
| Session overlaps 08:00–18:00 | Sun protection (hat, sunscreen) | Any positive overlap on any local day; ending exactly at 08:00 or beginning exactly at 18:00 does not overlap |
| Forecast temperature below 15°C during the session | Emergency blanket | At least one available, fresh overlapping hourly sample below 15°C; exactly 15°C does not trigger it |
| Uneven terrain | Trekking poles | Usable route analysis reports rough or technical ground |
| Wet conditions | Spare dry socks; Pack rain cover | Route analysis reports mud, or fresh session forecast has rain probability above 50%, measurable precipitation, or a precipitation weather code |

Times use the forecast's UTC offset, with Malaysia UTC+8 as the fallback. Weather rules use the planned session itself, not the weather chart's two-hour buffers. A fresh but incomplete forecast can establish a requirement from a known sample; incomplete/missing data is also disclosed. Missing or stale weather does not establish that it will be warm or dry. Map tags cannot prove the current surface condition. Map and weather checks run before Start becomes available; unavailable checks are disclosed rather than represented as successful verification.

**GPS device or app** and **Emergency contacts saved** are removed from the displayed pack. Emergency contacts are an informational status in Safety readiness. Old saved item tokens remain readable but do not count toward the current pack or satisfy its requirements.

Start is disabled until every currently required item is checked and the current checks/saves are finished. Recommended items can remain unchecked. Requirements are recalculated when weather or route analysis changes. Each required tile has a badge and a tooltip explaining the trigger. Tabs with outstanding required items have an indicator.

## Other scenario items for your decision

No additional mandatory rules from this table are enabled. “Current” means the existing recommender can suggest that category; “candidate” means it needs a later decision or additional data. A listed item may already be required for a different approved trigger above. Items shared across categories are displayed once.

| Scenario | Items to classify as mandatory or recommended | Current status / trigger |
|---|---|---|
| Basic hike, remaining optional items | Emergency whistle; headlamp with spare batteries; raincoat | Current essentials, recommended |
| Long day | Power bank; extra food for delays; extra drinking water; blister care | Current: over 10 km or at least 6 planned hours; does not imply camping |
| Possible river crossing | Dry bag / waterproof phone pouch; secure water-crossing footwear; spare dry socks; trekking poles | Current: mapped ford or possible unbridged crossing; equipment never confirms a crossing is safe |
| Water near route, no detected crossing | Dry bag / waterproof phone pouch | Current: water within the assessed 50 m corridor; no crossing assumed |
| Uneven terrain, remaining additions | Grippy hiking footwear; blister care | Current rough/technical route findings; poles are already required |
| Steep ascent | Trekking poles; blister care | Current: at least 500 m accumulated ascent; this is not a slope-angle threshold. Poles are only required if the uneven-terrain rule also applies |
| Wet conditions, remaining additions | Dry bag / waterproof phone pouch; raincoat | Current; socks and pack rain cover are already required |
| Overnight / camping | Tent or suitable shelter; sleeping bag and mat; meals plus reserve; water treatment; permitted stove and fuel; camp permit/booking; warm layer; waste bags | Current: at least 18 planned hours. Confirm actual overnight intent and local rules before expanding this heuristic |
| Remote / unreliable communication | Physical map; compass; power bank; suitable satellite communicator; water treatment; multi-tool | Catalog exists but automatic activation is disabled: nearby map features cannot establish phone coverage |
| Before sunrise / after sunset | Headlamp with spare batteries; spare light | Candidate dedicated darkness requirement; headlamp is currently recommended in Essentials |
| High heat / strong sun | Additional drinking water; sun hat/sunscreen; breathable protective clothing | Candidate additional heat rules; sun protection is already required for the approved time window |
| Cold / windy exposure | Warm layer; waterproof outer layer; suitable headwear/gloves | Candidate additional cold/exposure rules; blanket is already required below 15°C |
| Poor visibility / uncertain navigation | Physical map; compass; independent lighting; backup power | Candidate; the redundant “GPS device or app” checkbox is not being reintroduced |
| Long gaps between reliable water sources | Extra water capacity; appropriate water treatment | Candidate; a mapped spring is not verified potable or available |
| Personal medical or accessibility needs | Personal prescribed medication; appropriate first-aid additions; individually suitable supports | Candidate personal planning, not automatic medical advice or a generic mandatory list |
| Wildlife / insects | Region-appropriate repellent; protective clothing; suitable food storage | Candidate; species and destination matter |
| Coastal / tidal route | Reliable local tide information; offline route; backup light | Candidate; tides require a separate source and safe timing, not just more equipment |
| Technical snow, glacier, climbing or cave route | Activity-specific equipment plus appropriate training/qualified guidance | Candidate specialist review; do not implement as an automatic shopping list |

The candidates are a synthesis of the earlier 84-scenario report and primary guidance: [NPS preparation systems](https://www.nps.gov/articles/10essentials.htm), [NZ Mountain Safety Council river planning](https://www.mountainsafety.org.nz/learn/skills/river-safety), and [multiday preparation](https://www.mountainsafety.org.nz/learn/activities/multiday-tramping). River decisions also require skills, catchment conditions and a retreat option; possessing listed items is not a clearance to cross.

For a follow-up, specify a scenario and exact required items, for example: **“Before sunrise: headlamp with spare batteries mandatory; spare light recommended.”**

## Code and persistence

| Responsibility | Code |
|---|---|
| Scenario additions, required-item reasons, overlap/temperature/wet/rough rules | `lib/home/Model/trail_gear_plan.dart` |
| Missing required items and preparation state | `lib/home/Model/hike_session_models.dart` |
| Tabs, requirement badges, packing tiles, progress | `lib/home/View/trail_gear_checklist.dart` |
| Full page, safety tab, route/weather refresh, disabled Start, save rollback | `lib/home/View/final_preparation_review_page.dart` |
| Navigation, scheduled and immediate start entry checks | `lib/home/View/hiker_home_page.dart` |
| Existing local per-user/per-hike checklist storage | `_updatePlannedHike` and `local_session_database.dart` |
| Current community difficulty merges | `lib/home/Data/planned_hike_state_service.dart` |
| Next Hike date/time presentation and rating | `lib/home/View/next_hike_briefing.dart` |
| Countdown without redundant caption | `lib/home/View/hike_departure_countdown.dart` |
| Shared difficulty label and trail hero | `lib/trail/Model/trail_models.dart`, `lib/trail/View/trail_page.dart` |

The saved checked-item set and SQLite schema are unchanged. Immediate-start selections are copied into the resulting hike draft. This is an app start gate, not a newly deployed server policy or physical verification that gear is carried. Requirements use the reviewed data snapshot; later changes in actual weather/terrain still require hiker judgement.

The Next Hike card no longer shows the ambiguous Hosting/Joined suffix. Hosting previously meant the signed-in user created the hike. Difficulty now uses current live community votes when available; both the trail hero and Next Hike show **Difficulty not rated** when there are no votes, instead of presenting an old scheduled value as a current rating.

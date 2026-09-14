# Trail Map Caution Detection

## Scope

HikerCircle renders every trail and caution on Mapbox. Other providers are used only to enrich the caution dataset:

- Mapbox Streets supplies waterways, bridges, fords and cliffs near sampled route positions.
- OpenStreetMap supplies mapped crossing, assisted-trail and surface tags through Overpass.
- Open-Meteo Elevation supplies Copernicus DEM samples used to estimate steep route sections.

The enrichment results are converted to HikerCircle's local caution model, cached in SQLite and drawn as Mapbox point annotations. No alternative map is shown in the app.

## Implemented cautions

| Caution | Detection | Map icon |
| --- | --- | --- |
| Water crossing | River or stream is at most 10 m from the route and no mapped bridge or ford is within 30 m | Blue water waves |
| Bridge | Mapped walking/trail bridge within 12 m of the full saved route geometry | Amber bridge arch |
| River ford | `ford=*`, `highway=ford`, or Mapbox `road.structure=ford` | Teal ford/water path |
| Stepping stones | `ford=stepping_stones` | Cyan stepping stones |
| Steep ascent | Elevation segment has at least 25% uphill grade and at least 15 m vertical rise | Orange up arrow |
| Steep descent | Elevation segment has at least 25% downhill grade and at least 15 m vertical drop | Red down arrow |
| Rope-assisted section | Positive `assisted_trail`, `safety_rope`, `rungs` or equivalent mapped assistance | Purple rope |
| Ladder section | `highway=ladder` or a positive `ladder=*` tag | Indigo ladder |
| Scrambling section | Via ferrata or demanding/alpine `sac_scale` mapping | Violet mountain/scramble |
| Loose rock or scree | `natural=scree`, `surface=scree`, or `surface=loose_gravel` | Ochre loose rocks |
| Muddy surface | `surface=mud` | Brown mud/puddle |
| Rough surface | Rocky/stone/gravel surfaces, poor `smoothness`, or grade 4/5 track | Grey rough path |
| Cliff | Mapped cliff close to the route | Crimson cliff ledge |

Each caution type has its own vector marker. The previous shared warning-triangle artwork is no longer used for these categories.

## Water false-positive control

Waterways are not warnings merely because they exist in the wider map query. A water caution is retained only when all of the following are true:

1. The mapped river or stream is no more than 10 m from the route geometry.
2. No mapped bridge or ford geometry is within 30 m of that water feature.
3. A matching higher-confidence OpenStreetMap caution has not already replaced the Mapbox result.

A ford is shown as a ford, not as a generic water warning. A bridge is shown with the bridge icon and suppresses a duplicate water pin at the same crossing.

Mapbox's tile-query distance is measured from a query sample and is not used as proof that a bridge is crossed. HikerCircle projects every returned bridge onto the complete saved route polyline and hides off-route bridges, even when they are near one of the sparse query samples. The bridge must also be mapped as a path, footway, steps, pedestrian way, track, or bridleway; vehicle-road bridges that cross above or below the hiking route are excluded.

## Route and elevation thresholds

- OpenStreetMap features are queried in a 35 m route corridor and then projected to the nearest route segment before acceptance.
- Elevation is sampled at approximately 100 m intervals, up to 500 samples per trail.
- A steep section requires a sustained roughly 300 m window with both an absolute grade of at least 25% and an absolute rise/drop of at least 15 m. The wider window reduces false alternating pins caused by a 90 m terrain model on tight switchbacks.
- Adjacent steep samples of the same direction are grouped to avoid a dense row of duplicate pins.
- Before rendering, nearby steep samples are consolidated into physical terrain areas. Out-and-back ascent/descent records at the same location become one `Steep terrain area` pin, while the underlying measurements remain stored.
- Cross-provider duplicates in the same caution family are spatially suppressed within 35 m, preferring the OpenStreetMap result.

When a steep pin is opened, the primary view uses plain-language direction, approximate elevation change and difficulty. Average grade and terrain-sampling details remain available in an expandable technical section rather than appearing in the main warning sentence.

## Refresh and failure behaviour

The caution dataset is available offline after download and automatically refreshes after 30 days. The cache namespace is versioned so devices rescan after this detection update. Provider failures are isolated: Mapbox hazards remain usable if an enrichment source is temporarily unavailable, and one enrichment provider can still contribute when the other fails.

Public map tags and elevation models are advisory and may be incomplete or outdated. HikerCircle must not represent a missing pin as proof that the trail is safe. Field conditions, closures, rain and erosion still require current local checks.

## Data attribution

- Mapbox Streets: https://docs.mapbox.com/data/tilesets/reference/mapbox-streets-v8/
- OpenStreetMap contributors: https://www.openstreetmap.org/copyright
- Overpass API: https://wiki.openstreetmap.org/wiki/Overpass_API
- Open-Meteo Elevation API: https://open-meteo.com/en/docs/elevation-api

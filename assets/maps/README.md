# Malaysia state boundaries

`malaysia_states.geojson` is the unmodified full-resolution Malaysia ADM1 dataset distributed by geoBoundaries (16 states/federal territories; Polygon and MultiPolygon geometries).

- © OpenStreetMap contributors; source: OpenStreetMap / Wambacher, distributed by geoBoundaries.
- License: [Open Data Commons Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/).
- Attribution and contributor information: https://www.openstreetmap.org/copyright
- Dataset ID: MYS-ADM1-15666254; represented year: 2017; geoBoundaries build: 12 December 2023.
- Metadata: `malaysia_states.metadata.json`, retrieved from https://www.geoboundaries.org/api/current/gbOpen/MYS/ADM1/
- Exact source: https://github.com/wmgeolab/geoBoundaries/blob/9469f09/releaseData/gbOpen/MYS/ADM1/geoBoundaries-MYS-ADM1.geojson

Redistribution of this dataset remains under ODbL 1.0. The complete, unmodified source data and its metadata are retained here. Map attribution is supplied through the Mapbox GeoJSON source.

The app preloads this local asset, then filters `shapeISO` to draw the selected state's boundary. Three blue line layers create a subtle outer halo, inner glow and sharp edge, with zoom-dependent widths and blur to keep overview borders crisp. A translucent blue polygon fill animates three pulses over five seconds (glow, off, glow, off, glow, then clear), using native 400ms opacity transitions. The border stays visible. Selecting another state restarts the sequence; style reloads preserve its progress and leaving the page cancels its timers. The fill stays beneath borders, labels and pins. Borders render above basemap layers and below interactive annotations. The starting-point picker uses a flat map without 3D terrain draping, so hills cannot obscure the outline. Switching states only changes their filters; it makes no network request. Returning to Peninsular Malaysia clears the outline. This is a navigation aid; selecting a region or showing its boundary does not modify the selected pin or the trail's persisted state/country. The actual selected location continues through reverse geocoding.

Code: `lib/core/widgets/state_boundary_overlay.dart`, `lib/trail/Model/malaysia_map_region.dart`, and the Add Trail picker in `lib/trail/View/trail_page.dart`.

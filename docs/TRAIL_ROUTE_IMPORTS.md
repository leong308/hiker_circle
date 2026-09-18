# Native route storage

The app reads `trails/{trailId}.routeEncodedPolyline` and `checkpoints` from
Firestore. Full coordinates are stored in `routeGeometry/{revisionId}` under the
trail. There is no runtime dependency on the website used to obtain an input file.

The main document retains the existing precision-5 polyline format. Its
`routeGeometryMetadata` contains only schema version, geometry checksum, geometry
document location, point count, precision and update time. Geometry documents
contain native WGS84 latitude/longitude/elevation points, with no source URLs,
provider labels, embedded GPX or reference notes.

## GPX import

Create a JSON array containing `trailId`, `sourceFile`, `trackName`, `routeShape`
and `durationMinutes`. `sourceFile` can be absolute or relative to the manifest.
`trackName` must match the GPX title. Route shape is `out-and-back`, `loop`, or
`point-to-point`; duration describes the complete itinerary.

Run `node scripts/import_gpx_tracks.js /path/to/manifest.json` to validate;
append `--apply` to save. The importer validates every vertex, traversal order,
geometry gaps, route shape, trail location and document size. It saves the native
geometry and main trail atomically, then reads both back to verify all values.
No vertices are simplified or rerouted. The precision-5 display path must keep
every source vertex within one metre; native coordinates keep full numeric
precision. Distance/elevation are calculated from the track and may differ from
rounded or smoothed published statistics.

Named GPX waypoints become editor checkpoints when compatible with the existing
3–12 checkpoint editor. Tracks without named waypoints receive seven on-track
controls. Controls are independent of the complete route: all track vertices
remain stored. More than 12 named waypoints requires deliberate control selection.

## Manual editing

Manual routes use Mapbox walking Directions in checkpoint order, with a 50 m
snap limit and the existing hiking-provider fallbacks. Label-only edits preserve
the saved path; changed checkpoint coordinates require a fresh path before saving.
Changing geometry clears old geometry metadata. Sparse checkpoints can describe
multiple paths; place controls at forks to specify the intended route.

Checkpoint fingerprints use SHA-256 of ordered six-decimal coordinates, shared
by Dart and the importer. Legacy hashes remain readable.

## Current native conversion

Penang Hill Heritage Trail (`malaysia-penang-hill-heritage-trail`) has 1,081 native
track points and seven editor controls. Its full out-and-back polyline has zero
coordinate loss relative to the supplied GPX. The obsolete source archive and
reference fields were removed.

The catalogue migration uses `node scripts/migrate_native_trail_routes.js`
for read-only validation; append `--apply` to convert all existing saved routes.
It preserves polylines, checkpoints, IDs and unrelated fields, reuses native
precision/elevation when available, and removes obsolete reference fields. It
does not fetch new tracks or certify agreement with an external reference.
The native save transaction also removes obsolete fields so editing a cached
trail cannot restore old references. A per-trail verification report is written
to `output/route-audit/native-route-migration.json`.

## Standard trail IDs

The four original timestamp-based trail IDs were migrated to
`malaysia-penang-hill-heritage-trail`, `malaysia-bukit-gasing-loop`,
`malaysia-bukit-jambul-trail`, and `malaysia-near-teluk-kumbar`.
`node scripts/rename_trail_ids.js` audits the migration without writing;
`--apply` performs each trail's move and reference updates in one atomic commit.
It moves geometry and rating subcollections, repairs nested hike snapshots and
download records, and preserves existing image URLs and on-device map paths.
Backups and verification reports are kept locally under
`output/trail-id-migration/` (excluded from Git).

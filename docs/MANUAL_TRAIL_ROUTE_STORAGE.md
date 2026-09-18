# Manual trail route storage

Manual trail creation and editing now save the fetched route in the same native
Firestore structure used by Penang Hill Heritage Trail. No separate import
command is needed when using the app.

## What happens when you save

1. The trail form collects ordered checkpoints and fetches a hiking route.
   Mapbox walking Directions follows checkpoint order. Existing hiking-provider
   fallbacks remain available if Mapbox cannot route.
2. The form associates the fetched path with a SHA-256 checkpoint fingerprint.
   If the checkpoints change, saving requires a route for the new coordinates.
3. Both `createTrailByAdmin` and `updateTrailByAdmin` call
   `_saveTrailWithGeometry` in the Firebase repository.
4. `TrailGeometryStorage` decodes every vertex from the precision-5 polyline into
   native `{lat, lon}` coordinate maps. It preserves traversal order, duplicates
   and the return leg. It calculates a SHA-256 checksum of the polyline.
5. A Firestore transaction writes the coordinate document and the parent trail
   together. If either write fails, neither is committed. The save only returns
   successfully after Firebase commits the transaction.
6. If the parent already points to an existing geometry document with the same
   polyline and checksum, the transaction preserves that geometry and metadata.
   This prevents a name-only edit from discarding imported precision or altitude.
   If that document is missing, the transaction rebuilds it from the polyline.

## Where it is saved

Project: `hiker-circle`, Firestore database: `(default)`.

```text
trails/{trailId}
  checkpoints                 Ordered editor checkpoints
  routeEncodedPolyline        Complete path used by map previews and tracking
  routeCheckpointsHash        Fingerprint of ordered checkpoint coordinates
  routeGeometryMetadata
    schemaVersion             1
    geometrySha256            SHA-256 of the stored polyline
    geometryDocument          Path to the coordinate document
    pointCount                Number of route vertices
    polylinePrecision         5
    updatedAt                 UTC timestamp

trails/{trailId}/routeGeometry/{geometrySha256}
  coordinateSystem            WGS84
  points                      [{lat: ..., lon: ...}, ...]
  pointCount                  Number of route vertices
  updatedAt                   UTC timestamp
```

Existing imported geometry can use a different revision ID and a fully qualified
Firestore document path. Both forms remain supported. Changed routes create a
geometry document under their new checksum; older revisions are retained. The
parent metadata always identifies the current route.

The coordinate list is separate from editor checkpoints: a trail can have seven
checkpoints and thousands of stored route vertices. The app still renders the
parent polyline, so previews do not need another routing API call or an additional
geometry read.

## Elevation and precision

Manually saved coordinates come from the complete API polyline, at its existing
five-decimal precision. The current route-result model provides summary ascent
and minimum/maximum elevation, not elevation at every vertex. Those summaries
remain on the parent trail; per-point `ele` values are not invented. Existing
imported documents that contain `ele` are preserved on unchanged-route edits.

Coordinate JSON above 700,000 UTF-8 bytes is rejected before any write, leaving
room below Firestore's document limit. The app displays an error rather than
saving only part of the route. Very large tracks would need chunked geometry
storage, which this change does not introduce.

API routing follows the available path network; sparse checkpoints can describe
multiple valid paths. Place checkpoints at forks to select the intended trail.
This storage mechanism preserves the fetched route rather than certifying its
real-world accuracy.

## Relevant code

Paths are relative to the repository root.

| File | Responsibility |
| --- | --- |
| `lib/trail/View/trail_page.dart` | Manual form: `_saveTrail`, `_doSaveTrail`, `_freshRouteForSave`, `_save`; refreshes stale checkpoint routes and preserves unchanged paths. |
| `lib/core/services/hiking_route_service.dart` | `findHikingRouteForTrail`, checkpoint fingerprints, saved-route/cache reads. |
| `lib/core/services/mapbox_optimization_service.dart` | `walkingRouteInOrder`: fetches the path in the selected checkpoint order. |
| `lib/core/services/trail_geometry_storage.dart` | Decodes and validates the complete polyline; builds native coordinate documents and metadata. |
| `lib/app/Data/hiker_circle_firebase_repository.dart` | `createTrailByAdmin`, `updateTrailByAdmin`, `_saveTrailWithGeometry`: atomic persistence and geometry reuse. |
| `lib/trail/Model/trail_models.dart` | Reads, copies and serializes `routeGeometryMetadata` with the trail. |
| `firestore.rules` | Signed-in read and admin-only write permissions for `trails/{trailId}/routeGeometry/{geometryId}`. |
| `test/core/trail_geometry_storage_test.dart` | Vertex preservation, checksums, metadata shape and invalid-route rejection. |
| `test/core/hiking_route_service_test.dart` | Saved-route reuse and portable checkpoint fingerprints. |
| `test/trail/trail_route_reference_test.dart` | Geometry metadata survives ordinary edits and clears when the route changes. |

## Deployment and validation

The app changes take effect in the next build containing this code. The geometry
subcollection rule must also be deployed; parent document rules do not implicitly
cover subcollections. This change deploys the Firestore rules to `hiker-circle`.

Focused Flutter tests cover the native geometry conversion and existing route
persistence behavior. Firebase deployment compiles the rules. A full emulator
security/integration run requires a Java runtime, which was unavailable in this
workspace during implementation; no real-device manual-add test was performed.

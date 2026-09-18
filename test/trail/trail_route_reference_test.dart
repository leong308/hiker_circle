import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  test('route source and AllTrails reference survive persistence', () {
    final trail = Trail.fromPersistence({
      'trailId': 'malaysia-example',
      'dataSource': 'OpenStreetMap hiking relation, verified against AllTrails',
      'dataSourceUrl': 'https://www.openstreetmap.org/relation/123',
      'osmRelationId': '123',
      'routeProvider': 'osm-hiking-relation',
      'routeActivity': 'hiking',
      'routeShape': 'loop',
      'routeReferenceName': 'Example Trail',
      'routeReferenceUrl': 'https://www.alltrails.com/trail/example',
      'routeReferenceNote': 'Identity and shape reference.',
      'routeVerifiedAtLocal': '2026-09-01T00:00:00.000Z',
    });

    expect(trail.routeActivity, 'hiking');
    expect(trail.routeReferenceName, 'Example Trail');
    expect(
      trail.toPersistence(),
      containsPair(
        'routeReferenceUrl',
        'https://www.alltrails.com/trail/example',
      ),
    );

    final copied = trail.copyWith(name: 'Edited trail');
    expect(copied.dataSourceUrl, trail.dataSourceUrl);
    expect(copied.routeReferenceUrl, trail.routeReferenceUrl);
    expect(copied.routeVerifiedAtLocal, trail.routeVerifiedAtLocal);
  });
  test(
    'exact-source metadata survives edits and clears when geometry changes',
    () {
      final trail = Trail.fromPersistence({
        'trailId': 'imported',
        'name': 'Imported track',
        'routeEncodedPolyline': '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
        'routeGeometryMetadata': {
          'origin': 'alltrails-gpx-export',
          'sourcePointCount': 1081,
          'maximumVertexErrorMeters': 0,
        },
      });
      final renamed = trail.copyWith(name: 'New title');
      expect(
        renamed.toFirestore()['routeGeometryMetadata'],
        trail.routeGeometryMetadata,
      );
      expect(
        trail.copyWith(routeEncodedPolyline: 'new-route').routeGeometryMetadata,
        isEmpty,
      );
    },
  );
}

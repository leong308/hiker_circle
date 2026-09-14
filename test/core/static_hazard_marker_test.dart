import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/local_session_database.dart';
import 'package:hiker_circle/core/widgets/static_hazard_marker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bridge crossings select the bridge marker artwork', () {
    expect(usesBridgeHazardMarker(_match('bridge_crossing')), isTrue);
    expect(usesBridgeHazardMarker(_match('river')), isFalse);
    expect(usesBridgeHazardMarker(_match('cliff')), isFalse);
  });

  test('every supported caution type has a dedicated marker kind', () {
    final types = [
      'river',
      'bridge_crossing',
      'cliff',
      'ford_crossing',
      'stepping_stones',
      'steep_ascent',
      'steep_descent',
      'steep_section',
      'rope_assisted_section',
      'ladder_section',
      'scrambling_section',
      'loose_rock',
      'muddy_surface',
      'rough_surface',
    ];
    final kinds = types.map(staticHazardMarkerKindForType).toSet();

    expect(kinds.length, types.length);
    expect(kinds, isNot(contains(StaticHazardMarkerKind.generic)));
  });

  test(
    'bridge and general hazards render distinct PNG marker images',
    () async {
      final bridge = await staticHazardMarkerImageFor(
        _match('bridge_crossing'),
      );
      final water = await staticHazardMarkerImageFor(_match('stream'));

      expect(bridge, isNotEmpty);
      expect(water, isNotEmpty);
      expect(bridge, isNot(equals(water)));
      expect(bridge.take(8), equals(const [137, 80, 78, 71, 13, 10, 26, 10]));
    },
  );

  test('nearby steep warnings become one interactive terrain area', () {
    final display = prepareStaticHazardsForMapDisplay([
      _match(
        'steep_ascent',
        latitude: 5,
        longitude: 100,
        sourceFeatureId: 'steep_ascent:0.2:grade=31:change=72:span=302',
      ),
      _match(
        'steep_descent',
        latitude: 5.0002,
        longitude: 100.0002,
        sourceFeatureId: 'steep_descent:0.8:grade=37:change=84:span=298',
      ),
      _match(
        'steep_ascent',
        latitude: 5.02,
        longitude: 100.02,
        sourceFeatureId: 'steep_ascent:0.5:grade=28:change=61:span=300',
      ),
      _match('bridge_crossing'),
    ]);

    expect(display, hasLength(3));
    final combined = display.singleWhere(
      (match) => match.hazard.hazardType == 'steep_section',
    );
    expect(combined.hazard.title, 'Steep terrain area');
    expect(combined.hazard.description, contains('2 nearby steep'));
    expect(combined.hazard.sourceFeatureId, contains('grade=37'));
  });
}

LocalTrailHazardMatch _match(
  String hazardType, {
  double latitude = 5,
  double longitude = 100,
  String sourceFeatureId = 'feature',
}) {
  final now = DateTime.utc(2026, 9, 12);
  final hazard = LocalStaticHazard(
    hazardId: 'hazard-$hazardType',
    hazardType: hazardType,
    title: 'Hazard',
    description: 'Description',
    latitude: latitude,
    longitude: longitude,
    severity: 'warning',
    confidence: 'mapped_feature',
    sourceName: 'Map source',
    sourceUrl: 'https://example.com',
    sourceFeatureId: sourceFeatureId,
    safetyGuidance: 'Use care.',
    downloadedAt: now,
  );
  return LocalTrailHazardMatch(
    trailId: 'trail',
    hazard: hazard,
    relationship: hazardType == 'bridge_crossing'
        ? 'bridge_crossing'
        : 'nearby',
    distanceMeters: 2,
    routeProgress: 0.5,
    computedAt: now,
  );
}

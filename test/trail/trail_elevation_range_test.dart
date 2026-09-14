import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  test('trail elevation range survives Firestore persistence', () {
    final trail = Trail.fromPersistence({
      'trailId': 'range-trail',
      'minElevationMeters': 42,
      'maxElevationMeters': 318,
    });

    expect(trail.hasElevationRange, isTrue);
    expect(trail.elevationRangeLabel, '42 m – 318 m');
    expect(trail.toFirestore()['minElevationMeters'], 42);
    expect(trail.toFirestore()['maxElevationMeters'], 318);
  });

  test('legacy trails do not present elevation gain as altitude', () {
    final trail = Trail.fromPersistence({
      'trailId': 'legacy-trail',
      'elevationGainMeters': 520,
    });

    expect(trail.hasElevationRange, isFalse);
    expect(trail.elevationRangeLabel, 'Not available');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/ModelView/stationary_location_policy.dart';

void main() {
  group('StationaryLocationPolicy', () {
    test('keeps the five metre boundary for precise fixes', () {
      expect(
        StationaryLocationPolicy.movementThresholdMeters(
          referenceAccuracyMeters: 2,
          currentAccuracyMeters: 3,
        ),
        5,
      );
    });

    test('does not treat ordinary GPS uncertainty as hiker movement', () {
      expect(
        StationaryLocationPolicy.isMeaningfulMovement(
          distanceMeters: 12,
          referenceAccuracyMeters: 18,
          currentAccuracyMeters: 20,
        ),
        isFalse,
      );
      expect(
        StationaryLocationPolicy.isMeaningfulMovement(
          distanceMeters: 35,
          referenceAccuracyMeters: 18,
          currentAccuracyMeters: 20,
        ),
        isTrue,
      );
    });

    test('caps a weak fix so genuine movement is still detected', () {
      expect(
        StationaryLocationPolicy.movementThresholdMeters(
          referenceAccuracyMeters: 150,
          currentAccuracyMeters: 200,
        ),
        100,
      );
    });
  });
}

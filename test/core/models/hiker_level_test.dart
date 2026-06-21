import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/models/hiker_level.dart';

void main() {
  group('HikerLevel', () {
    test('selects the correct tier at every boundary', () {
      expect(HikerLevel.fromPoints(0).badgeLabel, 'Lv. 1 Trailhead');
      expect(HikerLevel.fromPoints(249).number, 1);
      expect(HikerLevel.fromPoints(250).number, 2);
      expect(HikerLevel.fromPoints(600).name, 'Trekker');
      expect(HikerLevel.fromPoints(5500).name, 'HikerCircle Elite');
    });

    test('calculates progress and points remaining', () {
      final level = HikerLevel.fromPoints(425);

      expect(level.number, 2);
      expect(level.progressFor(425), 0.5);
      expect(level.pointsToNextLevel(425), 175);
    });

    test('clamps negative points to the first level', () {
      expect(HikerLevel.fromPoints(-50).number, 1);
      expect(HikerLevel.fromPoints(-50).progressFor(-50), 0);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/Model/hike_shirt_color.dart';
import 'package:hiker_circle/home/Model/hike_weather_briefing.dart';

void main() {
  group('hike shirt colour guidance', () {
    test('stores exactly one valid colour in preparation preferences', () {
      final selected = HikeShirtColor.setPreference({
        'Drinking water',
        HikeShirtColor.black.preference,
      }, HikeShirtColor.lightBlue);

      expect(
        HikeShirtColor.fromPreferences(selected),
        HikeShirtColor.lightBlue,
      );
      expect(selected, isNot(contains(HikeShirtColor.black.preference)));
      expect(GearChecklistCatalog.sanitize(selected), selected);
    });

    test('warns against a dark shirt when the hike overlaps daylight', () {
      final advice = HikeShirtColorAdvice.forSelection(
        color: HikeShirtColor.navy,
        overlapsDaylight: true,
      );

      expect(advice.tone, HikeShirtColorSuitability.avoidInDaylight);
      expect(advice.title, contains('lighter shirt'));
      expect(advice.summary, contains('solar heat'));
      expect(advice.summary, contains('biting insects'));
    });

    test('high-visibility colour explains emergency spotting benefit', () {
      final advice = HikeShirtColorAdvice.forSelection(
        color: HikeShirtColor.highVisibilityYellow,
        overlapsDaylight: true,
      );

      expect(advice.tone, HikeShirtColorSuitability.visible);
      expect(advice.summary, contains('rescuers'));
      expect(advice.points.join(' '), contains('solar heat'));
    });

    test('uses actual sunrise and sunset to detect daylight overlap', () {
      final day = DateTime.utc(2026, 9, 23);
      final briefing = HikeWeatherBriefing(
        hours: const [],
        covered: false,
        utcOffset: const Duration(hours: 8),
        sunrise: day.add(const Duration(hours: 23)),
        sunset: day.add(const Duration(hours: 35)),
      );

      expect(
        HikeShirtColorAdvice.overlapsDaylight(
          departure: day.add(const Duration(hours: 22)),
          returning: day.add(const Duration(hours: 24)),
          briefing: briefing,
        ),
        isTrue,
      );
      expect(
        HikeShirtColorAdvice.overlapsDaylight(
          departure: day.add(const Duration(hours: 20)),
          returning: day.add(const Duration(hours: 22)),
          briefing: briefing,
        ),
        isFalse,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Model/trail_gear_plan.dart';
import 'package:hiker_circle/home/Model/route_gear_assessment.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  final midnight = DateTime.utc(2026, 9, 20).subtract(const Duration(hours: 8));
  Trail route({
    double temperature = 26,
    double chance = 0,
    double rain = 0,
    bool stale = false,
  }) =>
      Trail.fromPersistence({'trailId': 'required', 'distanceKm': 3}).copyWith(
        weather: TrailWeather(
          summary: '',
          temperatureRange: '',
          rainProbability: chance.round(),
          cachedAt: DateTime.now().subtract(Duration(hours: stale ? 5 : 0)),
          forecastData: {
            'utc_offset_seconds': 28800,
            'hourly': {
              'time': [
                for (var i = 0; i < 72; i++)
                  midnight.add(Duration(hours: i)).millisecondsSinceEpoch ~/
                      1000,
              ],
              'temperature_2m': List.filled(72, temperature),
              'precipitation_probability': List.filled(72, chance),
              'precipitation': List.filled(72, rain),
            },
          },
        ),
      );
  TrailGearPlan gear({
    int start = 8,
    int end = 10,
    double temperature = 26,
    double chance = 0,
    double rain = 0,
    bool stale = false,
    RouteGearAssessment? assessment,
  }) => TrailGearPlan.forTrail(
    route(temperature: temperature, chance: chance, rain: rain, stale: stale),
    midnight.add(Duration(hours: start)),
    midnight.add(Duration(hours: end)),
    assessment: assessment,
  );
  test('every hike requires basic three; recommended items do not block', () {
    final plan = gear(start: 19, end: 21);
    expect(plan.requiredItems, {
      'Drinking water',
      'Energy snack',
      'First-aid kit',
    });
    expect(plan.missingRequired(plan.requiredItems), isEmpty);
    expect(
      plan.missingRequired({'GPS device or app', 'Emergency contacts saved'}),
      plan.requiredItems,
    );
  });
  test(
    'sun protection uses positive local overlap including overnight sessions',
    () {
      for (final (start, end, expected) in [
        (6, 8, false),
        (7, 9, true),
        (8, 10, true),
        (17, 18, true),
        (18, 20, false),
        (23, 31, false),
        (23, 33, true),
        (1, 49, true),
      ]) {
        expect(
          gear(
            start: start,
            end: end,
          ).requiredItems.contains('Sun protection (hat, sunscreen)'),
          expected,
          reason: '$start -> $end',
        );
      }
    },
  );
  test('blanket threshold is strictly below 15 and ignores stale forecast', () {
    expect(
      gear(temperature: 15).requiredItems,
      isNot(contains('Emergency blanket')),
    );
    expect(
      gear(temperature: 14.9).requiredItems,
      contains('Emergency blanket'),
    );
    expect(
      gear(temperature: 10, stale: true).requiredItems,
      isNot(contains('Emergency blanket')),
    );
  });
  test(
    'wet conditions from probability, observed model rain or map mud require socks and cover',
    () {
      final required = {'Spare dry socks', 'Pack rain cover'};
      expect(gear(chance: 50).requiredItems.intersection(required), isEmpty);
      for (final plan in [
        gear(chance: 51),
        gear(rain: .1),
        gear(
          assessment: RouteGearAssessment(
            routeKey: 'x',
            checkedAt: DateTime.now(),
            status: 'complete',
            muddy: true,
          ),
        ),
      ]) {
        expect(plan.requiredItems, containsAll(required));
        expect(plan.items, containsAll(plan.requiredItems));
      }
    },
  );
  test(
    'rough terrain requires poles even when river category already holds them',
    () {
      final plan = gear(
        assessment: RouteGearAssessment(
          routeKey: 'x',
          checkedAt: DateTime.now(),
          status: 'complete',
          rough: true,
          possibleCrossing: true,
        ),
      );
      expect(plan.requiredItems, contains('Trekking poles'));
      expect(
        plan.sections.values
            .expand((x) => x)
            .where((x) => x == 'Trekking poles'),
        hasLength(1),
      );
      expect(
        gear(
          assessment: RouteGearAssessment(
            routeKey: 'x',
            checkedAt: DateTime.now(),
            status: 'complete',
            waterNearby: true,
          ),
        ).requiredItems,
        isNot(contains('Trekking poles')),
      );
    },
  );
  test('cold outside the actual session does not mandate blanket', () {
    final trail = route();
    final hourly = trail.weather.forecastData['hourly'] as Map;
    (hourly['temperature_2m'] as List)[7] = 10.0;
    final plan = TrailGearPlan.forTrail(
      trail,
      midnight.add(const Duration(hours: 8)),
      midnight.add(const Duration(hours: 10)),
    );
    expect(plan.requiredItems, isNot(contains('Emergency blanket')));
  });
}

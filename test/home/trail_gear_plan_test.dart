import 'package:hiker_circle/home/Model/route_gear_assessment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Model/trail_gear_plan.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  final start = DateTime(2026, 9, 20, 8);
  Trail route({double km = 3, String surface = 'paved', int elevation = 50}) =>
      Trail.fromPersistence({
        'trailId': 'test',
        'distanceKm': km,
        'elevationGainMeters': elevation,
        'routeGeometryMetadata': {'surface': surface},
      });
  test('short paved hike has essentials without duplicate gear or camping', () {
    final gear = TrailGearPlan.forTrail(
      route(),
      start,
      start.add(const Duration(hours: 2)),
    );
    expect(gear.sections.keys, ['Essentials']);
    expect(gear.items.length, 8);
    expect(gear.items, isNot(contains('GPS device or app')));
    expect(gear.items, isNot(contains('Emergency contacts saved')));
    expect(gear.items, isNot(contains('Charged phone')));
    expect(gear.items, contains('Headlamp with spare batteries'));
    expect(gear.items, isNot(contains('Tent or suitable shelter')));
  });
  test(
    'long day adds reserves without assuming camping, overnight adds shelter',
    () {
      final day = TrailGearPlan.forTrail(
        route(km: 15),
        start,
        start.add(const Duration(hours: 8)),
      );
      expect(day.items, contains('Extra food for delays'));
      expect(day.items, isNot(contains('Tent or suitable shelter')));
      final overnight = TrailGearPlan.forTrail(
        route(km: 15),
        start,
        start.add(const Duration(hours: 26)),
      );
      expect(
        overnight.items,
        containsAll([
          'Tent or suitable shelter',
          'Sleeping bag and sleeping mat',
        ]),
      );
    },
  );
  test('crossings and rough terrain have distinct, deduplicated additions', () {
    final gear = TrailGearPlan.forTrail(
      route(surface: 'dirt river crossing', elevation: 750),
      start,
      start.add(const Duration(hours: 4)),
      assessment: RouteGearAssessment(
        routeKey: 'test',
        checkedAt: DateTime.now(),
        status: 'complete',
        possibleCrossing: true,
        rough: true,
      ),
    );
    expect(
      gear.items,
      containsAll([
        'Trekking poles',
        'Dry bag / waterproof phone pouch',
        'Grippy hiking footwear',
      ]),
    );
    expect(
      gear.sections.values
          .expand((x) => x)
          .where((x) => x == 'Trekking poles')
          .length,
      1,
    );
  });
  test('legacy manual choices cannot override automatic map analysis', () {
    final saved = TrailGearPlan.setScenario({'Drinking water'}, 'river', true);
    final persisted = GearChecklistCatalog.sanitize(saved);
    final gear = TrailGearPlan.forTrail(
      route(),
      start,
      start.add(const Duration(hours: 2)),
      saved: persisted,
    );
    expect(gear.scenarios['river'], false);
    expect(gear.completed(persisted), 1);
    final changed = TrailGearPlan.setScenario(persisted, 'river', false);
    final shorter = TrailGearPlan.forTrail(
      route(),
      start,
      start.add(const Duration(hours: 2)),
      saved: changed,
    );
    expect(shorter.items, isNot(contains('Dry bag / waterproof phone pouch')));
    expect(shorter.completed(changed), 1);
    expect(
      GearChecklistCatalog.sanitize(['gear:scenario:unknown:on']),
      isEmpty,
    );
  });
}

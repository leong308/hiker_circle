// TrailGearPlan derives a compact packing list from route, weather and hike conditions.
import 'route_gear_assessment.dart';
import '../../trail/Model/trail_models.dart';
import 'hike_weather_briefing.dart';

/// A small base pack plus explicit, explainable additions for this itinerary.
/// Map-based additions come from a 50 m route corridor assessment. Legacy
/// preference tokens are readable but cannot override automatic recommendations.
class TrailGearPlan {
  TrailGearPlan(
    this.sections,
    this.reasons,
    this.scenarios,
    this.requiredReasons,
  );
  final Map<String, String> requiredReasons;
  Set<String> get requiredItems => requiredReasons.keys.toSet();
  Set<String> missingRequired(Iterable<String> saved) =>
      requiredItems.difference(saved.toSet());
  final Map<String, List<String>> sections;
  final Map<String, String> reasons;
  final Map<String, bool> scenarios;
  Set<String> get items => sections.values.expand((items) => items).toSet();
  int completed(Iterable<String> saved) =>
      saved.where(items.contains).toSet().length;
  static const scenarioLabels = {
    'river': 'River crossings',
    'rough': 'Uneven / unpaved terrain',
    'overnight': 'Overnight / camping',
    'wet': 'Wet conditions',
    'remote': 'Remote / limited signal',
  };
  static const base = [
    'Drinking water',
    'Energy snack',
    'First-aid kit',
    'Emergency whistle',
    'Headlamp with spare batteries',
    'Raincoat',
    'Sun protection (hat, sunscreen)',
    'Emergency blanket',
  ];
  static const additions = {
    'Long day': [
      'Power bank',
      'Extra food for delays',
      'Extra drinking water',
      'Blister care',
    ],
    'River crossings': [
      'Dry bag / waterproof phone pouch',
      'Secure water-crossing footwear',
      'Spare dry socks',
      'Trekking poles',
    ],
    'Water near route': ['Dry bag / waterproof phone pouch'],
    'Uneven terrain': [
      'Grippy hiking footwear',
      'Trekking poles',
      'Blister care',
    ],
    'Overnight camp': [
      'Tent or suitable shelter',
      'Sleeping bag and sleeping mat',
      'Meals for each day + reserve',
      'Water filter or tablets',
      'Stove and fuel where permitted',
      'Camp permit / booking',
      'Warm clothing layer',
      'Waste bags',
    ],
    'Wet conditions': [
      'Dry bag / waterproof phone pouch',
      'Spare dry socks',
      'Pack rain cover',
    ],
    'Remote route': [
      'Physical map',
      'Compass',
      'Power bank',
      'Satellite communicator if no signal',
      'Water filter or tablets',
      'Multi-tool',
    ],
    'Steep ascent': ['Trekking poles', 'Blister care'],
  };
  static Set<String> get allItems => {
    ...base,
    ...additions.values.expand((v) => v),
  };
  static bool isPreference(String value) => scenarioLabels.keys.any(
    (key) =>
        value == 'gear:scenario:$key:on' || value == 'gear:scenario:$key:off',
  );
  static Set<String> setScenario(
    Iterable<String> saved,
    String key,
    bool value,
  ) => {
    ...saved.where((v) => !v.startsWith('gear:scenario:$key:')),
    'gear:scenario:$key:${value ? 'on' : 'off'}',
  };

  /// Positive overlap with the trail-local [08:00, 18:00) interval on any day.
  static bool overlapsSunProtectionWindow(
    DateTime start,
    DateTime end,
    Duration offset,
  ) {
    if (!end.isAfter(start)) return false;
    final localStart = start.toUtc().add(offset),
        localEnd = end.toUtc().add(offset);
    for (
      var day = DateTime.utc(localStart.year, localStart.month, localStart.day);
      day.isBefore(localEnd);
      day = day.add(const Duration(days: 1))
    ) {
      if (localStart.isBefore(day.add(const Duration(hours: 18))) &&
          localEnd.isAfter(day.add(const Duration(hours: 8)))) {
        return true;
      }
    }
    return false;
  }

  static TrailGearPlan forTrail(
    Trail trail,
    DateTime start,
    DateTime end, {
    Iterable<String> saved = const [],
    RouteGearAssessment? assessment,
  }) {
    final hours = end.difference(start).inMinutes / 60;
    final forecast = HikeWeatherBriefing.fromWeather(trail.weather, start, end);
    final map = assessment?.usable == true ? assessment : null;
    final fresh = !trail.weather.isStale;
    final required = <String, String>{
      'Drinking water': 'Required for every hike',
      'Energy snack': 'Required for every hike',
      'First-aid kit': 'Required for every hike',
    };
    final offset = Duration(
      seconds:
          (trail.weather.forecastData['utc_offset_seconds'] as num?)?.toInt() ??
          8 * 3600,
    );
    if (overlapsSunProtectionWindow(start, end, offset)) {
      required['Sun protection (hat, sunscreen)'] =
          'Your hike overlaps 08:00–18:00 at the trail';
    }
    if (fresh &&
        forecast.hours.any(
          (h) => h.temperature != null && h.temperature! < 15,
        )) {
      required['Emergency blanket'] =
          'Forecast temperature below 15°C during this hike';
    }
    final scenarios = <String, bool>{
      'river': map?.possibleCrossing == true,
      'rough': map?.rough == true || map?.technical == true,
      'overnight': hours >= 18,
      'wet':
          map?.muddy == true ||
          (fresh &&
              forecast.hours.any(
                (h) =>
                    (h.rainChance ?? 0) > 50 ||
                    (h.value('precipitation') ?? 0) > 0 ||
                    ((h.value('weather_code') ?? 0) >= 51 &&
                        (h.value('weather_code') ?? 0) <= 99),
              )),
      'remote': false, // Map proximity cannot establish phone coverage.
    };
    if (scenarios['rough']!) {
      required['Trekking poles'] = 'Uneven terrain detected along your route';
    }
    if (scenarios['wet']!) {
      required['Spare dry socks'] = 'Wet conditions detected for this hike';
      required['Pack rain cover'] = 'Wet conditions detected for this hike';
    }
    final reasons = <String, String>{
      'Essentials':
          'A compact safety pack for every hike, including short routes.',
    };
    final sections = <String, List<String>>{'Essentials': base};
    final added = <String>{...base};
    void add(String name, String reason) {
      final items = additions[name]!.where(added.add).toList();
      if (items.isNotEmpty) {
        sections[name] = items;
        reasons[name] = reason;
      }
    }

    if (trail.distanceKm > 10 || hours >= 6) {
      add(
        'Long day',
        '${trail.distanceKm.toStringAsFixed(1)} km · ${hours.toStringAsFixed(1)} hours planned. Add reserves for delays.',
      );
    }
    if (scenarios['river']!) {
      add(
        'River crossings',
        'A mapped ford or possible unbridged water crossing intersects this route. Gear does not make fast or deep water safe; turn back when unsafe.',
      );
    }
    if (!scenarios['river']! && map?.waterNearby == true) {
      add(
        'Water near route',
        'Water is mapped within 50 m. This does not establish a crossing; protect essential gear.',
      );
    }
    if (scenarios['rough']!) {
      add(
        'Uneven terrain',
        'Mapped unpaved ground or technical features within 50 m of the route suggest extra grip and support.',
      );
    }
    if (scenarios['overnight']!) {
      add(
        'Overnight camp',
        'At least 18 hours are planned for this itinerary. Confirm campsite rules and size supplies to the number of days.',
      );
    }
    if (scenarios['wet']!) {
      add(
        'Wet conditions',
        'Protect dry clothing and electronics from rain and mud.',
      );
    }
    if (scenarios['remote']!) {
      add(
        'Remote route',
        'Backup navigation and communication for limited coverage.',
      );
    }
    if (trail.elevationGainMeters >= 500) {
      add(
        'Steep ascent',
        '${trail.elevationGainMeters} m of ascent; support for climbs and descents.',
      );
    }
    return TrailGearPlan(sections, reasons, scenarios, required);
  }
}

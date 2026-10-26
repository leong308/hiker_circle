import 'package:flutter/material.dart';

/// Shared report labels, also covered by the Help Center condition guide.
const trailHazardReportCategories = <String, (IconData, List<String>)>{
  'Trail surface': (
    Icons.terrain_rounded,
    [
      'Slippery pathway',
      'Loose rock',
      'Deep mud',
      'Ice or snow',
      'Eroded pathway',
      'Unstable ground',
      'Exposed roots',
      'Collapsed trail edge',
    ],
  ),
  'Blocked route': (
    Icons.block_rounded,
    [
      'Fallen tree',
      'Landslide',
      'Closed trail',
      'Other obstruction',
      'Dense overgrowth',
      'Blocked trail entrance',
      'Fallen branches',
    ],
  ),
  'Water': (
    Icons.water_rounded,
    [
      'Flooded route',
      'Fast river crossing',
      'Damaged bridge',
      'High water level',
      'Strong current',
      'Washed-out crossing',
      'Contaminated water',
    ],
  ),
  // Malaysian lowland and mountain conditions.
  // https://www.met.gov.my/en/pendidikan/fenomena-cuaca/
  'Weather': (
    Icons.thunderstorm_rounded,
    [
      'Heavy rain',
      'Thunderstorm or lightning',
      'Strong wind',
      'Heat and humidity',
      'Haze',
      'Poor visibility',
      'Cold or wet conditions',
    ],
  ),
  'Wildlife': (
    Icons.pets_rounded,
    [
      'Wild animal sighting',
      'Snakes',
      'Stinging insects',
      'Animal activity',
      'Animal tracks or den',
      'Leeches',
    ],
  ),
  'Trail structures': (
    Icons.stairs_rounded,
    [
      'Damaged steps',
      'Unsafe ladder or rope',
      'Missing sign',
      'Damaged handrail',
      'Unstable boardwalk',
      'Missing trail marker',
    ],
  ),
  'Other caution': (
    Icons.warning_amber_rounded,
    [
      'Unsafe human activity',
      'Other',
      'Limited mobile signal',
      'Illegal dumping',
    ],
  ),
};

/// Matches the backend catalog. Used only for legacy reports without a policy
/// result; current reports receive their classification from the server.
String? trailHazardCategoryFor(String type) {
  for (final entry in trailHazardReportCategories.entries) {
    if (entry.value.$2.contains(type)) return entry.key;
  }
  // Existing reports remain understandable after their option is retired.
  return type == 'Hail' ? 'Weather' : null;
}

/// Use the reported condition rather than one generic weather symbol.
IconData trailHazardIconFor(String type) => switch (type) {
  'Heavy rain' => Icons.water_drop_rounded,
  'Thunderstorm or lightning' => Icons.bolt_rounded,
  'Strong wind' => Icons.air_rounded,
  'Heat and humidity' => Icons.thermostat_rounded,
  'Haze' => Icons.blur_on_rounded,
  'Poor visibility' => Icons.foggy,
  'Cold or wet conditions' => Icons.ac_unit_rounded,
  'Hail' => Icons.thunderstorm_rounded,
  _ =>
    trailHazardReportCategories[trailHazardCategoryFor(type)]?.$1 ??
        Icons.warning_amber_rounded,
};

/// Computes trail hazard type is fatal.
bool trailHazardTypeIsFatal(String type) {
  final category = trailHazardCategoryFor(type);
  return category == 'Trail surface' ||
      category == 'Water' ||
      const {
        'Landslide',
        'Wild animal sighting',
        'Unsafe ladder or rope',
        'Heavy rain',
        'Thunderstorm or lightning',
        'Hail',
      }.contains(type);
}

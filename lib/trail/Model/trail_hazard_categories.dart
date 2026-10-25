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
      'Poor visibility',
      'Other',
      'Limited mobile signal',
      'Illegal dumping',
      'Strong wind',
    ],
  ),
};

/// Matches the backend catalog. Used only for legacy reports without a policy
/// result; current reports receive their classification from the server.
String? trailHazardCategoryFor(String type) {
  for (final entry in trailHazardReportCategories.entries) {
    if (entry.value.$2.contains(type)) return entry.key;
  }
  return null;
}

bool trailHazardTypeIsFatal(String type) {
  final category = trailHazardCategoryFor(type);
  return category == 'Trail surface' ||
      category == 'Water' ||
      const {
        'Landslide',
        'Wild animal sighting',
        'Unsafe ladder or rope',
      }.contains(type);
}

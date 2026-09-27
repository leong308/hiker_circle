import 'package:flutter/material.dart';

/// Shared report labels, also covered by the Help Center condition guide.
const trailHazardReportCategories = <String, (IconData, List<String>)>{
  'Trail surface': (
    Icons.terrain_rounded,
    ['Slippery pathway', 'Loose rock', 'Deep mud', 'Ice or snow'],
  ),
  'Blocked route': (
    Icons.block_rounded,
    ['Fallen tree', 'Landslide', 'Closed trail', 'Other obstruction'],
  ),
  'Water': (
    Icons.water_rounded,
    ['Flooded route', 'Fast river crossing', 'Damaged bridge'],
  ),
  'Wildlife': (
    Icons.pets_rounded,
    ['Wild animal sighting', 'Snakes', 'Stinging insects'],
  ),
  'Trail structures': (
    Icons.stairs_rounded,
    ['Damaged steps', 'Unsafe ladder or rope', 'Missing sign'],
  ),
  'Other caution': (
    Icons.warning_amber_rounded,
    ['Unsafe human activity', 'Poor visibility', 'Other'],
  ),
};

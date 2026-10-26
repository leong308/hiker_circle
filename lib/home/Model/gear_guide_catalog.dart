import 'trail_gear_plan.dart';

/// Explanations for the same item keys used by hike preparation.
/// Grouping is for browsing only; it does not change packing requirements.
enum GearGuideCategory {
  waterAndFood,
  safety,
  weather,
  footing,
  navigation,
  camping,
}

/// Represents gear guide catalog.
abstract final class GearGuideCatalog {
  static const _details =
      <String, ({GearGuideCategory category, String reason})>{
        'Drinking water': (
          category: GearGuideCategory.waterAndFood,
          reason: 'Keeps you hydrated throughout the hike.',
        ),
        'Energy snack': (
          category: GearGuideCategory.waterAndFood,
          reason: 'Provides a quick energy boost between meals.',
        ),
        'Extra food for delays': (
          category: GearGuideCategory.waterAndFood,
          reason: 'Keeps you fuelled if the hike takes longer than planned.',
        ),
        'Extra drinking water': (
          category: GearGuideCategory.waterAndFood,
          reason: 'Adds a reserve for long routes, heat or unexpected delays.',
        ),
        'Water filter or tablets': (
          category: GearGuideCategory.waterAndFood,
          reason: 'Treats water from suitable sources before drinking.',
        ),
        'First-aid kit': (
          category: GearGuideCategory.safety,
          reason: 'Carries supplies for minor injuries while help is arranged.',
        ),
        'Emergency whistle': (
          category: GearGuideCategory.safety,
          reason:
              'Helps you signal for attention without straining your voice.',
        ),
        'Headlamp with spare batteries': (
          category: GearGuideCategory.safety,
          reason: 'Lights your path after dark while keeping your hands free.',
        ),
        'Emergency blanket': (
          category: GearGuideCategory.safety,
          reason: 'Helps retain body heat during an unplanned stop.',
        ),
        'Blister care': (
          category: GearGuideCategory.safety,
          reason: 'Protects sore spots from further rubbing on long walks.',
        ),
        'Raincoat': (
          category: GearGuideCategory.weather,
          reason: 'Shields you from rain and helps keep your clothing dry.',
        ),
        'Sun protection (hat, sunscreen)': (
          category: GearGuideCategory.weather,
          reason: 'Reduces sun exposure on open sections of the trail.',
        ),
        'Dry bag / waterproof phone pouch': (
          category: GearGuideCategory.weather,
          reason: 'Protects your phone and essentials from rain and splashes.',
        ),
        'Spare dry socks': (
          category: GearGuideCategory.weather,
          reason: 'Lets you change out of wet socks and reduce rubbing.',
        ),
        'Pack rain cover': (
          category: GearGuideCategory.weather,
          reason: 'Helps shield your backpack and its contents from rain.',
        ),
        'Warm clothing layer': (
          category: GearGuideCategory.weather,
          reason: 'Adds warmth when temperatures drop or you stop moving.',
        ),
        'Grippy hiking footwear': (
          category: GearGuideCategory.footing,
          reason: 'Provides traction and support on uneven trail surfaces.',
        ),
        'Trekking poles': (
          category: GearGuideCategory.footing,
          reason: 'Adds balance and support on climbs and descents.',
        ),
        'Secure water-crossing footwear': (
          category: GearGuideCategory.footing,
          reason: 'Stays secure on wet ground. Never enter unsafe water.',
        ),
        'Power bank': (
          category: GearGuideCategory.navigation,
          reason: 'Recharges your phone for navigation and communication.',
        ),
        'Physical map': (
          category: GearGuideCategory.navigation,
          reason:
              'Provides a backup route reference if your phone is unavailable.',
        ),
        'Compass': (
          category: GearGuideCategory.navigation,
          reason: 'Helps you orient a map and find your direction.',
        ),
        'Satellite communicator if no signal': (
          category: GearGuideCategory.navigation,
          reason: 'Offers a backup way to request help beyond phone coverage.',
        ),
        'Multi-tool': (
          category: GearGuideCategory.navigation,
          reason: 'Helps with small gear repairs and adjustments on the trail.',
        ),
        'Tent or suitable shelter': (
          category: GearGuideCategory.camping,
          reason: 'Provides shelter from the weather during an overnight stay.',
        ),
        'Sleeping bag and sleeping mat': (
          category: GearGuideCategory.camping,
          reason: 'Adds warmth and insulation from the ground while resting.',
        ),
        'Meals for each day + reserve': (
          category: GearGuideCategory.camping,
          reason: 'Covers each day of the trip, with extra food for delays.',
        ),
        'Stove and fuel where permitted': (
          category: GearGuideCategory.camping,
          reason: 'Prepares hot food and drinks where local rules allow.',
        ),
        'Camp permit / booking': (
          category: GearGuideCategory.camping,
          reason:
              'Confirms access and a place to stay where booking is required.',
        ),
        'Waste bags': (
          category: GearGuideCategory.camping,
          reason: 'Lets you carry litter out and leave the campsite clean.',
        ),
      };

  /// Returns sections.
  static Map<GearGuideCategory, List<String>> get sections => {
    for (final category in GearGuideCategory.values)
      category: [
        for (final item in TrailGearPlan.allItems)
          if ((_details[item]?.category ?? GearGuideCategory.safety) ==
              category)
            item,
      ],
  };

  /// Computes reason for.
  static String reasonFor(String item) =>
      _details[item]?.reason ?? 'Supports the needs of your planned route.';
}

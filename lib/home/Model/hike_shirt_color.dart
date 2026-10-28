// HikeShirtColorAdvice evaluates the selected shirt color for hike visibility and conditions.
import 'hike_weather_briefing.dart';

/// Defines the hike shirt color suitability choices.
enum HikeShirtColorSuitability { recommended, visible, avoidInDaylight }

/// A per-hike clothing choice stored alongside the local preparation answers.
enum HikeShirtColor {
  white(
    label: 'White',
    colorValue: 0xFFF4F5F2,
    suitability: HikeShirtColorSuitability.recommended,
  ),
  lightGrey(
    label: 'Light grey',
    colorValue: 0xFFCFD4D1,
    suitability: HikeShirtColorSuitability.recommended,
  ),
  beige(
    label: 'Beige',
    colorValue: 0xFFDCC9A4,
    suitability: HikeShirtColorSuitability.recommended,
  ),
  lightBlue(
    label: 'Light blue',
    colorValue: 0xFF8EC9E8,
    suitability: HikeShirtColorSuitability.recommended,
  ),
  mintGreen(
    label: 'Mint green',
    colorValue: 0xFF8FD3AE,
    suitability: HikeShirtColorSuitability.recommended,
  ),
  highVisibilityYellow(
    label: 'Hi-vis yellow',
    colorValue: 0xFFD7F13A,
    suitability: HikeShirtColorSuitability.visible,
  ),
  brightOrange(
    label: 'Bright orange',
    colorValue: 0xFFFF8A3D,
    suitability: HikeShirtColorSuitability.visible,
  ),
  red(
    label: 'Red',
    colorValue: 0xFFE5484D,
    suitability: HikeShirtColorSuitability.visible,
  ),
  black(
    label: 'Black',
    colorValue: 0xFF171A18,
    suitability: HikeShirtColorSuitability.avoidInDaylight,
  ),
  navy(
    label: 'Navy',
    colorValue: 0xFF172D4F,
    suitability: HikeShirtColorSuitability.avoidInDaylight,
  ),
  darkGrey(
    label: 'Dark grey',
    colorValue: 0xFF434A46,
    suitability: HikeShirtColorSuitability.avoidInDaylight,
  );

  /// Creates this model.
  const HikeShirtColor({
    required this.label,
    required this.colorValue,
    required this.suitability,
  });

  static const preferencePrefix = 'gear:shirt-color:';

  final String label;
  final int colorValue;
  final HikeShirtColorSuitability suitability;

  /// Returns preference.
  String get preference => '$preferencePrefix$name';

  /// Restores an optional clothing snapshot without accepting arbitrary message text.
  static HikeShirtColor? fromName(Object? name) =>
      values.where((color) => color.name == name).firstOrNull;

  /// Checks whether preference.
  static bool isPreference(String value) =>
      value.startsWith(preferencePrefix) &&
      values.any((color) => color.preference == value);

  /// Creates from preferences.
  static HikeShirtColor? fromPreferences(Iterable<String> values) {
    for (final value in values) {
      for (final color in HikeShirtColor.values) {
        if (value == color.preference) return color;
      }
    }
    return null;
  }

  /// Sets preference.
  static Set<String> setPreference(
    Iterable<String> values,
    HikeShirtColor color,
  ) => {
    ...values.where((value) => !value.startsWith(preferencePrefix)),
    color.preference,
  };
}

/// Represents hike shirt color advice.
class HikeShirtColorAdvice {
  /// Creates hike shirt color advice.
  const HikeShirtColorAdvice({
    required this.tone,
    required this.title,
    required this.summary,
    required this.points,
  });

  final HikeShirtColorSuitability tone;
  final String title;
  final String summary;
  final List<String> points;

  /// Selects for selection.
  static HikeShirtColorAdvice forSelection({
    required HikeShirtColor color,
    required bool overlapsDaylight,
  }) {
    if (color.suitability == HikeShirtColorSuitability.avoidInDaylight) {
      return HikeShirtColorAdvice(
        tone: HikeShirtColorSuitability.avoidInDaylight,
        title: overlapsDaylight
            ? 'Choose a lighter shirt for this daytime hike'
            : 'A lighter colour is still safer to spot',
        summary: overlapsDaylight
            ? '${color.label} absorbs more solar heat and can make you more noticeable to some biting insects. Change to a light, visible colour if possible.'
            : '${color.label} will not add much solar heat before sunrise, but it is harder to spot in low light and vegetation.',
        points: [
          if (overlapsDaylight)
            'A light-coloured outer surface generally gains less heat in direct sun.',
          'Dark clothing can attract some mosquitoes; colour alone never prevents bites.',
          'A contrasting light or high-visibility colour helps teammates and rescuers locate you.',
        ],
      );
    }
    if (color.suitability == HikeShirtColorSuitability.visible) {
      return HikeShirtColorAdvice(
        tone: HikeShirtColorSuitability.visible,
        title: 'Easy to spot on the trail',
        summary:
            '${color.label} gives strong contrast against most vegetation, making you easier for teammates and rescuers to locate.',
        points: [
          'High visibility is useful when the group becomes separated or during an emergency.',
          if (overlapsDaylight)
            'A bright, lighter surface usually gains less solar heat than black, navy or dark grey.',
          'Some insects respond to particular vivid colours, so use long sleeves and repellent rather than relying on colour.',
        ],
      );
    }
    return HikeShirtColorAdvice(
      tone: HikeShirtColorSuitability.recommended,
      title: 'Good choice for hiking',
      summary:
          '${color.label} balances lower solar heat gain with better visibility than very dark clothing.',
      points: [
        if (overlapsDaylight)
          'Light fabric absorbs less solar energy than black, navy or dark grey.',
        'Light colours can be less attractive to some mosquitoes than dark clothing.',
        'Choose a shade that contrasts with the surroundings so it remains easy to spot in an emergency.',
      ],
    );
  }

  /// Uses forecast sunrise/sunset when present, with a trail-local daytime
  /// fallback for incomplete or offline forecasts.
  static bool overlapsDaylight({
    required DateTime departure,
    required DateTime returning,
    required HikeWeatherBriefing briefing,
  }) {
    if (!returning.isAfter(departure)) return false;
    final sunrise = briefing.sunrise;
    final sunset = briefing.sunset;
    if (sunrise != null && sunset != null) {
      return returning.toUtc().isAfter(sunrise.toUtc()) &&
          departure.toUtc().isBefore(sunset.toUtc());
    }

    final localStart = departure.toUtc().add(briefing.utcOffset);
    final localEnd = returning.toUtc().add(briefing.utcOffset);
    for (
      var day = DateTime.utc(localStart.year, localStart.month, localStart.day);
      day.isBefore(localEnd);
      day = day.add(const Duration(days: 1))
    ) {
      final fallbackSunrise = day.add(const Duration(hours: 7));
      final fallbackSunset = day.add(const Duration(hours: 19));
      if (localStart.isBefore(fallbackSunset) &&
          localEnd.isAfter(fallbackSunrise)) {
        return true;
      }
    }
    return false;
  }
}

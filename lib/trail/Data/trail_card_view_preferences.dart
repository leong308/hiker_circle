import 'package:shared_preferences/shared_preferences.dart';

/// Stores the device's preferred trail layout in SharedPreferences.
class TrailCardViewPreferences {
  /// Creates the trail layout preference store.
  const TrailCardViewPreferences();

  static const key = 'trailCardView';

  /// Reads only the trail layout preference.
  Future<String?> load() => SharedPreferencesAsync().getString(key);

  /// Persists the latest selected layout without touching other preferences.
  Future<void> save(String value) =>
      SharedPreferencesAsync().setString(key, value);
}

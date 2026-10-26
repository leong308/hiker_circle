part of '../me_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _MePageDataActions {
  /// Binds load trails to the selected data source.
  static Future<List<Trail>> Function() loadTrails(
    HikerCircleFirebaseRepository receiver,
  ) => receiver.loadTrails;

  /// Binds save preferred time zone to the selected data source.
  static Future<void> Function({
    required String preferredTimeZone,
    required AppSession session,
  })
  savePreferredTimeZone(HikerCircleFirebaseRepository receiver) =>
      receiver.savePreferredTimeZone;

  /// Binds load achievement leaderboard to the selected data source.
  static Future<List<Map<String, dynamic>>> Function({String period})
  loadAchievementLeaderboard(HikerCircleFirebaseRepository receiver) =>
      receiver.loadAchievementLeaderboard;
}

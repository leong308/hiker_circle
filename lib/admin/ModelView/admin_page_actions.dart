part of '../admin_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _AdminPageDataActions {
  /// Binds load admin dashboard analytics to the selected data source.
  static Future<Map<String, dynamic>> Function({
    bool forceRefresh,
    required AppSession session,
  })
  loadAdminDashboardAnalytics(HikerCircleFirebaseRepository receiver) =>
      receiver.loadAdminDashboardAnalytics;

  /// Binds load admin hazard reports to the selected data source.
  static Future<List<Map<String, dynamic>>> Function({
    required AppSession session,
  })
  loadAdminHazardReports(HikerCircleFirebaseRepository receiver) =>
      receiver.loadAdminHazardReports;

  /// Binds load admin achievements to the selected data source.
  static Future<List<Map<String, dynamic>>> Function({
    required AppSession session,
  })
  loadAdminAchievements(HikerCircleFirebaseRepository receiver) =>
      receiver.loadAdminAchievements;

  /// Binds review hazard report to the selected data source.
  static Future<void> Function({
    String adminNote,
    required bool approved,
    required Map<String, dynamic> report,
    required AppSession session,
  })
  reviewHazardReport(HikerCircleFirebaseRepository receiver) =>
      receiver.reviewHazardReport;

  /// Binds dump all tables to the selected data source.
  static Future<Map<String, List<Map<String, dynamic>>>> Function()
  dumpAllTables(LocalSessionDatabase receiver) => receiver.dumpAllTables;

  /// Binds save achievement by admin to the selected data source.
  static Future<String> Function({
    required Map<String, dynamic> achievement,
    String achievementId,
    required AppSession session,
  })
  saveAchievementByAdmin(HikerCircleFirebaseRepository receiver) =>
      receiver.saveAchievementByAdmin;

  /// Binds set achievement active by admin to the selected data source.
  static Future<void> Function({
    required String achievementId,
    required bool isActive,
    required AppSession session,
  })
  setAchievementActiveByAdmin(HikerCircleFirebaseRepository receiver) =>
      receiver.setAchievementActiveByAdmin;
}

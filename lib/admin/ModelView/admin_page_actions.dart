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

  /// Binds dump all tables to the selected data source.
  static Future<Map<String, List<Map<String, dynamic>>>> Function()
  dumpAllTables(LocalSessionDatabase receiver) => receiver.dumpAllTables;
}

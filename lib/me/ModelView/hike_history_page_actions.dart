part of '../hike_history_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _HikeHistoryPageDataActions {
  /// Binds load page to the selected data source.
  static Future<ExpiredHikesPage> Function({
    ExpiredHikesCursor? cursor,
    int limit,
    bool force,
    bool cacheOnly,
    required String ownerPhoneNumber,
  })
  loadPage(ExpiredHikesRepository receiver) => receiver.loadPage;
}

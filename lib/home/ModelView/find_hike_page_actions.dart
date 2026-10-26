part of '../find_hike_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _FindHikePageDataActions {
  /// Binds load upcoming hikes to the selected data source.
  static Future<List<UpcomingHike>> Function() loadUpcomingHikes(
    HikerCircleFirebaseRepository receiver,
  ) => receiver.loadUpcomingHikes;
}

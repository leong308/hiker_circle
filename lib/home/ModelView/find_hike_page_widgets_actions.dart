part of '../find_hike_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _FindHikePageWidgetsDataActions {
  /// Binds request to join upcoming hike to the selected data source.
  static Future<String> Function({required String hikeId})
  requestToJoinUpcomingHike(HikerCircleFirebaseRepository receiver) =>
      receiver.requestToJoinUpcomingHike;

  /// Binds join upcoming hike to the selected data source.
  static Future<bool> Function({required String hikeId}) joinUpcomingHike(
    HikerCircleFirebaseRepository receiver,
  ) => receiver.joinUpcomingHike;

  /// Binds load upcoming hike reminder preference to the selected data source.
  static Future<HikeReminderPreference> Function({
    required String hikeId,
    required AppSession session,
  })
  loadUpcomingHikeReminderPreference(HikerCircleFirebaseRepository receiver) =>
      receiver.loadUpcomingHikeReminderPreference;

  /// Binds save upcoming hike reminder preference to the selected data source.
  static Future<void> Function({
    UpcomingHike? hike,
    required String hikeId,
    required HikeReminderPreference preference,
    required AppSession session,
  })
  saveUpcomingHikeReminderPreference(HikerCircleFirebaseRepository receiver) =>
      receiver.saveUpcomingHikeReminderPreference;

  /// Binds remind upcoming hike host to the selected data source.
  static Future<Map<String, dynamic>> Function({required String hikeId})
  remindUpcomingHikeHost(HikerCircleFirebaseRepository receiver) =>
      receiver.remindUpcomingHikeHost;
}

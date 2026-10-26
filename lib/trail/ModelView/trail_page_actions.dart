part of '../trail_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _TrailPageDataActions {
  /// Binds watch trails to the selected data source.
  static Stream<List<Trail>> Function() watchTrails(
    HikerCircleFirebaseRepository receiver,
  ) => receiver.watchTrails;

  /// Binds load trails to the selected data source.
  static Future<List<Trail>> Function() loadTrails(
    HikerCircleFirebaseRepository receiver,
  ) => receiver.loadTrails;

  /// Binds create trail by admin to the selected data source.
  static Future<void> Function({
    required AppSession session,
    required Trail trail,
  })
  createTrailByAdmin(HikerCircleFirebaseRepository receiver) =>
      receiver.createTrailByAdmin;

  /// Binds update trail by admin to the selected data source.
  static Future<void> Function({
    required AppSession session,
    required Trail trail,
  })
  updateTrailByAdmin(HikerCircleFirebaseRepository receiver) =>
      receiver.updateTrailByAdmin;

  /// Binds delete trail by admin to the selected data source.
  static Future<void> Function({
    required AppSession session,
    required Trail trail,
  })
  deleteTrailByAdmin(HikerCircleFirebaseRepository receiver) =>
      receiver.deleteTrailByAdmin;

  /// Binds weather from firestore to the selected data source.
  static TrailWeather Function(Object?) weatherFromFirestore(
    HikerCircleFirebaseRepository receiver,
  ) => receiver.weatherFromFirestore;

  /// Binds refresh trail weather via cloud to the selected data source.
  static Future<Trail> Function(Trail) refreshTrailWeatherViaCloud(
    HikerCircleFirebaseRepository receiver,
  ) => receiver.refreshTrailWeatherViaCloud;
}

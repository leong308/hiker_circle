part of '../recorded_trail_requests_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _RecordedTrailRequestsPageDataActions {
  /// Binds load recorded trail request points to the selected data source.
  static Future<List<HikeCoordinate>> Function({
    required String requestId,
    required AppSession session,
  })
  loadRecordedTrailRequestPoints(HikerCircleFirebaseRepository receiver) =>
      receiver.loadRecordedTrailRequestPoints;

  /// Binds approve recorded trail request to the selected data source.
  static Future<void> Function({
    required List<HikeCoordinate> points,
    required String requestId,
    required AppSession session,
    required Trail trail,
  })
  approveRecordedTrailRequest(HikerCircleFirebaseRepository receiver) =>
      receiver.approveRecordedTrailRequest;

  /// Binds reject recorded trail request to the selected data source.
  static Future<void> Function({
    required String note,
    required String requestId,
    required AppSession session,
  })
  rejectRecordedTrailRequest(HikerCircleFirebaseRepository receiver) =>
      receiver.rejectRecordedTrailRequest;
}

part of '../recorded_trail_request_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _RecordedTrailRequestPageDataActions {
  /// Binds submit recorded trail request to the selected data source.
  static Future<String> Function({
    required ActiveHikeSession activeHike,
    required List<Map<String, dynamic>> checkpointSelections,
    void Function(double)? onProgress,
    required Map<String, String> proposed,
    required HikeSummaryReport report,
    required AppSession session,
  })
  submitRecordedTrailRequest(HikerCircleFirebaseRepository receiver) =>
      receiver.submitRecordedTrailRequest;
}

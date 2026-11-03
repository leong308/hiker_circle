part of '../hazard_report_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _HazardReportPageDataActions {
  /// Binds submit hazard report to the selected data source.
  static Future<LocalCautionReport> Function({
    required String description,
    required String hazardType,
    SosTriggerLocation? location,
    List<PendingCautionMedia> media,
    String? reportId,
    required AppSession session,
    required String severity,
    required Trail trail,
  })
  submitHazardReport(HikerCircleFirebaseRepository receiver) =>
      receiver.submitHazardReport;
}

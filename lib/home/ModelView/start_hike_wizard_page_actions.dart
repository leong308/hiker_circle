part of '../start_hike_wizard_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _StartHikeWizardPageDataActions {
  /// Binds schedule upcoming hike to the selected data source.
  static Future<String> Function({
    required HikeSessionDraft draft,
    String joinPolicy,
    HikeReminderPreference reminderPreference,
    required AppSession session,
  })
  scheduleUpcomingHike(HikerCircleFirebaseRepository receiver) =>
      receiver.scheduleUpcomingHike;
}

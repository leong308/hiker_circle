part of '../safety_questions_setup_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _SafetyQuestionsSetupPageDataActions {
  /// Binds authenticated phone number to the selected data source.
  static Future<String> Function() authenticatedPhoneNumber(
    MultiFactorAuthService receiver,
  ) => receiver.authenticatedPhoneNumber;
}

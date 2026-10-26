part of '../onboarding_profile_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _OnboardingProfilePageDataActions {
  /// Binds authenticated phone number to the selected data source.
  static Future<String> Function() authenticatedPhoneNumber(
    MultiFactorAuthService receiver,
  ) => receiver.authenticatedPhoneNumber;
}

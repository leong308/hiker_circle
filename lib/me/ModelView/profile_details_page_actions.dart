part of '../profile_details_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _ProfileDetailsPageDataActions {
  /// Binds load profile to the selected data source.
  static Future<OnboardingProfile> Function(AppSession) loadProfile(
    OnboardingRepository receiver,
  ) => receiver.loadProfile;

  /// Binds upload profile photo to the selected data source.
  static Future<String> Function({
    required Uint8List bytes,
    String contentType,
    required String fileName,
    required String phoneNumber,
  })
  uploadProfilePhoto(HikerCircleFirebaseRepository receiver) =>
      receiver.uploadProfilePhoto;

  /// Binds save profile to the selected data source.
  static Future<void> Function({
    required OnboardingProfile profile,
    required AppSession session,
  })
  saveProfile(OnboardingRepository receiver) => receiver.saveProfile;

  /// Binds save session to the selected data source.
  static Future<void> Function(AppSession) saveSession(
    LocalSessionDatabase receiver,
  ) => receiver.saveSession;
}

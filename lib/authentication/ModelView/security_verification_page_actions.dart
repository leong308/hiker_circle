part of '../security_verification_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _SecurityVerificationPageDataActions {
  /// Binds finish totp enrollment to the selected data source.
  static Future<AppSession?> Function({
    required String challengeId,
    required String code,
    String? mfaToken,
  })
  finishTotpEnrollment(MultiFactorAuthService receiver) =>
      receiver.finishTotpEnrollment;

  /// Binds verify totp login to the selected data source.
  static Future<AppSession> Function({
    required String code,
    required String mfaToken,
  })
  verifyTotpLogin(MultiFactorAuthService receiver) => receiver.verifyTotpLogin;
}

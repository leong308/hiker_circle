part of '../security_methods_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _SecurityMethodsPageDataActions {
  /// Binds load status to the selected data source.
  static Future<MfaStatus> Function() loadStatus(
    MultiFactorAuthService receiver,
  ) => receiver.loadStatus;

  /// Binds finish totp enrollment to the selected data source.
  static Future<AppSession?> Function({
    required String challengeId,
    required String code,
    String? mfaToken,
  })
  finishTotpEnrollment(MultiFactorAuthService receiver) =>
      receiver.finishTotpEnrollment;
}

// PrivateScreenUnlock requests device authentication before protected app surfaces become visible.
import 'package:local_auth/local_auth.dart';

/// Distinguishes canceled verification from device setup and access problems.
enum BiometricUnlockResult {
  authenticated,
  canceled,
  notEnrolled,
  unavailable,
  lockedOut,
  failed,
}

/// Requests biometric-only app unlock without a permission-dependent enrollment gate.
abstract final class PrivateScreenUnlock {
  static final _auth = LocalAuthentication();

  /// Lets the OS request biometric access and report the actual verification result.
  static Future<BiometricUnlockResult> requestAuthentication() async {
    try {
      final verified = await _auth.authenticate(
        localizedReason: 'Unlock HikerCircle with biometrics',
        biometricOnly: true,
        persistAcrossBackgrounding: false,
      );
      return verified
          ? BiometricUnlockResult.authenticated
          : BiometricUnlockResult.failed;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback =>
          BiometricUnlockResult.canceled,
        LocalAuthExceptionCode.noBiometricsEnrolled =>
          BiometricUnlockResult.notEnrolled,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout =>
          BiometricUnlockResult.lockedOut,
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
          BiometricUnlockResult.unavailable,
        _ => BiometricUnlockResult.failed,
      };
    } catch (_) {
      return BiometricUnlockResult.failed;
    }
  }

  /// Keeps protected app content locked unless biometric verification succeeds.
  static Future<bool> authenticate() async =>
      await requestAuthentication() == BiometricUnlockResult.authenticated;
}

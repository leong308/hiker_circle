// PrivateScreenUnlock requests device authentication before protected app surfaces become visible.
import 'package:local_auth/local_auth.dart';

/// Represents private screen unlock.
abstract final class PrivateScreenUnlock {
  static final _auth = LocalAuthentication();

  /// Computes available.
  static Future<bool> available() async =>
      await _auth.canCheckBiometrics &&
      (await _auth.getAvailableBiometrics()).isNotEmpty;

  /// Computes authenticate.
  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock your private HikerCircle screens',
        biometricOnly: true,
        persistAcrossBackgrounding: false,
      );
    } catch (_) {
      return false;
    }
  }
}

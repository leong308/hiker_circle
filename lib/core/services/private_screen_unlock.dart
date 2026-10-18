// PrivateScreenUnlock requests device authentication before protected app surfaces become visible.
import 'package:local_auth/local_auth.dart';

abstract final class PrivateScreenUnlock {
  static final _auth = LocalAuthentication();
  static Future<bool> available() async =>
      await _auth.canCheckBiometrics &&
      (await _auth.getAvailableBiometrics()).isNotEmpty;
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

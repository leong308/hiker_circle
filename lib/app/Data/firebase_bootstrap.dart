import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../firebase_options.dart';

class FirebaseBootstrapResult {
  const FirebaseBootstrapResult.available()
    : isAvailable = true,
      errorMessage = null;

  const FirebaseBootstrapResult.unavailable(this.errorMessage)
    : isAvailable = false;

  final bool isAvailable;
  final String? errorMessage;
}

abstract final class FirebaseBootstrap {
  static const MethodChannel _buildConfigChannel = MethodChannel(
    'hiker_circle/build_config',
  );
  static bool _appCheckActivated = false;

  static Future<FirebaseBootstrapResult> initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      if (!_appCheckActivated) {
        final useAndroidDebugProvider = await _useAndroidDebugProvider();
        await FirebaseAppCheck.instance.activate(
          providerAndroid: useAndroidDebugProvider
              ? const AndroidDebugProvider()
              : const AndroidPlayIntegrityProvider(),
          providerApple: kDebugMode
              ? const AppleDebugProvider()
              : const AppleAppAttestWithDeviceCheckFallbackProvider(),
        );
        _appCheckActivated = true;
      }

      if (kDebugMode &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android) {
        await FirebaseAuth.instance.setSettings(forceRecaptchaFlow: true);
      }
      return const FirebaseBootstrapResult.available();
    } on FirebaseException catch (error) {
      return FirebaseBootstrapResult.unavailable(error.message ?? error.code);
    } catch (error) {
      return FirebaseBootstrapResult.unavailable(error.toString());
    }
  }

  static Future<bool> _useAndroidDebugProvider() async {
    if (kDebugMode) return true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      return await _buildConfigChannel.invokeMethod<bool>(
            'isDevelopmentOnlyRelease',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static User requireAuthenticatedUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) return user;
    throw FirebaseAuthException(
      code: 'user-not-authenticated',
      message: 'The HikerCircle session is not signed in to Firebase.',
    );
  }
}

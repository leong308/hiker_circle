// FirebaseBootstrap initializes Firebase once and exposes availability so offline workflows can
// remain usable.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import 'app_check_build_support.dart';

/// Represents firebase bootstrap result.
class FirebaseBootstrapResult {
  /// Creates firebase bootstrap result using available.
  const FirebaseBootstrapResult.available()
    : isAvailable = true,
      errorMessage = null;

  /// Creates firebase bootstrap result using unavailable.
  const FirebaseBootstrapResult.unavailable(this.errorMessage)
    : isAvailable = false;

  final bool isAvailable;
  final String? errorMessage;
}

/// Represents firebase bootstrap.
abstract final class FirebaseBootstrap {
  /// Computes initialize.
  static Future<FirebaseBootstrapResult> initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      if (kDebugMode &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android) {
        await FirebaseAuth.instance.setSettings(forceRecaptchaFlow: true);
      }
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: kDebugMode
              ? const AndroidDebugProvider()
              : const AndroidPlayIntegrityProvider(),
          providerApple: await appleAppCheckProviderForBuild(),
        );
      }
      return const FirebaseBootstrapResult.available();
    } on FirebaseException catch (error) {
      return FirebaseBootstrapResult.unavailable(error.message ?? error.code);
    } catch (error) {
      return FirebaseBootstrapResult.unavailable(error.toString());
    }
  }

  /// Computes require authenticated user.
  static User requireAuthenticatedUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) return user;
    throw FirebaseAuthException(
      code: 'user-not-authenticated',
      message: 'The HikerCircle session is not signed in to Firebase.',
    );
  }
}

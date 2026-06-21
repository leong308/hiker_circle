import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

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
      return const FirebaseBootstrapResult.available();
    } on FirebaseException catch (error) {
      return FirebaseBootstrapResult.unavailable(error.message ?? error.code);
    } catch (error) {
      return FirebaseBootstrapResult.unavailable(error.toString());
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

import 'package:firebase_core/firebase_core.dart';

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
      return const FirebaseBootstrapResult.available();
    } on FirebaseException catch (error) {
      return FirebaseBootstrapResult.unavailable(error.message ?? error.code);
    } catch (error) {
      return FirebaseBootstrapResult.unavailable(error.toString());
    }
  }
}

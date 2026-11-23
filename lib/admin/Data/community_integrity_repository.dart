import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Requests the same server-owned rule scan used by automatic checks.
class CommunityIntegrityRepository {
  /// Defers Firebase access until an administrator explicitly refreshes.
  const CommunityIntegrityRepository();

  /// Waits for the protected scan result from the backend.
  Future<Map<String, dynamic>> runChecks() async {
    final owner = FirebaseAuth.instance.currentUser?.uid;
    if (owner == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Sign in again to run checks.',
      );
    }
    // Update cloud: run and save moderation scan
    final result = await FirebaseFunctions.instance
        .httpsCallable(
          'refreshCommunityContentIntegrity',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 570)),
        )
        .call<Map<String, dynamic>>({'expectedOwner': owner});
    if (FirebaseAuth.instance.currentUser?.uid != owner) {
      throw FirebaseFunctionsException(
        code: 'cancelled',
        message: 'The signed-in account changed. Please try again.',
      );
    }
    return Map<String, dynamic>.from(result.data);
  }
}

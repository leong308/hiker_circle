import 'package:firebase_app_check/firebase_app_check.dart';

typedef AppCheckTokenLoader = Future<String?> Function();

class FirebaseAppCheckGuard {
  FirebaseAppCheckGuard({AppCheckTokenLoader? tokenLoader})
    : _tokenLoader = tokenLoader ?? _loadFirebaseToken;

  final AppCheckTokenLoader _tokenLoader;

  static Future<String?> _loadFirebaseToken() =>
      FirebaseAppCheck.instance.getToken();

  Future<void> ensureAuthorized() async {
    try {
      final token = (await _tokenLoader())?.trim() ?? '';
      if (!_looksLikeJwt(token)) {
        throw const FirebaseAppCheckUnavailable();
      }
    } on FirebaseAppCheckUnavailable {
      rethrow;
    } catch (_) {
      throw const FirebaseAppCheckUnavailable();
    }
  }

  static bool _looksLikeJwt(String token) {
    final parts = token.split('.');
    return token.length >= 80 &&
        parts.length == 3 &&
        parts.every((part) => part.isNotEmpty);
  }
}

class FirebaseAppCheckUnavailable implements Exception {
  const FirebaseAppCheckUnavailable();

  static const message =
      'App security verification failed. This installation is not authorized '
      'by Firebase App Check. Register the development debug token or install '
      'the signed production app.';

  @override
  String toString() => message;
}

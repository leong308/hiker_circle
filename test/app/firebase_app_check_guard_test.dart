import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_app_check_guard.dart';

void main() {
  test('accepts a structurally valid App Check JWT', () async {
    final guard = FirebaseAppCheckGuard(
      tokenLoader: () async => '${'a' * 30}.${'b' * 30}.${'c' * 30}',
    );

    await expectLater(guard.ensureAuthorized(), completes);
  });

  test('rejects a missing or placeholder token', () async {
    for (final token in <String?>[null, '', 'placeholder-token']) {
      final guard = FirebaseAppCheckGuard(tokenLoader: () async => token);

      await expectLater(
        guard.ensureAuthorized(),
        throwsA(isA<FirebaseAppCheckUnavailable>()),
      );
    }
  });

  test('normalizes provider exceptions into an actionable failure', () async {
    final guard = FirebaseAppCheckGuard(
      tokenLoader: () async => throw StateError('403 blocked'),
    );

    await expectLater(
      guard.ensureAuthorized(),
      throwsA(
        isA<FirebaseAppCheckUnavailable>().having(
          (error) => error.toString(),
          'message',
          contains('Firebase App Check'),
        ),
      ),
    );
  });
}

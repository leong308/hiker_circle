import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_user_repository.dart';
import 'package:hiker_circle/app/Model/app_session.dart';

void main() {
  test(
    'late token validation never signs out a newer Firebase account',
    () async {
      final oldUser = _User('+60111111111');
      final auth = _Auth()..user = oldUser;
      final repository = FirebaseUserRepository(firebaseAuth: auth);
      final refresh = repository.refreshBoundSession(
        AppSession(
          phoneNumber: oldUser.uid,
          appInstanceId: 'device',
          signedInAt: DateTime.utc(2026),
        ),
      );
      final newUser = _User('+60222222222');
      auth.user = newUser;
      oldUser.token.complete(_Token());
      await expectLater(
        refresh,
        throwsA(isA<FirebaseUserRepositoryException>()),
      );
      expect(auth.currentUser, same(newUser));
      expect(auth.signOutCalls, 0);
    },
  );
}

class _Auth extends Fake implements FirebaseAuth {
  User? user;
  int signOutCalls = 0;
  @override
  User? get currentUser => user;
  @override
  Future<void> signOut() async {
    signOutCalls++;
    user = null;
  }
}

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
  final token = Completer<IdTokenResult>();
  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) =>
      token.future;
}

class _Token extends Fake implements IdTokenResult {
  @override
  Map<String, dynamic>? get claims => {'mfa': false};
}

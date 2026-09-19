import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_user_repository.dart';
import 'package:hiker_circle/app/Data/local_session_database.dart';
import 'package:hiker_circle/app/Data/session_repository.dart';
import 'package:hiker_circle/app/Model/app_session.dart';

void main() {
  final saved = AppSession(
    phoneNumber: '+60111111111',
    appInstanceId: 'device',
    signedInAt: DateTime.utc(2026),
  );
  test('local startup returns before cloud validation resolves', () async {
    final cloud = _Cloud();
    final repository = SessionRepository(
      localSessionDatabase: _Local(saved),
      firebaseUserRepository: cloud,
    );
    await repository.loadSavedSession().timeout(
      const Duration(milliseconds: 100),
    );
    expect(repository.currentSession, isNotNull);
    cloud.refresh.complete(saved.copyWith(username: 'Cloud name'));
    await repository.changes.firstWhere(
      (session) => session?.username == 'Cloud name',
    );
  });
  test(
    'late background validation cannot restore a signed-out session',
    () async {
      final cloud = _Cloud();
      final local = _Local(saved);
      final repository = SessionRepository(
        localSessionDatabase: local,
        firebaseUserRepository: cloud,
      );
      await repository.loadSavedSession();
      await repository.signOut();
      cloud.refresh.complete(saved.copyWith(username: 'Late result'));
      await Future<void>.delayed(Duration.zero);
      expect(repository.currentSession, isNull);
      expect(local.session, isNull);
    },
  );
  test(
    'explicit invalid credentials clear the locally restored session',
    () async {
      final cloud = _Cloud();
      final local = _Local(saved);
      final repository = SessionRepository(
        localSessionDatabase: local,
        firebaseUserRepository: cloud,
      );
      await repository.loadSavedSession();
      final signedOut = repository.changes.firstWhere(
        (session) => session == null,
      );
      cloud.refresh.completeError(
        const FirebaseUserRepositoryException('revoked', requiresSignIn: true),
      );
      await signedOut;
      await Future<void>.delayed(Duration.zero);
      expect(repository.currentSession, isNull);
      expect(local.session, isNull);
    },
  );
}

class _Local extends LocalSessionDatabase {
  _Local(this.session);
  AppSession? session;
  @override
  Future<AppSession?> loadSession() async => session;
  @override
  Future<void> saveSession(AppSession value) async {
    session = value;
  }

  @override
  Future<void> clearUserSessionOnly() async {
    session = null;
  }
}

class _Cloud extends FirebaseUserRepository {
  final refresh = Completer<AppSession>();
  @override
  Future<AppSession> refreshBoundSession(AppSession session) => refresh.future;
  @override
  Future<void> signOut() async {}
}

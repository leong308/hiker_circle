import 'dart:async';

import '../Model/app_session.dart';
import 'firebase_user_repository.dart';
import 'local_session_database.dart';

class SessionRepositoryException implements Exception {
  const SessionRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SessionRepository {
  SessionRepository({
    LocalSessionDatabase? localSessionDatabase,
    FirebaseUserRepository? firebaseUserRepository,
  }) : _localSessionDatabase = localSessionDatabase ?? LocalSessionDatabase(),
       _firebaseUserRepository =
           firebaseUserRepository ?? FirebaseUserRepository();

  final LocalSessionDatabase _localSessionDatabase;
  final FirebaseUserRepository _firebaseUserRepository;

  AppSession? _session;

  AppSession? get currentSession => _session;

  bool get isSignedIn => _session != null;

  Future<void> loadSavedSession() async {
    try {
      _session = await _localSessionDatabase.loadSession();
    } catch (_) {
      _session = null;
    }
  }

  Future<void> signIn(AppSession session) async {
    try {
      final registeredSession = await _firebaseUserRepository
          .registerOrLoadUser(session);
      await _localSessionDatabase.saveSession(registeredSession);
      _session = registeredSession;
    } on FirebaseUserRepositoryException catch (error) {
      throw SessionRepositoryException(error.message);
    } catch (_) {
      throw const SessionRepositoryException(
        'Unable to store your login. Please check your connection and try again.',
      );
    }
  }

  void signOut() {
    _session = null;
    unawaited(_localSessionDatabase.clearSession());
  }
}

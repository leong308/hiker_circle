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
      final savedSession = await _localSessionDatabase.loadSession();
      if (savedSession == null) {
        await _firebaseUserRepository.signOut();
        _session = null;
        return;
      }
      final appInstanceId = savedSession.appInstanceId.isEmpty
          ? await _localSessionDatabase.loadOrCreateAppInstanceId()
          : savedSession.appInstanceId;
      final boundSession = savedSession.copyWith(appInstanceId: appInstanceId);
      final refreshedSession = await _firebaseUserRepository
          .refreshBoundSession(boundSession);
      await _localSessionDatabase.saveSession(refreshedSession);
      _session = refreshedSession;
    } catch (_) {
      await _firebaseUserRepository.signOut();
      await _localSessionDatabase.clearSession();
      _session = null;
    }
  }

  Future<void> signIn(AppSession session) async {
    try {
      final existingSession = await _localSessionDatabase.loadSession();
      if (existingSession != null &&
          existingSession.phoneNumber != session.phoneNumber) {
        throw const SessionRepositoryException(
          'This phone is already bound to another HikerCircle account. Sign out first before using a different phone number.',
        );
      }
      final appInstanceId = await _localSessionDatabase
          .loadOrCreateAppInstanceId();
      final registeredSession = await _firebaseUserRepository
          .registerOrLoadUser(session.copyWith(appInstanceId: appInstanceId));
      await _localSessionDatabase.saveSession(registeredSession);
      _session = registeredSession;
    } on SessionRepositoryException {
      rethrow;
    } on FirebaseUserRepositoryException catch (error) {
      throw SessionRepositoryException(error.message);
    } catch (_) {
      throw const SessionRepositoryException(
        'Unable to store your login. Please check your connection and try again.',
      );
    }
  }

  Future<void> refreshCurrentSession() async {
    final session = _session;
    if (session == null) {
      return;
    }
    try {
      final refreshedSession = await _firebaseUserRepository
          .refreshBoundSession(session);
      await _localSessionDatabase.saveSession(refreshedSession);
      _session = refreshedSession;
    } on FirebaseUserRepositoryException catch (error) {
      throw SessionRepositoryException(error.message);
    }
  }

  void signOut() {
    _session = null;
    unawaited(_firebaseUserRepository.signOut());
    unawaited(_localSessionDatabase.clearSession());
  }
}

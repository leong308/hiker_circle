import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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
      final cachedSession = await _withCachedProfilePhoto(
        refreshedSession,
        previousSession: savedSession,
      );
      await _localSessionDatabase.saveSession(cachedSession);
      _session = cachedSession;
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
      final cachedSession = await _withCachedProfilePhoto(
        registeredSession,
        previousSession: existingSession,
      );
      await _localSessionDatabase.saveSession(cachedSession);
      _session = cachedSession;
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
      final cachedSession = await _withCachedProfilePhoto(
        refreshedSession,
        previousSession: session,
      );
      await _localSessionDatabase.saveSession(cachedSession);
      _session = cachedSession;
    } on FirebaseUserRepositoryException catch (error) {
      throw SessionRepositoryException(error.message);
    }
  }

  void signOut() {
    _session = null;
    unawaited(_firebaseUserRepository.signOut());
    unawaited(_localSessionDatabase.clearSession());
  }

  Future<AppSession> _withCachedProfilePhoto(
    AppSession session, {
    AppSession? previousSession,
  }) async {
    final photoURL = session.photoURL?.trim() ?? '';
    if (photoURL.isEmpty) {
      return session;
    }
    final previousPhotoURL = previousSession?.photoURL?.trim() ?? '';
    final previousBytes = previousSession?.photoBytes;
    if (previousPhotoURL == photoURL &&
        previousBytes != null &&
        previousBytes.isNotEmpty) {
      return session.copyWith(photoBytes: previousBytes);
    }

    final downloadedBytes = await _downloadProfilePhoto(photoURL);
    if (downloadedBytes == null || downloadedBytes.isEmpty) {
      return previousBytes == null
          ? session
          : session.copyWith(photoBytes: previousBytes);
    }
    return session.copyWith(photoBytes: downloadedBytes);
  }

  Future<Uint8List?> _downloadProfilePhoto(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) {
        return null;
      }
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      if (response.bodyBytes.length > 10 * 1024 * 1024) {
        return null;
      }
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}

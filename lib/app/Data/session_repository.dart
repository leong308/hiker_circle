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
    AppSession? boundSession;
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
      boundSession = savedSession.copyWith(appInstanceId: appInstanceId);
      // Make the locally authenticated session available immediately. A cold
      // start without connectivity must not erase the user's account or their
      // in-progress hike merely because cloud revalidation cannot run.
      _session = boundSession;
      final refreshedSession = await _firebaseUserRepository
          .refreshBoundSession(boundSession);
      final cachedSession = await _withCachedProfilePhoto(
        refreshedSession,
        previousSession: savedSession,
      );
      await _localSessionDatabase.saveSession(cachedSession);
      _session = cachedSession;
    } on FirebaseUserRepositoryException catch (error) {
      if (error.requiresSignIn) {
        await _firebaseUserRepository.signOut();
        await _localSessionDatabase.clearUserSessionOnly();
        _session = null;
        return;
      }
      // Transient Firebase/network failures retain the locally saved session.
      // The next foreground/reconnect refresh will revalidate it.
      _session = boundSession;
      if (boundSession != null) {
        try {
          await _localSessionDatabase.saveSession(boundSession);
        } catch (_) {
          // The original cached row is still the best available source.
        }
      }
    } catch (_) {
      // Local corruption or an unexpected startup error must not delete an
      // active hike. Leave the recoverable session untouched on disk.
      _session = boundSession;
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
    unawaited(_ignoreSignOutFailure(_firebaseUserRepository.signOut()));
    unawaited(
      _ignoreSignOutFailure(_localSessionDatabase.clearUserSessionOnly()),
    );
  }

  Future<void> _ignoreSignOutFailure(Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      // Local UI state is already signed out. Cleanup can be retried later.
    }
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
    final client = http.Client();
    try {
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.scheme != 'https' ||
          !_isTrustedProfilePhotoHost(uri.host)) {
        return null;
      }
      final request = http.Request('GET', uri);
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (!contentType.startsWith('image/')) {
        return null;
      }
      const maxBytes = 10 * 1024 * 1024;
      final advertisedLength = response.contentLength;
      if (advertisedLength != null && advertisedLength > maxBytes) {
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (builder.length + chunk.length > maxBytes) {
          return null;
        }
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      return _hasSupportedImageSignature(bytes) ? bytes : null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  bool _isTrustedProfilePhotoHost(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized == 'firebasestorage.googleapis.com' ||
        normalized == 'storage.googleapis.com' ||
        normalized.endsWith('.firebasestorage.app') ||
        normalized.endsWith('.appspot.com');
  }

  bool _hasSupportedImageSignature(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
    final isPng =
        bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A;
    final isGif =
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38;
    final isWebp =
        bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return isJpeg || isPng || isGif || isWebp;
  }
}

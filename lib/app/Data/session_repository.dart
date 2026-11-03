// SessionRepository serializes sign-in/sign-out persistence and observes the active server session
// without discarding offline safety queues.
import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../Model/app_session.dart';
import '../../core/services/mobile_security_service.dart';
import 'firebase_user_repository.dart';
import 'local_session_database.dart';
import '../../core/models/account_role.dart';
import '../../authentication/Data/auth_flow_diagnostics.dart';

/// Represents session repository exception.
class SessionRepositoryException implements Exception {
  /// Creates session repository exception.
  const SessionRepositoryException(this.message);

  final String message;

  /// Converts to string.
  @override
  String toString() => message;
}

/// Represents session repository.
class SessionRepository {
  /// Creates session repository.
  SessionRepository({
    LocalSessionDatabase? localSessionDatabase,
    FirebaseUserRepository? firebaseUserRepository,
    Duration cloudTimeout = const Duration(seconds: 8),
    Future<String> Function()? readSessionId,
    Future<void> Function()? endServerSession,
  }) : _localSessionDatabase = localSessionDatabase ?? LocalSessionDatabase(),
       _cloudTimeout = cloudTimeout,
       _readSessionId = readSessionId ?? MobileSecurityService.currentSessionId,
       _endServerSession = endServerSession ?? MobileSecurityService.endSession,
       _firebaseUserRepository =
           firebaseUserRepository ?? FirebaseUserRepository();

  final LocalSessionDatabase _localSessionDatabase;
  final FirebaseUserRepository _firebaseUserRepository;

  final Duration _cloudTimeout;
  final Future<String> Function() _readSessionId;
  final Future<void> Function() _endServerSession;
  final _changes = StreamController<AppSession?>.broadcast();

  /// Returns changes.
  Stream<AppSession?> get changes => _changes.stream;
  AppSession? _session;
  int _generation = 0;
  Future<void> _localWrites = Future<void>.value();
  Future<void> _signOutFuture = Future<void>.value();
  StreamSubscription<Map<String, dynamic>>? _sessionStateSubscription;
  String? _watchedSession;
  StreamSubscription<Map<String, dynamic>>? _accountSubscription;
  String? _watchedAccount;
  AccountRole? _confirmedRole;
  String? securityMessage;

  /// Keeps slow startup/profile responses from restoring a superseded role.
  AppSession _withConfirmedRole(AppSession session) =>
      _watchedAccount == '${session.phoneNumber}:$_generation' &&
          _confirmedRole != null
      ? session.copyWith(
          isAdmin: _confirmedRole != AccountRole.hiker,
          isSuperAdmin: _confirmedRole == AccountRole.superadmin,
        )
      : session;

  /// Refreshes the shell immediately on a confirmed account change, then persists it.
  void _watchAccount(AppSession session) {
    final generation = _generation;
    final key = '${session.phoneNumber}:$generation';
    if (_watchedAccount == key) return;
    unawaited(_accountSubscription?.cancel());
    _watchedAccount = key;
    _confirmedRole = null;
    try {
      _accountSubscription = _firebaseUserRepository
          .watchAccountState(session.phoneNumber)
          .listen(
            (data) {
              if (generation != _generation ||
                  _session?.phoneNumber != session.phoneNumber) {
                return;
              }
              if (data.isEmpty ||
                  data['accountDisabled'] == true ||
                  data['status'] == 'disabled') {
                unawaited(
                  signOut(
                    securityNotice:
                        'Your account is unavailable. Sign in again to continue.',
                  ),
                );
                return;
              }
              _confirmedRole = AccountRole.fromAccount(data);
              final previous = _session!;
              final updated = _withConfirmedRole(previous);
              if (previous.isAdmin == updated.isAdmin &&
                  previous.isSuperAdmin == updated.isSuperAdmin) {
                return;
              }
              _publishSession(updated);
              unawaited(
                _persistRolesIfCurrent(generation).catchError((Object _) {}),
              );
            },
            onError: (Object _) {
              // Offline listeners reconnect; server authorization continues to enforce current roles.
            },
          );
    } catch (_) {
      _watchedAccount = null;
      // Local startup remains usable when Firebase has not initialized yet.
    }
  }

  // _watchServerSession detects server revocation or replacement without treating transient read
  // failures as sign-out.
  /// Watches server session.
  Future<void> _watchServerSession(AppSession session) async {
    final generation = _generation;
    try {
      final sid = await _readSessionId();
      if (generation != _generation || sid.isEmpty) return;
      final key = '${session.phoneNumber}:$sid';
      if (_watchedSession == key) return;
      await _sessionStateSubscription?.cancel();
      if (generation != _generation) return;
      _watchedSession = key;
      _sessionStateSubscription = _firebaseUserRepository
          .watchSessionState(session.phoneNumber)
          .listen(
            (state) {
              if (generation != _generation ||
                  state['activeSessionId'] == sid) {
                return;
              }
              final reason = state['reason'];
              final device = state['device'];
              final name = device is Map ? device['name'] as String? : null;
              final message = reason == 'password-reset'
                  ? 'You have been signed out because your account password was reset. Sign in again to continue.'
                  : reason == 'account-disabled'
                  ? 'You have been signed out because this account is disabled.'
                  : 'You have been signed out because this account was signed in on ${name ?? 'another device'}. If this was not you, reset your password.';
              unawaited(signOut(securityNotice: message));
            },
            onError: (Object error) {
              // Offline listeners reconnect themselves. Do not erase local safety queues.
            },
          );
    } catch (_) {
      // Cloud authorization remains fail-closed; a transient watch failure is retried on refresh.
    }
  }

  /// Computes publish session.
  void _publishSession(AppSession? session) {
    _session = session == null ? null : _withConfirmedRole(session);
    _changes.add(_session);
    if (session != null) {
      _watchAccount(session);
      unawaited(_watchServerSession(session));
    } else {
      _watchedSession = null;
      unawaited(_sessionStateSubscription?.cancel());
      _sessionStateSubscription = null;
      _watchedAccount = null;
      _confirmedRole = null;
      unawaited(_accountSubscription?.cancel());
      _accountSubscription = null;
    }
  }

  /// Queues only role columns so a newer profile response cannot be overwritten.
  Future<void> _persistRolesIfCurrent(int generation) {
    final operation = _localWrites.then((_) async {
      final current = _session;
      if (generation != _generation || current == null) return;
      await _localSessionDatabase.updateSessionRoles(
        ownerPhoneNumber: current.phoneNumber,
        isAdmin: current.isAdmin,
        isSuperAdmin: current.isSuperAdmin,
      );
    });
    _localWrites = operation.catchError((_) {});
    return operation;
  }

  /// Persists the profile while retaining the latest confirmed cloud-owned role.
  Future<void> _persistIfCurrent(int generation, AppSession? session) {
    final operation = _localWrites.then((_) async {
      if (generation != _generation) return;
      if (session == null) {
        await _localSessionDatabase.clearUserSessionOnly();
      } else {
        await _localSessionDatabase.saveSession(_withConfirmedRole(session));
      }
    });
    _localWrites = operation.catchError((_) {});
    return operation;
  }

  /// Returns current session.
  AppSession? get currentSession => _session;

  /// Returns is signed in.
  bool get isSignedIn => _session != null;

  // loadSavedSession restores local state first, then validates the current Firebase
  // account/session asynchronously.
  /// Loads saved session.
  Future<void> loadSavedSession() async {
    final generation = ++_generation;
    try {
      final saved = await _localSessionDatabase.loadSession();
      if (generation != _generation) return;
      if (saved == null) {
        _publishSession(null);
        unawaited(
          _ignoreSignOutFailure(
            _firebaseUserRepository.signOut().timeout(_cloudTimeout),
          ),
        );
        return;
      }
      final instanceId = saved.appInstanceId.isEmpty
          ? await _localSessionDatabase.loadOrCreateAppInstanceId()
          : saved.appInstanceId;
      if (generation != _generation) return;
      final bound = saved.copyWith(appInstanceId: instanceId);
      _publishSession(bound);
      // Restoring the local session is sufficient to leave the startup screen.
      // Cloud validation continues independently with a bounded deadline.
      unawaited(_refreshSavedSession(bound, generation));
    } catch (error) {
      // Never delete an active hike because local startup data could not load.
      AuthFlowDiagnostics.event(
        'restore-local-session',
        'failure',
        error: error,
      );
      if (generation == _generation) _publishSession(null);
    }
  }

  /// Refreshes saved session.
  Future<void> _refreshSavedSession(AppSession saved, int generation) async {
    try {
      final refreshed = await _firebaseUserRepository
          .refreshBoundSession(saved)
          .timeout(_cloudTimeout);
      if (generation != _generation) return;
      final cached = await _withCachedProfilePhoto(
        refreshed,
        previousSession: saved,
      ).timeout(_cloudTimeout, onTimeout: () => refreshed);
      if (generation != _generation) return;
      await _persistIfCurrent(generation, cached);
      if (generation == _generation) _publishSession(cached);
    } on FirebaseUserRepositoryException catch (error) {
      if (generation == _generation && error.requiresSignIn) await signOut();
    } catch (_) {
      // A transient cloud/profile failure retains the locally restored session.
    }
  }

  // signIn serializes local profile persistence and starts the server-session observer for the new
  // account.
  /// Computes sign in.
  Future<void> signIn(AppSession session) async {
    await _signOutFuture;
    final generation = ++_generation;
    try {
      await _localWrites;
      final existingSession = await _localSessionDatabase.loadSession();
      if (existingSession != null &&
          existingSession.phoneNumber != session.phoneNumber) {
        throw const SessionRepositoryException(
          'This phone is already bound to another HikerCircle account. Sign out first before using a different phone number.',
        );
      }
      final appInstanceId = await _localSessionDatabase
          .loadOrCreateAppInstanceId();
      final registered = await _firebaseUserRepository
          .registerOrLoadUser(session.copyWith(appInstanceId: appInstanceId))
          .timeout(_cloudTimeout);
      if (generation != _generation) return;
      final cached = await _withCachedProfilePhoto(
        registered,
        previousSession: existingSession,
      ).timeout(_cloudTimeout, onTimeout: () => registered);
      if (generation != _generation) return;
      await _persistIfCurrent(generation, cached);
      if (generation == _generation) _publishSession(cached);
    } on SessionRepositoryException {
      rethrow;
    } on FirebaseUserRepositoryException catch (error) {
      if (generation == _generation && error.requiresSignIn) await signOut();
      throw SessionRepositoryException(error.message);
    } catch (_) {
      throw const SessionRepositoryException(
        'Unable to store your login. Please check your connection and try again.',
      );
    }
  }

  /// Refreshes current session.
  Future<void> refreshCurrentSession() async {
    final session = _session;
    final generation = _generation;
    if (session == null) return;
    try {
      final refreshed = await _firebaseUserRepository
          .refreshBoundSession(session)
          .timeout(_cloudTimeout);
      if (generation != _generation) return;
      final cached = await _withCachedProfilePhoto(
        refreshed,
        previousSession: session,
      ).timeout(_cloudTimeout, onTimeout: () => refreshed);
      if (generation != _generation) return;
      await _persistIfCurrent(generation, cached);
      if (generation == _generation) _publishSession(cached);
    } on FirebaseUserRepositoryException catch (error) {
      if (generation == _generation && error.requiresSignIn) await signOut();
      throw SessionRepositoryException(error.message);
    } on TimeoutException {
      throw const SessionRepositoryException(
        'Profile refresh timed out. Please try again.',
      );
    }
  }

  // signOut invalidates pending profile writes, ends the server session and removes only local
  // account state.
  /// Computes sign out.
  Future<void> signOut({String? securityNotice}) {
    securityMessage = securityNotice;
    final generation = ++_generation;
    _publishSession(null);
    // Queue local deletion behind an in-flight save; a later sign-in waits for
    // this cleanup so neither a late refresh nor deletion can revive/erase it.
    final localCleanup = _persistIfCurrent(generation, null);
    final cleanup = Future.wait<void>([
      _ignoreSignOutFailure(localCleanup),
      _ignoreSignOutFailure(
        (() async {
          if (securityNotice == null) {
            try {
              await _endServerSession().timeout(_cloudTimeout);
            } catch (_) {}
          }
          await _firebaseUserRepository.signOut().timeout(_cloudTimeout);
        })(),
      ),
    ]).then((_) {});
    _signOutFuture = cleanup;
    return cleanup;
  }

  /// Computes ignore sign out failure.
  Future<void> _ignoreSignOutFailure(Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      // In-memory authentication is already cleared.
    }
  }

  /// Applies cached profile photo.
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

  /// Downloads profile photo.
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
      await (() async {
        await for (final chunk in response.stream) {
          if (builder.length + chunk.length > maxBytes) {
            throw const FormatException('Profile image is too large.');
          }
          builder.add(chunk);
        }
      })().timeout(_cloudTimeout);
      final bytes = builder.takeBytes();
      return _hasSupportedImageSignature(bytes) ? bytes : null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Checks whether trusted profile photo host.
  bool _isTrustedProfilePhotoHost(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized == 'firebasestorage.googleapis.com' ||
        normalized == 'storage.googleapis.com' ||
        normalized.endsWith('.firebasestorage.app') ||
        normalized.endsWith('.appspot.com');
  }

  /// Checks whether there is supported image signature.
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

// AppViewModel publishes session changes to the app shell and coordinates authentication changes
// with home-screen safety widgets.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../Data/session_repository.dart';
import '../../home/Data/home_screen_widget_service.dart';
import '../Model/app_session.dart';

/// Coordinates app view model state and actions.
class AppViewModel extends ChangeNotifier {
  /// Creates app view model.
  AppViewModel({
    required SessionRepository sessionRepository,
    FirebaseAuth? firebaseAuth,
    bool firebaseAvailable = true,
  }) : _sessionRepository = sessionRepository,
       _firebaseAuth = firebaseAvailable
           ? (firebaseAuth ?? FirebaseAuth.instance)
           : null {
    _sessionSubscription = _sessionRepository.changes.listen((_) {
      if (!_isDisposed && !_isInitializing) notifyListeners();
    });
    final auth = _firebaseAuth;
    _hasObservedAuthenticatedFirebaseUser = auth?.currentUser != null;
    _firebaseAuthSubscription = auth?.authStateChanges().listen(
      _handleFirebaseAuthChanged,
      onError: (Object error, StackTrace stackTrace) {
        // A transient auth-stream failure should not crash or erase the
        // locally recoverable mobile session.
      },
    );
  }

  final SessionRepository _sessionRepository;
  final FirebaseAuth? _firebaseAuth;
  StreamSubscription<User?>? _firebaseAuthSubscription;
  StreamSubscription<AppSession?>? _sessionSubscription;
  bool _isInitializing = true;
  bool _hasObservedAuthenticatedFirebaseUser = false;
  bool _isDisposed = false;

  /// Returns session.
  AppSession? get session => _sessionRepository.currentSession;

  /// Returns is signed in.
  bool get isSignedIn => _sessionRepository.isSignedIn;

  /// Returns security message.
  String? get securityMessage => _sessionRepository.securityMessage;

  /// Computes acknowledge security message.
  void acknowledgeSecurityMessage() {
    _sessionRepository.securityMessage = null;
  }

  /// Returns is initializing.
  bool get isInitializing => _isInitializing;

  /// Computes initialize.
  Future<void> initialize() async {
    await _sessionRepository.loadSavedSession();
    if (!_sessionRepository.isSignedIn) {
      await HomeScreenWidgetService.shared.clear();
    }
    if (_isDisposed) return;
    if (_sessionRepository.isSignedIn) {
      HomeScreenWidgetService.shared.activate();
    }
    _isInitializing = false;
    notifyListeners();
  }

  /// Computes complete sign in.
  Future<void> completeSignIn(AppSession session) async {
    await HomeScreenWidgetService.shared.clear();
    await _sessionRepository.signIn(session);
    HomeScreenWidgetService.shared.activate();
    if (_isDisposed) return;
    notifyListeners();
  }

  /// Computes complete onboarding.
  Future<void> completeOnboarding() async {
    await _sessionRepository.refreshCurrentSession();
    if (_isDisposed) return;
    notifyListeners();
  }

  /// Computes sign out.
  void signOut() {
    unawaited(HomeScreenWidgetService.shared.clear());
    unawaited(_sessionRepository.signOut());
    if (_isDisposed) return;
    notifyListeners();
  }

  /// Handles firebase auth changed.
  void _handleFirebaseAuthChanged(User? user) {
    if (_isDisposed) return;
    if (user != null) {
      _hasObservedAuthenticatedFirebaseUser = true;
      return;
    }
    if (_isInitializing ||
        !_hasObservedAuthenticatedFirebaseUser ||
        session == null) {
      return;
    }
    unawaited(HomeScreenWidgetService.shared.clear());
    unawaited(_sessionRepository.signOut());
    notifyListeners();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_sessionSubscription?.cancel());
    final subscription = _firebaseAuthSubscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}

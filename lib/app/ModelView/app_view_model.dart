import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../Data/session_repository.dart';
import '../../home/Data/home_screen_widget_service.dart';
import '../Model/app_session.dart';

class AppViewModel extends ChangeNotifier {
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

  AppSession? get session => _sessionRepository.currentSession;

  bool get isSignedIn => _sessionRepository.isSignedIn;
  bool get isInitializing => _isInitializing;

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

  Future<void> completeSignIn(AppSession session) async {
    await HomeScreenWidgetService.shared.clear();
    await _sessionRepository.signIn(session);
    HomeScreenWidgetService.shared.activate();
    if (_isDisposed) return;
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    await _sessionRepository.refreshCurrentSession();
    if (_isDisposed) return;
    notifyListeners();
  }

  void signOut() {
    unawaited(HomeScreenWidgetService.shared.clear());
    unawaited(_sessionRepository.signOut());
    if (_isDisposed) return;
    notifyListeners();
  }

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

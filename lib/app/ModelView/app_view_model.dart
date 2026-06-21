import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../Data/session_repository.dart';
import '../Model/app_session.dart';

class AppViewModel extends ChangeNotifier {
  AppViewModel({required SessionRepository sessionRepository})
    : _sessionRepository = sessionRepository {
    _firebaseAuthSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _handleFirebaseAuthChanged,
    );
  }

  final SessionRepository _sessionRepository;
  late final StreamSubscription<User?> _firebaseAuthSubscription;
  bool _isInitializing = true;
  bool _hasObservedAuthenticatedFirebaseUser =
      FirebaseAuth.instance.currentUser != null;

  AppSession? get session => _sessionRepository.currentSession;

  bool get isSignedIn => _sessionRepository.isSignedIn;
  bool get isInitializing => _isInitializing;

  Future<void> initialize() async {
    await _sessionRepository.loadSavedSession();
    _isInitializing = false;
    notifyListeners();
  }

  Future<void> completeSignIn(AppSession session) async {
    await _sessionRepository.signIn(session);
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    await _sessionRepository.refreshCurrentSession();
    notifyListeners();
  }

  void signOut() {
    _sessionRepository.signOut();
    notifyListeners();
  }

  void _handleFirebaseAuthChanged(User? user) {
    if (user != null) {
      _hasObservedAuthenticatedFirebaseUser = true;
      return;
    }
    if (_isInitializing ||
        !_hasObservedAuthenticatedFirebaseUser ||
        session == null) {
      return;
    }
    _sessionRepository.signOut();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_firebaseAuthSubscription.cancel());
    super.dispose();
  }
}

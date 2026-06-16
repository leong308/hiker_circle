import 'package:flutter/foundation.dart';

import '../Data/session_repository.dart';
import '../Model/app_session.dart';

class AppViewModel extends ChangeNotifier {
  AppViewModel({required SessionRepository sessionRepository})
    : _sessionRepository = sessionRepository;

  final SessionRepository _sessionRepository;
  bool _isInitializing = true;

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
}

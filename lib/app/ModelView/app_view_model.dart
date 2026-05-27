import 'package:flutter/foundation.dart';

import '../Data/session_repository.dart';
import '../Model/app_session.dart';

class AppViewModel extends ChangeNotifier {
  AppViewModel({required SessionRepository sessionRepository})
    : _sessionRepository = sessionRepository;

  final SessionRepository _sessionRepository;

  AppSession? get session => _sessionRepository.currentSession;

  bool get isSignedIn => _sessionRepository.isSignedIn;

  void completeSignIn(AppSession session) {
    _sessionRepository.signIn(session);
    notifyListeners();
  }

  void signOut() {
    _sessionRepository.signOut();
    notifyListeners();
  }
}

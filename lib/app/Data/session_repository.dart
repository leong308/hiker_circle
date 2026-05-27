import '../Model/app_session.dart';

class SessionRepository {
  AppSession? _session;

  AppSession? get currentSession => _session;

  bool get isSignedIn => _session != null;

  void signIn(AppSession session) {
    _session = session;
  }

  void signOut() {
    _session = null;
  }
}

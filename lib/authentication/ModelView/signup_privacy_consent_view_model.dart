part of '../signup_privacy_consent_feature.dart';

class _SignupPrivacyConsentViewModel extends ChangeNotifier {
  _SignupPrivacyConsentViewModel(this.repository, this.owner);

  final PrivacyConsentRepository repository;
  final String owner;
  bool loading = true;
  bool accepted = false;
  bool checked = false;
  bool saving = false;
  bool loadFailed = false;
  bool saveFailed = false;
  bool _disposed = false;

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    loadFailed = false;
    _publish();
    try {
      final saved = await repository.load(owner);
      if (_disposed) return;
      accepted = saved != null;
    } catch (_) {
      loadFailed = true;
    } finally {
      loading = false;
      _publish();
    }
  }

  void setChecked(bool value) {
    if (saving) return;
    checked = value;
    _publish();
  }

  Future<void> accept() async {
    if (!checked || saving || accepted || loadFailed) return;
    saving = true;
    saveFailed = false;
    _publish();
    try {
      await repository.accept(owner, languageCode: 'en');
      if (_disposed) return;
      accepted = true;
    } catch (_) {
      saveFailed = true;
    } finally {
      saving = false;
      _publish();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

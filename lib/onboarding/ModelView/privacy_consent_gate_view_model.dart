part of '../privacy_consent_gate_feature.dart';

class _PrivacyConsentGateViewModel extends ChangeNotifier {
  _PrivacyConsentGateViewModel(this.repository, this.owner);

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
      if (accepted) _upload();
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
      _upload();
    } catch (_) {
      saveFailed = true;
    } finally {
      saving = false;
      _publish();
    }
  }

  void _upload() {
    // The local action is authoritative for continuing. Reconnect recovery
    // also drains this account's receipt if this network attempt fails.
    unawaited(repository.flush(owner).catchError((Object _) {}));
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

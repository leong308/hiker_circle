part of '../recent_security_verification_page_feature.dart';

/// Owns the state and non-visual actions of RecentSecurityVerificationPage.
class _RecentSecurityVerificationPageStateViewModel extends ChangeNotifier {
  /// Creates recent security verification page state view model.
  _RecentSecurityVerificationPageStateViewModel({
    required this.readPhoneNumber,
  });
  final String Function() readPhoneNumber;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late final AuthViewModel stateViewModel;

  String? stateError;

  /// Refreshes.
  void commandRefresh() {
    if (mounted) _publish(() {});
  }

  /// Sends code.
  Future<void> commandSendCode() async {
    if (!mounted || stateViewModel.isBusy) return;
    _publish(() => stateError = null);
    await stateViewModel.sendCode(
      readPhoneNumber(),
      authenticatedReverification: true,
    );
  }

  /// Returns command masked phone.
  String get commandMaskedPhone {
    final value = readPhoneNumber();
    if (value.length <= 6) return value;
    return '${value.substring(0, 4)} •••• ${value.substring(value.length - 3)}';
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

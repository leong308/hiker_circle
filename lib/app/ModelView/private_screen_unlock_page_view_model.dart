part of '../private_screen_unlock_page_feature.dart';

/// Owns the state and non-visual actions of PrivateScreenUnlockPage.
class _PrivateScreenUnlockPageStateViewModel extends ChangeNotifier {
  /// Creates private screen unlock page state view model.
  _PrivateScreenUnlockPageStateViewModel({required this.readOnUnlocked});
  final VoidCallback Function() readOnUnlocked;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  bool stateBusy = false;

  bool stateFailed = false;

  /// Computes unlock.
  Future<void> commandUnlock() async {
    if (stateBusy) return;
    _publish(() => stateBusy = true);
    final ok = await PrivateScreenUnlock.authenticate();
    if (!mounted) return;
    _publish(() {
      stateBusy = false;
      stateFailed = !ok;
    });
    if (ok) readOnUnlocked()();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

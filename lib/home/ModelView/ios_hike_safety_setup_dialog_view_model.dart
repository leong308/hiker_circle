part of '../ios_hike_safety_setup_dialog_feature.dart';

/// Owns the state and non-visual actions of _IosHikeSafetySetupDialog.
class _IosHikeSafetySetupDialogStateViewModel extends ChangeNotifier {
  /// Creates ios hike safety setup dialog state view model.
  _IosHikeSafetySetupDialogStateViewModel({required this.readService});
  final ActiveHikeLiveStatusService Function() readService;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  bool stateChecking = false;

  bool stateOpeningSettings = false;

  bool stateFinished = false;

  String? stateError;

  /// Opens settings.
  Future<void> commandOpenSettings() async {
    if (stateOpeningSettings || stateChecking || stateFinished) return;
    _publish(() {
      stateOpeningSettings = true;
      stateError = null;
    });
    try {
      await readService().openIosSafetySettings().timeout(
        const Duration(seconds: 10),
      );
      // Opening Settings is not permission approval. Leave the dialog and its
      // caller's prepared draft in place until the resume check confirms it.
    } catch (_) {
      if (mounted && !stateFinished) {
        _publish(
          () => stateError = 'Settings could not open. Please try again.',
        );
      }
    } finally {
      if (mounted && !stateFinished) {
        _publish(() => stateOpeningSettings = false);
      }
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

part of '../hiker_circle_app_feature.dart';

/// Owns the state and non-visual actions of HikerCircleApp.
class _HikerCircleAppStateViewModel extends ChangeNotifier {
  /// Creates hiker circle app state view model.
  _HikerCircleAppStateViewModel();

  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late final AppViewModel stateAppViewModel;

  final AppSettingsController stateSettingsController =
      AppSettingsController.instance;

  bool stateCheckingLaunchLock = true;

  bool stateLaunchLocked = false;

  /// Computes initialize launch.
  Future<void> commandInitializeLaunch() async {
    await stateAppViewModel.initialize();
    await stateSettingsController.ready;
    final session = stateAppViewModel.session;
    var lock = false;
    if (session != null && stateSettingsController.privateScreenUnlockEnabled) {
      // Decide exactly once on a terminated-to-foreground launch. No resume hook.
      final active = await LocalSessionDatabase().loadActiveHikeSession(
        phoneNumber: session.phoneNumber,
      );
      lock = active == null;
    }
    if (mounted) {
      _publish(() {
        stateLaunchLocked = lock;
        stateCheckingLaunchLock = false;
      });
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

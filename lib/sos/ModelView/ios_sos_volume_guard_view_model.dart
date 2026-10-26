part of '../ios_sos_volume_guard_feature.dart';

/// Owns the state and non-visual actions of _IosSosVolumeGuardDialog.
class _IosSosVolumeGuardDialogStateViewModel extends ChangeNotifier {
  /// Creates ios sos volume guard dialog state view model.
  _IosSosVolumeGuardDialogStateViewModel({
    required this.readDeviceAlertService,
  });
  final SosDeviceAlertService Function() readDeviceAlertService;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late SosOutputVolumeStatus stateStatus;

  bool stateIsRefreshing = false;

  /// Prepares volume monitoring.
  Future<void> commandPrepareVolumeMonitoring() async {
    await readDeviceAlertService().beginOutputVolumeMonitoring();
    await commandRefreshStatus();
  }

  /// Refreshes status.
  Future<void> commandRefreshStatus() async {
    if (stateIsRefreshing) {
      return;
    }

    stateIsRefreshing = true;
    try {
      final nextStatus = await readDeviceAlertService().getOutputVolumeStatus(
        minimumRequiredVolume: stateStatus.minimumRequiredVolume,
      );
      if (mounted) {
        _publish(() {
          stateStatus = nextStatus;
        });
      }
    } catch (_) {
      // Keep the last known value; the next poll/resume refresh will retry.
    } finally {
      stateIsRefreshing = false;
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

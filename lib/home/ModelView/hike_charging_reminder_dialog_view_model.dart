part of '../hike_charging_reminder_dialog_feature.dart';

/// Owns the state and non-visual actions of HikeChargingReminderDialog.
class _HikeChargingReminderDialogStateViewModel extends ChangeNotifier {
  /// Creates hike charging reminder dialog state view model.
  _HikeChargingReminderDialogStateViewModel({
    required this.readLoadBatteryLevel,
  });
  final Future<int?> Function() Function() readLoadBatteryLevel;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  int? stateBatteryLevel;

  bool stateLoading = false;

  bool stateRefreshAgain = false;

  /// Refreshes battery.
  Future<void> commandRefreshBattery() async {
    if (!mounted) return;
    if (stateLoading) {
      stateRefreshAgain = true;
      return;
    }
    _publish(() => stateLoading = true);
    do {
      stateRefreshAgain = false;
      int? level;
      try {
        final value = await readLoadBatteryLevel()().timeout(
          const Duration(seconds: 5),
        );
        if (value != null && value >= 0 && value <= 100) level = value;
      } catch (_) {
        // Battery access is optional; keep the charging reminder usable.
      }
      if (!mounted) return;
      _publish(() => stateBatteryLevel = level);
    } while (stateRefreshAgain);
    if (mounted) _publish(() => stateLoading = false);
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

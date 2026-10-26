part of '../hike_hazard_alert_host_feature.dart';

/// Owns the state and non-visual actions of _NotificationHazardDialog.
class _NotificationHazardDialogStateViewModel extends ChangeNotifier {
  /// Creates notification hazard dialog state view model.
  _NotificationHazardDialogStateViewModel({required this.readLoadAlerts});
  final Future<List<TrailHazardAlert>> Function() Function() readLoadAlerts;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  List<TrailHazardAlert>? stateAlerts;

  bool stateFailed = false;

  bool stateLoading = false;

  /// Loads.
  Future<void> commandLoad() async {
    if (stateLoading) return;
    _publish(() {
      stateLoading = true;
      stateFailed = false;
    });
    try {
      final alerts = await readLoadAlerts()();
      if (mounted) {
        _publish(
          () => stateAlerts = alerts
              .where((alert) => alert.active(DateTime.now()))
              .toList(),
        );
      }
    } catch (_) {
      if (mounted) _publish(() => stateFailed = true);
    } finally {
      if (mounted) _publish(() => stateLoading = false);
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

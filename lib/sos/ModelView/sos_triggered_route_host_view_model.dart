part of '../sos_triggered_route_host_feature.dart';

/// Owns the state and non-visual actions of SosTriggeredRouteHost.
class _SosTriggeredRouteHostStateViewModel extends ChangeNotifier {
  /// Creates sos triggered route host state view model.
  _SosTriggeredRouteHostStateViewModel({
    required this.effectScheduleSync,
    required this.effectSyncPresentation,
  });
  final void Function() effectScheduleSync;
  final void Function() effectSyncPresentation;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Computes on presentation changed.
  void commandOnPresentationChanged() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      effectScheduleSync();
    } else {
      effectSyncPresentation();
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

part of '../checkpoint_flow_feature.dart';

/// Owns the state and non-visual actions of CheckpointFlow.
class _CheckpointFlowStateViewModel extends ChangeNotifier {
  /// Creates checkpoint flow state view model.
  _CheckpointFlowStateViewModel({
    required this.readCheckpoints,
    required this.readOnShowOnMap,
    required this.readPlayback,
    required this.effectScheduleFollow,
  });
  final List<TrailCheckpoint> Function() readCheckpoints;
  final ValueChanged<int> Function() readOnShowOnMap;
  final ValueListenable<RouteCheckpointProgress>? Function() readPlayback;
  final void Function() effectScheduleFollow;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  bool stateFollowing = true;

  /// Returns command progress.
  RouteCheckpointProgress get commandProgress =>
      readPlayback()?.value ?? const RouteCheckpointProgress();

  /// Returns command order.
  List<int> get commandOrder =>
      List.generate(readCheckpoints().length, (i) => i)..sort(
        (a, b) =>
            readCheckpoints()[a].order.compareTo(readCheckpoints()[b].order),
      );

  /// Computes on playback.
  void commandOnPlayback() {
    if (!mounted) return;
    _publish(() {});
    effectScheduleFollow();
  }

  /// Selects.
  void commandSelect(int index) {
    _publish(() => stateFollowing = false);
    readOnShowOnMap()(index);
  }

  /// Computes distance label.
  String commandDistanceLabel(double meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(2)} km';

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

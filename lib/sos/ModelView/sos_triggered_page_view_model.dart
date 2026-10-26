part of '../sos_triggered_page_feature.dart';

/// Owns the state and non-visual actions of _SlideToEndSos.
class _SlideToEndSosStateViewModel extends ChangeNotifier {
  /// Creates slide to end sos state view model.
  _SlideToEndSosStateViewModel({
    required this.readBusy,
    required this.readOnConfirmed,
  });
  final bool Function() readBusy;
  final Future<void> Function() Function() readOnConfirmed;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  double stateProgress = 0;

  bool stateDragging = false;

  /// Computes confirm.
  void commandConfirm() {
    if (readBusy()) return;
    _publish(() {
      stateProgress = 1;
      stateDragging = false;
    });
    readOnConfirmed()();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

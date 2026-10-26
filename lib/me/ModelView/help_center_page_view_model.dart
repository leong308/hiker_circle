part of '../help_center_page_feature.dart';

/// Coordinates guided help page state view model state and actions.
class _GuidedHelpPageStateViewModel extends ChangeNotifier {
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late final Future<void> Function(int? initialPage)
  effectPresentOpenGuideEffect1;

  bool stateGuideOpen = false;

  int stateResumePage = 0;

  /// Opens guide.
  Future<void> commandOpenGuide([int? initialPage]) async {
    if (stateGuideOpen) return;
    stateGuideOpen = true;
    stateResumePage = initialPage ?? stateResumePage;
    try {
      await effectPresentOpenGuideEffect1(initialPage);
    } finally {
      stateGuideOpen = false;
      if (mounted) _publish(() {});
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Coordinates hike basics page state view model state and actions.
class _HikeBasicsPageStateViewModel extends ChangeNotifier {
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late final Future<String?> Function() effectPresentChooseCategoryEffect1;

  String stateCategory = 'All';

  /// Computes choose category.
  Future<void> commandChooseCategory() async {
    final selected = await effectPresentChooseCategoryEffect1();
    if (selected != null && mounted) _publish(() => stateCategory = selected);
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

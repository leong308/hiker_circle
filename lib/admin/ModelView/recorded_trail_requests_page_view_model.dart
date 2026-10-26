part of '../recorded_trail_requests_page_feature.dart';

/// Owns the state and non-visual actions of RecordedTrailRequestsPage.
class _RecordedTrailRequestsPageStateViewModel extends ChangeNotifier {
  /// Creates recorded trail requests page state view model.
  _RecordedTrailRequestsPageStateViewModel({
    required this.readRepository,
    required this.readSession,
  });
  final HikerCircleFirebaseRepository Function() readRepository;
  final AppSession Function() readSession;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  List<Map<String, dynamic>>? stateRows;

  String? stateError;

  /// Loads.
  Future<void> commandLoad() async {
    _publish(() => stateError = null);
    try {
      final data = await readRepository().loadAdminTrailRequests(
        session: readSession(),
      );
      if (mounted) {
        _publish(() => stateRows = data);
      }
    } catch (e) {
      if (mounted) {
        _publish(
          () => stateError = 'Trail requests could not load. Refresh to retry.',
        );
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

/// Owns the state and non-visual actions of _RecordedTrailReviewPage.
class _RecordedTrailReviewPageStateViewModel extends ChangeNotifier {
  /// Creates recorded trail review page state view model.
  _RecordedTrailReviewPageStateViewModel({
    required this.readRepository,
    required this.effectChooseDuplicateAction,
  });
  final HikerCircleFirebaseRepository Function() readRepository;
  final Future<void> Function() effectChooseDuplicateAction;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  List<HikeCoordinate>? statePoints;

  String? stateError;

  bool stateSaving = false, stateVerified = false;

  bool stateCheckingDuplicate = false,
      stateReviewAllowed = false,
      stateDuplicateDialogOpen = false;

  TrailDuplicateMatch? stateDuplicateMatch;

  /// Checks duplicate.
  Future<void> commandCheckDuplicate() async {
    if (statePoints == null || stateSaving || stateCheckingDuplicate) return;
    _publish(() {
      stateCheckingDuplicate = true;
      stateReviewAllowed = false;
      stateError = null;
    });
    try {
      final match = await TrailDuplicateChecker(readRepository().localDatabase)
          .check([
            for (final p in statePoints!)
              (latitude: p.latitude, longitude: p.longitude),
          ]);
      if (!mounted) return;
      _publish(() {
        stateDuplicateMatch = match;
        stateCheckingDuplicate = false;
        stateReviewAllowed = match == null;
      });
      if (match != null) await effectChooseDuplicateAction();
    } catch (_) {
      if (mounted) {
        _publish(() {
          stateCheckingDuplicate = false;
          stateError =
              'Saved trails could not be checked. Retry the duplicate check before reviewing.';
        });
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

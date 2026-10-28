part of '../final_preparation_review_page_feature.dart';

/// Owns the state and non-visual actions of FinalPreparationReviewPage.
class _PreparationStateViewModel extends ChangeNotifier {
  /// Creates preparation state view model.
  _PreparationStateViewModel({
    required this.readHike,
    required this.readImmediate,
    required this.readIsHost,
    required this.readPrimaryActionLabel,
    required this.readCheckTrailheadOnStart,
  });
  final UpcomingHike Function() readHike;
  final bool Function() readImmediate;
  final bool Function() readIsHost;
  final String? Function() readPrimaryActionLabel;
  final bool Function() readCheckTrailheadOnStart;
  final _trailhead = TrailheadProximityViewModel();
  late final Future<TrailheadProximityAction?> Function(TrailheadProximity?)
  presentTrailheadWarning;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  bool stateBusy = false;

  bool stateStartRequested = false;

  String? stateError;

  bool stateAnalyzing = false;

  bool stateCheckingWeather = false;

  int statePendingGearSaves = 0;

  bool stateOpeningDetails = false, stateLoadingBattery = false;

  /// Returns command interaction busy.
  bool get commandInteractionBusy =>
      stateBusy || stateOpeningDetails || stateStartRequested;

  /// Returns command saving gear.
  bool get commandSavingGear => statePendingGearSaves > 0;

  /// Returns command checking conditions.
  bool get commandCheckingConditions => stateAnalyzing || stateCheckingWeather;

  /// Opens details.
  Future<void> commandOpenDetails(
    Future<void> Function() open, {
    Future<void> Function()? refresh,
  }) async {
    if (commandInteractionBusy) {
      return;
    }
    _publish(() {
      stateOpeningDetails = true;
      stateError = null;
    });
    try {
      await open();
      if (mounted) {
        await refresh?.call();
      }
    } catch (_) {
      if (mounted) {
        _publish(
          () => stateError = 'Could not open these details. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        _publish(() => stateOpeningDetails = false);
      }
    }
  }

  /// Computes time.
  String commandTime(DateTime date) {
    final d = date.toLocal();
    return '${d.day}/${d.month} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// Returns command start label.
  String get commandStartLabel =>
      readPrimaryActionLabel() ??
      (!readImmediate() && readHike().isLocalPendingSync
          ? 'Waiting for sync'
          : !readIsHost()
          ? 'Waiting for organizer'
          : readHike().participantCount > 1
          ? 'Start team readiness'
          : 'Start hike');

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    _trailhead.dispose();
    super.dispose();
  }

  late final Future<bool> Function(PlannedHike) Function() readOnStart;

  late final void Function(Route<String> route) effectPresentStartHikeEffect1;

  bool stateStartInFlight = false;

  bool stateCompletionDelivered = false;

  /// Checks a scheduled hike's trailhead distance before requesting its start.
  Future<void> commandStartHike(PlannedHike plan, Route<String> route) async {
    try {
      if (readCheckTrailheadOnStart() && !plan.trail.isUnlisted) {
        final accepted = await _trailhead.confirmContinue(
          plan.trail,
          refreshLocation: true,
          presentWarning: presentTrailheadWarning,
          onDirectionsUnavailable: () => _publish(
            () => stateError = 'Unable to open Waze. Please try again.',
          ),
        );
        if (!mounted) return;
        if (!accepted) {
          _publish(() {
            stateStartInFlight = false;
            stateStartRequested = false;
          });
          return;
        }
      }
      final started = await readOnStart()(plan);
      if (!mounted) return;
      if (started) {
        _publish(() => stateCompletionDelivered = true);
        effectPresentStartHikeEffect1(route);
        return;
      }
      _publish(() {
        stateStartInFlight = false;
        stateStartRequested = false;
        stateError = 'Your hike has not started. You can retry from here.';
      });
    } catch (_) {
      if (!mounted) return;
      _publish(() {
        stateStartInFlight = false;
        stateStartRequested = false;
        stateError =
            'Could not start the hike. Your preparation is kept; please try again.';
      });
    }
  }
}

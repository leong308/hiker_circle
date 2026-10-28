import '../../trail/Model/trail_hazard_alert.dart';
import '../../trail/Model/trail_hazard_assessment.dart';
import '../Model/active_trail_hazard_notice.dart';

/// Keeps notification popups tied to the current hike and freshly loaded report.
class ActiveTrailHazardAlertCoordinator {
  /// Receives app state and presentation boundaries without owning navigation or tracking.
  ActiveTrailHazardAlertCoordinator({
    required this.readCurrent,
    required this.load,
    required this.present,
  });

  final ({String sessionId, String trailId})? Function() readCurrent;
  final Future<TrailHazardAssessment> Function(String trailId) load;
  final Future<void> Function(
    Future<List<TrailHazardAlert>> Function() loadAlerts,
  )
  present;
  final _opening = <String>{};
  bool _disposed = false;

  /// Rejects notifications for ended hikes, another session or another trail.
  bool _matches(ActiveTrailHazardNotice notice) {
    final current = readCurrent();
    return !_disposed &&
        current?.sessionId == notice.sessionId &&
        current?.trailId == notice.trailId;
  }

  /// Uses the existing loading/retry dialog, then shows only the requested active report.
  Future<void> open(Uri uri) async {
    final notice = ActiveTrailHazardNotice.fromUri(uri);
    if (notice == null || !_matches(notice) || !_opening.add(notice.key)) {
      return;
    }
    try {
      await present(() async {
        if (!_matches(notice)) return const [];
        final assessment = await load(notice.trailId);
        if (!_matches(notice)) return const [];
        if (!assessment.isFresh) {
          throw StateError('Current report status is unavailable.');
        }
        return assessment.alerts
            .where(
              (alert) =>
                  alert.id == notice.hazardId &&
                  alert.trailId == notice.trailId &&
                  alert.active(DateTime.now()),
            )
            .toList();
      });
    } finally {
      _opening.remove(notice.key);
    }
  }

  /// Stops late reads from presenting report data after the home session closes.
  void dispose() {
    _disposed = true;
    _opening.clear();
  }
}

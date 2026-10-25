import '../../trail/Model/trail_hazard_alert.dart';
import '../../trail/Model/trail_hazard_assessment.dart';
import '../../trail/View/trail_hazard_alert_dialog.dart';

enum UnavailableHazardAction { retry, proceed, abort }

/// One start attempt may check again at READY and after a team countdown.
/// Acknowledgements belong to this attempt; a new report/cycle still interrupts.
class TrailHazardStartGate {
  TrailHazardStartGate({
    required this.load,
    required this.confirm,
    required this.confirmUnavailable,
  });

  final Future<TrailHazardAssessment> Function(String trailId) load;
  final Future<TrailHazardAlertAction> Function(List<TrailHazardAlert>) confirm;
  final Future<UnavailableHazardAction> Function() confirmUnavailable;
  final Set<String> _acknowledged = {};
  bool _acceptedUnavailable = false;
  String? fatalHazardId;

  Future<TrailHazardAlertAction> check(String trailId) async {
    while (true) {
      final assessment = await load(trailId);
      fatalHazardId = assessment.alerts
          .where(
            (alert) =>
                alert.trailId == trailId &&
                alert.isFatal &&
                alert.active(DateTime.now()),
          )
          .map((alert) => alert.id)
          .firstOrNull;
      final pending = assessment.alerts
          .where(
            (alert) =>
                alert.trailId == trailId &&
                alert.active(DateTime.now()) &&
                !_acknowledged.contains(alert.fingerprint),
          )
          .toList();
      if (pending.isNotEmpty) {
        final action = await confirm(pending);
        if (action != TrailHazardAlertAction.proceed &&
            action != TrailHazardAlertAction.acknowledge) {
          return action;
        }
        _acknowledged.addAll(pending.map((alert) => alert.fingerprint));
      }
      if (assessment.isFresh || _acceptedUnavailable) {
        return TrailHazardAlertAction.proceed;
      }
      switch (await confirmUnavailable()) {
        case UnavailableHazardAction.retry:
          continue;
        case UnavailableHazardAction.proceed:
          _acceptedUnavailable = true;
          return TrailHazardAlertAction.proceed;
        case UnavailableHazardAction.abort:
          return TrailHazardAlertAction.abort;
      }
    }
  }
}

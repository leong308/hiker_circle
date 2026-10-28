import 'dart:async';
import '../../sos/Model/sos_models.dart';
import '../Model/hike_session_models.dart';
import '../Model/team_hike_identity.dart';

/// Records the current hiker's own preparation fixes without starting an active hike.
class TeamReadinessLocationViewModel {
  /// Accepts authenticated persistence and foreground/session readers for isolated testing.
  TeamReadinessLocationViewModel({
    required this.readTeam,
    required this.phoneNumber,
    required this.isForeground,
    required this.capture,
    required this.record,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final TeamHikeSession Function() readTeam;
  final String phoneNumber;
  final bool Function() isForeground;
  final Future<SosTriggerLocation?> Function() capture;
  final Future<void> Function(SosTriggerLocation) record;
  final DateTime Function() _clock;
  Timer? _timer;
  bool _disposed = false, _pending = false;
  DateTime? _lastSent;

  /// Polls only while the readiness flow is visible and the caller has joined.
  void start() {
    _timer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  /// Rejects missing, stale and inaccurate fixes rather than substituting the planned trailhead.
  Future<void> refresh() async {
    if (_disposed || _pending || !isForeground()) return;
    final team = readTeam();
    if (!const {
      TeamHikePhase.inviting,
      TeamHikePhase.readyCheck,
      TeamHikePhase.countdown,
    }.contains(team.phase)) {
      return;
    }
    final participant = team.participants
        .where(
          (p) =>
              TeamHikeIdentity.key(p.phoneNumber) ==
              TeamHikeIdentity.key(phoneNumber),
        )
        .firstOrNull;
    if (participant == null ||
        !const {
          TeamHikeParticipantStatus.joined,
          TeamHikeParticipantStatus.ready,
        }.contains(participant.status)) {
      return;
    }
    _pending = true;
    try {
      final fix = await capture().timeout(const Duration(seconds: 5));
      if (_disposed ||
          !isForeground() ||
          readTeam().id != team.id ||
          readTeam().phase == TeamHikePhase.active ||
          readTeam().phase == TeamHikePhase.completed) {
        return;
      }
      final time = fix?.capturedAt, accuracy = fix?.accuracyMeters;
      if (fix?.hasValidPosition != true ||
          time == null ||
          accuracy == null ||
          !accuracy.isFinite ||
          accuracy < 0 ||
          accuracy > 250) {
        return;
      }
      final age = _clock().toUtc().difference(time.toUtc());
      if (age < const Duration(seconds: -10) ||
          age > const Duration(minutes: 2) ||
          _lastSent != null && !time.isAfter(_lastSent!)) {
        return;
      }
      await record(fix!);
      if (!_disposed) _lastSent = time;
    } catch (_) {
      // Existing shared fixes remain visible when permissions, GPS or connectivity are unavailable.
    } finally {
      _pending = false;
    }
  }

  /// Stops foreground sampling without touching SOS or active-hike recording.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}

/// Selects real recorded team points and provides honest freshness labels for their legend.
abstract final class TeamReadinessLocations {
  /// Keeps valid last-known fixes even when they are old, with age shown separately.
  static List<TeamHikeParticipant> located(
    TeamHikeSession team, {
    DateTime? now,
  }) {
    final limit = (now ?? DateTime.now()).toUtc().add(
      const Duration(seconds: 10),
    );
    return team.participants
        .where(
          (p) =>
              p.status != TeamHikeParticipantStatus.ended &&
              p.latestLocation?.hasValidPosition == true &&
              p.effectiveLocationUpdatedAt != null &&
              !p.effectiveLocationUpdatedAt!.toUtc().isAfter(limit),
        )
        .toList();
  }

  /// Formats the capture age without claiming that an older record is a current live fix.
  static String label(TeamHikeParticipant participant, DateTime now) {
    if (participant.status == TeamHikeParticipantStatus.ended) {
      return 'Not participating';
    }
    if (participant.latestLocation?.hasValidPosition != true ||
        participant.effectiveLocationUpdatedAt == null) {
      return 'No recorded location';
    }
    final age = now.toUtc().difference(
      participant.effectiveLocationUpdatedAt!.toUtc(),
    );
    if (age < const Duration(seconds: -10)) return 'Recorded time unavailable';
    final seconds = age.inSeconds.clamp(0, 315360000);
    if (seconds < 60) return 'Recorded just now';
    if (seconds < 3600) return 'Recorded ${seconds ~/ 60} min ago';
    if (seconds < 86400) return 'Recorded ${seconds ~/ 3600} hr ago';
    return 'Recorded ${seconds ~/ 86400} days ago';
  }
}

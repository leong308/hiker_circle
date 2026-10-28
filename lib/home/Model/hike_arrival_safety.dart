import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';

import '../../trail/Model/trail_models.dart';
import 'hike_session_models.dart';

/// A stored summit or trail end, with intermediate gates that protect loop trailheads.
class HikeArrivalTarget {
  /// Creates a destination from the saved hike plan.
  const HikeArrivalTarget({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.requiresGate,
    required this.gates,
  });
  final String id, name;
  final double latitude, longitude;
  final bool requiresGate;
  final List<TrailCheckpoint> gates;

  /// Serializes the same geographic contract used by the native and cloud checks.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'requiresGate': requiresGate,
    'gates': gates
        .map((gate) => {'latitude': gate.latitude, 'longitude': gate.longitude})
        .toList(),
  };
}

/// Owns arrival evidence independently of notification, navigation and contact delivery.
class HikeArrivalPlan {
  /// Creates the immutable plan for one physical hike and latest-arrival deadline.
  const HikeArrivalPlan({
    required this.targets,
    required this.startedAtMillis,
    required this.latestArrivalAtMillis,
  });
  static const radiusMeters = 100.0;
  static const maximumAccuracyMeters = 100.0;
  static const responseWindow = Duration(minutes: 5);
  final List<HikeArrivalTarget> targets;
  final int startedAtMillis, latestArrivalAtMillis;

  /// Uses the same event identity as the server without trusting a notification's display text.
  String eventId(String sessionId) =>
      eventForSession(sessionId, latestArrivalAtMillis);

  /// Restores an event identity from a native-only pending hike record.
  static String eventForSession(String sessionId, int latestArrivalAtMillis) =>
      sha256
          .convert(utf8.encode('$sessionId:$latestArrivalAtMillis'))
          .toString();

  /// Keeps local acknowledgements intact when an offline session receives its cloud ID.
  String trackingKey(String owner) => sha256
      .convert(utf8.encode('$owner:$startedAtMillis:$latestArrivalAtMillis'))
      .toString();

  /// Finds explicitly named peaks and the final saved checkpoint; location-only hikes have no destination.
  static HikeArrivalPlan? fromHike(ActiveHikeSession hike) {
    if (hike.trail.isUnlisted) return null;
    var checkpoints = [...hike.draft.effectiveCheckpoints]
      ..sort((a, b) => a.order.compareTo(b.order));
    if (checkpoints.length < 2) {
      final points = _geometry(hike.trail);
      if (points.length < 2) return null;
      checkpoints = [points.first, points[points.length ~/ 2], points.last]
          .asMap()
          .entries
          .map(
            (entry) => TrailCheckpoint(
              name: entry.key == 2 ? 'Trail end' : '',
              latitude: entry.value.$1,
              longitude: entry.value.$2,
              order: entry.key,
            ),
          )
          .toList();
    }
    final start = checkpoints.first;
    final candidates = [
      ...checkpoints
          .skip(1)
          .where(
            (point) => RegExp(
              r'\b(peak|summit|puncak)\b',
              caseSensitive: false,
            ).hasMatch(point.name),
          ),
      checkpoints.last,
    ];
    final targets = <HikeArrivalTarget>[];
    for (final point in candidates) {
      final id =
          '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}';
      if (targets.any((target) => target.id == id)) continue;
      final gated =
          _distance(
            start.latitude,
            start.longitude,
            point.latitude,
            point.longitude,
          ) <=
          radiusMeters * 2;
      targets.add(
        HikeArrivalTarget(
          id: id,
          name: point.name.isEmpty ? 'Trail end' : point.name,
          latitude: point.latitude,
          longitude: point.longitude,
          requiresGate: gated,
          gates: gated
              ? checkpoints
                    .sublist(1, checkpoints.length - 1)
                    .where(
                      (gate) =>
                          _distance(
                            gate.latitude,
                            gate.longitude,
                            point.latitude,
                            point.longitude,
                          ) >
                          radiusMeters * 2,
                    )
                    .toList()
              : const [],
        ),
      );
    }
    return HikeArrivalPlan(
      targets: targets,
      startedAtMillis: hike.startedAt.millisecondsSinceEpoch,
      latestArrivalAtMillis:
          hike.draft.expectedReturnTime.millisecondsSinceEpoch,
    );
  }

  /// Advances chronological footprint evidence while retaining previously visited loop gates.
  Map<String, dynamic> advance(
    Iterable<HikeCoordinate> samples,
    Map<String, dynamic> previous,
    DateTime now,
  ) {
    if (previous['arrivedAtMillis'] is num) return previous;
    final gates = Map<String, dynamic>.from(
      previous['passedGates'] as Map? ?? const {},
    );
    final ordered = samples.where((point) => point.hasValidPosition).toList()
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    for (final sample in ordered) {
      final time = sample.capturedAt.millisecondsSinceEpoch;
      final accuracy = sample.accuracyMeters;
      if (time < startedAtMillis ||
          time > now.millisecondsSinceEpoch + 10000 ||
          accuracy == null ||
          !accuracy.isFinite ||
          accuracy < 0 ||
          accuracy > maximumAccuracyMeters) {
        continue;
      }
      for (final target in targets) {
        if (target.requiresGate &&
            gates[target.id] == null &&
            target.gates.any(
              (gate) =>
                  _distance(
                    gate.latitude,
                    gate.longitude,
                    sample.latitude,
                    sample.longitude,
                  ) <=
                  radiusMeters,
            )) {
          gates[target.id] = time;
        }
        final gateAt = gates[target.id];
        if ((!target.requiresGate ||
                gateAt is num && gateAt >= startedAtMillis && gateAt < time) &&
            _distance(
                  target.latitude,
                  target.longitude,
                  sample.latitude,
                  sample.longitude,
                ) <=
                radiusMeters) {
          return {
            'passedGates': gates,
            'arrivedAtMillis': time,
            'targetId': target.id,
            'targetName': target.name,
          };
        }
      }
    }
    return {'passedGates': gates};
  }

  /// Sends bounded destinations rather than the entire route history through a platform channel.
  Map<String, dynamic> toJson() => {
    'targets': targets.map((target) => target.toJson()).toList(),
    'startedAtMillis': startedAtMillis,
    'latestArrivalAtMillis': latestArrivalAtMillis,
    'radiusMeters': radiusMeters,
    'maximumAccuracyMeters': maximumAccuracyMeters,
  };

  /// Measures the same spherical radius as the backend.
  static double _distance(double latA, double lngA, double latB, double lngB) {
    final lat = (latB - latA) * math.pi / 180,
        lng = (lngB - lngA) * math.pi / 180;
    final h =
        math.pow(math.sin(lat / 2), 2) +
        math.cos(latA * math.pi / 180) *
            math.cos(latB * math.pi / 180) *
            math.pow(math.sin(lng / 2), 2);
    return 6371000 *
        2 *
        math.atan2(math.sqrt(h), math.sqrt(math.max(0, 1 - h)));
  }

  /// Decodes either saved polyline precision and selects the geometry nearest the stored trailhead.
  static List<(double, double)> _geometry(Trail trail) {
    final encoded = trail.routeEncodedPolyline ?? '';
    if (encoded.isEmpty || encoded.length > 650000) return const [];
    final candidates = <List<(double, double)>>[];
    for (final precision in [5, 6]) {
      try {
        var offset = 0, lat = 0, lng = 0;
        final points = <(double, double)>[];

        /// Reject malformed, truncated or oversized encoded deltas.
        int delta() {
          var value = 0, shift = 0, byte = 0;
          do {
            if (offset >= encoded.length || shift >= 30) {
              throw const FormatException('Invalid route');
            }
            byte = encoded.codeUnitAt(offset++) - 63;
            if (byte < 0 || byte > 63) {
              throw const FormatException('Invalid route');
            }
            value |= (byte & 31) << shift;
            shift += 5;
          } while (byte >= 32);
          return value.isOdd ? ~(value >> 1) : value >> 1;
        }

        while (offset < encoded.length) {
          lat += delta();
          lng += delta();
          final point = (
            lat / math.pow(10, precision),
            lng / math.pow(10, precision),
          );
          if (point.$1.abs() > 90 ||
              point.$2.abs() > 180 ||
              points.length >= 100000) {
            throw const FormatException('Invalid route');
          }
          points.add(point);
        }
        if (points.length >= 2) candidates.add(points);
      } on FormatException {
        /* Another saved precision may still be valid. */
      }
    }
    candidates.sort(
      (a, b) =>
          ((a.first.$1 - trail.latitude).abs() +
                  (a.first.$2 - trail.longitude).abs())
              .compareTo(
                (b.first.$1 - trail.latitude).abs() +
                    (b.first.$2 - trail.longitude).abs(),
              ),
    );
    return candidates.firstOrNull ?? const [];
  }
}

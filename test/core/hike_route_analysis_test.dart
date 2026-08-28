import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/models/hike_route_analysis.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';

void main() {
  test('matches checkpoints in route order and calculates segment pace', () {
    final start = DateTime.utc(2026, 8, 20, 1);
    final analysis = analyzeHikeRoute(
      fallbackStartedAt: start,
      routePoints: [
        HikeCoordinate(
          latitude: 3,
          longitude: 101,
          capturedAt: start,
        ),
        HikeCoordinate(
          latitude: 3,
          longitude: 101.01,
          capturedAt: start.add(const Duration(minutes: 15)),
        ),
        HikeCoordinate(
          latitude: 3,
          longitude: 101.02,
          capturedAt: start.add(const Duration(minutes: 35)),
        ),
      ],
      checkpoints: const [
        HikeAnalysisCheckpoint(
          name: 'Start',
          order: 1,
          latitude: 3,
          longitude: 101,
        ),
        HikeAnalysisCheckpoint(
          name: 'Lookout',
          order: 2,
          latitude: 3,
          longitude: 101.01,
        ),
        HikeAnalysisCheckpoint(
          name: 'Finish',
          order: 3,
          latitude: 3,
          longitude: 101.02,
        ),
      ],
    );

    expect(analysis.checkpoints, hasLength(3));
    expect(analysis.checkpoints.every((checkpoint) => checkpoint.reached), isTrue);
    expect(
      analysis.checkpoints[1].timeFromPrevious,
      const Duration(minutes: 15),
    );
    expect(analysis.checkpoints[1].distanceFromPreviousKm, closeTo(1.11, 0.03));
    expect(analysis.checkpoints[1].paceMinutesPerKm, closeTo(13.5, 0.5));
    expect(analysis.totalDistanceKm, closeTo(2.22, 0.05));
  });

  test('marks a checkpoint as not reached when the track stays outside 100m', () {
    final start = DateTime.utc(2026, 8, 20, 1);
    final analysis = analyzeHikeRoute(
      routePoints: [
        HikeCoordinate(latitude: 3, longitude: 101, capturedAt: start),
        HikeCoordinate(
          latitude: 3,
          longitude: 101.001,
          capturedAt: start.add(const Duration(minutes: 2)),
        ),
      ],
      checkpoints: const [
        HikeAnalysisCheckpoint(
          name: 'Far checkpoint',
          order: 1,
          latitude: 3.1,
          longitude: 101.1,
        ),
      ],
    );

    expect(analysis.checkpoints.single.reached, isFalse);
    expect(analysis.checkpoints.single.reachedAt, isNull);
  });
}

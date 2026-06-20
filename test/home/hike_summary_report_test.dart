import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  test('summary uses exact elapsed time and actual safety events', () {
    final trail = Trail(
      trailId: 'summary-trail',
      name: 'Summary Trail',
      area: 'Test',
      state: 'Test',
      latitude: 3,
      longitude: 101,
      distanceKm: 2,
      difficulty: 'Easy',
      estimatedDurationMinutes: 60,
      elevationGainMeters: 50,
      ratingAverage: 4,
      offlineMapAvailable: false,
      offlineMapDownloaded: false,
      isVerifiedTrail: true,
      routeFilePath: '',
      coverColorValue: 0xFF34A853,
      checkpoints: const [
        TrailCheckpoint(name: 'Start', latitude: 3, longitude: 101, order: 1),
        TrailCheckpoint(
          name: 'End',
          latitude: 3.01,
          longitude: 101.01,
          order: 2,
        ),
      ],
      weather: TrailWeather(
        summary: '',
        temperatureRange: '',
        rainProbability: 0,
        cachedAt: DateTime.utc(2026),
      ),
      hazards: const [],
    );
    final startedAt = DateTime.utc(2026, 6, 20, 1);
    final coordinate = HikeCoordinate(
      latitude: 3.005,
      longitude: 101.005,
      capturedAt: startedAt.add(const Duration(minutes: 2)),
    );
    final hike = ActiveHikeSession(
      sessionId: 'summary-session',
      draft: HikeSessionDraft.fromTrail(trail),
      startedAt: startedAt,
      batteryLevel: 85,
      queuedUpdates: 0,
      manualPins: 99,
      checkIns: 1,
      routePoints: [
        HikeCoordinate(latitude: 3, longitude: 101, capturedAt: startedAt),
        coordinate,
      ],
      manualPinLocations: [
        HikeManualPin(
          id: 'real-pin',
          coordinate: coordinate,
          pinnedAt: startedAt.add(const Duration(minutes: 2)),
        ),
      ],
      checkInRecords: [
        HikeCheckInRecord(
          id: 'real-check-in',
          checkedInAt: startedAt.add(const Duration(minutes: 1)),
          coordinate: coordinate,
        ),
      ],
    );

    final report = HikeSummaryReport.fromActiveHike(
      activeHike: hike,
      endedAt: startedAt.add(const Duration(hours: 1, minutes: 2, seconds: 3)),
    );

    expect(report.duration, const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(report.checkIns, 1);
    expect(report.manualPins, 1);
    expect(report.shareText, contains('Duration: 1h 2m 3s'));
  });
}

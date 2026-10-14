import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/admin/View/recorded_trail_requests_page.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Data/hiker_circle_firebase_repository.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/View/recorded_trail_request_page.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

final recordedPoints = [
  for (var i = 0; i < 5; i++)
    HikeCoordinate(
      latitude: 5.123456789 + i * .001,
      longitude: 100.123456789 + i * .001,
      capturedAt: DateTime.utc(2026, 10, 12, 8, i),
      altitudeMeters: 50 + i.toDouble(),
    ),
];

Map<String, dynamic> request() => {
  'requestId': 'recorded-request',
  'pointCount': recordedPoints.length,
  'durationMinutes': 60,
  'status': 'pending',
  'proposed': {
    'name': 'Forest Path',
    'area': 'Local forest',
    'state': 'Penang',
    'country': 'Malaysia',
  },
  'checkpoints': [
    for (final i in [0, 2, 4])
      {
        'name': 'Stop $i',
        'order': [0, 2, 4].indexOf(i) + 1,
        'latitude': recordedPoints[i].latitude,
        'longitude': recordedPoints[i].longitude,
      },
  ],
};

class RecordingRepository extends HikerCircleFirebaseRepository {
  RecordingRepository()
    : super(
        firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
          'Test',
        ),
      );
  int submitAttempts = 0;
  Map<String, String>? submittedIdentity;
  List<Map<String, dynamic>>? submittedCheckpoints;
  Trail? published;
  List<HikeCoordinate>? publishedPoints;

  @override
  Future<String> submitRecordedTrailRequest({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required HikeSummaryReport report,
    required Map<String, String> proposed,
    required List<Map<String, dynamic>> checkpointSelections,
    ValueChanged<double>? onProgress,
  }) async {
    submitAttempts++;
    submittedIdentity = proposed;
    submittedCheckpoints = checkpointSelections;
    onProgress?.call(1);
    if (submitAttempts == 1) {
      throw const HikerCircleFirebaseRepositoryException(
        'Reconnect and retry.',
      );
    }
    return 'recorded-request';
  }

  @override
  Future<List<Map<String, dynamic>>> loadAdminTrailRequests({
    required AppSession session,
  }) async => published == null ? [request()] : [];

  @override
  Future<List<HikeCoordinate>> loadRecordedTrailRequestPoints({
    required AppSession session,
    required String requestId,
  }) async => recordedPoints;

  @override
  Future<void> approveRecordedTrailRequest({
    required AppSession session,
    required String requestId,
    required Trail trail,
    required List<HikeCoordinate> points,
  }) async {
    published = trail;
    publishedPoints = points;
  }
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

Future<void> enterField(WidgetTester tester, String label, String value) async {
  final finder = field(label);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
}

void main() {
  final session = AppSession(
    phoneNumber: 'hiker',
    signedInAt: DateTime.utc(2026),
  );
  final hike = ActiveHikeSession.fromDraft(
    HikeSessionDraft.fromTrail(
      Trail.fromPersistence({
        'trailId': 'unlisted_1234567890',
        'routeProvider': 'recorded-location-hike',
        'name': 'Hike from current location',
        'latitude': recordedPoints.first.latitude,
        'longitude': recordedPoints.first.longitude,
      }),
    ),
  ).copyWith(routePoints: recordedPoints);
  final report = HikeSummaryReport.fromActiveHike(
    activeHike: hike,
    endedAt: DateTime.utc(2026, 10, 12, 9),
  );

  testWidgets('failed submission keeps identity and checkpoints for retry', (
    tester,
  ) async {
    final repository = RecordingRepository();
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecordedTrailRequestPage(
                      session: session,
                      repository: repository,
                      hike: hike,
                      report: report,
                      recordedMapOverride: const SizedBox(),
                    ),
                  ),
                );
              },
              child: const Text('Open request'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open request'));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(2);
    await tester.pump();
    await tester.ensureVisible(find.text('Add checkpoint here'));
    await tester.tap(find.text('Add checkpoint here'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'River crossing');
    await tester.tap(find.text('Add checkpoint'));
    await tester.pumpAndSettle();
    await enterField(tester, 'Trail name', 'Forest Path');
    await enterField(tester, 'Area / locality', 'Local forest');
    await enterField(tester, 'State / region', 'Penang');
    await tester.ensureVisible(find.text('Send for admin review'));
    await tester.tap(find.text('Send for admin review'));
    await tester.pumpAndSettle();
    expect(find.text('Reconnect and retry.'), findsOneWidget);
    expect(find.text('Forest Path'), findsOneWidget);
    expect(find.text('River crossing'), findsOneWidget);
    expect(result, isNull);
    await tester.ensureVisible(find.text('Send for admin review'));
    await tester.tap(find.text('Send for admin review'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(repository.submitAttempts, 2);
    expect(repository.submittedIdentity!['country'], 'Malaysia');
    expect(repository.submittedCheckpoints!.map((c) => c['index']), [0, 2, 4]);
    expect(repository.submittedCheckpoints![1]['name'], 'River crossing');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'admin reviews all recorded samples and publishes chosen checkpoints',
    (tester) async {
      final repository = RecordingRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: RecordedTrailRequestsPage(
            session: session.copyWith(isAdmin: true),
            repository: repository,
            recordedMapBuilder: (trail, points) {
              expect(points, same(recordedPoints));
              expect(trail.checkpoints, hasLength(3));
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forest Path'));
      await tester.pumpAndSettle();
      expect(find.text('Review recorded trail'), findsOneWidget);
      expect(find.textContaining('Stop 2'), findsOneWidget);
      await enterField(tester, 'Typical duration (minutes)', '90');
      await enterField(tester, 'Elevation gain (m)', '150');
      final publish = find.text('Add to trail library');
      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await tester.pumpAndSettle();
      expect(repository.published!.estimatedDurationMinutes, 90);
      expect(repository.published!.elevationGainMeters, 150);
      expect(
        repository.published!.checkpoints[1].latitude,
        recordedPoints[2].latitude,
      );
      expect(repository.publishedPoints, same(recordedPoints));
      expect(find.text('No requests awaiting review'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

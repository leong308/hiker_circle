import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Data/hiker_circle_firebase_repository.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/core/widgets/community_hazard_marker.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'package:hiker_circle/trail/View/trail_page.dart';

void main() {
  test('nearby reports share a badge count, repeated documents do not', () {
    const a = CommunityHazard(
      id: 'a',
      type: 'Mud',
      latitude: 3,
      longitude: 101,
    );
    const b = CommunityHazard(
      id: 'b',
      type: 'Fallen tree',
      latitude: 3.0001,
      longitude: 101,
    );
    const c = CommunityHazard(
      id: 'c',
      type: 'Flood',
      latitude: 3.01,
      longitude: 101,
    );
    final clusters = clusterCommunityHazards([a, b, a, c]);
    expect(clusters.map((c) => c.count), [2, 1]);
    expect(clusters.first.reports.map((r) => r.type), ['Mud', 'Fallen tree']);
  });

  test('malformed or resolved reports never produce invalid map pins', () {
    expect(
      CommunityHazard.fromMap('a', {'latitude': double.nan, 'longitude': 101}),
      isNull,
    );
    expect(
      CommunityHazard.fromMap('a', {'latitude': 91, 'longitude': 101}),
      isNull,
    );
    expect(
      CommunityHazard.fromMap('a', {
        'latitude': 3,
        'longitude': 101,
        'status': 'resolved',
      }),
      isNull,
    );
    final report = CommunityHazard.fromMap('a', {
      'latitude': 3,
      'longitude': 101,
      'hazardType': 7,
      'description': [],
      'reportedAtLocal': 5,
    });
    expect(report?.type, 'Caution');
    expect(report?.description, '');
    expect(report?.reportedAt, isNull);
  });

  testWidgets('reporting uses nested category choices with optional details', (
    tester,
  ) async {
    final trail = Trail.fromPersistence({
      'trailId': 't',
      'name': 'Test trail',
      'latitude': 3.0,
      'longitude': 101.0,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: HazardReportPage(
          session: AppSession(
            phoneNumber: '+60111111111',
            signedInAt: DateTime.utc(2026),
          ),
          hikerCircleRepository: HikerCircleFirebaseRepository(
            firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
              'test',
            ),
          ),
          trail: trail,
        ),
      ),
    );
    expect(find.text('What is on the trail?'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('Report here'), findsNothing);
    await tester.tap(find.text('Blocked route'));
    await tester.pumpAndSettle();
    expect(find.text('Fallen tree'), findsOneWidget);
    await tester.tap(find.text('Fallen tree'));
    await tester.pumpAndSettle();
    expect(find.text('Add a note (optional)'), findsOneWidget);
    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Report here'),
    );
    expect(submit.onPressed, isNotNull);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('What is on the trail?'), findsOneWidget);
    expect(find.text('Report here'), findsNothing);
  });
}

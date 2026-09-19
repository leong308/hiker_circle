import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Data/hiker_circle_firebase_repository.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/me/Data/expired_hikes_repository.dart';
import 'package:hiker_circle/me/View/hike_history_page.dart';

void main() {
  testWidgets(
    'expired plans paginate separately and open read-only original details',
    (tester) async {
      final requests = <ExpiredHikesCursor?>[];
      const cursor = ExpiredHikesCursor(
        departureTimeLocal: '2026-07-01T08:00:00.000Z',
        hikeId: 'recent',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: HikeHistoryPage(
            repository: HikerCircleFirebaseRepository(
              firebaseBootstrapResult:
                  const FirebaseBootstrapResult.unavailable('test'),
            ),
            loadHistory: () async => [],
            loadExpiredHikes: (next) async {
              requests.add(next);
              return ExpiredHikesPage(
                hikes: [_hike(next == null ? 'recent' : 'older')],
                nextCursor: next == null ? cursor : null,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No completed hikes yet'), findsOneWidget);
      await tester.tap(find.text('Expired'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('expired-hike-recent')), findsOneWidget);
      expect(find.text('No completed hikes yet'), findsNothing);
      await tester.tap(find.text('Load older plans'));
      await tester.pumpAndSettle();
      expect(requests.last, same(cursor));
      expect(find.byKey(const Key('expired-hike-older')), findsOneWidget);
      expect(find.text('Load older plans'), findsNothing);
      await tester.tap(find.byKey(const Key('expired-hike-recent')));
      await tester.pumpAndSettle();
      expect(find.text('Expired hike plan'), findsOneWidget);
      expect(find.text('Expected return'), findsOneWidget);
      expect(find.text('Organizer'), findsOneWidget);
      expect(find.text('Original host'), findsOneWidget);
      expect(find.text('Start hike'), findsNothing);
      expect(find.text('Join hike'), findsNothing);
      expect(find.text('Actual hike'), findsNothing);
    },
  );

  testWidgets(
    'expired history failure can retry independently of completed history',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: HikeHistoryPage(
            repository: HikerCircleFirebaseRepository(
              firebaseBootstrapResult:
                  const FirebaseBootstrapResult.unavailable('test'),
            ),
            loadHistory: () async => [],
            loadExpiredHikes: (_) async {
              if (calls++ == 0) throw StateError('offline');
              return const ExpiredHikesPage(hikes: []);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expired'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load expired plans'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('No expired plans'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

UpcomingHike _hike(String id) => UpcomingHike.fromFirestore(id, {
  'trailName': '$id plan',
  'departureTimeLocal': '2026-07-01T08:00:00.000Z',
  'expectedReturnTimeLocal': '2026-07-01T12:00:00.000Z',
  'creatorName': 'Original host',
  'hikeType': 'team',
  'participantCount': 3,
  'distanceKm': 8.0,
  'durationMinutes': 240,
});

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Data/hiker_circle_firebase_repository.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/View/find_hike_page.dart';

void main() {
  test('normalizes each hike reminder preference to bounded options', () {
    final preference = const HikeReminderPreference(
      firstReminderMinutesBefore: 999,
      repeatIntervalMinutes: 7,
      finalReminderMinutesBefore: 60,
      maximumReminders: 99,
    ).normalized();

    expect(preference.firstReminderMinutesBefore, 120);
    expect(preference.repeatIntervalMinutes, 30);
    expect(preference.finalReminderMinutesBefore, 60);
    expect(preference.maximumReminders, 4);
  });

  testWidgets('joining keeps the list visible and opens per-hike reminders', (
    tester,
  ) async {
    final repository = _ReminderRepository();
    final now = DateTime.now().toUtc();
    final session = AppSession(
      phoneNumber: '+60999999999',
      username: 'Joiner',
      signedInAt: now,
    );
    final hike = UpcomingHike(
      id: 'hike-reminder-1',
      sessionId: 'hike-reminder-1',
      trailId: 'trail-1',
      trailName: 'World Ridge',
      latitude: 5.4141,
      longitude: 100.3288,
      area: 'George Town',
      state: 'Penang',
      country: 'Malaysia',
      distanceKm: 6,
      durationMinutes: 150,
      difficulty: 'Moderate',
      startPointName: 'Gate',
      destinationName: 'Summit',
      departureTime: now.add(const Duration(hours: 4)),
      expectedReturnTime: now.add(const Duration(hours: 8)),
      hikeType: 'team',
      participantCount: 1,
      creatorPhone: '+60111111111',
      creatorName: 'Host',
      createdAt: now,
    );
    var parentRefreshes = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: UpcomingHikeCard(
              hike: hike,
              session: session,
              repository: repository,
              onJoin: () => parentRefreshes += 1,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Join Group Hike'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Set your hike reminders'), findsOneWidget);
    expect(find.text('World Ridge'), findsWidgets);
    expect(parentRefreshes, 0);

    await tester.ensureVisible(find.text('Save reminders'));
    await tester.tap(find.text('Save reminders'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.savedHikeId, 'hike-reminder-1');
    expect(repository.savedPreference, isNotNull);
    expect(parentRefreshes, 1);
    expect(find.text('You joined this hike'), findsOneWidget);
  });
}

class _ReminderRepository extends HikerCircleFirebaseRepository {
  _ReminderRepository()
    : super(
        firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
          'test',
        ),
      );

  String? savedHikeId;
  HikeReminderPreference? savedPreference;

  @override
  Future<bool> joinUpcomingHike({required String hikeId}) async => true;

  @override
  Future<HikeReminderPreference> loadUpcomingHikeReminderPreference({
    required AppSession session,
    required String hikeId,
  }) async => const HikeReminderPreference();

  @override
  Future<void> saveUpcomingHikeReminderPreference({
    required AppSession session,
    required String hikeId,
    required HikeReminderPreference preference,
  }) async {
    savedHikeId = hikeId;
    savedPreference = preference;
  }
}

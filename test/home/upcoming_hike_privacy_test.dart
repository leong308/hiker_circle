import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Data/hiker_circle_firebase_repository.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/View/find_hike_page.dart';

void main() {
  test('preview parser rejects malformed entries and ignores extra fields', () {
    final hikes = parseUpcomingHikePreviewPayload({
      'hikes': [
        null,
        'not-a-map',
        {'id': ''},
        {
          'id': 'hike-1',
          'trailName': 'Pine Trail',
          'departureTimeLocal': '2099-08-05T08:00:00.000Z',
          'creatorName': 'Aina',
          'creatorPhone': '+60111111111',
          'participantPhones': ['+60111111111'],
          'draft': {'sensitive': true},
        },
        {'id': 'hike-1', 'trailName': 'Duplicate'},
      ],
    });

    expect(hikes, hasLength(1));
    expect(hikes.single.id, 'hike-1');
    expect(hikes.single.trailName, 'Pine Trail');
    expect(hikes.single.draft, isNull);
  });

  test('preview parser retains only the caller join-request status', () {
    final hikes = parseUpcomingHikePreviewPayload({
      'hikes': [
        {
          'id': 'solo-1',
          'trailName': 'Pine Trail',
          'departureTimeLocal': '2099-08-05T08:00:00.000Z',
          'joinRequestStatus': 'pending',
          'requesterPhone': '+60111111111',
        },
      ],
    });

    expect(hikes.single.joinRequestStatus, 'pending');
    expect(hikes.single.toFirestore().containsKey('requesterPhone'), isFalse);
  });

  testWidgets('solo hike is labelled Solo and requires host approval', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final hike = UpcomingHike(
      id: 'solo-1',
      sessionId: 'solo-1',
      trailId: 'trail-1',
      trailName: 'Pine Trail',
      latitude: 3.139,
      longitude: 101.687,
      area: 'Kuala Lumpur',
      state: 'Wilayah Persekutuan',
      distanceKm: 4.2,
      durationMinutes: 90,
      difficulty: 'Moderate',
      startPointName: 'North Gate',
      destinationName: 'Summit',
      departureTime: now.add(const Duration(days: 1)),
      expectedReturnTime: now.add(const Duration(days: 1, hours: 2)),
      hikeType: 'solo',
      participantCount: 1,
      creatorPhone: '+60123456789',
      creatorName: 'Host',
      createdAt: now,
    );
    final repository = HikerCircleFirebaseRepository(
      firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
        'test',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: UpcomingHikeCard(
              hike: hike,
              session: AppSession(phoneNumber: '+60999999999', signedInAt: now),
              repository: repository,
              onJoin: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Solo'), findsOneWidget);
    expect(find.text('Request to join'), findsOneWidget);
    expect(find.text('Join Group Hike'), findsNothing);
  });

  testWidgets('upcoming hike card does not expose the host phone number', (
    tester,
  ) async {
    const hostPhone = '+60123456789';
    final now = DateTime.now().toUtc();
    final hike = UpcomingHike(
      id: 'hike-1',
      sessionId: 'session-1',
      trailId: 'trail-1',
      trailName: 'Pine Trail',
      latitude: 3.139,
      longitude: 101.687,
      area: 'Kuala Lumpur',
      state: 'Wilayah Persekutuan',
      distanceKm: 4.2,
      durationMinutes: 90,
      difficulty: 'Moderate',
      startPointName: 'North Gate',
      destinationName: 'Summit',
      departureTime: now.add(const Duration(days: 1)),
      expectedReturnTime: now.add(const Duration(days: 1, hours: 2)),
      hikeType: 'team',
      participantCount: 1,
      creatorPhone: hostPhone,
      creatorName: '',
      createdAt: now,
      participantPhones: const [hostPhone],
    );
    final repository = HikerCircleFirebaseRepository(
      firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
        'test',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: UpcomingHikeCard(
              hike: hike,
              session: AppSession(phoneNumber: '+60999999999', signedInAt: now),
              repository: repository,
              onJoin: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Hike host'), findsOneWidget);
    expect(find.text('Group'), findsOneWidget);
    expect(find.text('Solo'), findsNothing);
    expect(find.text('Join Group Hike'), findsOneWidget);
    expect(find.text('Phone'), findsNothing);
    expect(find.text(hostPhone), findsNothing);
  });
}

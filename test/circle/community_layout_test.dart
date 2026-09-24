import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Data/hiker_circle_firebase_repository.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/circle/View/circle_page.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('community discovery and composer work in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const bootstrap = FirebaseBootstrapResult.unavailable('Offline test');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: CirclePage(
              session: AppSession(
                phoneNumber: '+60123456789',
                signedInAt: DateTime.utc(2026),
              ),
              hikerCircleRepository: _CommunityRepository(),
              firebaseBootstrapResult: bootstrap,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find hikers'));
      await tester.pumpAndSettle();
      expect(find.text('Find your next hiking buddy'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'nonexistent');
      await tester.pump();
      expect(
        find.text('No hikers match this view. Try another search.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Stories'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Write a story'));
      await tester.tap(find.text('Write a story'));
      await tester.pumpAndSettle();
      expect(find.text('Create a post'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('friend request avatar opens the requester profile overview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FriendRequestRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CirclePage(
            session: AppSession(
              phoneNumber: '+60123456789',
              signedInAt: DateTime.utc(2026),
            ),
            hikerCircleRepository: repository,
            firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
              'Offline test',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Friend requests'));
    await tester.pumpAndSettle();
    expect(find.text('Friend Requests'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('buddy-request-profile-60111222333')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Requested you'), findsOneWidget);
    expect(find.text('Trekker'), findsWidgets);
    expect(find.text('Penang'), findsOneWidget);
    expect(repository.loadedProfilePhone, '+60111222333');
  });
}

class _CommunityRepository extends HikerCircleFirebaseRepository {
  _CommunityRepository()
    : super(
        firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
          'Offline test',
        ),
      );

  @override
  Stream<List<GroupChat>> userGroupChatsStream(String phoneNumber) =>
      const Stream.empty();

  @override
  Future<List<Map<String, dynamic>>> loadCommunityPosts({
    int limit = 30,
  }) async => [];
}

class _FriendRequestRepository extends _CommunityRepository {
  String loadedProfilePhone = '';

  static final List<Map<String, dynamic>> _requests = [
    {
      'phoneNumber': '+60111222333',
      'displayName': 'Maya Hiker',
      'handle': '@maya',
      'photoURL': '',
      'createdAtLocal': DateTime.utc(2026, 1, 1).toIso8601String(),
    },
  ];

  @override
  Stream<List<Map<String, dynamic>>> watchBuddyRequests({
    required AppSession session,
  }) => Stream.value(_requests);

  @override
  Future<List<Map<String, dynamic>>> loadBuddyRequests({
    required AppSession session,
  }) async => _requests;

  @override
  Future<Map<String, dynamic>?> loadCommunityProfile({
    String userId = '',
    String phoneNumber = '',
  }) async {
    loadedProfilePhone = phoneNumber;
    return {
      'userId': 'maya-user',
      'phoneNumber': phoneNumber,
      'displayName': 'Maya Hiker',
      'handle': '@maya',
      'photoURL': '',
      'hikerExperience': 'Intermediate',
      'hikeFrequency': 'Weekly',
      'residentialLocation': 'Penang',
      'level': 3,
      'levelName': 'Trekker',
    };
  }

  @override
  Future<Map<String, dynamic>> loadPublicHikerProfile({
    String userId = '',
    String phoneNumber = '',
  }) async => {
    'profile': {'hikeFrequency': 'Weekly'},
    'achievements': <Map<String, dynamic>>[],
    'hikeHistory': <Map<String, dynamic>>[],
  };
}

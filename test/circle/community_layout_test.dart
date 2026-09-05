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

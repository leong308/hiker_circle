import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/admin/View/community_post_management_page.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/app/Data/hiker_circle_firebase_repository.dart';
import 'admin_dashboard_test.dart';

class _Repository extends DashboardTestRepository {
  String caption = 'Original caption';
  String visibility = 'public';
  bool failSave = false;
  int saves = 0;
  @override
  Future<List<Map<String, dynamic>>> loadAdminCommunityPosts({
    required AppSession session,
  }) async => [
    {
      'postId': 'a',
      'caption': caption,
      'authorName': 'Hiker',
      'visibility': visibility,
      'imageUrls': <String>[],
    },
  ];
  @override
  Future<void> editAdminCommunityPost({
    required AppSession session,
    required Map<String, dynamic> original,
    required String caption,
    required List<String> imageUrls,
  }) async {
    saves++;
    if (failSave)
      throw const HikerCircleFirebaseRepositoryException(
        'Connection unavailable',
      );
    this.caption = caption;
  }

  @override
  Future<void> moderateCommunityPost({
    required AppSession session,
    required String postId,
    required String moderationStatus,
    String reason = '',
  }) async {
    visibility = moderationStatus == 'approved' ? 'public' : moderationStatus;
  }
}

Widget _app(_Repository repository, {bool admin = true, double scale = 1}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: CommunityPostManagementPage(
          repository: repository,
          session: AppSession(
            phoneNumber: 'admin',
            signedInAt: DateTime.utc(2026),
            isAdmin: admin,
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'failed edits retain input and successful retry refreshes the post',
    (tester) async {
      final repository = _Repository()..failSave = true;
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit post'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Caption'),
        'Revised caption',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Connection unavailable'), findsOneWidget);
      expect(find.text('Revised caption'), findsOneWidget);
      repository.failSave = false;
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Edit community post'), findsNothing);
      expect(find.text('Revised caption'), findsOneWidget);
      expect(repository.saves, 2);
    },
  );
  testWidgets('hide requires confirmation and the post can be restored', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.visibility, 'public');
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Hide'));
    await tester.pumpAndSettle();
    expect(repository.visibility, 'hidden');
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pumpAndSettle();
    expect(repository.visibility, 'public');
  });
  testWidgets('management fits a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(_Repository(), scale: 1.8));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('non-admin cannot access post management', (tester) async {
    await tester.pumpWidget(_app(_Repository(), admin: false));
    await tester.pumpAndSettle();
    expect(find.text('Admin privilege is required.'), findsOneWidget);
    expect(find.text('Edit post'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/admin/View/admin_page.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Data/hiker_circle_firebase_repository.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

class DashboardTestRepository extends HikerCircleFirebaseRepository {
  DashboardTestRepository({this.fail = false})
    : super(
        firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
          'Test',
        ),
      );
  final bool fail;
  int loads = 0;
  @override
  Future<Map<String, dynamic>> loadAdminDashboardAnalytics({
    required AppSession session,
    bool forceRefresh = false,
  }) async {
    if (fail) throw Exception('Offline');
    return {
      'totals': {'users': 12, 'trails': 2, 'posts': 1},
      'safety': {'pendingHazards': 1},
      'generatedAtMillis': 1791792000000,
    };
  }

  @override
  Future<List<Trail>> loadAdminTrails({required AppSession session}) async {
    loads++;
    if (fail) throw Exception('Offline');
    return [
      Trail.fromPersistence({
        'trailId': 'hill',
        'name': 'Penang Hill Heritage Trail',
        'state': 'Penang',
        'isVerifiedTrail': true,
      }),
      Trail.fromPersistence({
        'trailId': 'forest',
        'name': 'Forest Loop',
        'state': 'Perak',
      }),
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> loadAdminHazardReports({
    required AppSession session,
  }) async => [
    {
      'hazardId': 'a',
      'hazardType': 'Fallen tree',
      'status': 'pending',
      'trailName': 'Forest Loop',
      'severity': 'medium',
    },
    {
      'hazardId': 'b',
      'hazardType': 'Loose rocks',
      'status': 'approved',
      'trailName': 'Penang Hill',
    },
  ];
  @override
  Future<List<Map<String, dynamic>>> loadAdminCommunityPosts({
    required AppSession session,
  }) async => [
    {
      'postId': 'a',
      'caption': 'Morning on Penang Hill',
      'visibility': 'public',
    },
  ];
  @override
  Future<List<Map<String, dynamic>>> loadAdminAchievements({
    required AppSession session,
  }) async => [
    {'achievementId': 'first', 'title': 'First summit', 'isActive': true},
  ];
}

Widget dashboardTestApp({
  DashboardTestRepository? repository,
  Brightness brightness = Brightness.light,
  double scale = 1,
  bool admin = true,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    fontFamily: 'Inter',
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF438765),
      brightness: brightness,
    ),
  ),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: AdminPage(
        session: AppSession(
          phoneNumber: 'admin',
          signedInAt: DateTime.utc(2026),
          isAdmin: admin,
        ),
        hikerCircleRepository: repository ?? DashboardTestRepository(),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'section navigation, search reset and diagnostics stay accessible',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(dashboardTestApp());
      await tester.pumpAndSettle();
      expect(find.text('Registered users'), findsOneWidget);
      expect(find.text('HikerCircle is operational'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('admin-nav-trails')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Penang');
      await tester.pump();
      expect(find.text('Penang Hill Heritage Trail'), findsOneWidget);
      expect(find.text('Forest Loop'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('admin-nav-hazards')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text ?? '',
        '',
      );
      expect(find.text('Fallen tree'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to admin dashboard'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Admin tools'));
      await tester.tap(find.text('Admin tools'));
      await tester.pumpAndSettle();
      expect(find.text('Hiker feedback'), findsOneWidget);
      expect(find.text('Button Debugging'), findsOneWidget);
      await tester.ensureVisible(find.text('Data diagnostics'));
      await tester.tap(find.text('Data diagnostics'));
      await tester.pumpAndSettle();
      expect(find.text('Cloud Firestore'), findsOneWidget);
      expect(find.text('Local SQLite Database'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final config in [
    (390.0, 1.0, Brightness.light),
    (1024.0, 1.0, Brightness.dark),
    (320.0, 1.8, Brightness.light),
  ]) {
    testWidgets(
      'all dashboard sections fit ${config.$1}px at ${config.$2} scale',
      (tester) async {
        tester.view.physicalSize = Size(config.$1, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          dashboardTestApp(scale: config.$2, brightness: config.$3),
        );
        await tester.pumpAndSettle();
        for (final section in [
          'overview',
          'trails',
          'hazards',
          'community',
          'achievements',
          'tools',
        ]) {
          final tab = find.byKey(ValueKey('admin-nav-$section'));
          await tester.ensureVisible(tab);
          await tester.tap(tab);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: section);
        }
      },
    );
  }

  testWidgets('moderation shows flags separately from post management', (
    tester,
  ) async {
    await tester.pumpWidget(dashboardTestApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-nav-community')));
    await tester.pumpAndSettle();
    expect(find.text('Morning on Penang Hill'), findsNothing);
    expect(find.text('Approve'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.ensureVisible(find.text('Manage community posts'));
    await tester.tap(find.text('Manage community posts'));
    await tester.pumpAndSettle();
    expect(find.text('Community posts'), findsOneWidget);
    expect(find.text('Morning on Penang Hill'), findsOneWidget);
    expect(find.text('Edit post'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Morning on Penang Hill'), findsNothing);
  });

  testWidgets('load error does not claim a healthy empty queue', (
    tester,
  ) async {
    await tester.pumpWidget(
      dashboardTestApp(repository: DashboardTestRepository(fail: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to refresh workspace'), findsOneWidget);
    expect(find.text('No pending reports in the latest batch'), findsNothing);
  });

  testWidgets('non-admin dashboard does not load admin data', (tester) async {
    final repository = DashboardTestRepository();
    await tester.pumpWidget(
      dashboardTestApp(repository: repository, admin: false),
    );
    await tester.pumpAndSettle();
    expect(repository.loads, 0);
    expect(find.text('Admin privilege is required.'), findsOneWidget);
  });
}

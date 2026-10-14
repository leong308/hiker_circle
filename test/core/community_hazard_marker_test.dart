import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Data/hiker_circle_firebase_repository.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/core/widgets/community_hazard_marker.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'package:hiker_circle/trail/View/trail_page.dart';

void main() {
  setUpAll(() async {
    final text = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([text.load(), icons.load()]);
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'report page uses the shared header and readable selection cards in ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        final scheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F8F5E),
          brightness: brightness,
          primary: brightness == Brightness.dark
              ? const Color(0xFF7AD69C)
              : const Color(0xFF3F8F5E),
        );
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              fontFamily: 'Inter',
              brightness: brightness,
              colorScheme: scheme,
              scaffoldBackgroundColor: brightness == Brightness.dark
                  ? const Color(0xFF0C120F)
                  : Colors.white,
            ),
            home: RepaintBoundary(
              key: key,
              child: HazardReportPage(
                session: AppSession(
                  phoneNumber: '+60111111111',
                  signedInAt: DateTime.utc(2026),
                ),
                hikerCircleRepository: HikerCircleFirebaseRepository(
                  firebaseBootstrapResult:
                      const FirebaseBootstrapResult.unavailable('test'),
                ),
                trail: Trail.fromPersistence({
                  'trailId': 't',
                  'name': 'Penang Hill Heritage Trail',
                }),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsNothing);
        expect(find.text('Report a Caution'), findsOneWidget);
        await captureCautionPreview(
          tester,
          key,
          'report-caution-${brightness.name}',
        );
        await tester.tap(find.text('Blocked route'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Fallen tree'));
        await tester.pumpAndSettle();
        expect(find.text('Add photos or videos'), findsOneWidget);
        expect(find.text('Report here'), findsOneWidget);
        await captureCautionPreview(
          tester,
          key,
          'report-caution-details-${brightness.name}',
        );
        expect(tester.takeException(), isNull);
        tester.view.physicalSize = const Size(320, 700);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness, fontFamily: 'Inter'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: HazardReportPage(
              session: AppSession(
                phoneNumber: '+60111111111',
                signedInAt: DateTime.utc(2026),
              ),
              hikerCircleRepository: HikerCircleFirebaseRepository(
                firebaseBootstrapResult:
                    const FirebaseBootstrapResult.unavailable('test'),
              ),
              trail: Trail.fromPersistence({
                'trailId': 't',
                'name': 'Penang Hill Heritage Trail',
              }),
            ),
          ),
        );
        expect(
          MediaQuery.textScalerOf(
            tester.element(find.byType(HazardReportPage)),
          ).scale(10),
          18,
        );
        await tester.scrollUntilVisible(find.text('Blocked route'), 160);
        await tester.tap(find.text('Blocked route'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Fallen tree'));
        await tester.pumpAndSettle();
        expect(find.text('Report here').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'resolved cautions retain a faded marker until seven days, then history retains them',
    () {
      final time = DateTime.utc(2026, 10, 12);
      final data = {
        'latitude': 3,
        'longitude': 101,
        'status': 'resolved',
        'resolutionCount': 3,
        'reportCount': 4,
        'reportedAtLocal': time.toIso8601String(),
      };
      final report = CommunityHazard.fromMap(
        'resolved',
        data,
        now: time.add(const Duration(days: 1)),
      )!;
      expect(report.isResolved, isTrue);
      final cluster = CommunityHazardCluster([report]);
      expect(cluster.confirmations, 4);
      expect(communityHazardAnnotation(cluster, Uint8List(0)).iconOpacity, .35);
      expect(
        CommunityHazard.fromMap(
          'resolved',
          data,
          now: time.add(const Duration(days: 7)),
        ),
        isNull,
      );
      expect(
        CommunityHazard.fromMap(
          'resolved',
          data,
          now: time.add(const Duration(days: 8)),
          includeExpired: true,
        ),
        isNotNull,
      );
    },
  );
  test(
    'map cautions scale smoothly to 3.5 times at ten metres per centimetre',
    () {
      double zoom(double meters) =>
          math.log(156543.03392 * math.cos(5 * math.pi / 180) * 38 / meters) /
          math.ln2;
      expect(cautionMarkerScale(zoom(200), 5), closeTo(.65, 1e-8));
      expect(cautionMarkerScale(zoom(100), 5), closeTo(.65, 1e-8));
      expect(cautionMarkerScale(zoom(30), 5), inExclusiveRange(.65, .65 * 3.5));
      expect(cautionMarkerScale(zoom(10), 5), closeTo(.65 * 3.5, 1e-8));
      expect(cautionMarkerScale(zoom(1), 5), closeTo(.65 * 3.5, 1e-8));
    },
  );
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

  test('malformed and undated reports never produce invalid map pins', () {
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
    }, includeExpired: true);
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
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('What is on the trail?'), findsOneWidget);
    expect(find.text('Report here'), findsNothing);
  });
}

Future<void> captureCautionPreview(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  if (!const bool.fromEnvironment('CAPTURE_CAUTION_PREVIEW')) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage(pixelRatio: 2);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    await Directory('tmp').create(recursive: true);
    await File('tmp/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

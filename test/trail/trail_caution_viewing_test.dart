import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/community_hazard_marker.dart';
import 'package:hiker_circle/trail/View/caution_media.dart';
import 'package:hiker_circle/trail/View/trail_caution_details.dart';

CommunityHazard caution(
  String id, {
  String status = 'unverified',
  DateTime? time,
  DateTime? expires,
  String description = 'A tree is blocking the path.',
  List<Map<String, dynamic>> media = const [],
}) => CommunityHazard(
  id: id,
  type: 'Fallen tree',
  latitude: 5,
  longitude: 100,
  reportedAt: time ?? DateTime.now().subtract(const Duration(hours: 1)),
  expiresAt: expires,
  status: status,
  description: description,
  media: media,
);

ThemeData theme(Brightness brightness) => ThemeData(
  useMaterial3: true,
  fontFamily: 'Inter',
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF3F8F5E),
    brightness: brightness,
  ),
);

Future<void> openPopup(
  WidgetTester tester,
  List<CommunityHazard> reports, {
  bool allowFeedback = false,
  Brightness brightness = Brightness.dark,
  GlobalKey? captureKey,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme(brightness),
      builder: (context, child) =>
          RepaintBoundary(key: captureKey, child: child!),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showCommunityHazardDetails(
                context,
                CommunityHazardCluster(reports),
                allowFeedback: allowFeedback,
              ),
              child: const Text('View caution'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('View caution'));
  await tester.pumpAndSettle();
}

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
      'short ${brightness.name} preview popup is view-only and fits its content',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        await openPopup(
          tester,
          [caution('active')],
          brightness: brightness,
          captureKey: key,
        );
        expect(find.text('Trail caution'), findsOneWidget);
        expect(find.text('A tree is blocking the path.'), findsOneWidget);
        expect(find.byTooltip('Upvote this issue'), findsNothing);
        expect(find.text('Resolved / Not Seen'), findsNothing);
        expect(find.byIcon(Icons.thumb_up_alt_outlined), findsNothing);
        expect(tester.getSize(find.byType(BottomSheet)).height, lessThan(360));
        expect(tester.takeException(), isNull);
        await capture(tester, key, 'caution-view-only-${brightness.name}');
      },
    );
  }

  testWidgets(
    'only the live-hike mode exposes issue and resolution actions with the new upvote icon',
    (tester) async {
      await openPopup(tester, [caution('active')], allowFeedback: true);
      expect(find.byTooltip('Upvote this issue'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_circle_up_rounded), findsOneWidget);
      expect(find.text('Resolved / Not Seen'), findsOneWidget);
      expect(find.byIcon(Icons.thumb_up_alt_outlined), findsNothing);
      await tester.tap(find.text('Resolved / Not Seen'));
      await tester.pumpAndSettle();
      expect(find.text('Add photos or videos'), findsOneWidget);
      expect(find.text('Submit update'), findsOneWidget);
    },
  );

  testWidgets(
    'read-only resolved cautions display status and media without reopening or resolution votes',
    (tester) async {
      await openPopup(tester, [
        CommunityHazard(
          id: 'resolved',
          type: 'Damaged bridge',
          latitude: 5,
          longitude: 100,
          status: 'resolved',
          resolutionId: 'resolution',
          resolutionCount: 3,
          reportedAt: DateTime.now(),
          media: const [
            {
              'url': 'https://example.test/photo.jpg',
              'contentType': 'image/jpeg',
            },
          ],
        ),
      ]);
      expect(
        find.text('Resolved / Not seen · 3 confirmations'),
        findsOneWidget,
      );
      expect(find.byTooltip('Report issue again with evidence'), findsNothing);
      expect(find.byTooltip('Confirm resolved / not seen'), findsNothing);
      await tester.tap(find.byType(InkWell).last);
      await tester.pumpAndSettle();
      expect(find.byType(CautionMediaViewer), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    },
  );

  testWidgets(
    'long caution popup stays within the screen and scrolls to the last caution',
    (tester) async {
      tester.view.physicalSize = const Size(430, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openPopup(tester, [
        for (var i = 0; i < 8; i++)
          caution(
            'caution-$i',
            description:
                'Long observation $i. ${'Check the obstruction and nearby footing. ' * 20}',
          ),
        caution('last', description: 'The final observation.'),
      ]);
      expect(tester.getSize(find.byType(BottomSheet)).height, lessThan(700));
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('The final observation.').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'history prioritizes open active cautions, then resolved, then archived; newest first per group',
    () {
      final now = DateTime.now();
      final reports = [
        caution('resolved', status: 'resolved', time: now),
        caution(
          'archived',
          time: now,
          expires: now.subtract(const Duration(seconds: 1)),
        ),
        caution('open-old', time: now.subtract(const Duration(days: 6))),
        caution('open-new', time: now.subtract(const Duration(hours: 1))),
      ];
      expect(sortTrailCautionsForHistory(reports, now: now).map((r) => r.id), [
        'open-new',
        'open-old',
        'resolved',
        'archived',
      ]);
      final afterExpiry = now.add(const Duration(days: 8));
      expect(
        sortTrailCautionsForHistory(reports, now: afterExpiry).first.id,
        'archived',
      );
    },
  );

  testWidgets(
    'only open active cards pulse red and the pulse stops when resolved',
    (tester) async {
      final now = DateTime.now();
      var open = caution('open');
      late StateSetter rebuild;
      final resolved = caution('resolved', status: 'resolved');
      await tester.pumpWidget(
        MaterialApp(
          theme: theme(Brightness.dark),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return TrailCautionsHistoryList(
                  reports: [resolved, open],
                  now: now,
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      final cards = tester
          .widgetList<TrailCautionHistoryCard>(
            find.byType(TrailCautionHistoryCard),
          )
          .toList();
      expect(cards.map((c) => c.report.id), ['open', 'resolved']);
      final openCard = find.byKey(const ValueKey('trail-caution-history-open'));
      final calmCard = find.byKey(
        const ValueKey('trail-caution-history-resolved'),
      );
      BoxDecoration decoration(Finder card) =>
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: card,
                          matching: find.byWidgetPredicate(
                            (w) =>
                                w is Container && w.decoration is BoxDecoration,
                          ),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      final initial = decoration(openCard);
      final calmInitial = decoration(calmCard);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(decoration(openCard).boxShadow, isNot(initial.boxShadow));
      expect(
        decoration(openCard).boxShadow!.single.blurRadius,
        greaterThan(initial.boxShadow!.single.blurRadius),
      );
      expect(decoration(calmCard), calmInitial);
      rebuild(() => open = caution('open', status: 'resolved'));
      await tester.pumpAndSettle();
      expect(decoration(openCard).boxShadow, isEmpty);
      final settled = decoration(openCard);
      await tester.pump(const Duration(seconds: 4));
      expect(decoration(openCard), settled);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history respects reduced motion and opens a read-only popup', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: TrailCautionsHistoryList(reports: [caution('open')]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(find.text('Trail caution'), findsOneWidget);
    expect(find.byTooltip('Upvote this issue'), findsNothing);
    expect(find.text('Resolved / Not Seen'), findsNothing);
    expect(tester.getSize(find.byType(BottomSheet)).height, lessThan(360));
    expect(tester.takeException(), isNull);
  });
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_CAUTION_PREVIEW')) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('tmp')..createSync(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

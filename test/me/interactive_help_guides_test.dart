import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/feedback/feedback_page.dart';
import 'package:hiker_circle/me/View/help_center_page.dart';

ThemeData _guideTheme(Brightness brightness) => ThemeData(
  fontFamily: 'Inter',
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF34A853),
    brightness: brightness,
    primary: brightness == Brightness.dark
        ? const Color(0xFF7AD69C)
        : const Color(0xFF34A853),
    surface: brightness == Brightness.dark
        ? const Color(0xFF141C17)
        : Colors.white,
  ),
);

const _frameKey = ValueKey('help-guide-preview-frame');
const _guides = [
  (
    id: 'team',
    title: 'Team hike basics',
    count: 7,
    chapter: 'Ready & start',
    start: 2,
  ),
  (
    id: 'sos',
    title: 'Using SOS safely',
    count: 8,
    chapter: 'Understand alerts',
    start: 3,
  ),
  (
    id: 'account',
    title: 'Account & troubleshooting',
    count: 8,
    chapter: 'Phone & updates',
    start: 4,
  ),
];

Future<void> _openGuidePage(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(
    find.text(title),
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

Future<void> _startGuide(WidgetTester tester, String id) async {
  await tester.scrollUntilVisible(
    find.byKey(ValueKey('$id-guide-start')),
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(ValueKey('$id-guide-start')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('$id-guide-start')));
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_HELP_GUIDES')) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_frameKey),
    );
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = Directory('tmp/help-guides');
    await output.create(recursive: true);
    await File(
      '${output.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final text = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    final cupertino = FontLoader('packages/cupertino_icons/CupertinoIcons')
      ..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      );
    await Future.wait([text.load(), icons.load(), cupertino.load()]);
  });

  for (final guide in _guides) {
    testWidgets(
      '${guide.id} chapters jump to a topic and preserve position when reopened',
      (tester) async {
        tester.view.physicalSize = const Size(430, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(const MaterialApp(home: HelpCenterPage()));
        await _openGuidePage(tester, guide.title);
        await tester.scrollUntilVisible(
          find.text(guide.chapter),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text(guide.chapter));
        await tester.pumpAndSettle();
        expect(
          find.text('Step ${guide.start + 1} of ${guide.count}'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<PageView>(find.byKey(ValueKey('${guide.id}-guide-pages')))
              .childrenDelegate
              .estimatedChildCount,
          guide.count,
        );
        await tester.tap(find.byKey(ValueKey('${guide.id}-guide-close')));
        await tester.pumpAndSettle();
        await _startGuide(tester, guide.id);
        expect(
          find.text('Step ${guide.start + 1} of ${guide.count}'),
          findsOneWidget,
        );
        await tester.drag(
          find.byKey(ValueKey('${guide.id}-guide-pages')),
          const Offset(-330, 0),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Step ${guide.start + 2} of ${guide.count}'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(ValueKey('${guide.id}-guide-close')));
        await tester.pumpAndSettle();
        await _startGuide(tester, guide.id);
        expect(
          find.text('Step ${guide.start + 2} of ${guide.count}'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(ValueKey('${guide.id}-guide-previous')));
        await tester.pumpAndSettle();
        expect(
          find.text('Step ${guide.start + 1} of ${guide.count}'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    for (final brightness in Brightness.values) {
      testWidgets(
        '${guide.id} all topics remain usable with large text in ${brightness.name}',
        (tester) async {
          tester.view.physicalSize = const Size(320, 740);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: _guideTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.8),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: const HelpCenterPage(),
            ),
          );
          await _openGuidePage(tester, guide.title);
          await _startGuide(tester, guide.id);
          for (var page = 0; page < guide.count; page++) {
            expect(
              find.text('Step ${page + 1} of ${guide.count}'),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await tester.tap(find.byKey(ValueKey('${guide.id}-guide-next')));
            await tester.pumpAndSettle();
          }
          expect(
            find.byKey(ValueKey('${guide.id}-guide-overlay')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('${guide.id} presentation in ${brightness.name}', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: _guideTheme(brightness),
            builder: (context, child) =>
                RepaintBoundary(key: _frameKey, child: child!),
            home: const HelpCenterPage(),
          ),
        );
        await _openGuidePage(tester, guide.title);
        await _capture(tester, '${guide.id}-${brightness.name}-overview');
        await _startGuide(tester, guide.id);
        await _capture(tester, '${guide.id}-${brightness.name}-step');
        expect(find.text('What to do'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'account guide opens Feedback from its final topic, preserving admin access',
    (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: HelpCenterPage(isAdmin: true)),
      );
      await _openGuidePage(tester, 'Account & troubleshooting');
      await tester.scrollUntilVisible(
        find.text('Get support'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Get support'));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('account-guide-feedback'));
      await tester.scrollUntilVisible(
        button,
        160,
        scrollable: find
            .ancestor(of: button, matching: find.byType(Scrollable))
            .first,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(FeedbackPage), findsOneWidget);
      expect(
        tester.widget<FeedbackPage>(find.byType(FeedbackPage)).isAdmin,
        isTrue,
      );
      expect(find.byKey(const ValueKey('account-guide-overlay')), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Find the fix, step by step.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

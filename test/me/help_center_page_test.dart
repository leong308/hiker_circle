import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/static_hazard_marker.dart';
import 'package:hiker_circle/me/Model/help_center_content.dart';
import 'package:hiker_circle/me/View/help_center_page.dart';
import 'package:hiker_circle/trail/Model/trail_hazard_categories.dart';

void main() {
  test('every reportable condition and map marker has practical guidance', () {
    final titles = trailConditionGuides.map((entry) => entry.title).toSet();
    expect(titles.length, trailConditionGuides.length);
    for (final category in trailHazardReportCategories.values) {
      for (final label in category.$2) {
        expect(titles, contains(label), reason: 'Missing help for $label');
      }
    }
    final supportedMarkers = trailConditionGuides
        .expand((entry) => entry.types)
        .map(staticHazardMarkerKindForType)
        .toSet();
    expect(supportedMarkers, containsAll(StaticHazardMarkerKind.values));
    for (final entry in trailConditionGuides) {
      expect(entry.meaning.trim(), isNotEmpty);
      expect(entry.action.trim(), isNotEmpty);
    }
  });

  testWidgets('category sheet filters conditions and preserves selection', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HikeBasicsPage()));
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byKey(const ValueKey('condition-category-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-Water')));
    await tester.pumpAndSettle();
    expect(find.text('Deep mud'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('River ford'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('River ford'));
    await tester.pumpAndSettle();
    expect(find.text('What to do'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('condition-category-selector')),
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('condition-category-selector')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('category-Water')))
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('category-All')));
    await tester.pumpAndSettle();
    expect(find.text('Slippery pathway'), findsOneWidget);
  });

  testWidgets('help home opens hike basics and a complete team guide', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HelpCenterPage()));
    await tester.tap(find.text('Explore Hike Basics'));
    await tester.pumpAndSettle();
    expect(find.byType(HikeBasicsPage), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Team hike basics'));
    await tester.tap(find.text('Team hike basics'));
    await tester.pumpAndSettle();
    expect(find.text('Create or join a hike'), findsOneWidget);
    expect(find.text('Get ready together'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'plan and track opens a horizontally swipeable seven-step guide',
    (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: HelpCenterPage()));
      await tester.tap(find.text('Plan & track a hike'));
      await tester.pumpAndSettle();

      expect(find.text('Your hike in 7 clear steps'), findsOneWidget);
      expect(find.text('At a glance'), findsOneWidget);
      expect(find.textContaining('Mark this step'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('plan-guide-start')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('plan-guide-overlay')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('plan-guide-step-strip')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('plan-guide-pages')), findsOneWidget);
      expect(find.text('Step 1 of 7'), findsOneWidget);
      expect(find.textContaining('Mark this step'), findsNothing);

      final pages = tester.widget<PageView>(
        find.byKey(const ValueKey('plan-guide-pages')),
      );
      expect(pages.childrenDelegate.estimatedChildCount, 7);

      await tester.drag(
        find.byKey(const ValueKey('plan-guide-pages')),
        const Offset(-320, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 7'), findsOneWidget);
      expect(find.text('Read the map'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('plan and track guide remains usable with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const HelpCenterPage(),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Plan & track a hike'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Plan & track a hike'));
    await tester.pumpAndSettle();

    expect(find.text('Your hike in 7 clear steps'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-guide-start')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-guide-overlay')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('narrow layout supports large text in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const HelpCenterPage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Explore Hike Basics'));
      await tester.tap(find.text('Explore Hike Basics'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('condition-category-selector')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('category-Ground')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Deep mud'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Deep mud'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

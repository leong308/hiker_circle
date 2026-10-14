import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/admin/View/community_integrity_panel.dart';
import 'package:hiker_circle/admin/View/community_moderation_rules.dart';

void main() {
  test('displayed phrases and categories match the backend policy', () {
    final backend = File(
      'functions/community_moderation.js',
    ).readAsStringSync();
    final phrases = RegExp(
      r'\(\?:((?:my name is\|)[^)]+)\)',
    ).firstMatch(backend)!.group(1)!.split('|');
    final categories = RegExp(
      r"const CATEGORIES = \[([^\]]+)\]",
    ).firstMatch(backend)!.group(1)!;
    expect(communitySensitivePhrases, orderedEquals(phrases));
    expect(
      communityReviewCategories.keys,
      orderedEquals(
        RegExp(r"'([^']+)'").allMatches(categories).map((m) => m.group(1)!),
      ),
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('rules popup scrolls on a small screen in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const Scaffold(
            body: Center(child: CommunityModerationRulesButton()),
          ),
        ),
      );
      await tester.tap(find.text('Moderation rules'));
      await tester.pumpAndSettle();
      expect(find.text('Sensitive phrases'), findsOneWidget);
      for (final phrase in communitySensitivePhrases) {
        expect(find.text(phrase), findsOneWidget);
      }
      expect(find.textContaining('They are not banned words.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Sensitive patterns'),
        150,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Email addresses'), findsOneWidget);
      expect(find.text('Phone-like numbers'), findsOneWidget);
      expect(find.text('Coordinate pairs'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Manual review categories'),
        150,
        scrollable: find.byType(Scrollable),
      );
      expect(
        find.textContaining('Administrators review meaning and context'),
        findsOneWidget,
      );
      for (final category in communityReviewCategories.values) {
        expect(find.text(category), findsOneWidget);
      }
      await tester.scrollUntilVisible(
        find.text('Other checks & limits'),
        150,
        scrollable: find.byType(Scrollable),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close moderation rules'));
      await tester.pumpAndSettle();
      expect(find.text('Sensitive phrases'), findsNothing);
    });
  }

  testWidgets('rules are accessible without a Firebase connection', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CommunityIntegrityPanel())),
    );
    await tester.tap(find.text('Moderation rules'));
    await tester.pumpAndSettle();
    expect(find.text('Sensitive phrases'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

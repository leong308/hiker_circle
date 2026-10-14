import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/Model/path_deviation_policy.dart';
import 'package:hiker_circle/home/View/path_deviation_distance_setting.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  final trail = Trail.fromPersistence({
    'trailId': 'test-route',
    'name': 'Forest walk',
  });

  test('selected alert distance replaces the old 75 m threshold', () {
    for (final distance in [10, 25, 37, 50]) {
      final threshold = PathDeviationPolicy.effectiveThreshold(
        selectedDistanceMeters: distance,
        accuracyMeters: 3,
      );
      expect(threshold, distance);
    }
  });

  test('GPS drift still raises the effective threshold on uncertain fixes', () {
    expect(
      PathDeviationPolicy.effectiveThreshold(
        selectedDistanceMeters: 10,
        accuracyMeters: 18,
      ),
      36,
    );
    expect(
      PathDeviationPolicy.effectiveThreshold(
        selectedDistanceMeters: 50,
        accuracyMeters: 18,
      ),
      50,
    );
    for (final accuracy in [null, -1.0, double.nan, double.infinity]) {
      expect(
        PathDeviationPolicy.effectiveThreshold(
          selectedDistanceMeters: 25,
          accuracyMeters: accuracy,
        ),
        25,
      );
    }
  });

  test(
    'saved drafts clamp out-of-range values and migrate missing or invalid distances',
    () {
      final saved = HikeSessionDraft.fromTrail(trail).toPersistence();
      for (final entry in <Object?, int>{
        -1: 10,
        0: 10,
        10: 10,
        36.7: 37,
        50: 50,
        999: 50,
      }.entries) {
        final restored = HikeSessionDraft.fromPersistence({
          ...saved,
          'pathDeviationDistanceMeters': entry.key,
        });
        expect(restored.pathDeviationDistanceMeters, entry.value);
      }
      for (final value in [null, '20', double.nan, double.infinity]) {
        expect(
          HikeSessionDraft.fromPersistence({
            ...saved,
            'pathDeviationDistanceMeters': value,
          }).pathDeviationDistanceMeters,
          30,
        );
      }
      saved.remove('pathDeviationDistanceMeters');
      expect(
        HikeSessionDraft.fromPersistence(saved).pathDeviationDistanceMeters,
        30,
      );
    },
  );

  test(
    'active hike JSON restart and unrelated draft edits retain the selected distance',
    () {
      final draft = HikeSessionDraft.fromTrail(trail)
          .copyWith(pathDeviationDistanceMeters: 17)
          .copyWith(
            shareLiveLocation: true,
            completedChecklistItems: {'water'},
          );
      final hike = ActiveHikeSession.fromDraft(draft);
      final restored = ActiveHikeSession.fromPersistence(
        Map<String, dynamic>.from(
          jsonDecode(jsonEncode(hike.toPersistence())) as Map,
        ),
      );
      expect(restored.draft.pathDeviationDistanceMeters, 17);
      expect(restored.draft.shareLiveLocation, isTrue);
      expect(restored.draft.completedChecklistItems, {'water'});
      expect(
        draft.copyWith(pathDeviationEnabled: false).pathDeviationDistanceMeters,
        17,
      );
    },
  );

  testWidgets(
    'slider allows both bounds, updates the label and keeps the value when disabled',
    (tester) async {
      var distance = 30;
      var enabled = true;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return PathDeviationDistanceSetting(
                  value: distance,
                  enabled: enabled,
                  onChanged: (value) => setState(() => distance = value),
                );
              },
            ),
          ),
        ),
      );
      final slider = find.byKey(
        const ValueKey('path-deviation-distance-slider'),
      );
      final bounds = tester.getRect(slider);
      await tester.tapAt(Offset(bounds.left + 4, bounds.center.dy));
      await tester.pumpAndSettle();
      expect(distance, 10);
      await tester.tapAt(Offset(bounds.right - 4, bounds.center.dy));
      await tester.pumpAndSettle();
      expect(distance, 50);
      expect(find.text('50 m'), findsNWidgets(2));
      rebuild(() => enabled = false);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).onChanged, isNull);
      expect(distance, 50);
      expect(
        find.text('Alerts are off. Your selected distance is kept.'),
        findsOneWidget,
      );
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'distance control fits narrow ${brightness.name} screens with larger text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.green,
                brightness: brightness,
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.8)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: PathDeviationDistanceSetting(
                    value: 30,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(PathDeviationDistanceSetting.accuracyHint),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

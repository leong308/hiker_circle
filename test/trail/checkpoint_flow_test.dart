import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/route_checkpoint_progress.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'package:hiker_circle/trail/View/checkpoint_flow.dart';

void main() {
  testWidgets('leg distance chip opens live progress and destination action', (
    tester,
  ) async {
    int? selected;
    final playback = ValueNotifier(
      const RouteCheckpointProgress(
        progress: .25,
        checkpointFractions: {0: 0, 1: 1},
        checkpointDistancesMeters: {0: 0, 1: 800},
        distanceMeters: 200,
        estimatedDuration: Duration(minutes: 40),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CheckpointFlow(
            checkpoints: const [
              TrailCheckpoint(
                name: 'Start',
                latitude: 3,
                longitude: 101,
                order: 0,
              ),
              TrailCheckpoint(
                name: 'Summit',
                latitude: 3,
                longitude: 101,
                order: 1,
              ),
            ],
            highlightedIndex: null,
            playback: playback,
            onShowOnMap: (i) => selected = i,
          ),
        ),
      ),
    );
    expect(find.text('800 m'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('checkpoint-leg-0-1')));
    await tester.pumpAndSettle();
    expect(find.text('Start → Summit'), findsOneWidget);
    expect(find.text('Distance along the trail'), findsOneWidget);
    expect(
      find.text('About 40 min at the estimated hiking pace'),
      findsOneWidget,
    );
    expect(find.text('25% of this leg · 600 m remaining'), findsOneWidget);
    playback.value = const RouteCheckpointProgress(
      progress: .5,
      checkpointFractions: {0: 0, 1: 1},
      checkpointDistancesMeters: {0: 0, 1: 800},
      distanceMeters: 400,
      estimatedDuration: Duration(minutes: 40),
    );
    await tester.pump();
    expect(find.text('50% of this leg · 400 m remaining'), findsOneWidget);
    await tester.tap(find.text('Show destination on map'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    await tester.pumpWidget(const SizedBox());
    playback.dispose();
  });

  testWidgets(
    'timeline follows map progress, pauses, finish and replay; swiping allows manual browsing',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final playback = ValueNotifier(const RouteCheckpointProgress());
      addTearDown(playback.dispose);
      final checkpoints = List.generate(
        6,
        (i) => TrailCheckpoint(
          name: 'Stop $i',
          latitude: 3 + i / 100,
          longitude: 101,
          order: i,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CheckpointFlow(
              checkpoints: checkpoints,
              highlightedIndex: null,
              playback: playback,
              onShowOnMap: (_) {},
            ),
          ),
        ),
      );
      const fractions = {0: 0.0, 1: .1, 2: .2, 3: .5, 4: .8, 5: 1.0};
      void move(double value) => playback.value = RouteCheckpointProgress(
        progress: value,
        checkpointFractions: fractions,
      );
      ScrollPosition scroll() => tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(const ValueKey('checkpoint-timeline-scroll')),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      move(.6);
      await tester.pump();
      await tester.pump();
      expect(find.text('Next · Stop 4'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
      expect(scroll().pixels, greaterThan(300));
      final pausedOffset = scroll().pixels;
      await tester.pump(const Duration(seconds: 1));
      expect(scroll().pixels, pausedOffset); // No independent animation clock.
      await tester.drag(
        find.byKey(const ValueKey('checkpoint-timeline-scroll')),
        const Offset(160, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Follow'), findsOneWidget);
      final manualOffset = scroll().pixels;
      move(.9);
      await tester.pump();
      expect(scroll().pixels, manualOffset);
      await tester.tap(find.text('Follow'));
      await tester.pump();
      await tester.pump();
      expect(scroll().pixels, greaterThan(manualOffset));
      move(1);
      await tester.pumpAndSettle();
      expect(find.text('Route complete'), findsOneWidget);
      move(0);
      await tester.pumpAndSettle();
      expect(find.text('Next · Stop 1'), findsOneWidget);
      expect(scroll().pixels, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'sorts checkpoint order and preserves original map-action index with large text',
    (tester) async {
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: CheckpointFlow(
              checkpoints: const [
                TrailCheckpoint(
                  name: 'Finish with a long descriptive name',
                  latitude: 3,
                  longitude: 101,
                  order: 2,
                ),
                TrailCheckpoint(
                  name: 'Start',
                  latitude: 3,
                  longitude: 101,
                  order: 1,
                ),
              ],
              highlightedIndex: null,
              onShowOnMap: (index) => selected = index,
            ),
          ),
        ),
      );
      final first = tester.getTopLeft(
        find.byKey(const ValueKey('checkpoint-stop-1')),
      );
      final second = tester.getTopLeft(
        find.byKey(const ValueKey('checkpoint-stop-0')),
      );
      expect(first.dx, lessThan(second.dx));
      await tester.tap(find.byTooltip('Show on map').first);
      expect(selected, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('checkpoint selection and map action in $brightness', (
      tester,
    ) async {
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CheckpointFlow(
                checkpoints: const [
                  TrailCheckpoint(
                    name: 'Trailhead',
                    latitude: 3,
                    longitude: 101,
                    order: 1,
                  ),
                  TrailCheckpoint(
                    name: 'Summit',
                    latitude: 3.1,
                    longitude: 101.1,
                    order: 2,
                  ),
                ],
                highlightedIndex: null,
                onShowOnMap: (i) => selected = i,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Trailhead'), findsOneWidget);
      expect(find.text('Summit'), findsOneWidget);
      final start = tester.getTopLeft(
        find.byKey(const ValueKey('checkpoint-stop-0')),
      );
      final end = tester.getTopLeft(
        find.byKey(const ValueKey('checkpoint-stop-1')),
      );
      expect(start.dy, end.dy);
      expect(end.dx, greaterThan(start.dx));
      expect(find.byType(ExpansionTile), findsNothing);
      expect(selected, isNull);
      await tester.tap(find.byTooltip('Show on map').last);
      expect(selected, 1);
      expect(find.text('Show on map'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

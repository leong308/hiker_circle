import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'package:hiker_circle/trail/View/checkpoint_flow.dart';

void main() {
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
      expect(find.text('3.00000, 101.00000'), findsOneWidget);
      expect(find.text('3.10000, 101.10000'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(selected, isNull);
      await tester.tap(find.byTooltip('Show on map').last);
      expect(selected, 1);
      expect(find.text('Show on map'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

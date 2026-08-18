import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/map_controls.dart';

void main() {
  testWidgets('MapScaleBar tolerates non-finite camera values', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MapScaleBar(zoom: double.nan, latitude: double.infinity),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(MapScaleBar), findsOneWidget);
  });
}

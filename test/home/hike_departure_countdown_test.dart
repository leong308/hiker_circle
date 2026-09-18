import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/View/hike_departure_countdown.dart';

void main() {
  testWidgets(
    'seconds tick, roll into minutes, respect disabled state and dispose',
    (tester) async {
      var now = DateTime(2026, 9, 20, 8);
      final departure = now.add(const Duration(minutes: 1));
      Future<void> show(bool enabled) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HikeDepartureCountdown(
                departure: departure,
                now: () => now,
                enabled: enabled,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(true);
      expect(find.byKey(const ValueKey('2_1')), findsOneWidget);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('2_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('3_59')), findsOneWidget);
      await show(false);
      now = now.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 10));
      expect(find.byKey(const ValueKey('3_59')), findsOneWidget);
      await show(true);
      expect(find.byKey(const ValueKey('3_49')), findsOneWidget);
      now = departure.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Departure time reached'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );
}

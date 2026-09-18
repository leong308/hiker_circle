import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Model/solo_hike_policy.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/View/solo_hike_distance_dialog.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  HikeSessionDraft draft(double km) => HikeSessionDraft.fromTrail(
    Trail.fromPersistence({
      'trailId': 'route',
      'distanceKm': km,
      'name': 'Test route',
    }),
  );
  test(
    'distance limits use strictly greater than and invalidate changed route acknowledgement',
    () {
      expect(SoloHikePolicy.requiresAcknowledgement(10), false);
      expect(SoloHikePolicy.requiresAcknowledgement(10.001), true);
      expect(SoloHikePolicy.requiresAcknowledgement(20), true);
      expect(SoloHikePolicy.requiresGroup(20), false);
      expect(SoloHikePolicy.requiresGroup(20.001), true);
      final ack = draft(15).copyWith(soloDistanceAcknowledgedKm: 15);
      final restored = HikeSessionDraft.fromPersistence(ack.toPersistence());
      expect(restored.soloDistanceAcknowledgedKm, 15);
      expect(
        ack
            .copyWith(trail: ack.trail.copyWith(distanceKm: 16))
            .soloDistanceAcknowledgedKm,
        isNull,
      );
    },
  );
  testWidgets(
    'solo can acknowledge 15 km but cannot bypass group requirement at 21 km',
    (tester) async {
      HikeSessionDraft? result;
      Future<void> open(double km) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await confirmSoloHikeDistance(context, draft(km));
                  },
                  child: const Text('Start'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Start'));
        await tester.pumpAndSettle();
      }

      await open(15);
      await tester.tap(find.text('Acknowledge & continue solo'));
      await tester.pumpAndSettle();
      expect(result?.soloDistanceAcknowledgedKm, 15);
      await open(21);
      expect(find.text('Group hike required'), findsOneWidget);
      expect(find.text('Acknowledge & continue solo'), findsNothing);
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    },
  );
}

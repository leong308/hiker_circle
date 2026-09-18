import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/route_checkpoint_progress.dart';

void main() {
  test(
    'leg distance follows stored route length even for repeated coordinates',
    () {
      const value = RouteCheckpointProgress(
        checkpointDistancesMeters: {0: 0, 1: 450, 2: 1500},
        distanceMeters: 975,
      );
      expect(value.legDistanceMeters(0, 1), 450);
      expect(value.legDistanceMeters(1, 2), 1050);
      expect(value.legProgress(1, 2), .5);
      expect(value.legProgress(0, 1), 1);
      expect(value.legDistanceMeters(2, 0), isNull);
      expect(value.legDistanceMeters(0, 3), isNull);
    },
  );

  test('timeline follows unequal route legs and ordered return visits', () {
    const fractions = {2: 0.0, 0: .2, 1: .8, 3: 1.0};
    const order = [2, 0, 1, 3];
    RouteCheckpointProgress at(double p) =>
        RouteCheckpointProgress(progress: p, checkpointFractions: fractions);
    expect(at(.1).positionIn(order), closeTo(.5, 1e-9));
    expect(at(.5).positionIn(order), closeTo(1.5, 1e-9));
    expect(at(.2).nextIndex, 1);
    expect(at(.9).nextIndex, 3); // Final visit is distinct from the start.
    expect(at(1).positionIn(order), 3);
    expect(at(1).isComplete, isTrue);
    expect(at(0).positionIn(order), 0);
  });
  test('unknown routes and shared checkpoint fractions remain finite', () {
    expect(const RouteCheckpointProgress().isReady, isFalse);
    expect(const RouteCheckpointProgress().positionIn([]), 0);
    const same = RouteCheckpointProgress(
      progress: .5,
      checkpointFractions: {0: 0, 1: .5, 2: .5, 3: 1},
    );
    expect(same.positionIn([0, 1, 2, 3]), 2);
    expect(same.nextIndex, 3);
  });
}

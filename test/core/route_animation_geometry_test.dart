import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/route_animation_geometry.dart';

void main() {
  test('out and back crossings match checkpoints in itinerary order', () {
    // A B F C E D E C F B A: D is the summit. E and F glow on return.
    const route = [0, 1, 5, 2, 4, 3, 4, 2, 5, 1, 0];
    const stops = [0, 1, 2, 3, 4, 5, 0];
    final matches = orderedCheckpointMatches([
      for (final stop in stops)
        [for (final vertex in route) (stop - vertex).abs().toDouble()],
    ]);
    expect(matches, [0, 1, 3, 5, 6, 8, 10]);
  });
  test('identical out and back positions do not glow together', () {
    const route = [0, 1, 2, 3, 2, 1, 0];
    expect(
      orderedCheckpointMatches([
        for (final stop in route)
          [for (final vertex in route) (stop - vertex).abs().toDouble()],
      ]),
      [0, 1, 2, 3, 4, 5, 6],
    );
  });
  test('tail discards old route geometry by distance', () {
    expect(cometTailStart([0, 10, 20, 100, 110, 120, 130], 6, 30), 3);
    expect(cometTailStart([0, 10, 20, 100, 110, 120, 130], 2, 30), 0);
    expect(orderedCheckpointMatches([]), isEmpty);
  });
}

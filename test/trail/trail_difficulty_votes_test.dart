import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  test('legacy administrator difficulty is not treated as a hiker result', () {
    final trail = Trail.fromPersistence({'difficulty': 'moderate'});

    expect(trail.difficulty, 'Moderate');
    expect(trail.difficultyRatingCount, 0);
    expect(trail.hasCommunityDifficulty, isFalse);
    expect(trail.toFirestore().containsKey('difficulty'), isFalse);
  });

  test('community difficulty votes round-trip with their breakdown', () {
    final trail = Trail.fromPersistence({
      'difficulty': 'hard',
      'difficultyVoteCounts': {'easy': 1, 'moderate': 2, 'hard': 5},
    });

    expect(trail.hasCommunityDifficulty, isTrue);
    expect(trail.difficulty, 'Hard');
    expect(trail.difficultyRatingCount, 8);
    expect(trail.difficultyVoteFraction('easy'), closeTo(0.125, 0.0001));
    expect(trail.difficultyVoteFraction('moderate'), closeTo(0.25, 0.0001));
    expect(trail.difficultyVoteFraction('hard'), closeTo(0.625, 0.0001));
    expect(trail.toFirestore()['difficultyVoteCounts'], {
      'easy': 1,
      'moderate': 2,
      'hard': 5,
    });
  });
}

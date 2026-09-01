'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  trailDifficultyAggregate,
  trailRatingAggregate,
  validDifficultyVote,
  validRating,
} = require('../trail_rating_helpers');

test('rating validation accepts only whole stars from one to five', () => {
  assert.equal(validRating(1), true);
  assert.equal(validRating(5), true);
  assert.equal(validRating(3.5), false);
  assert.equal(validRating(0), false);
  assert.equal(validRating(6), false);
});

test('difficulty accepts only the three hiker-facing levels', () => {
  assert.equal(validDifficultyVote('easy'), true);
  assert.equal(validDifficultyVote('Moderate'), true);
  assert.equal(validDifficultyVote('hard'), true);
  assert.equal(validDifficultyVote('expert'), false);
  assert.equal(validDifficultyVote(''), false);
});

test('first difficulty vote creates the community aggregate', () => {
  assert.deepEqual(
    trailDifficultyAggregate({}, null, 'hard'),
    {
      difficulty: 'hard',
      difficultyVoteCounts: { easy: 0, moderate: 0, hard: 1 },
      difficultyRatingCount: 1,
      difficultyScoreAverage: 3,
    }
  );
});

test('community difficulty is derived from the weighted hiker votes', () => {
  assert.deepEqual(
    trailDifficultyAggregate(
      { difficultyVoteCounts: { easy: 2, moderate: 3, hard: 1 } },
      null,
      'hard'
    ),
    {
      difficulty: 'moderate',
      difficultyVoteCounts: { easy: 2, moderate: 3, hard: 2 },
      difficultyRatingCount: 7,
      difficultyScoreAverage: 2,
    }
  );
});

test('resubmitting replaces the previous difficulty vote', () => {
  assert.deepEqual(
    trailDifficultyAggregate(
      { difficultyVoteCounts: { easy: 1, moderate: 2, hard: 1 } },
      'easy',
      'hard'
    ),
    {
      difficulty: 'hard',
      difficultyVoteCounts: { easy: 0, moderate: 2, hard: 2 },
      difficultyRatingCount: 4,
      difficultyScoreAverage: 2.5,
    }
  );
});

test('first real rating replaces a legacy dummy average', () => {
  assert.deepEqual(
    trailRatingAggregate({ ratingAverage: 4.5 }, null, 3),
    { ratingCount: 1, ratingSum: 3, ratingAverage: 3 }
  );
});

test('new ratings update the aggregate', () => {
  assert.deepEqual(
    trailRatingAggregate(
      { ratingCount: 2, ratingSum: 8, ratingAverage: 4 },
      null,
      5
    ),
    { ratingCount: 3, ratingSum: 13, ratingAverage: 4.33 }
  );
});

test('resubmitting the same completed hike replaces its prior rating', () => {
  assert.deepEqual(
    trailRatingAggregate(
      { ratingCount: 3, ratingSum: 13, ratingAverage: 4.33 },
      5,
      2
    ),
    { ratingCount: 3, ratingSum: 10, ratingAverage: 3.33 }
  );
});

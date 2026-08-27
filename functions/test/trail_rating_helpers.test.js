'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  trailRatingAggregate,
  validRating,
} = require('../trail_rating_helpers');

test('rating validation accepts only whole stars from one to five', () => {
  assert.equal(validRating(1), true);
  assert.equal(validRating(5), true);
  assert.equal(validRating(3.5), false);
  assert.equal(validRating(0), false);
  assert.equal(validRating(6), false);
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

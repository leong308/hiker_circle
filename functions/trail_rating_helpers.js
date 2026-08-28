'use strict';

function validRating(value) {
  const rating = Number(value);
  return Number.isInteger(rating) && rating >= 1 && rating <= 5;
}

function trailRatingAggregate(trail, previousRating, nextRating) {
  if (!validRating(nextRating)) {
    throw new TypeError('Rating must be an integer from 1 to 5.');
  }

  const rawCount = Number(trail?.ratingCount);
  const ratingCount = Number.isInteger(rawCount) && rawCount > 0
    ? rawCount
    : 0;
  const rawSum = Number(trail?.ratingSum);
  const fallbackAverage = Number(trail?.ratingAverage);
  const ratingSum = Number.isFinite(rawSum) && rawSum >= 0
    ? rawSum
    : ratingCount > 0 && Number.isFinite(fallbackAverage)
      ? fallbackAverage * ratingCount
      : 0;
  const replacing = ratingCount > 0 && validRating(previousRating);
  const nextCount = replacing ? ratingCount : ratingCount + 1;
  const nextSum = replacing
    ? Math.max(0, ratingSum - Number(previousRating) + Number(nextRating))
    : ratingSum + Number(nextRating);

  return {
    ratingCount: nextCount,
    ratingSum: Math.round(nextSum * 10000) / 10000,
    ratingAverage: Math.round((nextSum / nextCount) * 100) / 100,
  };
}

module.exports = { trailRatingAggregate, validRating };

// Completed-hike rating aggregates derive public trail scores and community difficulty from valid votes.
'use strict';

function validRating(value) {
  const rating = Number(value);
  return Number.isInteger(rating) && rating >= 1 && rating <= 5;
}

const difficultyValues = Object.freeze(['easy', 'moderate', 'hard']);

function validDifficultyVote(value) {
  return difficultyValues.includes(String(value || '').trim().toLowerCase());
}

function normalizedDifficultyVote(value) {
  const difficulty = String(value || '').trim().toLowerCase();
  if (!validDifficultyVote(difficulty)) {
    throw new TypeError('Difficulty must be easy, moderate, or hard.');
  }
  return difficulty;
}

function communityDifficultyFromVotes(rawCounts) {
  const counts = difficultyValues.map(key => {
    const value = Number(rawCounts?.[key]);
    return Number.isInteger(value) && value > 0 ? value : 0;
  });
  const total = counts.reduce((sum, value) => sum + value, 0);
  if (!total) return null;
  const average = (counts[0] + counts[1] * 2 + counts[2] * 3) / total;
  return average < 1.5 ? 'easy' : average < 2.5 ? 'moderate' : 'hard';
}

// trailDifficultyAggregate: Recompute community difficulty while keeping a defined unrated result.
function trailDifficultyAggregate(trail, previousDifficulty, nextDifficulty) {
  const next = normalizedDifficultyVote(nextDifficulty);
  const previous = validDifficultyVote(previousDifficulty)
    ? normalizedDifficultyVote(previousDifficulty)
    : null;
  const rawCounts = trail?.difficultyVoteCounts;
  const counts = Object.fromEntries(
    difficultyValues.map((difficulty) => {
      const value = Number(rawCounts?.[difficulty]);
      return [
        difficulty,
        Number.isInteger(value) && value > 0 ? value : 0,
      ];
    })
  );

  if (previous && counts[previous] > 0) counts[previous] -= 1;
  counts[next] += 1;

  const difficultyRatingCount = difficultyValues.reduce(
    (total, difficulty) => total + counts[difficulty],
    0
  );
  const scoreSum = counts.easy + counts.moderate * 2 + counts.hard * 3;
  const average = scoreSum / difficultyRatingCount;
  const difficulty = communityDifficultyFromVotes(counts);

  return {
    difficulty,
    difficultyVoteCounts: counts,
    difficultyRatingCount,
    difficultyScoreAverage: Math.round(average * 100) / 100,
  };
}

// trailRatingAggregate: Derive rating totals from validated completed-hike votes rather than trusting client counters.
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

module.exports = {
  communityDifficultyFromVotes,
  trailDifficultyAggregate,
  trailRatingAggregate,
  validDifficultyVote,
  validRating,
};

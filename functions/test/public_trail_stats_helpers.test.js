const test = require('node:test');
const assert = require('node:assert/strict');
const { publicTrailStats } = require('../public_trail_stats_helpers');
const trail = overrides => ({ isVerifiedTrail: false, ratingAverage: 0,
  checkpoints: [{ name: 'Start' }, { name: 'End' }], distanceKm: 2.25,
  state: 'Penang', difficulty: 'Easy', difficultyVoteCounts: {easy: 1}, ...overrides });

test('catalogue totals count each route once and normalize regions and difficulty', () => {
  assert.deepEqual(publicTrailStats([
    trail({}), trail({state: 'Pulau Pinang', difficultyVoteCounts: {moderate: 2}}),
    trail({state: 'Wilayah Persekutuan Kuala Lumpur', difficultyVoteCounts: {hard: 1}}),
  ]), { totalTrails: 3, trailDistanceKm: 6.8, regionsCovered: 2,
    easyTrails: 1, moderateTrails: 1, hardTrails: 1 });
});
test('incomplete catalogue entries and invalid numeric values do not inflate totals', () => {
  const missing = trail({}); delete missing.ratingAverage;
  assert.deepEqual(publicTrailStats([missing, trail({checkpoints: [{name: 'Start'}, {}]}),
    trail({distanceKm: NaN, state: 'unknown', difficultyVoteCounts: {}})]),
  {totalTrails: 1, trailDistanceKm: 0, regionsCovered: 0, easyTrails: 0, moderateTrails: 0, hardTrails: 0});
  assert.equal(publicTrailStats([]).totalTrails, 0);
});
test('difficulty uses actual votes, not imported labels, with app threshold rules', () => {
  const stats = publicTrailStats([
    trail({difficulty: 'hard', difficultyVoteCounts: null}),
    trail({difficulty: 'hard', difficultyVoteCounts: {easy: 3}}),
    trail({difficulty: 'easy', difficultyVoteCounts: {easy: 1, moderate: 1}}),
    trail({difficulty: 'easy', difficultyVoteCounts: {moderate: 1, hard: 1}}),
    trail({difficultyVoteCounts: {easy: -1, moderate: 1.5, hard: 'invalid'}}),
  ]);
  assert.equal(stats.totalTrails, 5);
  assert.equal(stats.easyTrails, 1);
  assert.equal(stats.moderateTrails, 1);
  assert.equal(stats.hardTrails, 1);
});

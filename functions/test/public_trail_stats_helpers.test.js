const test = require('node:test');
const assert = require('node:assert/strict');
const { publicTrailStats } = require('../public_trail_stats_helpers');
const trail = overrides => ({ isVerifiedTrail: false, ratingAverage: 0,
  checkpoints: [{ name: 'Start' }, { name: 'End' }], distanceKm: 2.25,
  state: 'Penang', difficulty: 'Easy', ...overrides });

test('catalogue totals count each route once and normalize regions and difficulty', () => {
  assert.deepEqual(publicTrailStats([
    trail({}), trail({state: 'Pulau Pinang', difficulty: 'Moderate'}),
    trail({state: 'Wilayah Persekutuan Kuala Lumpur', difficulty: 'HARD'}),
  ]), { totalTrails: 3, trailDistanceKm: 6.8, regionsCovered: 2,
    easyTrails: 1, moderateTrails: 1, hardTrails: 1 });
});
test('incomplete catalogue entries and invalid numeric values do not inflate totals', () => {
  const missing = trail({}); delete missing.ratingAverage;
  assert.deepEqual(publicTrailStats([missing, trail({checkpoints: [{name: 'Start'}, {}]}),
    trail({distanceKm: NaN, state: 'unknown', difficulty: 'unknown'})]),
  {totalTrails: 1, trailDistanceKm: 0, regionsCovered: 0, easyTrails: 0, moderateTrails: 0, hardTrails: 0});
  assert.equal(publicTrailStats([]).totalTrails, 0);
});

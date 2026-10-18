// Public trail totals mirror catalogue eligibility, rating-derived difficulty, and Malaysian region rules.
'use strict';

const { malaysiaStateSlug } = require('./achievement_helpers');
const { communityDifficultyFromVotes } = require('./trail_rating_helpers');

// Mirror the catalogue's required ordering fields and named-checkpoint filter.
// Return only aggregate numbers, never trail documents or contributor details.
// publicTrailStats: Count only catalogue-eligible trails and derive difficulty from current community votes.
function publicTrailStats(trails) {
  const totals = { totalTrails: 0, trailDistanceKm: 0, regionsCovered: 0,
    easyTrails: 0, moderateTrails: 0, hardTrails: 0 };
  const regions = new Set();
  for (const trail of trails) {
    if (!trail || !Object.hasOwn(trail, 'isVerifiedTrail') ||
        !Object.hasOwn(trail, 'ratingAverage') || !Array.isArray(trail.checkpoints) ||
        trail.checkpoints.filter(point => point && typeof point.name === 'string' && point.name.trim()).length < 2) continue;
    totals.totalTrails++;
    if (typeof trail.distanceKm === 'number' && Number.isFinite(trail.distanceKm) && trail.distanceKm > 0) {
      totals.trailDistanceKm += trail.distanceKm;
    }
    const state = String(trail.state || '').trim().toLowerCase();
    const territory = state.replace(/^wilayah persekutuan\s+/, '').replace(/^w\.?p\.?\s+/, '');
    const region = malaysiaStateSlug(state) || (['kuala lumpur', 'putrajaya', 'labuan'].includes(territory) ? territory : '');
    if (region) regions.add(region);
    const difficulty = communityDifficultyFromVotes(trail.difficultyVoteCounts);
    if (['easy', 'moderate', 'hard'].includes(difficulty)) totals[`${difficulty}Trails`]++;
  }
  totals.trailDistanceKm = Math.round(totals.trailDistanceKm * 10) / 10;
  totals.regionsCovered = regions.size;
  return totals;
}

module.exports = { publicTrailStats };

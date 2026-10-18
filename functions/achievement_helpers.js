// Achievement event identities and progress hashes, including Malaysian state reward rules.
'use strict';

const crypto = require('crypto');

const MALAYSIA_STATE_SLUGS = new Set([
  'johor',
  'kedah',
  'kelantan',
  'malacca',
  'negeri-sembilan',
  'pahang',
  'penang',
  'perak',
  'perlis',
  'sabah',
  'sarawak',
  'selangor',
  'terengganu',
]);

function achievementSlug(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 120);
}

function malaysiaStateSlug(value) {
  const slug = achievementSlug(value);
  const canonical = slug === 'melaka'
    ? 'malacca'
    : slug === 'pulau-pinang'
      ? 'penang'
      : slug;
  return MALAYSIA_STATE_SLUGS.has(canonical) ? canonical : '';
}

// completedHikeAchievementEvents: Use stable event keys so retries cannot award the same hike, trail, or state twice.
function completedHikeAchievementEvents({ sessionId, trailId, state, country }) {
  const normalizedSessionId = String(sessionId || '').trim();
  if (!normalizedSessionId) return [];

  const events = [
    {
      metricKey: 'hike_completed',
      eventKey: `hike-completed:${normalizedSessionId}`,
    },
  ];
  const normalizedTrailId = String(trailId || '').trim();
  if (normalizedTrailId) {
    events.push({
      metricKey: 'distinct_trail_completed',
      eventKey: `distinct-trail-completed:${achievementSlug(normalizedTrailId)}`,
    });
  }
  const normalizedCountry = achievementSlug(country);
  const normalizedState = malaysiaStateSlug(state);
  if (normalizedCountry === 'malaysia' && normalizedState) {
    events.push({
      metricKey: 'malaysia_state_hiked',
      eventKey: `malaysia-state-hiked:${normalizedState}`,
    });
  }
  return events;
}

// achievementProgressHash: Hash sorted achievement progress so unchanged mobile state can be reused.
function achievementProgressHash({ definitions = [], awards = [] }) {
  const awardsById = new Map(
    awards.map((award) => [String(award.achievementId || ''), award]),
  );
  const normalizedRows = definitions
    .map((definition) => {
      const achievementId = String(definition.achievementId || '');
      const award = awardsById.get(achievementId);
      if (definition.isActive === false && !award) return null;
      const rewardType = String(definition.rewardType || '') === 'cumulative'
        ? 'cumulative'
        : 'one_time';
      const targetCount = rewardType === 'one_time'
        ? 1
        : Math.max(1, Number(definition.targetCount || 1));
      const isUnlocked = award?.isUnlocked === true
        || award?.awardedAt != null
        || award?.awardedAtLocal != null;
      const progressCount = isUnlocked
        ? targetCount
        : Math.max(0, Math.min(targetCount, Number(award?.progressCount || 0)));
      const awardedAtLocal = award?.awardedAtLocal
        || (typeof award?.awardedAt?.toDate === 'function'
          ? award.awardedAt.toDate().toISOString()
          : '');
      const rewardPoints = Number(definition.rewardPoints || 0);
      return [
      achievementId,
      String(definition.title || ''),
      String(definition.condition || ''),
      String(definition.category || ''),
      String(definition.iconName || ''),
      rewardPoints,
      isUnlocked
        ? (Number(award?.pointsAwarded || 0) > 0
          ? Number(award.pointsAwarded)
          : rewardPoints)
        : 0,
      rewardType,
      String(definition.metricKey || ''),
      targetCount,
      progressCount,
      Number(definition.sortOrder || 0),
      Number(definition.accentColorValue || 0),
      definition.isActive !== false,
      isUnlocked,
      String(awardedAtLocal),
    ];
    })
    .filter(Boolean)
    .sort((left, right) => left[0].localeCompare(right[0]));
  return crypto
    .createHash('sha256')
    .update(JSON.stringify(normalizedRows))
    .digest('hex');
}

module.exports = {
  achievementProgressHash,
  achievementSlug,
  completedHikeAchievementEvents,
  malaysiaStateSlug,
};

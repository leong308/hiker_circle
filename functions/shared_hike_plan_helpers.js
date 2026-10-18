// Shared hike plans project route and timing fields while excluding each participant's private safety settings.
'use strict';

const SHARED_HIKE_PLAN_PRIVACY_VERSION = 1;

const SHARED_HIKE_PLAN_FIELDS = Object.freeze([
  'hikeType',
  'trail',
  'startPointName',
  'destinationName',
  'departureTime',
  'expectedArrivalTime',
  'expectedReturnTime',
  'teamBuddies',
  'customCheckpoints',
]);

const SHARED_HIKE_PLAN_FIELD_SET = new Set(SHARED_HIKE_PLAN_FIELDS);

function planObject(value) {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value
    : {};
}

// projectSharedHikePlan: Copy only the explicit public planning allowlist, excluding participant safety preferences.
function projectSharedHikePlan(rawPlan) {
  const plan = planObject(rawPlan);
  const projected = {};
  for (const field of SHARED_HIKE_PLAN_FIELDS) {
    if (Object.hasOwn(plan, field) && plan[field] !== undefined) {
      projected[field] = plan[field];
    }
  }
  return projected;
}

function sharedHikePlanNeedsRedaction(rawPlan) {
  if (
    rawPlan != null
    && (typeof rawPlan !== 'object' || Array.isArray(rawPlan))
  ) {
    return true;
  }
  const plan = planObject(rawPlan);
  return Object.keys(plan).some((field) => !SHARED_HIKE_PLAN_FIELD_SET.has(field));
}

function dateMillis(value) {
  if (value && typeof value.toMillis === 'function') return value.toMillis();
  if (value && typeof value.toDate === 'function') {
    return value.toDate().getTime();
  }
  if (typeof value === 'number') return value;
  return typeof value === 'string' ? Date.parse(value) : Number.NaN;
}

function normalizedCheckpoints(value) {
  if (!Array.isArray(value)) return [];
  return value.map((checkpoint) => {
    const data = planObject(checkpoint);
    return {
      name: String(data.name || data.label || '').trim(),
      latitude: Number(data.latitude),
      longitude: Number(data.longitude),
      order: Number(data.order),
    };
  });
}

function sharedRouteAndTimingMatch(candidatePlan, canonicalPlan) {
  const candidate = planObject(candidatePlan);
  const canonical = planObject(canonicalPlan);
  const candidateTrail = planObject(candidate.trail);
  const canonicalTrail = planObject(canonical.trail);
  if (
    String(candidateTrail.trailId || '').trim()
      !== String(canonicalTrail.trailId || '').trim()
    || String(candidate.startPointName || '').trim()
      !== String(canonical.startPointName || '').trim()
    || String(candidate.destinationName || '').trim()
      !== String(canonical.destinationName || '').trim()
  ) {
    return false;
  }
  for (const field of [
    'departureTime',
    'expectedArrivalTime',
    'expectedReturnTime',
  ]) {
    const candidateMillis = dateMillis(candidate[field]);
    const canonicalMillis = dateMillis(canonical[field]);
    if (
      !Number.isFinite(candidateMillis)
      || !Number.isFinite(canonicalMillis)
      || Math.abs(candidateMillis - canonicalMillis) > 1000
    ) {
      return false;
    }
  }
  return JSON.stringify(normalizedCheckpoints(candidate.customCheckpoints))
    === JSON.stringify(normalizedCheckpoints(canonical.customCheckpoints));
}

// teamSourceMatchesRequest: Match the shared source and route timing before a caller can adopt team state.
function teamSourceMatchesRequest(team, requestedSourceUpcomingHikeId) {
  const teamData = planObject(team);
  return String(teamData.sourceUpcomingHikeId || '').trim()
    === String(requestedSourceUpcomingHikeId || '').trim();
}

function scheduledTeamLaunchCanResume(
  existingTeam,
  upcomingHike,
  teamHikeSessionId,
  sourceUpcomingHikeId
) {
  const team = planObject(existingTeam);
  const upcoming = planObject(upcomingHike);
  const sourceId = String(sourceUpcomingHikeId || '').trim();
  const teamId = String(teamHikeSessionId || '').trim();
  const startedPhones = Array.isArray(upcoming.startedParticipantPhones)
    ? upcoming.startedParticipantPhones
    : [];
  return Boolean(
    sourceId
    && teamId
    && String(team.phase || '') === 'completed'
    && String(upcoming.teamHikeSessionId || '').trim() === teamId
    && !startedPhones.some((phone) => Boolean(String(phone || '').trim()))
  );
}

function legacyActiveHikeCanAdoptTeamSource(
  existingHike,
  requestedSourceUpcomingHikeId,
  requestedTeamHikeSessionId
) {
  const existing = planObject(existingHike);
  const requestedSource = String(requestedSourceUpcomingHikeId || '').trim();
  const requestedTeam = String(requestedTeamHikeSessionId || '').trim();
  return Boolean(
    requestedSource
    && requestedTeam
    && !String(existing.sourceUpcomingHikeId || '').trim()
    && String(existing.teamHikeSessionId || '').trim() === requestedTeam
  );
}

module.exports = {
  SHARED_HIKE_PLAN_PRIVACY_VERSION,
  projectSharedHikePlan,
  sharedHikePlanNeedsRedaction,
  sharedRouteAndTimingMatch,
  teamSourceMatchesRequest,
  scheduledTeamLaunchCanResume,
  legacyActiveHikeCanAdoptTeamSource,
};

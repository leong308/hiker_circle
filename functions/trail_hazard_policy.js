// Server-owned trail issue categories and risk framing. Community evidence remains unverified until reviewed.
'use strict';

const HAZARD_POLICY_VERSION = 2;
const REPORT_LIFETIME_MS = 7 * 86400000;
const HAZARD_CATEGORIES = Object.freeze({
  'Trail surface': Object.freeze(['Slippery pathway', 'Loose rock', 'Deep mud', 'Ice or snow',
    'Eroded pathway', 'Unstable ground', 'Exposed roots', 'Collapsed trail edge']),
  'Blocked route': Object.freeze(['Fallen tree', 'Landslide', 'Closed trail', 'Other obstruction',
    'Dense overgrowth', 'Blocked trail entrance', 'Fallen branches']),
  Water: Object.freeze(['Flooded route', 'Fast river crossing', 'Damaged bridge',
    'High water level', 'Strong current', 'Washed-out crossing', 'Contaminated water']),
  // Malaysian weather hazards; keep labels in sync with the mobile report catalog.
  Weather: Object.freeze(['Heavy rain', 'Thunderstorm or lightning', 'Strong wind',
    'Heat and humidity', 'Haze', 'Poor visibility', 'Cold or wet conditions']),
  Wildlife: Object.freeze(['Wild animal sighting', 'Snakes', 'Stinging insects',
    'Animal activity', 'Animal tracks or den', 'Leeches']),
  'Trail structures': Object.freeze(['Damaged steps', 'Unsafe ladder or rope', 'Missing sign',
    'Damaged handrail', 'Unstable boardwalk', 'Missing trail marker']),
  'Other caution': Object.freeze(['Unsafe human activity', 'Other',
    'Limited mobile signal', 'Illegal dumping']),
});
const TYPE_CATEGORIES = new Map(Object.entries(HAZARD_CATEGORIES)
  .flatMap(([category, types]) => types.map(type => [type, category])));
const FATAL_TYPES = new Set(['Landslide', 'Wild animal sighting', 'Unsafe ladder or rope',
  'Heavy rain', 'Thunderstorm or lightning', 'Hail']);

function classifyHazard(hazardType) {
  // Retired options cannot be submitted, but existing reports keep their risk.
  const hazardCategory = TYPE_CATEGORIES.get(hazardType) || (hazardType === 'Hail' ? 'Weather' : 'Other caution');
  const fatal = hazardCategory === 'Trail surface' || hazardCategory === 'Water' || FATAL_TYPES.has(hazardType);
  return {hazardCategory, severity: fatal ? 'fatal' : 'moderate',
    riskLevel: fatal ? 'fatal' : 'normal', hazardPolicyVersion: HAZARD_POLICY_VERSION};
}

function dateMillis(value) {
  if (typeof value?.toMillis === 'function') return value.toMillis();
  if (typeof value?.toDate === 'function') return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number') return value;
  return typeof value === 'string' ? Date.parse(value) : NaN;
}
function hazardExpiry(report) {
  const explicit = dateMillis(report?.expiresAt);
  if (Number.isFinite(explicit)) return explicit;
  const reported = dateMillis(report?.reportedAt) || dateMillis(report?.reportedAtLocal);
  return reported + REPORT_LIFETIME_MS;
}
function isActiveHazard(report, now = Date.now()) {
  return !!report && !['resolved', 'rejected', 'deleted', 'expired'].includes(String(report.status || '').toLowerCase())
    && Number.isFinite(hazardExpiry(report)) && hazardExpiry(report) > now;
}
function reportCycle(report) {
  return Number.isSafeInteger(report?.cycle) && report.cycle >= 0 ? report.cycle : 0;
}
function upcomingHazardRecipients(hike) {
  return [...new Set([hike?.creatorPhone, ...(Array.isArray(hike?.participantPhones) ? hike.participantPhones : [])]
    .filter(phone => typeof phone === 'string' && /^\+[1-9]\d{7,14}$/.test(phone.trim())).map(phone => phone.trim()))];
}
function isUpcomingHazardHike(hike, now = Date.now(), team) {
  const departure = dateMillis(hike?.departureTimeLocal || hike?.departureTime);
  return !!hike && hike.isDeleted !== true && !hike.startedAt && !hike.startedAtLocal
    && !['active', 'started', 'ended', 'completed', 'cancelled', 'canceled', 'abandoned'].includes(String(hike.status || '').toLowerCase())
    && !(Array.isArray(hike.startedParticipantPhones) && hike.startedParticipantPhones.length)
    && !['active', 'ended', 'completed', 'cancelled', 'canceled', 'abandoned'].includes(String(team?.phase || '').toLowerCase())
    && Number.isFinite(departure) && departure > now && typeof hike.trailId === 'string' && !!hike.trailId;
}

// Describe the actual report instead of inventing claims about what other hikers do.
function hazardAlertMessages(report) {
  if (classifyHazard(report?.hazardType).riskLevel === 'fatal') {
    return {framing: 'negative', title: 'Serious trail caution',
      injunctive: 'Do not start this hike while this serious hazard may be present. We recommend cancelling or choosing another time.',
      descriptive: 'Starting a hike with this hazard could expose you or your group to serious harm.'};
  }
  return {framing: 'positive', title: 'Prepare for a trail caution',
    injunctive: 'Check the caution details and stay alert while hiking.',
    descriptive: 'Knowing where this caution was reported helps you prepare and adjust your route.'};
}

module.exports = {HAZARD_POLICY_VERSION, HAZARD_CATEGORIES, TYPE_CATEGORIES, REPORT_LIFETIME_MS,
  classifyHazard, dateMillis, hazardExpiry, isActiveHazard, reportCycle,
  upcomingHazardRecipients, isUpcomingHazardHike, hazardAlertMessages};

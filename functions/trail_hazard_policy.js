// Server-owned trail issue categories, community lifecycle and risk framing.
'use strict';

const HAZARD_POLICY_VERSION = 2;
const REPORT_LIFETIME_MS = 7 * 86400000;
const CRITICAL_WEATHER_LIFETIME_MS = 24 * 3600000;
const NORMAL_WEATHER_LIFETIME_MS = 12 * 3600000;
const UPCOMING_START_GRACE_MS = 15 * 60000;
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

// Derive category and risk from the shared Malaysian caution catalog.
function classifyHazard(hazardType) {
  // Retired options cannot be submitted, but existing reports keep their risk.
  const hazardCategory = TYPE_CATEGORIES.get(hazardType) || (hazardType === 'Hail' ? 'Weather' : 'Other caution');
  const fatal = hazardCategory === 'Trail surface' || hazardCategory === 'Water' || FATAL_TYPES.has(hazardType);
  return {hazardCategory, severity: fatal ? 'fatal' : 'moderate',
    riskLevel: fatal ? 'fatal' : 'normal', hazardPolicyVersion: HAZARD_POLICY_VERSION};
}

// Accept Firestore timestamps and the persisted legacy date formats.
function dateMillis(value) {
  if (typeof value?.toMillis === 'function') return value.toMillis();
  if (typeof value?.toDate === 'function') return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number') return value;
  return typeof value === 'string' ? Date.parse(value) : NaN;
}
// Give weather reports a risk-based lifetime; other cautions keep their existing window.
function hazardLifetimeMs(hazardType) {
  const policy = classifyHazard(hazardType);
  return policy.hazardCategory === 'Weather'
    ? policy.riskLevel === 'fatal' ? CRITICAL_WEATHER_LIFETIME_MS : NORMAL_WEATHER_LIFETIME_MS
    : REPORT_LIFETIME_MS;
}

// Cap old weather expiries from the original report time without extending shorter explicit limits.
function hazardExpiry(report) {
  const stored = dateMillis(report?.expiresAt);
  const explicit = Number.isFinite(stored) ? stored : dateMillis(report?.expiresAtLocal);
  const serverReported = dateMillis(report?.reportedAt);
  const reported = Number.isFinite(serverReported) ? serverReported : dateMillis(report?.reportedAtLocal);
  const limit = reported + hazardLifetimeMs(report?.hazardType);
  if (!Number.isFinite(explicit)) return limit;
  return classifyHazard(report?.hazardType).hazardCategory === 'Weather' && Number.isFinite(limit)
    ? Math.min(explicit, limit) : explicit;
}
// Group reports by the community workflow; expiry does not require a status write.
function hazardLifecycleStage(report, now = Date.now()) {
  const status = String(report?.status || '').trim().toLowerCase();
  if (['rejected', 'deleted'].includes(status)) return null;
  const count = typeof report?.resolutionCount === 'number' && Number.isFinite(report.resolutionCount)
    ? Math.max(0, report.resolutionCount) : 0;
  const expiry = hazardExpiry(report);
  if (status === 'resolved' || count >= 3 || status === 'expired'
      || (Number.isFinite(expiry) && now >= expiry)) return 'Resolved';
  return count > 0 || (typeof report?.resolutionId === 'string' && report.resolutionId.trim())
    ? 'Resolving' : 'Reported';
}
// Suppress terminal and expired reports before notifying hikers.
function isActiveHazard(report, now = Date.now()) {
  return !!report && !['resolved', 'rejected', 'deleted', 'expired'].includes(String(report.status || '').toLowerCase())
    && Number.isFinite(hazardExpiry(report)) && hazardExpiry(report) > now;
}
// Legacy reports begin at cycle zero; reopening creates a new delivery identity.
function reportCycle(report) {
  return Number.isSafeInteger(report?.cycle) && report.cycle >= 0 ? report.cycle : 0;
}
// Include the creator and confirmed participants, excluding pending invitations.
function upcomingHazardRecipients(hike) {
  return [...new Set([hike?.creatorPhone, ...(Array.isArray(hike?.participantPhones) ? hike.participantPhones : [])]
    .filter(phone => typeof phone === 'string' && /^\+[1-9]\d{7,14}$/.test(phone.trim())).map(phone => phone.trim()))];
}
// Keep unstarted plans eligible until their 15-minute start window closes.
function isUpcomingHazardHike(hike, now = Date.now(), team) {
  const departure = dateMillis(hike?.departureTimeLocal || hike?.departureTime);
  return !!hike && hike.isDeleted !== true && !hike.startedAt && !hike.startedAtLocal
    && !['active', 'started', 'ended', 'completed', 'cancelled', 'canceled', 'abandoned'].includes(String(hike.status || '').toLowerCase())
    && !(Array.isArray(hike.startedParticipantPhones) && hike.startedParticipantPhones.length)
    && !['active', 'ended', 'completed', 'cancelled', 'canceled', 'abandoned'].includes(String(team?.phase || '').toLowerCase())
    && Number.isFinite(departure) && departure + UPCOMING_START_GRACE_MS > now && typeof hike.trailId === 'string' && !!hike.trailId;
}

// activeHazardRecipients: Each active tracking document belongs to one actual hiker, not invited buddies.
function activeHazardRecipients(hike) {
  const phone = typeof hike?.userPhoneNumber === 'string' ? hike.userPhoneNumber.trim() : '';
  return /^\+[1-9]\d{7,14}$/.test(phone) ? [phone] : [];
}

// isActiveHazardHike: Exclude terminal sessions even if a stale document retained an active status.
function isActiveHazardHike(hike) {
  return !!hike && hike.status === 'active' && typeof hike.trailId === 'string' && !!hike.trailId
    && !hike.endedAt && !hike.endedAtLocal && !hike.completedAt && !hike.completedAtLocal
    && !hike.abandonedAt && !hike.abandonedAtLocal && activeHazardRecipients(hike).length > 0;
}

// Describe the actual report instead of inventing claims about what other hikers do.
function hazardAlertMessages(report, {duringHike = false} = {}) {
  if (classifyHazard(report?.hazardType).riskLevel === 'fatal') {
    if (duringHike) return {framing: 'negative', title: 'Serious caution on your trail',
      injunctive: 'Pause in a safe place, review this report and avoid the affected area.',
      descriptive: 'Continuing through this hazard could expose you or your group to serious harm.'};
    return {framing: 'negative', title: 'Serious trail caution',
      injunctive: 'Do not start this hike while this serious hazard may be present. We recommend cancelling or choosing another time.',
      descriptive: 'Starting a hike with this hazard could expose you or your group to serious harm.'};
  }
  return {framing: 'positive', title: 'Prepare for a trail caution',
    injunctive: 'Check the caution details and stay alert while hiking.',
    descriptive: 'Knowing where this caution was reported helps you prepare and adjust your route.'};
}

module.exports = {HAZARD_POLICY_VERSION, HAZARD_CATEGORIES, TYPE_CATEGORIES, REPORT_LIFETIME_MS,
  CRITICAL_WEATHER_LIFETIME_MS, NORMAL_WEATHER_LIFETIME_MS, hazardLifetimeMs,
  classifyHazard, dateMillis, hazardExpiry, hazardLifecycleStage, isActiveHazard, reportCycle,
  upcomingHazardRecipients, isUpcomingHazardHike, hazardAlertMessages,
  activeHazardRecipients, isActiveHazardHike, UPCOMING_START_GRACE_MS};

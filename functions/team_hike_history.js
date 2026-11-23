'use strict';
const {participantKey, participantColors, applyParticipantColors} = require('./team_hike_policy');

// Validate a recorded fix without inventing a point for a member with no GPS.
function recordedLocation(raw) {
  if (!raw || typeof raw.latitude !== 'number' || typeof raw.longitude !== 'number'
    || !Number.isFinite(raw.latitude) || !Number.isFinite(raw.longitude)
    || Math.abs(raw.latitude) > 90 || Math.abs(raw.longitude) > 180) return null;
  const time = Date.parse(String(raw.capturedAtLocal || ''));
  if (!Number.isFinite(time)) return null;
  return {latitude: raw.latitude, longitude: raw.longitude, capturedAtLocal: new Date(time).toISOString()};
}

// Bound shared totals to the same range as individual completion reports.
function metric(value, maximum = 1000000) {
  return typeof value === 'number' && Number.isFinite(value) ? Math.max(0, Math.min(maximum, value)) : 0;
}

// Freeze everyone's recorded locations when a member finishes; the final end replaces this snapshot.
function buildSnapshot(team, nowIso) {
  const roster = Array.isArray(team.participants) ? team.participants : [];
  const members = applyParticipantColors(roster, participantColors(roster, team.participantColorsByPhone))
    .map(p => ({id: participantKey(p), name: String(p.buddy.name || 'Hiker').slice(0, 80),
      color: p.buddy.avatarColorValue, status: String(p.status || ''),
      ...(recordedLocation(p.latestLocation) ? {location: recordedLocation(p.latestLocation)} : {}),
      distanceKm: metric(p.completionMetrics?.distanceKm ?? metric(p.progressMeters) / 1000, 5000),
      routePointCount: Math.round(metric(p.completionMetrics?.routePointCount)),
      endedAtLocal: String(p.endedAtLocal || '')})).sort((a, b) => a.id.localeCompare(b.id));
  const finishedCount = members.filter(p => p.status === 'ended').length;
  const finalized = members.length > 0 && finishedCount === members.length;
  const startedAtLocal = String(team.startedAtLocal || team.createdAtLocal || nowIso);
  const endedAtLocal = members.map(p => p.endedAtLocal).filter(Boolean).sort().at(-1) || nowIso;
  const durationSeconds = Math.max(0, Math.round((Date.parse(endedAtLocal) - Date.parse(startedAtLocal)) / 1000)) || 0;
  return {teamHikeSessionId: String(team.teamHikeSessionId || ''), trailName: String(team.trailName || 'Team hike'),
    generatedAtLocal: nowIso, finalized, finishedCount, memberCount: members.length,
    startedAtLocal, endedAtLocal, durationSeconds, members,
    distanceKm: members.reduce((sum, p) => sum + p.distanceKm, 0),
    routePointCount: members.reduce((sum, p) => sum + p.routePointCount, 0)};
}

// Project one common history identity and aggregate metrics for every team member.
function historySession(team) {
  const snapshot = team.summarySnapshot || buildSnapshot(team, team.endedAtLocal || team.updatedAtLocal || new Date().toISOString());
  return {...(team.draft || {}), trailId: team.trailId, trailName: team.trailName,
    hikeType: 'team', teamHikeSessionId: team.teamHikeSessionId,
    sourceUpcomingHikeId: team.sourceUpcomingHikeId || '',
    teamBuddies: snapshot.members.slice(1).map(p => ({name: p.name})),
    summaryReport: snapshot, startedAtLocal: snapshot.startedAtLocal, endedAtLocal: snapshot.endedAtLocal};
}

// Authorize shared results using canonical membership and this hiker's terminal state.
async function loadDetail(db, teamId, phone, ErrorType, detailBuilder) {
  // Query team hike history by session ID
  const doc = await db.collection('teamHikeSessions').doc(teamId).get();
  const team = {...(doc.data() || {}), teamHikeSessionId: teamId};
  const member = (Array.isArray(team.participants) ? team.participants : []).find(p =>
    String(p.phoneNumber || p.buddy?.phoneNumber || '').trim() === phone);
  if (!doc.exists || !member || member.status !== 'ended' || !team.startedAtLocal) {
    throw new ErrorType('not-found', 'This team hike is not in your completed history.');
  }
  const shared = team.summarySnapshot || buildSnapshot(team, team.updatedAtLocal);
  const detail = detailBuilder({sessionId: `team-history_${teamId}`, session: historySession(team),
    capture: {}, checkIns: [], footprints: [], rating: null});
  return {...detail, teamSummary: shared};
}

module.exports = {recordedLocation, buildSnapshot, historySession, loadDetail};

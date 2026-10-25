// Team notice preflight rejects outdated launch/readiness cycles after cancellation or roster changes.
'use strict';
const {dateMillis} = require('./trail_hazard_policy');
const PREPARING = new Set(['inviting', 'readyCheck', 'countdown']);
const ACTIVE_TYPES = new Set(['team_hike_started', 'team_hike_ping', 'team_hike_ping_ok',
  'team_hike_separation_alert', 'team_hike_path_deviation']);
const HOST_TYPES = new Set(['team_hike_invite', 'team_hike_ready', 'team_hike_countdown',
  'team_hike_started', 'team_hike_completed', 'team_hike_separation_alert']);

function timestampFor(record, localField, serverField) {
  const local = dateMillis(record?.[localField]);
  return Number.isFinite(local) ? local : dateMillis(record?.[serverField]);
}
function sameCurrentCycle(payload, team, localField, serverField, capturedField) {
  const current = timestampFor(team, localField, serverField);
  const captured = dateMillis(payload?.[capturedField]);
  if (Number.isFinite(captured) && (!Number.isFinite(current) || captured !== current)) return false;
  if (!Number.isFinite(current)) return true;
  const created = timestampFor(payload, 'createdAtLocal', 'createdAt');
  return Number.isFinite(created) && created >= current;
}

function teamNoticeIsCurrent(payload, team) {
  const type = String(payload?.type || '');
  const phase = String(team?.phase || '');
  if (type === 'team_hike_ready') {
    return PREPARING.has(phase)
      && sameCurrentCycle(payload, team, 'readinessStartedAtLocal', 'readinessStartedAt', 'teamReadinessStartedAtLocal');
  }
  if (type === 'team_hike_countdown') {
    return phase === 'countdown'
      && sameCurrentCycle(payload, team, 'readinessStartedAtLocal', 'readinessStartedAt', 'teamReadinessStartedAtLocal')
      && sameCurrentCycle(payload, team, 'countdownStartedAtLocal', 'countdownStartedAt', 'teamCountdownStartedAtLocal');
  }
  if (ACTIVE_TYPES.has(type)) {
    return phase === 'active'
      && sameCurrentCycle(payload, team, 'startedAtLocal', 'startedAt', 'teamStartedAtLocal');
  }
  if (type === 'team_hike_completed') {
    return phase === 'completed'
      && sameCurrentCycle(payload, team, 'endedAtLocal', 'endedAt', 'teamEndedAtLocal');
  }
  if (type === 'team_hike_invite' || type === 'team_hike_invite_accepted') {
    return PREPARING.has(phase)
      && sameCurrentCycle(payload, team, 'createdAtLocal', 'createdAt', 'teamCreatedAtLocal');
  }
  return false;
}

function teamNoticeIsAuthorized(payload, team) {
  if (!teamNoticeIsCurrent(payload, team)) return false;
  const host = String(team?.hostPhoneNumber || '');
  const sender = String(payload?.senderPhoneNumber || '');
  const recipient = String(payload?.recipientPhoneNumber || '');
  const type = String(payload?.type || '');
  const participants = new Set((Array.isArray(team?.participants) ? team.participants : [])
    .map(participant => String(participant?.phoneNumber || participant?.buddy?.phoneNumber || '').trim()).filter(Boolean));
  if (!participants.has(recipient)) return false;
  if (HOST_TYPES.has(type)) return sender === host;
  if (type === 'team_hike_invite_accepted') return participants.has(sender) && recipient === host;
  return ['team_hike_ping', 'team_hike_ping_ok', 'team_hike_path_deviation'].includes(type) && participants.has(sender);
}

module.exports = {teamNoticeIsCurrent, teamNoticeIsAuthorized};

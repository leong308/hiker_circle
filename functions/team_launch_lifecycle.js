'use strict';

function teamTrackingStarted(team = {}) {
  return Boolean(team.startedAt || team.startedAtLocal || team.activeHikeSessionId
    || (team.participants || []).some(p => p.activeHikeSessionId || p.status === 'active'));
}

function consumesUpcomingHike(team, phase) {
  return phase === 'active' || teamTrackingStarted(team);
}

module.exports = {teamTrackingStarted, consumesUpcomingHike};

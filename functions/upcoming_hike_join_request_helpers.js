// Upcoming-hike join requests use requester-scoped IDs and terminal lifecycle rules.
'use strict';

const crypto = require('crypto');

function joinRequestDocumentId(hikeId, requesterPhone) {
  const digest = crypto
    .createHash('sha256')
    .update(`${String(hikeId || '').trim()}:${String(requesterPhone || '').trim()}`)
    .digest('hex');
  return `join_${digest.slice(0, 48)}`;
}

function dateMillis(value) {
  if (value && typeof value.toMillis === 'function') return value.toMillis();
  if (value && typeof value.toDate === 'function') return value.toDate().getTime();
  if (typeof value === 'number') return value;
  return typeof value === 'string' ? Date.parse(value) : Number.NaN;
}

function upcomingHikeUnavailableReason(hike, nowMillis = Date.now()) {
  if (!hike || typeof hike !== 'object' || hike.isDeleted === true) {
    return 'hike_removed';
  }
  const launchHasStarted = Boolean(
    String(hike.teamHikeSessionId || '').trim()
    || hike.teamLaunchLinkedAt
    || hike.teamLaunchLinkedAtLocal
    || (Array.isArray(hike.startedParticipantPhones)
      && hike.startedParticipantPhones.some(
        (phone) => Boolean(String(phone || '').trim())
      ))
  );
  if (launchHasStarted) return 'hike_started';
  const departureMillis = dateMillis(
    hike.departureTimeLocal || hike.departureTime
  );
  const expectedReturnMillis = dateMillis(
    hike.expectedReturnTimeLocal || hike.expectedReturnTime
  );
  const hikeEndMillis = Number.isFinite(expectedReturnMillis)
    ? expectedReturnMillis
    : departureMillis + 60 * 60 * 1000;
  if (
    !Number.isFinite(departureMillis)
    || !Number.isFinite(hikeEndMillis)
    || hikeEndMillis <= nowMillis
  ) {
    return 'hike_ended';
  }
  return '';
}

// joinRequestLifecycle: Keep accepted/rejected decisions terminal and expire requests when their source hike is unavailable.
function joinRequestLifecycle(request, hike, nowMillis = Date.now()) {
  const status = String(request?.status || '').trim();
  if (status === 'accepted' || status === 'rejected') {
    return { status, reason: status };
  }
  const unavailableReason = upcomingHikeUnavailableReason(hike, nowMillis);
  if (unavailableReason) {
    return { status: 'expired', reason: unavailableReason };
  }
  return { status: status === 'pending' ? 'pending' : 'expired', reason: '' };
}

module.exports = {
  joinRequestDocumentId,
  joinRequestLifecycle,
  upcomingHikeUnavailableReason,
};

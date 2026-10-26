'use strict';

const {dateMillis} = require('./trail_hazard_policy');
const START_WINDOW_MS = 15 * 60 * 1000;
const NON_EXPIRED_STATUSES = new Set(['active', 'started', 'ended', 'completed',
  'cancelled', 'canceled', 'abandoned', 'rejected', 'deleted']);

function isExpiredScheduledHike(hike, ownerPhoneNumber, now = Date.now()) {
  const departure = dateMillis(hike?.departureTimeLocal || hike?.departureTime);
  if (!Number.isFinite(departure) || departure + START_WINDOW_MS > now) return false;
  if (NON_EXPIRED_STATUSES.has(String(hike.status || '').toLowerCase())
      || hike.startedAt || hike.startedAtLocal || hike.endedAt || hike.endedAtLocal) return false;
  if (Array.isArray(hike.startedParticipantPhones)
      && hike.startedParticipantPhones.some(phone => String(phone || '').trim() === ownerPhoneNumber)) return false;
  if (hike.isDeleted === true && hike.expired !== true
      && hike.deletedReason !== 'departure_time_expired'
      && String(hike.status || '').toLowerCase() !== 'expired') return false;
  return true;
}

// Fill each page with eligible plans while preserving the authorized query and
// a cursor over every scanned document, including cancelled/started plans.
async function loadExpiredScheduledHikePage({query, ownerPhoneNumber, now, limit, sanitize}) {
  const hikes = [];
  const batchSize = Math.min(200, Math.max(30, limit * 2));
  let scanned = 0, last, more = false;
  while (scanned < 2000 && hikes.length < limit) {
    const take = Math.min(batchSize, 2000 - scanned);
    const snapshot = await query.limit(take + 1).get();
    const rows = snapshot.docs.slice(0, take);
    more = false;
    for (let i = 0; i < rows.length; i++) {
      const document = rows[i], data = document.data();
      last = {departureTimeLocal: String(data.departureTimeLocal), hikeId: document.id};
      scanned++;
      if (isExpiredScheduledHike(data, ownerPhoneNumber, now)) {
        hikes.push({...sanitize(data), hikeId: document.id});
      }
      more = i + 1 < snapshot.docs.length;
      if (hikes.length === limit) break;
    }
    if (!more || hikes.length === limit || scanned >= 2000) break;
    query = query.startAfter(last.departureTimeLocal, last.hikeId);
  }
  return {ownerPhoneNumber, hikes, nextCursor: more && last ? last : null};
}

module.exports = {START_WINDOW_MS, isExpiredScheduledHike, loadExpiredScheduledHikePage};

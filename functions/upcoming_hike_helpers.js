// Public upcoming-hike previews expose joinable plan details while withholding member and safety information.
'use strict';

function dateMillis(value) {
  if (value && typeof value.toMillis === 'function') {
    return value.toMillis();
  }
  if (value && typeof value.toDate === 'function') {
    return value.toDate().getTime();
  }
  if (typeof value === 'number') {
    return value;
  }
  return typeof value === 'string' ? Date.parse(value) : Number.NaN;
}

function boundedNumber(value, minimum, maximum, fallback = 0) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(minimum, Math.min(maximum, parsed));
}

function safeText(value, maximumLength) {
  return String(value || '').trim().slice(0, maximumLength);
}

function effectiveUpcomingHikeType(rawHike) {
  const hike = rawHike && typeof rawHike === 'object' ? rawHike : {};
  const draft = hike.draft && typeof hike.draft === 'object' ? hike.draft : {};
  const hasTeamBuddies = Array.isArray(draft.teamBuddies)
    && draft.teamBuddies.length > 0;
  return String(hike.hikeType || '') === 'team'
    || String(draft.hikeType || '') === 'team'
    || hasTeamBuddies
    ? 'team'
    : 'solo';
}

// buildUpcomingHikePreview: Expose only joinable plan data and the caller's own membership marker.
function buildUpcomingHikePreview(
  hikeId,
  rawHike,
  callerPhone,
  nowMillis = Date.now()
) {
  const hike = rawHike && typeof rawHike === 'object' && !Array.isArray(rawHike)
    ? rawHike
    : {};
  const id = safeText(hikeId, 200);
  const departureMillis = dateMillis(
    hike.departureTimeLocal || hike.departureTime
  );
  if (
    !id
    || hike.isDeleted === true
    || !Number.isFinite(departureMillis)
    || departureMillis + 15 * 60 * 1000 <= nowMillis
  ) {
    return null;
  }

  const expectedReturnMillis = dateMillis(
    hike.expectedReturnTimeLocal || hike.expectedReturnTime
  );
  const createdMillis = dateMillis(hike.createdAtLocal || hike.createdAt);
  const creatorPhone = safeText(hike.creatorPhone, 20);
  const normalizedCallerPhone = safeText(callerPhone, 20);
  const storedParticipantPhones = Array.isArray(hike.participantPhones)
    ? hike.participantPhones
        .map((phone) => safeText(phone, 20))
        .filter((phone) => phone)
    : [];
  const isCreator = creatorPhone === normalizedCallerPhone;
  const isParticipant = isCreator
    || storedParticipantPhones.includes(normalizedCallerPhone);
  const reminderPhones = Array.isArray(hike.departureReminderPhones)
    ? hike.departureReminderPhones
        .map((phone) => safeText(phone, 20))
        .filter((phone) => phone)
    : [];

  return {
    id,
    sessionId: id,
    trailId: safeText(hike.trailId, 200),
    trailName: safeText(hike.trailName, 160),
    latitude: boundedNumber(hike.latitude, -90, 90),
    longitude: boundedNumber(hike.longitude, -180, 180),
    area: safeText(hike.area, 160),
    state: safeText(hike.state, 160),
    country: safeText(hike.country, 160),
    distanceKm: boundedNumber(hike.distanceKm, 0, 1000),
    durationMinutes: Math.round(
      boundedNumber(hike.durationMinutes, 0, 43200)
    ),
    difficulty: safeText(hike.difficulty, 80),
    startPointName: safeText(hike.startPointName, 160),
    destinationName: safeText(hike.destinationName, 160),
    departureTimeLocal: new Date(departureMillis).toISOString(),
    expectedReturnTimeLocal: Number.isFinite(expectedReturnMillis)
      ? new Date(expectedReturnMillis).toISOString()
      : new Date(departureMillis).toISOString(),
    hikeType: effectiveUpcomingHikeType(hike),
    joinPolicy: String(hike.joinPolicy || '') === 'approval' ? 'approval' : 'open',
    participantCount: Math.round(
      boundedNumber(
        hike.participantCount,
        1,
        50,
        Math.max(1, storedParticipantPhones.length)
      )
    ),
    creatorName: safeText(hike.creatorName, 80),
    createdAt: Number.isFinite(createdMillis)
      ? new Date(createdMillis).toISOString()
      : new Date(departureMillis).toISOString(),
    // Membership markers reveal only information the authenticated caller
    // already knows about their own account.
    creatorPhone: isCreator ? normalizedCallerPhone : '',
    participantPhones: isParticipant ? [normalizedCallerPhone] : [],
    departureReminderCount: Math.min(3, new Set(reminderPhones).size),
    departureReminderSentByMe: reminderPhones.includes(normalizedCallerPhone),
  };
}

module.exports = { buildUpcomingHikePreview, effectiveUpcomingHikeType };

// Shared roster capacity, persisted team colours and preparation-location validation.
'use strict';
const MAX_TEAM_HIKERS = 30;
const TEAM_COLORS = Object.freeze([
  0xff34a853, 0xffe6194b, 0xff4363d8, 0xfff58231, 0xff911eb4,
  0xff42d4f4, 0xfff032e6, 0xffbfef45, 0xff469990, 0xff9a6324,
  0xff800000, 0xff808000, 0xff000075, 0xffa9a9a9, 0xffffe119,
  0xfffabed4, 0xffaaffc3, 0xffffd8b1, 0xffdcbeff, 0xffa6cee3,
  0xffd95f02, 0xff1b9e77, 0xff7570b3, 0xffe7298a, 0xff66a61e,
  0xffe6ab02, 0xffa6761d, 0xff666666, 0xffff6f61, 0xff00a6a6,
]);

// Use the same numeric account key on every client, independent of display order or viewer.
function participantKey(participant) {
  const direct = String(participant?.phoneNumber || '').replace(/\D/g, '');
  return direct || String(participant?.buddy?.phoneNumber || '').replace(/\D/g, '');
}

// Preserve existing assignments and fill unused palette slots deterministically for legacy rosters.
function participantColors(participants, stored = {}) {
  const ordered = [...participants].sort((a, b) => Number(b.isHost === true) - Number(a.isHost === true)
    || (participantKey(a) < participantKey(b) ? -1 : participantKey(a) > participantKey(b) ? 1 : 0));
  const result = {}, used = new Set();
  for (const participant of ordered) {
    const key = participantKey(participant), color = stored[key];
    if (key && TEAM_COLORS.includes(color) && !used.has(color)) { result[key] = color; used.add(color); }
  }
  for (const participant of ordered) {
    const key = participantKey(participant);
    if (!key || result[key] != null) continue;
    const color = TEAM_COLORS.find(value => !used.has(value));
    // Legacy over-capacity teams are retained; all new admission paths enforce the limit.
    result[key] = color ?? participant.buddy?.avatarColorValue ?? TEAM_COLORS[0];
    used.add(result[key]);
  }
  return result;
}

// Write colours onto each member as well as the stable identity map used after roster changes.
function applyParticipantColors(participants, colors) {
  return participants.map(participant => {
    const source = participant.buddy && typeof participant.buddy === 'object' ? participant.buddy : participant;
    const buddy = participant.buddy && typeof participant.buddy === 'object' ? {...source}
      : {name: String(source.name || ''), handle: String(source.handle || ''), role: String(source.role || 'Teammate'),
        ...(source.photoURL ? {photoURL: source.photoURL} : {})};
    return {...participant, buddy: {...buddy,
      phoneNumber: String(participant.phoneNumber || '').trim() || String(source.phoneNumber || '').trim(),
      avatarColorValue: colors[participantKey(participant)] ?? TEAM_COLORS[0]}};
  });
}

// Accept only a participant's own fresh preparation fix, without launching tracking or changing readiness.
function readinessLocation(participant, data, now, ErrorType) {
  if (!['joined', 'ready'].includes(participant.status)) {
    throw new ErrorType('failed-precondition', 'Join this team before sharing your preparation location.');
  }
  const {latitude, longitude, accuracyMeters, capturedAtMillis} = data;
  if (![latitude, longitude, accuracyMeters, capturedAtMillis].every(value => typeof value === 'number' && Number.isFinite(value))
    || Math.abs(latitude) > 90 || Math.abs(longitude) > 180 || accuracyMeters < 0 || accuracyMeters > 250
    || capturedAtMillis < now - 120000 || capturedAtMillis > now + 10000) {
    throw new ErrorType('invalid-argument', 'A fresh, accurate GPS fix is required.');
  }
  const previous = Date.parse(String(participant.latestLocation?.capturedAtLocal || ''));
  if (Number.isFinite(previous) && capturedAtMillis <= previous) return null;
  const capturedAtLocal = new Date(capturedAtMillis).toISOString();
  return {...participant, latestLocation: {latitude, longitude, accuracyMeters, capturedAtLocal},
    locationUpdatedAtLocal: capturedAtLocal, readinessLocationRecordedAtLocal: new Date(now).toISOString()};
}

module.exports = {MAX_TEAM_HIKERS, TEAM_COLORS, participantKey, participantColors, applyParticipantColors, readinessLocation};

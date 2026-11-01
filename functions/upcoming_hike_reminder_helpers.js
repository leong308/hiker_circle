// Departure reminders use fixed slots; version one retains its saved stop/count limits.
'use strict';

// Reads timestamps from Firestore or locally serialized preferences.
function dateMillis(value) {
  if (value && typeof value.toMillis === 'function') return value.toMillis();
  if (value && typeof value.toDate === 'function') {
    return value.toDate().getTime();
  }
  if (typeof value === 'number') return value;
  return typeof value === 'string' ? Date.parse(value) : Number.NaN;
}

// Accepts supported integer choices only.
function allowed(value, options, fallback) {
  const number = Number(value);
  return Number.isInteger(number) && options.includes(number)
    ? number
    : fallback;
}

// New schedules repeat until departure; existing schedules keep their old limits.
function normalizeUpcomingHikeReminderPreference(raw, { legacy = false } = {}) {
  const value = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
  const first = allowed(
    value.firstReminderMinutesBefore,
    [5, 10, 15, 30, 60, 120, 180, 360, 720, 1440],
    legacy ? 30 : 120
  );
  const repeat = allowed(
    value.repeatIntervalMinutes,
    [0, 15, 30, 60, 120, 360],
    legacy ? 0 : 30
  );
  if (value.schemaVersion === 2) {
    return {
      schemaVersion: 2,
      enabled: value.enabled !== false,
      firstReminderMinutesBefore: first,
      repeatIntervalMinutes: repeat < first ? repeat : 0,
    };
  }
  const finalBefore = Math.min(
    first,
    allowed(
      value.finalReminderMinutesBefore,
      [5, 10, 15, 30, 60],
      legacy ? 5 : 15
    )
  );
  const maximum = repeat === 0
    ? 1
    : allowed(value.maximumReminders, [1, 2, 3, 4, 5, 6, 7, 8], 4);
  return {
    enabled: value.enabled !== false,
    firstReminderMinutesBefore: first,
    repeatIntervalMinutes: repeat,
    finalReminderMinutesBefore: finalBefore,
    maximumReminders: maximum,
  };
}

// Slots never move to the present and never include the hike start itself.
function upcomingHikeReminderTimes(preference, departureMillis) {
  if (!preference.enabled || !Number.isFinite(departureMillis)) return [];
  const current = preference.schemaVersion === 2;
  const times = [];
  let minutes = preference.firstReminderMinutesBefore;
  for (let index = 0; minutes > 0; index++) {
    if (!current && (index >= preference.maximumReminders
      || minutes < preference.finalReminderMinutesBefore)) break;
    times.push(departureMillis - minutes * 60000);
    if (preference.repeatIntervalMinutes === 0) break;
    minutes -= preference.repeatIntervalMinutes;
  }
  return times;
}

// A five-minute scheduler may deliver a slot a few minutes late. Older slots
// are skipped permanently; a delayed worker must never replay a backlog.
function upcomingHikeReminderDue({
  rawPreference,
  departureMillis,
  nowMillis,
  legacy = false,
}) {
  const preference = normalizeUpcomingHikeReminderPreference(
    rawPreference,
    { legacy }
  );
  if (
    !preference.enabled
    || !Number.isFinite(departureMillis)
    || !Number.isFinite(nowMillis)
    || departureMillis <= nowMillis
  ) {
    return { due: false, preference };
  }

  const storedDeparture = dateMillis(rawPreference?.departureTimeLocal);
  const sameDeparture = Number.isFinite(storedDeparture)
    && Math.abs(storedDeparture - departureMillis) < 1000;
  const sentCount = sameDeparture
    ? Math.max(0, Math.floor(Number(rawPreference?.sentCount) || 0))
    : 0;
  const lastSentMillis = sameDeparture
    ? dateMillis(rawPreference?.lastSentAtLocal || rawPreference?.lastSentAt)
    : Number.NaN;
  const minutesUntil = Math.ceil((departureMillis - nowMillis) / 60000);

  // Fixed slots prevent replay. A lifetime count would incorrectly block
  // a new future slot when the hiker changes their reminder preferences.
  if (sentCount > 0 && !Number.isFinite(lastSentMillis)) {
    return { due: false, preference, sentCount, minutesUntil };
  }
  const times = upcomingHikeReminderTimes(preference, departureMillis);
  const slot = times.findLast(time => time <= nowMillis);
  const due = Number.isFinite(slot)
    && nowMillis - slot < 5 * 60000
    && (!Number.isFinite(lastSentMillis) || lastSentMillis < slot);
  return { due, preference, sentCount, minutesUntil, slotMillis: slot };
}

module.exports = {
  normalizeUpcomingHikeReminderPreference,
  upcomingHikeReminderTimes,
  upcomingHikeReminderDue,
};

'use strict';

function dateMillis(value) {
  if (value && typeof value.toMillis === 'function') return value.toMillis();
  if (value && typeof value.toDate === 'function') {
    return value.toDate().getTime();
  }
  if (typeof value === 'number') return value;
  return typeof value === 'string' ? Date.parse(value) : Number.NaN;
}

function allowed(value, options, fallback) {
  const number = Number(value);
  return Number.isInteger(number) && options.includes(number)
    ? number
    : fallback;
}

function normalizeUpcomingHikeReminderPreference(raw, { legacy = false } = {}) {
  const value = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
  const first = allowed(
    value.firstReminderMinutesBefore,
    [15, 30, 60, 120, 180, 360, 720, 1440],
    legacy ? 30 : 120
  );
  const repeat = allowed(
    value.repeatIntervalMinutes,
    [0, 15, 30, 60, 120, 360],
    legacy ? 0 : 30
  );
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

  if (
    minutesUntil > preference.firstReminderMinutesBefore
    || minutesUntil < preference.finalReminderMinutesBefore
    || sentCount >= preference.maximumReminders
  ) {
    return { due: false, preference, sentCount, minutesUntil };
  }
  if (sentCount === 0) {
    return { due: true, preference, sentCount, minutesUntil };
  }
  if (
    preference.repeatIntervalMinutes <= 0
    || !Number.isFinite(lastSentMillis)
    || nowMillis - lastSentMillis < preference.repeatIntervalMinutes * 60000
  ) {
    return { due: false, preference, sentCount, minutesUntil };
  }
  return { due: true, preference, sentCount, minutesUntil };
}

module.exports = {
  normalizeUpcomingHikeReminderPreference,
  upcomingHikeReminderDue,
};

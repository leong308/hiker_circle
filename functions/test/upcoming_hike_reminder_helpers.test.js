'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  normalizeUpcomingHikeReminderPreference,
  upcomingHikeReminderDue,
} = require('../upcoming_hike_reminder_helpers');

const departure = Date.parse('2026-08-21T10:00:00.000Z');

test('uses the legacy single 30 minute reminder when no preference exists', () => {
  const result = upcomingHikeReminderDue({
    rawPreference: {},
    departureMillis: departure,
    nowMillis: departure - 29 * 60 * 1000,
    legacy: true,
  });
  assert.equal(result.due, true);
  assert.equal(result.preference.firstReminderMinutesBefore, 30);
  assert.equal(result.preference.maximumReminders, 1);
});

test('applies each user repeat frequency and maximum independently', () => {
  const rawPreference = {
    enabled: true,
    firstReminderMinutesBefore: 120,
    repeatIntervalMinutes: 30,
    finalReminderMinutesBefore: 15,
    maximumReminders: 3,
    departureTimeLocal: new Date(departure).toISOString(),
    sentCount: 1,
    lastSentAtLocal: new Date(departure - 90 * 60 * 1000).toISOString(),
  };
  assert.equal(
    upcomingHikeReminderDue({
      rawPreference,
      departureMillis: departure,
      nowMillis: departure - 59 * 60 * 1000,
    }).due,
    true
  );
  assert.equal(
    upcomingHikeReminderDue({
      rawPreference: { ...rawPreference, sentCount: 3 },
      departureMillis: departure,
      nowMillis: departure - 59 * 60 * 1000,
    }).due,
    false
  );
});

test('disabled reminders and times after the final cutoff are skipped', () => {
  assert.equal(
    upcomingHikeReminderDue({
      rawPreference: { enabled: false },
      departureMillis: departure,
      nowMillis: departure - 30 * 60 * 1000,
    }).due,
    false
  );
  assert.equal(
    upcomingHikeReminderDue({
      rawPreference: {
        firstReminderMinutesBefore: 120,
        repeatIntervalMinutes: 15,
        finalReminderMinutesBefore: 15,
        maximumReminders: 8,
      },
      departureMillis: departure,
      nowMillis: departure - 4 * 60 * 1000,
    }).due,
    false
  );
});

test('normalizes unsupported client values to bounded options', () => {
  assert.deepEqual(normalizeUpcomingHikeReminderPreference({
    firstReminderMinutesBefore: 9999,
    repeatIntervalMinutes: 1,
    finalReminderMinutesBefore: 999,
    maximumReminders: 99,
  }), {
    enabled: true,
    firstReminderMinutesBefore: 120,
    repeatIntervalMinutes: 30,
    finalReminderMinutesBefore: 15,
    maximumReminders: 4,
  });
});

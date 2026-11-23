'use strict';

const crypto = require('node:crypto');
const {normalizeUpcomingHikeReminderPreference, upcomingHikeReminderTimes} = require('./upcoming_hike_reminder_helpers');

const MAX_HIKES = 96;
const MAX_SLOTS = 512;
const MAX_SLOTS_PER_HIKE = 128;
const idPattern = /^[A-Za-z0-9_-]{1,200}$/;

function millis(value) {
  if (value && typeof value.toMillis === 'function') return value.toMillis();
  if (value && typeof value.toDate === 'function') return value.toDate().getTime();
  if (typeof value === 'number') return value;
  return typeof value === 'string' ? Date.parse(value) : Number.NaN;
}

function preferenceHash(raw, {legacy = false} = {}) {
  return crypto.createHash('sha256').update(JSON.stringify(
    normalizeUpcomingHikeReminderPreference(raw, {legacy})
  )).digest('hex');
}

function sessionHash(sid) {
  return crypto.createHash('sha256').update(String(sid)).digest('hex');
}

function normalizeReport(data, ErrorType) {
  const fail = () => {throw new ErrorType('invalid-argument', 'The local reminder schedule is invalid.');};
  const installationId = String(data?.installationId || '');
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(installationId)
    || !Array.isArray(data?.schedules) || data.schedules.length > MAX_HIKES) fail();
  const ids = new Set();
  let count = 0;
  const schedules = data.schedules.map(raw => {
    const hikeId = String(raw?.hikeId || '');
    if (!idPattern.test(hikeId) || hikeId.startsWith('local_pending_') || ids.has(hikeId)
      || !Number.isSafeInteger(raw?.departureAtMillis)
      || !Number.isInteger(raw?.firstReminderMinutesBefore)
      || !Number.isInteger(raw?.repeatIntervalMinutes)
      || !Array.isArray(raw?.slots) || raw.slots.length > MAX_SLOTS_PER_HIKE) fail();
    ids.add(hikeId);
    const slots = [...new Set(raw.slots)];
    count += slots.length;
    if (count > MAX_SLOTS || slots.some(value => !Number.isSafeInteger(value))) fail();
    return {hikeId, departureAtMillis: raw.departureAtMillis,
      firstReminderMinutesBefore: raw.firstReminderMinutesBefore,
      repeatIntervalMinutes: raw.repeatIntervalMinutes,
      slots: slots.sort((a, b) => a - b)};
  });
  return {installationId, schedules};
}

// An acknowledgement is ownership of an OS-queued slot, never proof of display.
function ownsLocalSlot({rawPreference, departureMillis, slotMillis, sessionState}) {
  const local = rawPreference?.localDeliverySchedule;
  if (!local || local.version !== 1 || !sessionState?.activeSessionId
    || !local.installationId || local.installationId !== sessionState?.device?.appInstanceId
    || local.sessionHash !== sessionHash(sessionState.activeSessionId)
    || local.departureAtMillis !== departureMillis
    || local.preferenceHash !== preferenceHash(rawPreference)
    || !Array.isArray(local.slots) || !local.slots.includes(slotMillis)) return false;
  const preference = normalizeUpcomingHikeReminderPreference(rawPreference);
  return upcomingHikeReminderTimes(preference, departureMillis).includes(slotMillis);
}

// Full replacement also releases omitted/cancelled schedules for this account.
// Current mobile-session checks fence late acknowledgements from replaced phones.
async function acknowledgeLocalHikeReminderSlots({db, uid, sid, data, ErrorType, timestamp,
  now = Date.now()}) {
  const report = normalizeReport(data, ErrorType);
  const sessionRef = db.collection('mobileSessions').doc(uid);
  const accountRef = db.collection('users').doc(uid);
  return db.runTransaction(async tx => {
    // Query device session and account
    const [sessionSnapshot, accountSnapshot] = await Promise.all([tx.get(sessionRef), tx.get(accountRef)]);
    const state = sessionSnapshot.data() || {};
    const account = accountSnapshot.data() || {};
    if (!sid || !accountSnapshot.exists || account.accountDisabled === true || account.status === 'disabled'
      || state.activeSessionId !== sid || state.device?.appInstanceId !== report.installationId) {
      throw new ErrorType('unauthenticated', 'This phone no longer owns the active session.');
    }
    if (Number(state.localReminderDelivery?.reportAtMillis || 0) > now) {
      throw new ErrorType('aborted', 'A newer local reminder schedule has already been recorded.');
    }
    const previousIds = (Array.isArray(state.localReminderDelivery?.hikeIds)
      ? state.localReminderDelivery.hikeIds : []).filter(id =>
      typeof id === 'string' && idPattern.test(id)).slice(0, MAX_HIKES);
    const ids = [...new Set([...previousIds, ...report.schedules.map(row => row.hikeId)])];
    const documents = await Promise.all(ids.map(async hikeId => {
      const hikeRef = db.collection('upcomingHikes').doc(hikeId);
      const preferenceRef = hikeRef.collection('reminderPreferences').doc(uid);
      // Query planned hike reminder preference
      const [hikeSnapshot, preferenceSnapshot] = await Promise.all([tx.get(hikeRef), tx.get(preferenceRef)]);
      return {hikeId, hikeSnapshot, preferenceSnapshot, preferenceRef};
    }));
    const accepted = new Map();
    let retryNeeded = false;
    for (const row of report.schedules) {
      const document = documents.find(item => item.hikeId === row.hikeId);
      const hike = document.hikeSnapshot.data() || {};
      const raw = document.preferenceSnapshot.data() || {};
      const departure = millis(hike.departureTimeLocal || hike.departureTime);
      const participant = hike.creatorPhone === uid || (Array.isArray(hike.participantPhones)
        && hike.participantPhones.includes(uid));
      // Expired/removed plans release ownership without blocking other reports.
      if (!document.hikeSnapshot.exists || !participant || hike.isDeleted === true
        || hike.teamLaunchConsumed === true || !Number.isFinite(departure) || departure <= now) continue;
      // Creating an absent preference here would change the legacy scheduler's
      // defaults. Unconfigured/older records keep their cloud fallback intact.
      if (!document.preferenceSnapshot.exists) {
        retryNeeded = true;
        continue;
      }
      const preference = normalizeUpcomingHikeReminderPreference(raw, {legacy: !document.preferenceSnapshot.exists});
      const allowed = new Set(upcomingHikeReminderTimes(preference, departure));
      if (row.departureAtMillis !== departure
        || row.firstReminderMinutesBefore !== preference.firstReminderMinutesBefore
        || row.repeatIntervalMinutes !== preference.repeatIntervalMinutes
        || row.slots.some(slot => !allowed.has(slot))) {
        throw new ErrorType('failed-precondition', 'The hike reminder settings changed. Refresh and retry.');
      }
      if (row.slots.length) accepted.set(row.hikeId, {
        version: 1, installationId: report.installationId,
        sessionHash: sessionHash(sid), departureAtMillis: departure,
        preferenceHash: preferenceHash(raw, {legacy: !document.preferenceSnapshot.exists}),
        slots: row.slots, acknowledgedAt: timestamp(),
      });
    }
    // All reads precede all writes for Firestore transaction compatibility.
    for (const document of documents) {
      const owned = accepted.get(document.hikeId);
      if (owned || document.preferenceSnapshot.data()?.localDeliverySchedule) {
        // Update cloud: acknowledge scheduled reminders
        tx.set(document.preferenceRef, {localDeliverySchedule: owned || null}, {merge: true});
      }
    }
    tx.set(sessionRef, {localReminderDelivery: {
      installationId: report.installationId, hikeIds: [...accepted.keys()],
      reportAtMillis: now, acknowledgedAt: timestamp(),
    }}, {merge: true});
    return {acknowledgedHikes: accepted.size,
      acknowledgedSlots: [...accepted.values()].reduce((sum, value) => sum + value.slots.length, 0),
      retryNeeded};
  });
}

module.exports = {normalizeReport, preferenceHash, ownsLocalSlot, acknowledgeLocalHikeReminderSlots};

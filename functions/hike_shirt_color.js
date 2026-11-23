// One allowlisted clothing vocabulary for hike-related emergency-contact messages.
'use strict';
const {dateMillis} = require('./trail_hazard_policy');
const SHIRT_COLORS = Object.freeze({white: 'White', lightGrey: 'Light grey', beige: 'Beige',
  lightBlue: 'Light blue', mintGreen: 'Mint green', highVisibilityYellow: 'Hi-vis yellow',
  brightOrange: 'Bright orange', red: 'Red', black: 'Black', navy: 'Navy', darkGrey: 'Dark grey'});

// Ignore absent, unknown and untrusted display text rather than adding arbitrary message content.
function normalizeShirtColor(value) {
  return typeof value === 'string' && Object.hasOwn(SHIRT_COLORS, value) ? value : null;
}

// Select the canonical session answers, falling back only for legacy draft-only sessions.
function shirtColorForHike(hike) {
  const answers = Array.isArray(hike?.completedChecklistItems) ? hike.completedChecklistItems
    : Array.isArray(hike?.draft?.completedChecklistItems) ? hike.draft.completedChecklistItems : [];
  for (const answer of answers) {
    if (typeof answer !== 'string' || !answer.startsWith('gear:shirt-color:')) continue;
    const color = normalizeShirtColor(answer.slice('gear:shirt-color:'.length));
    if (color) return color;
  }
  return null;
}

// Do not reuse a completed hike's clothing for a later SOS outside that hike.
function hikeContainsAlert(hike, uid, triggeredAtMillis) {
  if (!hike || hike.userId !== uid || !Number.isFinite(triggeredAtMillis)) return false;
  const start = dateMillis(hike.startedAtLocal ?? hike.startedAt);
  if (!Number.isFinite(start) || start > triggeredAtMillis) return false;
  if (hike.status === 'active') return true;
  const end = dateMillis(hike.endedAtLocal ?? hike.endedAt ?? hike.abandonedAtLocal ?? hike.abandonedAt);
  return ['completed', 'ended', 'abandoned'].includes(hike.status)
    && Number.isFinite(end) && end >= triggeredAtMillis;
}

// Recover clothing for older app clients using the hike that actually covered the alert time.
async function resolveSosShirtColor({db, uid, triggeredAtMillis}) {
  let timer;
  let snapshot;
  try {
    snapshot = await Promise.race([
      // Query active hiker's SOS shirt colour
      db.collection('hikeSessions').where('userId', '==', uid)
        .where('startedAt', '<=', new Date(triggeredAtMillis)).orderBy('startedAt', 'desc').limit(1).get(),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('Clothing lookup timed out.')), 1000); }),
    ]);
  } finally { clearTimeout(timer); }
  const hike = snapshot.docs[0]?.data();
  return hikeContainsAlert(hike, uid, triggeredAtMillis) ? shirtColorForHike(hike) : null;
}

module.exports = {SHIRT_COLORS, normalizeShirtColor, shirtColorForHike, hikeContainsAlert, resolveSosShirtColor};

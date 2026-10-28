// Durable, owner-scoped arrival checks; external messaging is injectable so tests never contact real people.
'use strict';
const {createHash, randomUUID} = require('node:crypto');
const {arrivalPlan, advanceArrivalProof, arrivalEventId, sampleTime, validPoint} = require('./hike_arrival_policy');
const {loadFootprints} = require('./footprint_batch');
const {readUser} = require('./user_modules');
const {formatSosDateTime, classifySosProviderHttpFailure} = require('./sos_dispatch_helpers');
const {footprintImage} = require('./arrival_footprint_image');
const {SHIRT_COLORS, shirtColorForHike} = require('./hike_shirt_color');
const RESPONSE_WINDOW_MS = 5 * 60000;
const LEASE_MS = 2 * 60000;
const TERMINAL = new Set(['safe', 'arrived', 'completed']);
const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,180}$/.test(value);

// Return a safe public projection without exposing contacts, provider credentials or delivery receipts.
function publicState(record) {
  if (!record) return null;
  return Object.fromEntries(['version', 'eventId', 'enabled', 'status', 'latestArrivalAtMillis', 'warningAtMillis',
    'responseDeadlineMillis', 'safeAtMillis', 'arrivedAtMillis', 'targetName', 'sentCount', 'uncertainCount',
    'failedCount', 'lastAttemptAtMillis'].filter(key => record[key] !== undefined).map(key => [key, record[key]]));
}

// Read the complete private route inside the same transaction as the decision it protects.
async function recordedProof(tx, hike, sessionId, plan, now) {
  const samples = await loadFootprints(tx, sessionId, hike.footprint);
  return {samples, proof: advanceArrivalProof(plan, samples, {}, now)};
}

// Authenticate against the canonical tracking owner, independently of any supplied destination or deadline.
function requireOwner(hike, uid, ErrorType) {
  if (!hike || hike.userId !== uid) throw new ErrorType('permission-denied', 'This hike belongs to another hiker.');
}

// Arm only clients with the new local warning installed; older app sessions do not silently gain auto-dispatch.
async function arm({db, uid, sessionId, warningAtMillis: requestedWarningAt, now = Date.now(), ErrorType = Error}) {
  if (!validId(sessionId)) throw new ErrorType('invalid-argument', 'Select an active hike.');
  const ref = db.collection('hikeSessions').doc(sessionId);
  return db.runTransaction(async tx => {
    const hike = (await tx.get(ref)).data();
    requireOwner(hike, uid, ErrorType);
    if (hike.status !== 'active') throw new ErrorType('failed-precondition', 'This hike has ended.');
    const plan = arrivalPlan(hike);
    if (!plan) return null;
    const eventId = arrivalEventId(sessionId, plan.latestArrivalAtMillis);
    if (hike.arrivalSafety?.eventId === eventId) return publicState(hike.arrivalSafety);
    const {proof} = await recordedProof(tx, hike, sessionId, plan, now);
    const requested = Number(requestedWarningAt);
    const warningAtMillis = plan.latestArrivalAtMillis > now ? plan.latestArrivalAtMillis
      : Number.isFinite(requested) ? Math.max(plan.latestArrivalAtMillis, Math.min(now, requested)) : now;
    const record = {version: 1, eventId, enabled: !proof.arrivedAtMillis,
      status: proof.arrivedAtMillis ? 'arrived' : now >= warningAtMillis ? 'awaiting_response' : 'monitoring',
      latestArrivalAtMillis: plan.latestArrivalAtMillis, warningAtMillis, proof,
      responseDeadlineMillis: warningAtMillis + RESPONSE_WINDOW_MS,
      ...(proof.arrivedAtMillis ? {arrivedAtMillis: proof.arrivedAtMillis, targetName: proof.targetName} : {}),
      sentCount: 0, uncertainCount: 0, failedCount: 0};
    tx.update(ref, {arrivalSafety: record});
    return publicState(record);
  });
}

// Explicit confirmation cancels unstarted delivery work; already accepted provider messages cannot be recalled.
async function confirmSafe({db, uid, sessionId, eventId, reason, now = Date.now(), ErrorType = Error}) {
  if (!validId(sessionId) || !/^[a-f0-9]{64}$/.test(String(eventId))) throw new ErrorType('invalid-argument', 'This arrival check is invalid.');
  const ref = db.collection('hikeSessions').doc(sessionId);
  return db.runTransaction(async tx => {
    const hike = (await tx.get(ref)).data();
    requireOwner(hike, uid, ErrorType);
    const record = hike.arrivalSafety;
    if (record?.eventId !== eventId) throw new ErrorType('failed-precondition', 'This arrival check has changed.');
    if (TERMINAL.has(record.status)) return publicState(record);
    const receipts = await tx.get(db.collection('arrivalSafetyDeliveries').where('eventId', '==', eventId));
    const deliveries = receipts.docs.map(doc => doc.data());
    const next = {...record, enabled: false, status: 'safe', safeAtMillis: now,
      sentCount: deliveries.filter(item => item.status === 'sent').length,
      uncertainCount: deliveries.filter(item => ['sending', 'delivery_uncertain'].includes(item.status)).length,
      confirmationSource: reason === 'recorded_arrival' ? 'device_recorded_arrival' : 'hiker_confirmation'};
    tx.update(ref, {arrivalSafety: next});
    return publicState(next);
  });
}

// Re-evaluate uploaded history before showing warnings or allowing any contact send.
async function inspect({db, sessionId, uid, now = Date.now(), ErrorType = Error}) {
  const ref = db.collection('hikeSessions').doc(sessionId);
  return db.runTransaction(async tx => {
    const snapshot = await tx.get(ref), hike = snapshot.data();
    if (uid) requireOwner(hike, uid, ErrorType);
    const record = hike?.arrivalSafety;
    if (!hike || !record) return null;
    if (hike.status !== 'active') {
      if (record.enabled) tx.update(ref, {arrivalSafety: {...record, enabled: false, status: 'completed'}});
      return null;
    }
    if (!record.enabled || TERMINAL.has(record.status)) return {hike, record, samples: []};
    const plan = arrivalPlan(hike);
    if (!plan || record.eventId !== arrivalEventId(sessionId, plan.latestArrivalAtMillis)) return null;
    const {samples, proof} = await recordedProof(tx, hike, sessionId, plan, now);
    let next = record;
    if (proof.arrivedAtMillis) next = {...record, enabled: false, status: 'arrived', arrivedAtMillis: proof.arrivedAtMillis, targetName: proof.targetName};
    else if (now >= record.warningAtMillis && record.status === 'monitoring') next = {...record, status: 'awaiting_response'};
    if (next !== record) tx.update(ref, {arrivalSafety: next});
    return {hike, record: next, samples, plan};
  });
}

// Attach the last known facts without claiming that missing GPS proves injury or a precise current position.
function arrivalCaption({hike, samples, ownerName, preferredTimeZone, now}) {
  const clean = (value, limit) => String(value || '').replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, limit);
  const times = value => formatSosDateTime(value, preferredTimeZone);
  const plan = arrivalPlan(hike);
  const fixes = samples.filter(validPoint).filter(sample => Number.isFinite(sampleTime(sample))).sort((a, b) => sampleTime(a) - sampleTime(b));
  const last = fixes.at(-1);
  const clothing = shirtColorForHike(hike);
  const lines = ['HIKERCIRCLE - ARRIVAL NOT CONFIRMED',
    `${clean(ownerName || hike.userPhoneNumber, 70)} (${clean(hike.userPhoneNumber, 25)}) has not confirmed arrival or responded to the safety check.`,
    `Trail: ${clean(hike.trailName, 100)} (${hike.hikeType === 'team' ? 'team' : 'solo'})`,
    clothing ? `Shirt colour: ${SHIRT_COLORS[clothing]}` : '',
    `Expected: ${clean(plan.targets.map(target => target.name).join(' / '), 80)}`,
    `Departed: ${times(plan.startedAtMillis)}`,
    `Latest arrival: ${times(plan.latestArrivalAtMillis)}`,
    `Alert: ${times(now)}`,
    last ? `Last recorded GPS: ${times(sampleTime(last))}\nhttps://maps.google.com/?q=${last.latitude.toFixed(6)},${last.longitude.toFixed(6)}` : 'No recorded GPS is available.',
    Number.isFinite(hike.batteryLevel) ? `Last battery: ${Math.round(hike.batteryLevel)}%` : '',
    `Footprints: ${fixes.length}. Plot: blue path, green start, red last fix, orange destinations. No basemap.`,
    'GPS may be delayed or incomplete. Please contact the hiker and check their situation.'];
  return lines.filter(Boolean).join('\n').slice(0, 1024);
}

// Lease one contact message, then verify safe/arrival/end state again immediately before leaving the server.
async function deliverContact({db, sessionId, eventId, phone, sendFile, image, caption, now, clock}) {
  const id = createHash('sha256').update(`${sessionId}:${eventId}:${phone}`).digest('hex');
  const receipt = db.collection('arrivalSafetyDeliveries').doc(id), ref = db.collection('hikeSessions').doc(sessionId);
  const nonce = randomUUID();
  const claim = await db.runTransaction(async tx => {
    const hike = (await tx.get(ref)).data(), previous = (await tx.get(receipt)).data() || {};
    const record = hike?.arrivalSafety;
    if (hike?.status !== 'active' || record?.eventId !== eventId || !record.enabled || TERMINAL.has(record.status)
      || clock() < record.responseDeadlineMillis || ['sent', 'delivery_uncertain', 'sending'].includes(previous.status)
      || previous.leaseUntil > clock() || previous.status === 'failed' && previous.retryable !== true) return false;
    const plan = arrivalPlan(hike);
    if (!plan || arrivalEventId(sessionId, plan.latestArrivalAtMillis) !== eventId) return false;
    const {proof} = await recordedProof(tx, hike, sessionId, plan, clock());
    const user = (await readUser(db.collection('users').doc(hike.userId), ['sos'], tx)).data();
    const contacts = user?.sos_contacts || [];
    if (user?.accountDisabled === true || user?.status === 'disabled' || !contacts.some(contact => contact.phoneNumber === phone)) return false;
    if (proof.arrivedAtMillis) {
      tx.update(ref, {arrivalSafety: {...record, enabled: false, status: 'arrived', arrivedAtMillis: proof.arrivedAtMillis, targetName: proof.targetName}});
      return false;
    }
    tx.set(receipt, {sessionId, eventId, recipientPhone: phone, status: 'claimed', nonce, leaseUntil: clock() + LEASE_MS,
      attempts: (previous.attempts || 0) + 1, updatedAtMillis: clock()}, {merge: true});
    return true;
  });
  if (!claim) return;
  // Keep the irreversible send marker separate from a recoverable lease.
  const sending = await db.runTransaction(async tx => {
    const hike = (await tx.get(ref)).data(), current = (await tx.get(receipt)).data();
    if (current?.nonce !== nonce || current.status !== 'claimed') return false;
    let allowed = hike?.status === 'active' && hike.arrivalSafety?.eventId === eventId && hike.arrivalSafety.enabled;
    if (allowed) {
      const user = (await readUser(db.collection('users').doc(hike.userId), ['sos'], tx)).data();
      const plan = arrivalPlan(hike);
      const result = plan ? await recordedProof(tx, hike, sessionId, plan, clock()) : null;
      allowed = !!user && !user.accountDisabled && user.status !== 'disabled' && (user.sos_contacts || []).some(contact => contact.phoneNumber === phone)
        && !!result && !result.proof.arrivedAtMillis;
      if (result?.proof.arrivedAtMillis) tx.update(ref, {arrivalSafety: {...hike.arrivalSafety, enabled: false, status: 'arrived',
        arrivedAtMillis: result.proof.arrivedAtMillis, targetName: result.proof.targetName}});
    }
    if (!allowed) {
      tx.update(receipt, {status: 'cancelled', leaseUntil: 0}); return false;
    }
    tx.update(receipt, {status: 'sending', outboundAtMillis: clock()});
    return true;
  });
  if (!sending) return;
  let result;
  try {
    result = await sendFile({phone, image, caption, fileName: `hike-footprints-${eventId.slice(0, 12)}.png`});
  } catch (_) {
    // An interrupted upload may already be accepted. A retry must not silently duplicate it.
    result = {status: 'delivery_uncertain', retryable: false};
  }
  const status = result?.messageId ? 'sent' : result?.status || 'delivery_uncertain';
  await db.runTransaction(async tx => {
    const current = (await tx.get(receipt)).data();
    if (current?.nonce === nonce) tx.update(receipt, {status, retryable: result?.retryable === true,
      ...(result?.messageId ? {providerMessageId: result.messageId} : {}), leaseUntil: 0, updatedAtMillis: clock()});
  });
}

// Process one due session; shared receipts protect simultaneous foreground and scheduled workers.
async function processHike({db, sessionId, sendFile, now = Date.now(), clock = Date.now, uid, ErrorType = Error}) {
  const context = await inspect({db, sessionId, uid, now, ErrorType});
  if (!context || !context.record.enabled || now < context.record.responseDeadlineMillis) return publicState(context?.record);
  const {hike, samples, plan, record} = context;
  const account = (await readUser(db.collection('users').doc(hike.userId), ['profile', 'preferences', 'sos'])).data();
  if (!account || account.accountDisabled === true || account.status === 'disabled') return publicState(record);
  const phones = [...new Set((Array.isArray(account.sos_contacts) ? account.sos_contacts : [])
    .map(contact => contact.phoneNumber).filter(phone => /^\+[1-9]\d{7,14}$/.test(String(phone))))].slice(0, 3);
  if (phones.length) {
    const caption = arrivalCaption({hike, samples, ownerName: account.profile?.username,
      preferredTimeZone: account.preferredTimeZone, now});
    const image = footprintImage(samples, plan.targets);
    for (const phone of phones) await deliverContact({db, sessionId, eventId: record.eventId, phone, sendFile, image, caption, now, clock});
  }
  const receipts = await db.collection('arrivalSafetyDeliveries').where('eventId', '==', record.eventId).get();
  const data = receipts.docs.map(doc => doc.data()).filter(item => phones.includes(item.recipientPhone));
  const counts = {sentCount: data.filter(item => item.status === 'sent').length,
    uncertainCount: data.filter(item => ['delivery_uncertain', 'sending'].includes(item.status)).length,
    failedCount: data.filter(item => item.status === 'failed').length};
  const ref = db.collection('hikeSessions').doc(sessionId);
  const final = await db.runTransaction(async tx => {
    const currentHike = (await tx.get(ref)).data();
    const current = currentHike?.arrivalSafety;
    if (current?.eventId !== record.eventId) return current;
    const terminal = TERMINAL.has(current.status) || currentHike.status !== 'active';
    const complete = phones.length > 0 && counts.sentCount + counts.uncertainCount
      + data.filter(item => item.status === 'failed' && item.retryable !== true).length >= phones.length;
    const next = {...current, ...counts, lastAttemptAtMillis: now,
      ...(currentHike.status !== 'active' ? {enabled: false, status: 'completed'} : {}),
      ...(!terminal ? {status: !phones.length ? 'no_contacts' : complete
        ? counts.failedCount ? 'dispatch_failed' : 'dispatched' : 'dispatch_pending', enabled: !complete} : {})};
    tx.update(ref, {arrivalSafety: next});
    return next;
  });
  return publicState(final);
}

module.exports = {arm, confirmSafe, inspect, processHike, publicState, arrivalCaption, RESPONSE_WINDOW_MS,
  classifySosProviderHttpFailure};

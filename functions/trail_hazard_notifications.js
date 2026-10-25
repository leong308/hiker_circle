// Fresh report/hike reads fence each leased, retryable delivery to affected upcoming hikers.
'use strict';
const {createHash, randomUUID} = require('node:crypto');
const {readUser} = require('./user_modules');
const {classifyHazard, dateMillis, hazardExpiry, isActiveHazard, reportCycle,
  upcomingHazardRecipients, isUpcomingHazardHike, hazardAlertMessages} = require('./trail_hazard_policy');

const LEASE_MS = 2 * 60000;
const PERMANENT_TOKEN_ERRORS = new Set(['messaging/registration-token-not-registered', 'messaging/invalid-registration-token']);
const digest = value => createHash('sha256').update(value).digest('hex');
const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,180}$/.test(value);
function alertRevision(report) {
  const policy = classifyHazard(report?.hazardType);
  return digest(JSON.stringify([report?.trailId || '', report?.hazardType || '',
    policy.hazardCategory, policy.riskLevel, policy.hazardPolicyVersion]));
}

async function normalizeHazardReport({db, hazardId}) {
  const ref = db.collection('hazardReports').doc(hazardId);
  return db.runTransaction(async tx => {
    const snapshot = await tx.get(ref);
    if (!snapshot.exists) return null;
    const report = snapshot.data();
    const classification = classifyHazard(report.hazardType);
    const patch = Object.fromEntries(Object.entries(classification).filter(([key, value]) => report[key] !== value));
    if (!Number.isSafeInteger(report.cycle) || report.cycle < 0) patch.cycle = 0;
    if (!Number.isFinite(dateMillis(report.expiresAt)) && Number.isFinite(hazardExpiry(report))) {
      patch.expiresAt = new Date(hazardExpiry(report));
    }
    if (Object.keys(patch).length) tx.update(ref, patch);
    return {id: hazardId, ref, data: () => ({...report, ...patch})};
  });
}

function shouldDispatchReportChange(before, after, now = Date.now()) {
  return isActiveHazard(after, now) && (!before || !isActiveHazard(before, now)
    || reportCycle(before) !== reportCycle(after) || before.hazardType !== after.hazardType);
}

async function deliveryContext({tx, reportRef, hikeRef, phone, cycle, revision, now}) {
  const [reportSnapshot, hikeSnapshot] = await Promise.all([tx.get(reportRef), tx.get(hikeRef)]);
  const report = reportSnapshot.data(), hike = hikeSnapshot.data();
  let team;
  if (validId(hike?.teamHikeSessionId)) {
    team = (await tx.get(hikeRef.firestore.collection('teamHikeSessions').doc(hike.teamHikeSessionId))).data();
  }
  if (!isActiveHazard(report, now) || reportCycle(report) !== cycle || alertRevision(report) !== revision
    || !isUpcomingHazardHike(hike, now, team)
    || hike.trailId !== report.trailId || !upcomingHazardRecipients(hike).includes(phone)) return null;
  return {report, hike};
}

async function claimDelivery({db, report, hike, phone, now}) {
  const cycle = reportCycle(report.data());
  const revision = alertRevision(report.data());
  const id = digest(`${report.id}:${cycle}:${revision}:${hike.id}:${phone}`);
  const ref = db.collection('trailHazardDeliveries').doc(id);
  return db.runTransaction(async tx => {
    const previous = (await tx.get(ref)).data() || {};
    const current = await deliveryContext({tx, reportRef: report.ref, hikeRef: hike.ref, phone, cycle, revision, now});
    if (!current || previous.status === 'delivered' || previous.leaseUntil > now) return null;
    const attemptId = randomUUID();
    tx.set(ref, {hazardId: report.id, cycle, alertRevision: revision, upcomingHikeId: hike.id, recipientPhone: phone,
      attemptId, leaseUntil: now + LEASE_MS, attempts: (previous.attempts || 0) + 1,
      status: 'sending', updatedAt: new Date(now), expiresAt: new Date(now + 30 * 86400000)}, {merge: true});
    return {ref, attemptId, cycle, revision, sentTokenHashes: previous.sentTokenHashes || [], ...current};
  });
}

async function updateClaim(db, claim, patch) {
  return db.runTransaction(async tx => {
    const previous = (await tx.get(claim.ref)).data();
    if (previous?.attemptId !== claim.attemptId) return false;
    tx.set(claim.ref, patch, {merge: true});
    return true;
  });
}

async function pruneInvalidTokens({db, userRef, tokens}) {
  if (!tokens.size) return;
  const ref = userRef.collection('modules').doc('devices');
  await db.runTransaction(async tx => {
    const snapshot = await tx.get(ref);
    if (!snapshot.exists) return;
    const current = snapshot.data()?.fcmTokenByAppId || {};
    const remaining = Object.fromEntries(Object.entries(current).filter(([, token]) => !tokens.has(token)));
    if (Object.keys(remaining).length !== Object.keys(current).length) {
      // Replace this map in a transaction so a concurrently refreshed token is preserved.
      tx.set(ref, {fcmTokenByAppId: remaining}, {mergeFields: ['fcmTokenByAppId']});
    }
  });
}

async function deliverToRecipient({db, messaging, userId, tokensFor, report, hike, phone,
  clock, loadRecipient, pruneTokens}) {
  // A large fan-out can outlive a lease duration; each recipient starts its own fresh lease.
  const claim = await claimDelivery({db, report, hike, phone, now: clock()});
  if (!claim) return 0;
  let retryNeeded = false, successCount = 0;
  const sent = new Set(claim.sentTokenHashes), invalid = new Set();
  const userRef = db.collection('users').doc(userId(phone));
  try {
    const user = loadRecipient ? await loadRecipient(phone) : (await readUser(userRef, ['devices'])).data();
    if (!user || user.accountDisabled === true || user.status === 'disabled') {
      await updateClaim(db, claim, {status: 'no_registered_device', leaseUntil: 0});
      return 0;
    }
    const tokens = [...new Set(tokensFor(user).filter(token => typeof token === 'string' && token))];
    const pending = tokens.filter(token => !sent.has(digest(token)));
    for (let start = 0; start < pending.length; start += 500) {
      // Scheduling, membership, report resolution and team phase may change during device lookup.
      const context = await db.runTransaction(async tx => {
        const currentClaim = (await tx.get(claim.ref)).data();
        if (currentClaim?.attemptId !== claim.attemptId) return null;
        return deliveryContext({tx, reportRef: report.ref, hikeRef: hike.ref, phone,
          cycle: claim.cycle, revision: claim.revision, now: clock()});
      });
      if (!context) {
        await updateClaim(db, claim, {status: 'stale', leaseUntil: 0});
        return successCount;
      }
      const batch = pending.slice(start, start + 500);
      const messages = hazardAlertMessages(context.report);
      const departure = dateMillis(context.hike.departureTimeLocal || context.hike.departureTime);
      const expires = Math.min(departure, hazardExpiry(context.report), clock() + 28 * 86400000);
      const response = await messaging.sendEachForMulticast({tokens: batch,
        notification: {title: messages.title,
          body: `${String(context.hike.trailName || context.report.trailName || 'Your trail').slice(0, 100)} — Community report: ${String(context.report.hazardType || 'Trail caution').slice(0, 100)}. ${messages.injunctive} ${messages.descriptive}`.slice(0, 900)},
        data: {type: 'trail_hazard_alert', hazardId: report.id, trailId: context.report.trailId,
          upcomingHikeId: hike.id, framing: messages.framing,
          deepLink: `hikercircle://upcoming-hike/view?upcomingHikeId=${encodeURIComponent(hike.id)}&hazardId=${encodeURIComponent(report.id)}`},
        android: {priority: 'high', ttl: Math.max(0, expires - clock()),
          notification: {channelId: 'hiker_circle_upcoming_hikes', priority: 'high'}},
        apns: {headers: {'apns-priority': '10', 'apns-expiration': String(Math.floor(expires / 1000))},
          payload: {aps: {sound: 'default'}}},
      });
      for (let i = 0; i < batch.length; i++) {
        const result = response.responses?.[i];
        if (result?.success) { sent.add(digest(batch[i])); successCount++; }
        else if (PERMANENT_TOKEN_ERRORS.has(result?.error?.code)) invalid.add(batch[i]);
        else retryNeeded = true;
      }
      await updateClaim(db, claim, {sentTokenHashes: [...sent], leaseUntil: clock() + LEASE_MS});
    }
    if (invalid.size) {
      if (pruneTokens) await pruneTokens(phone, invalid);
      else await pruneInvalidTokens({db, userRef, tokens: invalid});
    }
    const allCurrentDelivered = tokens.length > 0 && tokens.every(token => sent.has(digest(token)) || invalid.has(token));
    await updateClaim(db, claim, {leaseUntil: 0, sentTokenHashes: [...sent],
      status: retryNeeded ? 'retry' : allCurrentDelivered && sent.size ? 'delivered' : 'no_registered_device',
      ...(allCurrentDelivered && sent.size && !retryNeeded ? {sentAt: new Date(clock())} : {})});
    if (retryNeeded) throw Error('Some trail caution notifications need retry.');
    return successCount;
  } catch (error) {
    await updateClaim(db, claim, {status: 'retry', leaseUntil: 0, sentTokenHashes: [...sent]});
    throw error;
  }
}

// A provided report limits a new-report trigger to its trail; scheduler catch-up also handles later plans/joins.
async function sendTrailHazardAlerts({db, messaging, userId, tokensFor, now = Date.now(), clock = Date.now,
  hikes, report, loadRecipient, pruneTokens}) {
  if (report && (!isActiveHazard(report.data(), now) || !validId(report.data().trailId))) return {sent: 0};
  const snapshot = hikes || await (report
    ? db.collection('upcomingHikes').where('trailId', '==', report.data().trailId)
    : db.collection('upcomingHikes')).get();
  const reportsByTrail = new Map();
  const errors = [];
  let sent = 0;
  for (const hike of snapshot.docs) {
    const data = hike.data();
    if (!isUpcomingHazardHike(data, now) || !validId(data.trailId)) continue;
    let reports;
    if (report) reports = report.data().trailId === data.trailId ? [report] : [];
    else {
      if (!reportsByTrail.has(data.trailId)) {
        const cautions = await db.collection('hazardReports').where('trailId', '==', data.trailId).get();
        const normalized = [];
        for (const caution of cautions.docs.filter(doc => isActiveHazard(doc.data(), now))) {
          const current = await normalizeHazardReport({db, hazardId: caution.id});
          if (current && isActiveHazard(current.data(), now)) normalized.push(current);
        }
        reportsByTrail.set(data.trailId, normalized);
      }
      reports = reportsByTrail.get(data.trailId);
    }
    for (const caution of reports) {
      for (const phone of upcomingHazardRecipients(data)) {
        try {
          sent += await deliverToRecipient({db, messaging, userId, tokensFor,
            report: caution, hike, phone, clock, loadRecipient, pruneTokens});
        } catch (error) { errors.push(error); }
      }
    }
  }
  if (errors.length) throw new AggregateError(errors, `${errors.length} trail caution deliveries need retry.`);
  return {sent};
}

module.exports = {normalizeHazardReport, shouldDispatchReportChange, sendTrailHazardAlerts,
  pruneInvalidTokens, alertRevision, LEASE_MS};

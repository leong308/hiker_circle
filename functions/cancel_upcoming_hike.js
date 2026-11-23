// Cancellation and personal withdrawal share the launch transaction's schedule
// and team reads, so a racing activation cannot be mistaken for an unstarted hike.
'use strict';
const {createHash} = require('node:crypto');
const {classifyHazard, dateMillis, isActiveHazard} = require('./trail_hazard_policy');
const {cancelledHikeHistoryFields} = require('./cancelled_hike_history');
const {teamTrackingStarted} = require('./team_launch_lifecycle');

const PHONE = /^\+[1-9]\d{7,14}$/;
const UNSTARTED_PHASES = new Set(['inviting', 'readyCheck', 'countdown']);
const TERMINAL_STATUSES = new Set(['active', 'started', 'ended', 'completed', 'cancelled', 'canceled', 'abandoned']);
const participantPhone = participant => String(participant?.phoneNumber || participant?.buddy?.phoneNumber || '').trim();
const validId = value => typeof value === 'string' && value.length > 0 && value.length <= 200
  && !value.includes('/') && !/[\u0000-\u001f]/.test(value);

async function cancelUpcomingHike(
  db, {hikeId, uid, phoneNumber, withdrawSelf = false, hazardId = '', creationKey = '',
    archiveAsExpired = false, cancelledAtLocal, expectedTeamId, now = Date.now()},
  HttpsError, timestamp, existingTransaction,
) {
  const reference = db.collection('upcomingHikes').doc(hikeId);
  const hash = creationKey ? createHash('sha256').update(`${uid}:${creationKey}`).digest('hex') : '';
  if (creationKey && (!/^[A-Za-z0-9_-]{8,240}$/.test(creationKey) || hikeId !== `upcoming_${hash.slice(0, 40)}` || withdrawSelf)) {
    throw new HttpsError('invalid-argument', 'The schedule identity is invalid.');
  }
  const intent = hash ? db.collection('upcomingHikeIntents').doc(hash) : null;
  const apply = async transaction => {
    // Query hike or pending scheduling intent
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) {
      // Update cloud: save pending cancellation intent
      if (intent) { transaction.set(intent, {cancelled: true, owner: uid, cancelledAt: timestamp(),
        cancelledAtLocal:cancelledHikeHistoryFields({uid,timestamp:null,now,cancelledAtLocal}).cancelledAtLocal}); return {cancelled: true, needsHistoryUpload: true}; }
      throw new HttpsError('not-found', 'This hike is no longer available.');
    }
    const hike = snapshot.data();
    const personal = withdrawSelf === true;
    const isHost = hike.creatorUserId === uid && hike.creatorPhone === phoneNumber;
    if (!personal && !isHost) {
      throw new HttpsError('permission-denied', 'Only the host can cancel this hike.');
    }
    if (personal && (!PHONE.test(phoneNumber) || uid !== phoneNumber)) {
      throw new HttpsError('unauthenticated', 'Sign in to withdraw from this hike.');
    }
    if (personal && (hike.creatorPhone === phoneNumber || hike.creatorUserId === uid)) {
      throw new HttpsError('failed-precondition', 'The host must cancel the hike for the group.');
    }
    if (!personal && hike.isDeleted === true) {
      if (hike.teamLaunchConsumed || hike.startedAt || hike.startedAtLocal
          || ['active','started','ended','completed','abandoned'].includes(String(hike.status || '').toLowerCase())) throw launchError(HttpsError);
      if (archiveAsExpired && !(hike.status === 'cancelled' && hike.historyCategory === 'expired' && hike.expired === true)) {
        // Update cloud: cancel upcoming hike
        transaction.update(reference, cancelledHikeHistoryFields({uid,timestamp:timestamp(),now,cancelledAtLocal}));
      }
      return {cancelled: true};
    }

    const participants = Array.isArray(hike.participantPhones) ? hike.participantPhones : [];
    let receiptReference;
    if (personal) {
      receiptReference = reference.collection('withdrawals').doc(uid);
      // Query cancellation receipt and linked hazard
      const receiptSnapshot = await transaction.get(receiptReference);
      const receipt = receiptSnapshot.data() || {};
      if (participants.includes(phoneNumber) && cancelledAtLocal
          && receipt.requestedAtLocal === cancelledAtLocal) {
        return {withdrawn: false, rejoined: true};
      }
      if (!participants.includes(phoneNumber)) {
        if (receiptSnapshot.exists && receipt.userId === uid
            && receipt.phoneNumber === phoneNumber && receipt.hikeId === hikeId) {
          return {withdrawn: true, alreadyWithdrawn: true};
        }
        throw new HttpsError('permission-denied', 'You are not a participant in this hike.');
      }
    }

    const hazardAction = hazardId !== '';
    if (hazardAction) {
      if (!validId(hazardId)) throw new HttpsError('invalid-argument', 'Select a valid trail caution.');
      const hazardSnapshot = await transaction.get(db.collection('hazardReports').doc(hazardId));
      const hazard = hazardSnapshot.data();
      if (!hazardSnapshot.exists || hazard.trailId !== hike.trailId
          || !isActiveHazard(hazard, now) || classifyHazard(hazard.hazardType).riskLevel !== 'fatal') {
        throw new HttpsError('failed-precondition', 'This serious trail caution is no longer active. Refresh the hike details.');
      }
    }
    if (personal || hazardAction || archiveAsExpired) {
      const departure = dateMillis(hike.departureTimeLocal || hike.departureTime || hike.draft?.departureTime);
      if (hike.isDeleted === true || !Number.isFinite(departure) ||
          !archiveAsExpired && !expectedTeamId && departure + 15 * 60 * 1000 <= now) {
        throw new HttpsError('failed-precondition', 'This upcoming hike is no longer available.');
      }
      if (hike.startedAt || hike.startedAtLocal || TERMINAL_STATUSES.has(String(hike.status || '').toLowerCase())) {
        throw launchError(HttpsError);
      }
    }
    const startedPhones = Array.isArray(hike.startedParticipantPhones) ? hike.startedParticipantPhones : [];
    if (hike.teamLaunchConsumed || startedPhones.some(phone => Boolean(String(phone || '').trim()))) throw launchError(HttpsError);
    const teamId = String(hike.teamHikeSessionId || '').trim();
    if (expectedTeamId && teamId !== expectedTeamId) throw launchError(HttpsError);
    const launchLinked = teamId || hike.teamLaunchLinkedAt || hike.teamLaunchLinkedAtLocal;
    if (launchLinked && !personal && !hazardAction && !archiveAsExpired) throw launchError(HttpsError);

    let teamReference;
    let team;
    let teamParticipants;
    let closedBeforeStart = false;
    if (launchLinked) {
      // Query linked launch before changing membership.
      if (!validId(teamId)) throw launchError(HttpsError);
      teamReference = db.collection('teamHikeSessions').doc(teamId);
      // Query linked team and chats
      const teamSnapshot = await transaction.get(teamReference);
      team = teamSnapshot.data() || {};
      teamParticipants = Array.isArray(team.participants) ? team.participants : [];
      closedBeforeStart = team.phase === 'completed'
        && ['launch_cancelled', 'invitation_expired'].includes(team.completionReason);
      if (!teamSnapshot.exists || team.sourceUpcomingHikeId !== hikeId
          || team.trailId !== hike.trailId || team.hostPhoneNumber !== hike.creatorPhone
          || team.hostUserId !== hike.creatorUserId || (!closedBeforeStart && !UNSTARTED_PHASES.has(team.phase))
          || teamTrackingStarted({...team, participants: teamParticipants})
          || Object.values(team.activeHikeSessionIdsByPhone || {}).some(Boolean)
          || teamParticipants.some(p => p.status === 'offline' || (!closedBeforeStart && p.status === 'ended'))
          || (!closedBeforeStart && !teamParticipants.some(p => participantPhone(p) === phoneNumber))) {
        throw launchError(HttpsError);
      }
    }

    const chatReferences = (personal || hazardAction || archiveAsExpired)
      ? [db.collection('groupChats').doc(`hike_${hikeId}`),
        ...(teamReference && !closedBeforeStart ? [db.collection('groupChats').doc(`team_${teamId}`)] : [])]
      : [];
    const chatSnapshots = await Promise.all(chatReferences.map(ref => transaction.get(ref)));
    chatSnapshots.forEach((chatSnapshot, index) => {
      if (!chatSnapshot.exists) return;
      const chat = chatSnapshot.data() || {};
      const wrongIdentity = index === 0
        ? chat.hikeSessionId !== hikeId || Boolean(chat.teamHikeSessionId)
        : chat.teamHikeSessionId !== teamId;
      if (wrongIdentity || chat.chatType === 'direct'
          || (chat.creatorPhone && chat.creatorPhone !== hike.creatorPhone)) {
        throw new HttpsError('failed-precondition', 'The hike conversation is unavailable. Refresh and try again.');
      }
    });

    const nowIso = new Date(now).toISOString();
    const updatedAt = timestamp();
    if (!personal) {
      // Update cloud: cancel linked hike, team and chats
      if (intent) transaction.set(intent, {cancelled: true, owner: uid, cancelledAt: timestamp(),
        cancelledAtLocal:cancelledHikeHistoryFields({uid,timestamp:null,now,cancelledAtLocal}).cancelledAtLocal});
      transaction.update(reference, {...cancelledHikeHistoryFields({uid,timestamp:updatedAt,now,cancelledAtLocal}),
        ...(hazardAction ? {cancelledForHazardId: hazardId, updatedAt, updatedAtLocal: nowIso} : {})});
      if (teamReference && !closedBeforeStart) {
        transaction.update(teamReference, endedTeamPatch(teamParticipants, updatedAt, nowIso));
      }
      chatSnapshots.forEach((chatSnapshot, index) => {
        if (chatSnapshot.exists) transaction.update(chatReferences[index], archivedChatPatch(updatedAt, nowIso));
      });
      return {cancelled: true};
    }

    const remaining = [...new Set([hike.creatorPhone, ...participants].filter(phone => phone && phone !== phoneNumber))];
    const remainingCount = remaining.length;
    const closeTeam = Boolean(teamReference && remainingCount === 1);
    const patch = {participantPhones: remaining, participantCount: remainingCount, updatedAt, updatedAtLocal: nowIso};
    const savedDraft = hike.draft && typeof hike.draft === 'object' && !Array.isArray(hike.draft)
      ? hike.draft : {};
    if (Array.isArray(savedDraft.teamBuddies)) {
      patch.draft = {...savedDraft,
        teamBuddies: savedDraft.teamBuddies.filter(buddy => buddy?.phoneNumber !== phoneNumber)};
    }
    if (remainingCount === 1) {
      patch.hikeType = 'solo';
      patch.draft = {...savedDraft, hikeType: 'solo', teamBuddies: []};
      // Team preparation cannot serve as the solo-distance acknowledgement.
      delete patch.draft.soloDistanceAcknowledgedKm;
      if (Object.hasOwn(hike, 'soloDistanceAcknowledgedKm')) patch.soloDistanceAcknowledgedKm = null;
    }
    if (closeTeam || closedBeforeStart) {
      // Release a closed launch so the current roster can start again.
      Object.assign(patch, {teamHikeSessionId: null, teamLaunchLinkedAt: null, teamLaunchLinkedAtLocal: null});
    }
    // Update cloud: save roster and withdrawal receipt
    transaction.update(reference, patch);
    transaction.set(receiptReference, {hikeId, userId: uid, phoneNumber,
      ...(typeof cancelledAtLocal === 'string' && cancelledAtLocal.length <= 40 ? {requestedAtLocal: cancelledAtLocal} : {}),
      withdrawnAt: updatedAt, withdrawnAtLocal: nowIso, ...(hazardAction ? {hazardId} : {})});
    let updatedTeam;
    if (teamReference && !closedBeforeStart) {
      const remainingTeam = teamParticipants.filter(participant => participantPhone(participant) !== phoneNumber);
      const nextTeam = closeTeam
        ? endedTeamPatch(remainingTeam, updatedAt, nowIso)
        : {participants: remainingTeam.map(participant => ({...participant,
            ...(participant.status === 'ready' ? {status: 'joined', readyAtLocal: null} : {}), updatedAtLocal: nowIso})),
          participantPhoneNumbers: remainingTeam.map(participantPhone),
          phase: remainingTeam.some(participant => participant.status === 'invited') ? 'inviting' : 'readyCheck',
          countdownStartedAt: null, countdownStartedAtLocal: null,
          readinessStartedAt: updatedAt, readinessStartedAtLocal: nowIso, updatedAt, updatedAtLocal: nowIso};
      transaction.update(teamReference, nextTeam);
      if (expectedTeamId) updatedTeam = {...team, ...nextTeam};
    }
    chatSnapshots.forEach((chatSnapshot, index) => {
      if (!chatSnapshot.exists) return;
      const chat = chatSnapshot.data() || {};
      const chatPatch = {participantPhones: Array.isArray(chat.participantPhones)
          ? chat.participantPhones.filter(phone => phone !== phoneNumber) : remaining,
        updatedAt, updatedAtLocal: nowIso, ...(closeTeam && index === 1 ? archivedChatPatch(updatedAt, nowIso) : {})};
      const phoneKey = phoneNumber.replace(/\D/g, '');
      for (const field of ['participantNames', 'participantPhotoURLs']) {
        if (chat[field] && typeof chat[field] === 'object' && !Array.isArray(chat[field])) {
          const values = {...chat[field]};
          delete values[phoneKey];
          chatPatch[field] = values;
        }
      }
      transaction.update(chatReferences[index], chatPatch);
    });
    return {withdrawn: true, ...(updatedTeam ? {team: updatedTeam} : {})};
  };
  return existingTransaction ? apply(existingTransaction) : db.runTransaction(apply);
}

function launchError(HttpsError) {
  return new HttpsError('failed-precondition', 'This hike has already started its launch. Return to the active hike controls.');
}

function endedTeamPatch(participants, updatedAt, nowIso) {
  return {phase: 'completed', completionReason: 'launch_cancelled',
    participants: participants.map(participant => ({...participant, status: 'ended', updatedAtLocal: nowIso})),
    participantPhoneNumbers: participants.map(participantPhone), endedAtLocal: nowIso,
    countdownStartedAt: null, countdownStartedAtLocal: null, updatedAt, updatedAtLocal: nowIso};
}

function archivedChatPatch(updatedAt, nowIso) {
  return {hikeEndedAtLocal: nowIso, closureReason: 'hike_cancelled', requiresHostNaming: false,
    namingPromptShown: true, namingPromptActive: false, updatedAt, updatedAtLocal: nowIso};
}

module.exports = {cancelUpcomingHike};

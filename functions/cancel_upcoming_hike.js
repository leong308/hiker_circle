// Cancellation and personal withdrawal share the launch transaction's schedule
// and team reads, so a racing activation cannot be mistaken for an unstarted hike.
'use strict';
const {classifyHazard, dateMillis, isActiveHazard} = require('./trail_hazard_policy');

const PHONE = /^\+[1-9]\d{7,14}$/;
const UNSTARTED_PHASES = new Set(['inviting', 'readyCheck', 'countdown']);
const TERMINAL_STATUSES = new Set(['active', 'started', 'ended', 'completed', 'cancelled', 'canceled', 'abandoned']);
const participantPhone = participant => String(participant?.phoneNumber || participant?.buddy?.phoneNumber || '').trim();
const validId = value => typeof value === 'string' && value.length > 0 && value.length <= 200
  && !value.includes('/') && !/[\u0000-\u001f]/.test(value);

async function cancelUpcomingHike(
  db, {hikeId, uid, phoneNumber, withdrawSelf = false, hazardId = '', now = Date.now()},
  HttpsError, timestamp,
) {
  const reference = db.collection('upcomingHikes').doc(hikeId);
  return db.runTransaction(async transaction => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) throw new HttpsError('not-found', 'This hike is no longer available.');
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
    if (!personal && hike.isDeleted === true) return {cancelled: true};

    const participants = Array.isArray(hike.participantPhones) ? hike.participantPhones : [];
    let receiptReference;
    if (personal) {
      receiptReference = reference.collection('withdrawals').doc(uid);
      const receiptSnapshot = await transaction.get(receiptReference);
      if (!participants.includes(phoneNumber)) {
        const receipt = receiptSnapshot.data() || {};
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
    if (personal || hazardAction) {
      const departure = dateMillis(hike.departureTimeLocal || hike.departureTime || hike.draft?.departureTime);
      if (hike.isDeleted === true || !Number.isFinite(departure) || departure + 15 * 60 * 1000 <= now) {
        throw new HttpsError('failed-precondition', 'This upcoming hike is no longer available.');
      }
      if (hike.startedAt || hike.startedAtLocal || TERMINAL_STATUSES.has(String(hike.status || '').toLowerCase())) {
        throw launchError(HttpsError);
      }
    }
    const startedPhones = Array.isArray(hike.startedParticipantPhones) ? hike.startedParticipantPhones : [];
    if (startedPhones.some(phone => Boolean(String(phone || '').trim()))) throw launchError(HttpsError);
    const teamId = String(hike.teamHikeSessionId || '').trim();
    const launchLinked = teamId || hike.teamLaunchLinkedAt || hike.teamLaunchLinkedAtLocal;
    if (launchLinked && !hazardAction) throw launchError(HttpsError);

    let teamReference;
    let team;
    let teamParticipants;
    if (launchLinked) {
      // Only a currently active fatal report may relax the ordinary launch fence.
      // A missing/mismatched/started team always fails closed.
      if (!validId(teamId)) throw launchError(HttpsError);
      teamReference = db.collection('teamHikeSessions').doc(teamId);
      const teamSnapshot = await transaction.get(teamReference);
      team = teamSnapshot.data() || {};
      teamParticipants = Array.isArray(team.participants) ? team.participants : [];
      if (!teamSnapshot.exists || team.sourceUpcomingHikeId !== hikeId
          || team.trailId !== hike.trailId || team.hostPhoneNumber !== hike.creatorPhone
          || team.hostUserId !== hike.creatorUserId || !UNSTARTED_PHASES.has(team.phase)
          || team.startedAt || team.startedAtLocal || team.activeHikeSessionId
          || Object.values(team.activeHikeSessionIdsByPhone || {}).some(Boolean)
          || teamParticipants.some(participant => ['active', 'offline', 'ended'].includes(participant.status))
          || !teamParticipants.some(participant => participantPhone(participant) === phoneNumber)) {
        throw launchError(HttpsError);
      }
    }

    const chatReferences = (personal || hazardAction)
      ? [db.collection('groupChats').doc(`hike_${hikeId}`),
        ...(teamReference ? [db.collection('groupChats').doc(`team_${teamId}`)] : [])]
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
      transaction.update(reference, {isDeleted: true, cancelledByUserId: uid, cancelledAt: updatedAt,
        ...(hazardAction ? {cancelledForHazardId: hazardId, updatedAt, updatedAtLocal: nowIso} : {})});
      if (teamReference) {
        transaction.update(teamReference, endedTeamPatch(teamParticipants, updatedAt, nowIso));
      }
      chatSnapshots.forEach((chatSnapshot, index) => {
        if (chatSnapshot.exists) transaction.update(chatReferences[index], archivedChatPatch(updatedAt, nowIso));
      });
      return {cancelled: true};
    }

    const remaining = participants.filter(phone => phone !== phoneNumber);
    const remainingCount = new Set([hike.creatorPhone, ...remaining].filter(Boolean)).size;
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
    if (closeTeam) {
      // The remaining host must be able to retry as a solo hike. A closed team
      // cannot remain linked to a one-person source (the start callable rejects it).
      Object.assign(patch, {teamHikeSessionId: null, teamLaunchLinkedAt: null, teamLaunchLinkedAtLocal: null});
    }
    transaction.update(reference, patch);
    transaction.set(receiptReference, {hikeId, userId: uid, phoneNumber,
      withdrawnAt: updatedAt, withdrawnAtLocal: nowIso, ...(hazardAction ? {hazardId} : {})});
    if (teamReference) {
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
    return {withdrawn: true};
  });
}

function launchError(HttpsError) {
  return new HttpsError('failed-precondition', 'This hike has already started its launch. Return to the active hike controls.');
}

function endedTeamPatch(participants, updatedAt, nowIso) {
  return {phase: 'completed', participants: participants.map(participant => ({...participant, status: 'ended', updatedAtLocal: nowIso})),
    participantPhoneNumbers: participants.map(participantPhone), endedAtLocal: nowIso,
    countdownStartedAt: null, countdownStartedAtLocal: null, updatedAt, updatedAtLocal: nowIso};
}

function archivedChatPatch(updatedAt, nowIso) {
  return {hikeEndedAtLocal: nowIso, closureReason: 'hazard_hike_cancelled', requiresHostNaming: false,
    namingPromptShown: true, namingPromptActive: false, updatedAt, updatedAtLocal: nowIso};
}

module.exports = {cancelUpcomingHike};

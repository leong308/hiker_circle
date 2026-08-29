const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
} = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions/v2');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const {
  FieldPath,
  FieldValue,
  GeoPoint,
  Timestamp,
  getFirestore,
} = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { getMessaging } = require('firebase-admin/messaging');
const crypto = require('crypto');
const argon2 = require('argon2');
const {
  SosDispatchValidationError,
  classifySosProviderHttpFailure,
  composeSosMessage,
  normalizeSosTimeZone,
  parseSosDispatchRequest,
  sosDispatchDocumentId,
  sosDispatchPayloadHash,
} = require('./sos_dispatch_helpers');
const {
  greenApiMessageId,
  greenApiStateReadiness,
} = require('./green_api_helpers');
const {
  buildUpcomingHikePreview,
  effectiveUpcomingHikeType,
} = require('./upcoming_hike_helpers');
const {
  joinRequestDocumentId,
  joinRequestLifecycle,
  upcomingHikeUnavailableReason,
} = require('./upcoming_hike_join_request_helpers');
const {
  detailData: hikeHistoryDetailData,
  summaryData: hikeHistorySummaryData,
} = require('./hike_history_helpers');
const {
  trailRatingAggregate,
  validRating,
} = require('./trail_rating_helpers');
const {
  upcomingHikeReminderDue,
} = require('./upcoming_hike_reminder_helpers');
const {
  normalizeNearbySosReport,
} = require('./nearby_sos_helpers');
const {
  SHARED_HIKE_PLAN_PRIVACY_VERSION,
  projectSharedHikePlan,
  sharedHikePlanNeedsRedaction,
  sharedRouteAndTimingMatch,
  teamSourceMatchesRequest,
  scheduledTeamLaunchCanResume,
  legacyActiveHikeCanAdoptTeamSource,
} = require('./shared_hike_plan_helpers');
const {
  MFA_CHALLENGE_TTL_MILLIS,
  MFA_SESSION_TTL_MILLIS,
  decryptTotpSecret,
  encryptTotpSecret,
  generateTotpSecret,
  opaqueTokenDigest,
  otpauthUri,
  randomOpaqueToken,
  verifyTotp,
} = require('./mfa_helpers');

admin.initializeApp();

// firebase-admin v14 removed the legacy namespace accessors, while this
// backend intentionally still uses their concise syntax throughout. Keep one
// compatibility adapter at the entry point so every callable and trigger uses
// the supported modular SDK underneath without a risky whole-file rewrite.
const firestoreAccessor = () => getFirestore();
Object.assign(firestoreAccessor, {
  FieldPath,
  FieldValue,
  GeoPoint,
  Timestamp,
});
admin.firestore = firestoreAccessor;
admin.auth = () => getAuth();
admin.messaging = () => getMessaging();

const greenApiInstanceId = defineSecret('GREEN_API_INSTANCE_ID');
const greenApiToken = defineSecret('GREEN_API_TOKEN');
const mfaTotpEncryptionKey = defineSecret('MFA_TOTP_ENCRYPTION_KEY');

// Accepts an explicitly unverified observation from a signed-in nearby phone.
// A deterministic device/counter incident ID and one report per account prevent
// repeated BLE advertisements or reconnect retries from creating emergencies.
exports.forwardNearbySosIncident = onCall(
  {},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Sign in before forwarding a nearby SOS.');
    }
    let report;
    try {
      report = normalizeNearbySosReport(request.data);
    } catch (error) {
      logger.warn('Rejected invalid nearby SOS forwarding report', {
        uid,
        reason: error?.message || 'invalid-report',
      });
      throw new HttpsError('invalid-argument', 'The nearby SOS report is invalid or stale.');
    }

    const firestore = admin.firestore();
    const incidentRef = firestore.collection('nearbySosIncidents').doc(report.incidentId);
    const reporterHash = crypto.createHash('sha256').update(uid).digest('hex');
    const reporterRef = incidentRef.collection('reports').doc(reporterHash);
    let reporterCount = 1;
    let deduplicated = false;
    await firestore.runTransaction(async (transaction) => {
      const [incidentSnapshot, reporterSnapshot] = await Promise.all([
        transaction.get(incidentRef),
        transaction.get(reporterRef),
      ]);
      deduplicated = incidentSnapshot.exists;
      const existing = incidentSnapshot.data() || {};
      reporterCount = Number(existing.reporterCount || 0)
        + (reporterSnapshot.exists ? 0 : 1);
      const nowIso = new Date().toISOString();
      const location = report.reportedLocation || report.detectorLocation;
      transaction.set(incidentRef, {
        incidentId: report.incidentId,
        deviceIdHash: report.deviceIdHash,
        counter: report.counter,
        verificationState: 'unverified_nearby_ble',
        status: 'active',
        reporterCount,
        firstReceivedAtLocal: existing.firstReceivedAtLocal
          || new Date(report.receivedAtMillis).toISOString(),
        lastReceivedAtLocal: new Date(report.receivedAtMillis).toISOString(),
        updatedAt: FieldValue.serverTimestamp(),
        updatedAtLocal: nowIso,
        ...(location ? {
          latitude: location.latitude,
          longitude: location.longitude,
          accuracyMeters: location.accuracyMeters,
          locationSource: report.reportedLocation ? 'button_relay' : 'detector_phone',
        } : {}),
      }, { merge: true });
      transaction.set(reporterRef, {
        reporterHash,
        receivedAtLocal: new Date(report.receivedAtMillis).toISOString(),
        rssi: report.rssi,
        reportedLocation: report.reportedLocation,
        detectorLocation: report.detectorLocation,
        updatedAt: FieldValue.serverTimestamp(),
        updatedAtLocal: nowIso,
      }, { merge: true });
    });
    return { incidentId: report.incidentId, deduplicated, reporterCount };
  },
);

const achievementSeedDefinitions = Object.freeze({
  first_safe_hike: {
    title: 'First Safe Hike',
    condition: 'Complete first hike session',
    category: 'Hike milestone',
    iconName: 'verified_user',
    rewardPoints: 120,
    rewardType: 'one_time',
    metricKey: 'hike_completed',
    targetCount: 1,
    isActive: true,
    sortOrder: 10,
    accentColorValue: 0xff34a853,
  },
  prepared_adventurer: {
    title: 'Prepared Adventurer',
    condition: 'Download offline map before starting',
    category: 'Preparation',
    iconName: 'map',
    rewardPoints: 90,
    rewardType: 'one_time',
    // This metric must only be emitted once the backend can verify that an
    // offline map was available at departure. Starting a hike alone is not
    // proof of preparation.
    metricKey: 'offline_map_verified_at_hike_start',
    targetCount: 1,
    isActive: false,
    sortOrder: 20,
    accentColorValue: 0xff2f80ed,
  },
  safety_first: {
    title: 'Safety First',
    condition: 'Complete gear checklist before departure',
    category: 'Preparation',
    iconName: 'health_and_safety',
    rewardPoints: 100,
    rewardType: 'one_time',
    // A non-empty client list is not proof that the complete required
    // checklist was finished. Keep this metric reserved for a future
    // server-verified checklist workflow.
    metricKey: 'full_checklist_verified_at_departure',
    targetCount: 1,
    isActive: false,
    sortOrder: 30,
    accentColorValue: 0xfff2994a,
  },
  reliable_check_in: {
    title: 'Reliable Check-In',
    condition: 'Complete 5 scheduled check-ins during hikes',
    category: 'Safety habit',
    iconName: 'task_alt',
    rewardPoints: 110,
    rewardType: 'cumulative',
    metricKey: 'check_in_completed',
    targetCount: 5,
    isActive: true,
    sortOrder: 40,
    accentColorValue: 0xff9b51e0,
  },
  security_guardian: {
    title: 'Security Guardian',
    condition: 'Protect your account with both Authenticator and a passkey',
    category: 'Account security',
    iconName: 'verified_user',
    rewardPoints: 150,
    rewardType: 'cumulative',
    metricKey: 'security_factor_type_bound',
    targetCount: 2,
    isActive: true,
    sortOrder: 45,
    accentColorValue: 0xff2f80ed,
  },
  community_helper: {
    title: 'Community Helper',
    condition: 'Submit a hazard report later confirmed by others',
    category: 'Community',
    iconName: 'volunteer_activism',
    rewardPoints: 140,
    rewardType: 'one_time',
    metricKey: 'hazard_report_approved',
    targetCount: 1,
    isActive: true,
    sortOrder: 50,
    accentColorValue: 0xffeb5757,
  },
  team_guardian: {
    title: 'Team Guardian',
    condition: 'Complete 3 team hikes without a separation emergency',
    category: 'Team hike',
    iconName: 'groups',
    rewardPoints: 160,
    rewardType: 'cumulative',
    metricKey: 'team_hike_completed',
    targetCount: 3,
    isActive: true,
    sortOrder: 60,
    accentColorValue: 0xff00a99d,
  },
});

function userDocumentIdForPhone(phoneNumber) {
  return String(phoneNumber || '').replace(/\//g, '_');
}

function authenticatedPhoneClaim(request) {
  const token = request.auth?.token || {};
  const candidates = [
    token.phoneNumber,
    token.phone_number,
    request.auth?.uid,
  ];
  for (const candidate of candidates) {
    const phoneNumber = String(candidate || '').trim();
    if (/^\+[1-9]\d{7,14}$/.test(phoneNumber)) return phoneNumber;
  }
  return '';
}

function phoneKeyFor(phoneNumber) {
  return String(phoneNumber || '').replace(/\D/g, '');
}

function isAdminUser(user) {
  const role = String(user.role || '').toLowerCase();
  const roles = Array.isArray(user.roles)
    ? user.roles.map((value) => String(value || '').toLowerCase())
    : [];
  return (
    user.isAdmin === true ||
    role === 'admin' ||
    role === 'super_admin' ||
    roles.includes('admin')
  );
}

function latestFcmTokensForUser(user) {
  const fcmTokenByAppId =
    user.fcmTokenByAppId && typeof user.fcmTokenByAppId === 'object'
      ? user.fcmTokenByAppId
      : {};
  const latestAppInstanceId = [
    user.boundAppInstanceId,
    user.lastSignedInAppInstanceId,
    user.currentAppId,
    user.activeFcmAppInstanceId,
  ]
    .map((value) => String(value || '').trim())
    .find((value) => value);
  const activeAppInstanceId = String(user.activeFcmAppInstanceId || '').trim();

  if (latestAppInstanceId) {
    const token = fcmTokenByAppId[latestAppInstanceId];
    if (typeof token === 'string' && token.length > 20) {
      return [token];
    }

    const activeToken = String(user.activeFcmToken || '').trim();
    if (
      activeAppInstanceId === latestAppInstanceId &&
      activeToken.length > 20
    ) {
      return [activeToken];
    }

    return [];
  }

  const lastToken = String(user.lastFcmToken || '').trim();
  if (lastToken.length > 20) {
    return [lastToken];
  }

  const legacyTokens = Array.isArray(user.fcmTokens)
    ? user.fcmTokens.filter(
        (token) => typeof token === 'string' && token.length > 20
      )
    : [];
  return legacyTokens.length === 1 ? legacyTokens : [];
}

async function reserveOtpChallenge({
  reference,
  phoneNumber,
  codeHash,
  expiresAtMillis,
  cooldownMessage,
}) {
  const sentAtMillis = Date.now();
  await admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const previousSentAt = Number(snapshot.data()?.sentAtMillis || 0);
    if (sentAtMillis - previousSentAt < 60 * 1000) {
      throw new HttpsError('resource-exhausted', cooldownMessage);
    }
    transaction.set(reference, {
      phoneNumber,
      codeHash,
      attemptsRemaining: 5,
      consumed: false,
      deliveryState: 'sending',
      sentAtMillis,
      expiresAtMillis,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return sentAtMillis;
}

async function markOtpDeliveryFailed(reference, error) {
  const safeError = typeof error === 'string'
    ? error
    : String(error?.code || error?.name || 'transport_error');
  await reference.set(
    {
      deliveryState: 'failed',
      sentAtMillis: 0,
      deliveryError: safeError.slice(0, 160),
      deliveryFailedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

async function markOtpDeliveryUncertain(reference, error) {
  const safeError = String(error?.code || error?.name || 'transport_error');
  await reference.set(
    {
      deliveryState: 'uncertain',
      deliveryError: safeError.slice(0, 160),
      deliveryUncertainAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

async function updateTeamParticipantForHike(hike, nextStatus) {
  const teamHikeSessionId = String(hike.teamHikeSessionId || '');
  const phoneNumber = String(hike.userPhoneNumber || hike.phoneNumber || '');
  if (!teamHikeSessionId || !phoneNumber) {
    return;
  }
  const db = admin.firestore();
  const reference = db
    .collection('teamHikeSessions')
    .doc(teamHikeSessionId);
  const updatedTeam = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) {
      return null;
    }
    const team = snapshot.data() || {};
    if (team.phase === 'completed') {
      return team;
    }
    const nowIso = new Date().toISOString();
    const participants = (Array.isArray(team.participants) ? team.participants : [])
      .map((participant) => {
        if (teamParticipantPhone(participant) !== phoneNumber) {
          return participant;
        }
        return {
          ...participant,
          status: nextStatus,
          updatedAtLocal: nowIso,
        };
      });
    const everyoneEnded =
      participants.length > 0
      && participants.every((participant) => participant?.status === 'ended');
    const patch = {
      participants,
      participantPhoneNumbers: participants.map(teamParticipantPhone),
      ...(everyoneEnded
        ? {
            phase: 'completed',
            endedAtLocal: nowIso,
            completionReason: String(team.completionReason || 'all_participants_ended'),
          }
        : {}),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAtLocal: nowIso,
    };
    transaction.set(
      reference,
      patch,
      { merge: true }
    );
    return { ...team, ...patch };
  });
  if (updatedTeam && String(updatedTeam.phase || '') === 'completed') {
    await ensureTeamChatDocument(db, teamHikeSessionId, updatedTeam);
  }
}

exports.sendGreenApiLoginCode = onCall(
  { secrets: [greenApiInstanceId, greenApiToken] },
  async (request) => {
    const phoneNumber = String(request.data?.phoneNumber || '').trim();
    if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
      throw new HttpsError(
        'invalid-argument',
        'Enter a valid international phone number.'
      );
    }
    const intent = String(request.data?.intent || '').trim();
    if (!['sign_in', 'sign_up'].includes(intent)) {
      throw new HttpsError('invalid-argument', 'Choose Sign Up or Login and try again.');
    }
    const accountSnapshot = await admin.firestore()
      .collection('users')
      .doc(userDocumentIdForPhone(phoneNumber))
      .get();
    if (intent === 'sign_in' && !accountSnapshot.exists) {
      throw new HttpsError('not-found', 'No account was found for this phone number.');
    }
    if (intent === 'sign_up' && accountSnapshot.exists) {
      throw new HttpsError(
        'already-exists',
        'This phone number already has an account. Log in instead.'
      );
    }

    let credentials;
    try {
      credentials = await requireGreenApiReady();
    } catch (error) {
      logger.error(
        'GreenAPI login readiness failed',
        greenApiReadinessLog(error)
      );
      throw greenApiReadinessHttpsError(error);
    }

    const challengeId = crypto
      .createHash('sha256')
      .update(phoneNumber)
      .digest('hex');
    const challengeReference = admin
      .firestore()
      .collection('greenApiLoginChallenges')
      .doc(challengeId);
    const code = crypto.randomInt(0, 1000000).toString().padStart(6, '0');
    const expiresAtMillis = Date.now() + 5 * 60 * 1000;
    const codeHash = crypto
      .createHmac('sha256', greenApiToken.value())
      .update(`${challengeId}:${code}`)
      .digest('hex');
    await reserveOtpChallenge({
      reference: challengeReference,
      phoneNumber,
      codeHash,
      expiresAtMillis,
      cooldownMessage: 'Wait one minute before requesting another WhatsApp code.',
    });
    await challengeReference.set({ intent }, { merge: true });
    const digitsOnly = phoneNumber.replace(/\D/g, '');
    let response;
    try {
      response = await fetch(
        greenApiEndpoint('sendMessage', credentials),
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            chatId: `${digitsOnly}@c.us`,
            message:
              `Your HikerCircle verification code is ${code}. ` +
              'It expires in 5 minutes.',
          }),
          signal: AbortSignal.timeout(12 * 1000),
        }
      );
    } catch (error) {
      logger.error('GreenAPI login transport failed', {
        challengeId,
        errorName: String(error?.name || ''),
        errorCode: providerTransportErrorCode(error),
      });
      if (providerFailureWasDefinitelyUnsent(error)) {
        await markOtpDeliveryFailed(challengeReference, error);
      } else {
        await markOtpDeliveryUncertain(challengeReference, error);
      }
      throw new HttpsError(
        'unavailable',
        'WhatsApp verification is temporarily unavailable.'
      );
    }
    if (!response.ok) {
      logger.error('GreenAPI login message failed', {
        status: response.status,
        challengeId,
      });
      if (classifySosProviderHttpFailure(response.status).deliveryUncertain) {
        await markOtpDeliveryUncertain(
          challengeReference,
          `HTTP ${response.status}`
        );
      } else {
        await markOtpDeliveryFailed(challengeReference, `HTTP ${response.status}`);
      }
      throw new HttpsError(
        'unavailable',
        'WhatsApp verification is temporarily unavailable.'
      );
    }
    const responseData = await response.json().catch(() => null);
    const providerMessageId = greenApiMessageId(responseData);
    if (!providerMessageId) {
      logger.error('GreenAPI login response did not include idMessage', {
        challengeId,
      });
      await markOtpDeliveryUncertain(
        challengeReference,
        'Missing provider message id'
      );
      throw new HttpsError(
        'unavailable',
        'WhatsApp accepted the request but delivery could not be confirmed. Wait one minute before trying again.'
      );
    }
    await challengeReference.set(
      {
        deliveryState: 'sent',
        providerMessageId: providerMessageId.slice(0, 240),
        deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return { challengeId, expiresAtMillis };
  }
);

function sosDispatchClientResponse(record, { alreadySent = false } = {}) {
  const status = String(record.status || 'failed');
  if (status === 'sent') {
    return {
      sent: true,
      status: alreadySent ? 'already_sent' : 'sent',
      retryable: false,
      idMessage: String(record.providerMessageId || ''),
    };
  }
  if (status === 'delivery_uncertain') {
    return {
      sent: false,
      status: 'delivery_uncertain',
      retryable: false,
      message:
        'Delivery could not be confirmed. HikerCircle will not resend this dispatch automatically to avoid a duplicate alert.',
    };
  }
  if (status === 'claimed' || status === 'sending') {
    return {
      sent: false,
      status: 'in_progress',
      retryable: true,
      message: 'This emergency dispatch is already being processed.',
    };
  }
  return {
    sent: false,
    status: 'failed',
    retryable: record.retryable === true,
    message: String(
      record.clientMessage
        || 'Emergency messaging is unavailable. Call emergency services directly.'
    ),
  };
}

async function transitionSosDispatch(
  reference,
  attemptNonce,
  allowedStatuses,
  updates
) {
  return admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const current = snapshot.data() || {};
    if (
      !snapshot.exists
      || String(current.attemptNonce || '') !== attemptNonce
      || !allowedStatuses.has(String(current.status || ''))
    ) {
      return false;
    }
    transaction.set(
      reference,
      {
        ...updates,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: new Date().toISOString(),
      },
      { merge: true }
    );
    return true;
  });
}

function providerTransportErrorCode(error) {
  let current = error;
  for (let depth = 0; depth < 4 && current; depth++) {
    const code = String(current.code || '').trim();
    if (code) return code;
    current = current.cause;
  }
  return '';
}

function providerFailureWasDefinitelyUnsent(error) {
  return new Set([
    'ENOTFOUND',
    'EAI_AGAIN',
    'ECONNREFUSED',
    'UND_ERR_CONNECT_TIMEOUT',
  ]).has(providerTransportErrorCode(error));
}

class GreenApiReadinessError extends Error {
  constructor(message, { retryable = true, state = '', httpStatus = null } = {}) {
    super(message);
    this.name = 'GreenApiReadinessError';
    this.retryable = retryable;
    this.state = state;
    this.httpStatus = httpStatus;
  }
}

function greenApiCredentials() {
  const instanceId = String(greenApiInstanceId.value() || '').trim();
  const token = String(greenApiToken.value() || '').trim();
  if (!/^\d{4,20}$/.test(instanceId) || !/^[^\s/]{20,256}$/.test(token)) {
    throw new GreenApiReadinessError(
      'GreenAPI credentials are not configured correctly.',
      { retryable: false }
    );
  }
  return { instanceId, token };
}

function greenApiEndpoint(method, credentials = greenApiCredentials()) {
  return `https://api.green-api.com/waInstance${credentials.instanceId}`
    + `/${method}/${credentials.token}`;
}

async function requireGreenApiReady() {
  const credentials = greenApiCredentials();
  let response;
  try {
    response = await fetch(greenApiEndpoint('getStateInstance', credentials), {
      method: 'GET',
      signal: AbortSignal.timeout(8 * 1000),
    });
  } catch (error) {
    throw new GreenApiReadinessError(
      'GreenAPI status could not be reached. Try again shortly.',
      { retryable: true }
    );
  }
  if (!response.ok) {
    throw new GreenApiReadinessError(
      response.status === 401 || response.status === 403
        ? 'GreenAPI rejected the configured instance credentials.'
        : 'GreenAPI status is temporarily unavailable.',
      {
        retryable: response.status === 425
          || response.status === 429
          || response.status >= 500,
        httpStatus: response.status,
      }
    );
  }
  const body = await response.json().catch(() => null);
  const readiness = greenApiStateReadiness(body?.stateInstance);
  if (readiness.ready) return credentials;
  throw new GreenApiReadinessError(
    readiness.message,
    { retryable: readiness.retryable, state: readiness.state }
  );
}

function greenApiReadinessLog(error) {
  return {
    state: String(error?.state || '').slice(0, 40),
    httpStatus: Number.isFinite(error?.httpStatus) ? error.httpStatus : null,
    retryable: error?.retryable === true,
  };
}

function greenApiReadinessHttpsError(error) {
  return new HttpsError(
    error?.retryable === true ? 'unavailable' : 'failed-precondition',
    String(error?.message || 'GreenAPI is unavailable.')
  );
}

// Emergency messages must never carry the provider credential or arbitrary
// provider text in the mobile binary. A stable dispatch claim prevents normal
// client retries from sending the same alert twice. Once an outbound request
// may have reached the provider, an unconfirmed result is deliberately made
// terminal instead of risking a duplicate emergency message.
exports.sendSosWhatsAppMessage = onCall(
  {
    secrets: [greenApiInstanceId, greenApiToken],
    timeoutSeconds: 30,
  },
  async (request) => {
    const uid = String(request.auth?.uid || '');
    const ownerPhone = authenticatedPhoneClaim(request);
    if (
      !uid
      || uid !== userDocumentIdForPhone(ownerPhone)
      || !/^\+[1-9]\d{7,14}$/.test(ownerPhone)
    ) {
      logger.warn('Rejected unauthenticated SOS WhatsApp request', {
        hasAuth: Boolean(request.auth),
        hasUid: Boolean(uid),
        hasPhoneClaim: Boolean(ownerPhone),
        uidMatchesPhoneClaim:
          Boolean(uid && ownerPhone)
          && uid === userDocumentIdForPhone(ownerPhone),
      });
      throw new HttpsError('unauthenticated', 'Sign in before sending SOS messages.');
    }

    let dispatch;
    try {
      dispatch = parseSosDispatchRequest(request.data);
    } catch (error) {
      if (error instanceof SosDispatchValidationError) {
        throw new HttpsError('invalid-argument', error.message);
      }
      logger.error('Unable to validate structured SOS dispatch', {
        uid,
        errorName: String(error?.name || ''),
      });
      throw new HttpsError(
        'internal',
        'The emergency dispatch could not be validated.'
      );
    }

    const db = admin.firestore();
    const userReference = db.collection('users').doc(uid);
    const dispatchReference = db
      .collection('sosWhatsAppDispatches')
      .doc(sosDispatchDocumentId(uid, dispatch.dispatchId, dispatch.recipientPhone));
    const rateReference = db
      .collection('sosMessageRateLimits')
      .doc(dispatch.isTest ? `${uid}_test` : uid);
    const payloadHash = sosDispatchPayloadHash(dispatch);
    const attemptNonce = crypto.randomBytes(24).toString('hex');
    const claim = await db.runTransaction(async (transaction) => {
      const [userSnapshot, dispatchSnapshot, rateSnapshot] = await Promise.all([
        transaction.get(userReference),
        transaction.get(dispatchReference),
        transaction.get(rateReference),
      ]);
      const user = userSnapshot.data() || {};
      if (
        !userSnapshot.exists
        || String(user.phoneNumber || '') !== ownerPhone
        || user.accountDisabled === true
        || user.status === 'disabled'
      ) {
        throw new HttpsError('permission-denied', 'The signed-in account is invalid.');
      }
      const recipientDigits = dispatch.recipientPhone.replace(/\D/g, '');
      const preferredTimeZone = normalizeSosTimeZone(
        user.preferredTimeZone
      );
      const savedContacts = Array.isArray(user.sos_contacts) ? user.sos_contacts : [];
      const isSavedContact = savedContacts.some(
        (contact) =>
          String(contact?.phoneNumber || '').replace(/\D/g, '') === recipientDigits
      );
      if (!isSavedContact) {
        throw new HttpsError(
          'permission-denied',
          'SOS messages can only be sent to a saved emergency contact.'
        );
      }

      const now = Date.now();
      const previous = dispatchSnapshot.data() || {};
      if (dispatchSnapshot.exists) {
        if (String(previous.payloadHash || '') !== payloadHash) {
          throw new HttpsError(
            'already-exists',
            'This dispatch id was already used for different emergency content.'
          );
        }
        const previousStatus = String(previous.status || '');
        if (previousStatus === 'sent') {
          return {
            send: false,
            response: sosDispatchClientResponse(previous, { alreadySent: true }),
          };
        }
        if (previousStatus === 'delivery_uncertain') {
          return { send: false, response: sosDispatchClientResponse(previous) };
        }
        if (previousStatus === 'sending') {
          if (Number(previous.leaseExpiresAtMillis || 0) <= now) {
            const uncertain = {
              ...previous,
              status: 'delivery_uncertain',
              retryable: false,
              clientMessage: 'The provider result could not be confirmed.',
            };
            transaction.set(
              dispatchReference,
              {
                status: 'delivery_uncertain',
                retryable: false,
                wasSent: false,
                deliveryUncertain: true,
                clientMessage: uncertain.clientMessage,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAtLocal: new Date(now).toISOString(),
              },
              { merge: true }
            );
            return { send: false, response: sosDispatchClientResponse(uncertain) };
          }
          return { send: false, response: sosDispatchClientResponse(previous) };
        }
        if (
          previousStatus === 'failed'
          && (
            previous.retryable !== true
            || Number(previous.attemptCount || 0) >= 3
          )
        ) {
          const terminal = { ...previous, retryable: false };
          if (previous.retryable === true) {
            transaction.set(
              dispatchReference,
              {
                retryable: false,
                clientMessage: 'The provider retry limit was reached.',
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAtLocal: new Date(now).toISOString(),
              },
              { merge: true }
            );
          }
          return { send: false, response: sosDispatchClientResponse(terminal) };
        }
        if (
          previousStatus === 'claimed'
          && Number(previous.leaseExpiresAtMillis || 0) > now
        ) {
          return { send: false, response: sosDispatchClientResponse(previous) };
        }
      }

      const isReclaimingUnsentClaim =
        dispatchSnapshot.exists
        && String(previous.status || '') === 'claimed';
      const rate = rateSnapshot.data() || {};
      const windowMillis = dispatch.isTest ? 60 * 60 * 1000 : 5 * 60 * 1000;
      const sendLimit = dispatch.isTest ? 6 : 30;
      const windowStartedAtMillis = Number(rate.windowStartedAtMillis || 0);
      const inWindow = now - windowStartedAtMillis < windowMillis;
      const sendCount = inWindow ? Number(rate.sendCount || 0) : 0;
      if (!isReclaimingUnsentClaim && sendCount >= sendLimit) {
        throw new HttpsError(
          'resource-exhausted',
          'Too many emergency messages were requested. Try again shortly or call emergency services.'
        );
      }
      if (!isReclaimingUnsentClaim) {
        transaction.set(
          rateReference,
          {
            windowStartedAtMillis: inWindow ? windowStartedAtMillis : now,
            sendCount: sendCount + 1,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
      const attemptCount = isReclaimingUnsentClaim
        ? Math.max(1, Number(previous.attemptCount || 1))
        : Math.max(0, Number(previous.attemptCount || 0)) + 1;
      transaction.set(
        dispatchReference,
        {
          ownerUid: uid,
          senderPhoneNumber: ownerPhone,
          recipientPhoneNumber: dispatch.recipientPhone,
          dispatchId: dispatch.dispatchId,
          sourceId: dispatch.dispatchId,
          messageType: dispatch.isTest ? 'sos_test' : 'sos_alert',
          mode: dispatch.mode,
          triggerSource: dispatch.triggerSource,
          preferredTimeZone,
          isTest: dispatch.isTest,
          triggeredAtMillis: dispatch.triggeredAtMillis,
          payloadHash,
          status: 'claimed',
          retryable: true,
          wasSent: false,
          deliveryUncertain: false,
          attemptCount,
          attemptNonce,
          leaseExpiresAtMillis: now + 30 * 1000,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAtLocal: new Date(now).toISOString(),
          ...(!dispatchSnapshot.exists
            ? {
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                createdAtLocal: new Date(now).toISOString(),
              }
            : {}),
        },
        { merge: true }
      );
      return { send: true, recipientDigits, preferredTimeZone };
    });
    if (!claim.send) return claim.response;

    let credentials;
    try {
      // SOS is the latency-critical path. Sending directly avoids a separate
      // GreenAPI state request before every emergency message; the structured
      // send response below remains the authoritative provider ACK.
      credentials = greenApiCredentials();
    } catch (error) {
      logger.error('GreenAPI SOS readiness failed', {
        uid,
        ...greenApiReadinessLog(error),
      });
      await transitionSosDispatch(
        dispatchReference,
        attemptNonce,
        new Set(['claimed']),
        {
          status: 'failed',
          retryable: error?.retryable === true,
          wasSent: false,
          deliveryUncertain: false,
          clientMessage: String(
            error?.message
              || 'Emergency messaging is unavailable. Call emergency services directly.'
          ),
          providerState: String(error?.state || '').slice(0, 40),
          providerHttpStatus: Number.isFinite(error?.httpStatus)
            ? error.httpStatus
            : null,
        }
      );
      return sosDispatchClientResponse({
        status: 'failed',
        retryable: error?.retryable === true,
        clientMessage: String(error?.message || ''),
      });
    }

    const markedSending = await transitionSosDispatch(
      dispatchReference,
      attemptNonce,
      new Set(['claimed']),
      {
        status: 'sending',
        outboundStartedAt: admin.firestore.FieldValue.serverTimestamp(),
        outboundStartedAtLocal: new Date().toISOString(),
      }
    );
    if (!markedSending) {
      return sosDispatchClientResponse({ status: 'sending' });
    }

    let response;
    try {
      response = await fetch(
        greenApiEndpoint('sendMessage', credentials),
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            chatId: `${claim.recipientDigits}@c.us`,
            message: composeSosMessage({
              ownerPhone,
              mode: dispatch.mode,
              isTest: dispatch.isTest,
              triggeredAtMillis: dispatch.triggeredAtMillis,
              customNote: dispatch.customNote,
              location: dispatch.location,
              triggerSource: dispatch.triggerSource,
              preferredTimeZone: claim.preferredTimeZone,
            }),
          }),
          signal: AbortSignal.timeout(12 * 1000),
        }
      );
    } catch (error) {
      const definitelyUnsent = providerFailureWasDefinitelyUnsent(error);
      logger.error('GreenAPI SOS transport failed', {
        uid,
        errorName: String(error?.name || ''),
        errorCode: providerTransportErrorCode(error),
        definitelyUnsent,
      });
      const status = definitelyUnsent ? 'failed' : 'delivery_uncertain';
      const retryable = definitelyUnsent;
      await transitionSosDispatch(
        dispatchReference,
        attemptNonce,
        new Set(['sending']),
        {
          status,
          retryable,
          wasSent: false,
          deliveryUncertain: !definitelyUnsent,
          clientMessage: definitelyUnsent
            ? 'The messaging provider could not be reached.'
            : 'The provider result could not be confirmed.',
          transportErrorCode: providerTransportErrorCode(error).slice(0, 80),
        }
      );
      return sosDispatchClientResponse({ status, retryable });
    }
    if (!response.ok) {
      // Once GreenAPI has received the HTTP request, a timeout or server-side
      // failure is not proof that the message was never queued. Retrying those
      // ambiguous responses can duplicate an emergency alert. Only explicit
      // pre-enqueue throttling responses are safe for an automatic retry.
      const {
        deliveryUncertain,
        retryable,
        status,
      } = classifySosProviderHttpFailure(response.status);
      logger.error('GreenAPI SOS message failed', {
        uid,
        status: response.status,
      });
      await transitionSosDispatch(
        dispatchReference,
        attemptNonce,
        new Set(['sending']),
        {
          status,
          retryable,
          wasSent: false,
          deliveryUncertain,
          providerHttpStatus: response.status,
          clientMessage: deliveryUncertain
            ? 'The provider result could not be confirmed.'
            : retryable
              ? 'The messaging provider is temporarily unavailable.'
              : 'The messaging provider rejected this emergency dispatch.',
        }
      );
      return sosDispatchClientResponse({ status, retryable });
    }
    const responseData = await response.json().catch(() => ({}));
    const providerMessageId = greenApiMessageId(responseData);
    if (!providerMessageId) {
      logger.error('GreenAPI SOS response did not include idMessage', { uid });
      await transitionSosDispatch(
        dispatchReference,
        attemptNonce,
        new Set(['sending']),
        {
          status: 'delivery_uncertain',
          retryable: false,
          wasSent: false,
          deliveryUncertain: true,
          clientMessage: 'The provider accepted the request but delivery could not be confirmed.',
        }
      );
      return sosDispatchClientResponse({ status: 'delivery_uncertain' });
    }
    try {
      const finalized = await transitionSosDispatch(
        dispatchReference,
        attemptNonce,
        new Set(['sending']),
        {
          status: 'sent',
          retryable: false,
          wasSent: true,
          deliveryUncertain: false,
          providerMessageId,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
          sentAtLocal: new Date().toISOString(),
        }
      );
      if (!finalized) {
        return sosDispatchClientResponse({ status: 'delivery_uncertain' });
      }
    } catch (error) {
      // The provider accepted the message, so a persistence failure must never
      // cause the mobile retry queue to send it again.
      logger.error('Unable to persist confirmed SOS provider delivery', {
        uid,
        errorName: String(error?.name || ''),
      });
      return sosDispatchClientResponse({ status: 'delivery_uncertain' });
    }
    return sosDispatchClientResponse({ status: 'sent', providerMessageId });
  }
);

exports.manageBuddyRequest = onCall({}, async (request) => {
  const ownerPhone = authenticatedPhoneClaim(request);
  const uid = String(request.auth?.uid || '');
  const action = String(request.data?.action || '');
  const otherPhone = String(request.data?.phoneNumber || '').trim();
  if (
    !uid
    || uid !== userDocumentIdForPhone(ownerPhone)
    || !/^\+[1-9]\d{7,14}$/.test(ownerPhone)
  ) {
    throw new HttpsError('unauthenticated', 'Sign in to manage buddies.');
  }
  if (
    !['send', 'accept', 'decline'].includes(action)
    || !/^\+[1-9]\d{7,14}$/.test(otherPhone)
    || phoneKeyFor(ownerPhone) === phoneKeyFor(otherPhone)
  ) {
    throw new HttpsError('invalid-argument', 'The buddy request is invalid.');
  }

  const db = admin.firestore();
  const ownerRef = db.collection('users').doc(uid);
  const otherRef = db
    .collection('users')
    .doc(userDocumentIdForPhone(otherPhone));
  const ownerKey = phoneKeyFor(ownerPhone);
  const otherKey = phoneKeyFor(otherPhone);

  if (action === 'send') {
    const rateRef = db.collection('buddyRequestRateLimits').doc(uid);
    await db.runTransaction(async (transaction) => {
      const [rateSnapshot, ownerSnapshot, otherSnapshot] = await Promise.all([
        transaction.get(rateRef),
        transaction.get(ownerRef),
        transaction.get(otherRef),
      ]);
      if (!ownerSnapshot.exists || !otherSnapshot.exists) {
        throw new HttpsError('not-found', 'This hiker is no longer available.');
      }
      const other = otherSnapshot.data() || {};
      if (other.accountDisabled === true || other.status === 'disabled') {
        throw new HttpsError('failed-precondition', 'This hiker is unavailable.');
      }
      const rate = rateSnapshot.data() || {};
      const nowMillis = Date.now();
      const windowStartedAtMillis = Number(rate.windowStartedAtMillis || 0);
      const inWindow = nowMillis - windowStartedAtMillis < 60 * 60 * 1000;
      const requestCount = inWindow ? Number(rate.requestCount || 0) : 0;
      if (requestCount >= 20) {
        throw new HttpsError(
          'resource-exhausted',
          'Too many buddy requests were sent. Try again later.'
        );
      }
      const owner = ownerSnapshot.data() || {};
      const profile = owner.profile && typeof owner.profile === 'object'
        ? owner.profile
        : {};
      const displayName = String(
        owner.username || profile.username || `Hiker ${ownerKey.slice(-4)}`
      ).slice(0, 80);
      const photoURL = String(owner.photoURL || profile.photoURL || '').slice(
        0,
        2000
      );
      const nowIso = new Date(nowMillis).toISOString();
      transaction.set(
        otherRef,
        {
          [`buddyRequestsIncoming.${ownerKey}`]: {
            phoneNumber: ownerPhone,
            displayName,
            handle: `@hiker${ownerKey.slice(-4)}`,
            ...(photoURL ? { photoURL } : {}),
            createdAtLocal: nowIso,
          },
          buddyRequestsUpdatedAt:
            admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      transaction.set(
        ownerRef,
        {
          [`buddyRequestsOutgoing.${otherKey}`]: {
            phoneNumber: otherPhone,
            createdAtLocal: nowIso,
          },
          buddyRequestsUpdatedAt:
            admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      transaction.set(
        rateRef,
        {
          windowStartedAtMillis: inWindow ? windowStartedAtMillis : nowMillis,
          requestCount: requestCount + 1,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    });
    return { status: 'sent' };
  }

  await db.runTransaction(async (transaction) => {
    const [ownerSnapshot, otherSnapshot] = await Promise.all([
      transaction.get(ownerRef),
      transaction.get(otherRef),
    ]);
    if (!ownerSnapshot.exists || !otherSnapshot.exists) {
      throw new HttpsError('not-found', 'This buddy request no longer exists.');
    }
    const incoming = ownerSnapshot.data()?.buddyRequestsIncoming;
    if (!incoming || typeof incoming !== 'object' || !incoming[otherKey]) {
      throw new HttpsError(
        'failed-precondition',
        'This buddy request has already been handled.'
      );
    }
    const ownerUpdate = {
      [`buddyRequestsIncoming.${otherKey}`]:
        admin.firestore.FieldValue.delete(),
      buddyRequestsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    const otherUpdate = {
      [`buddyRequestsOutgoing.${ownerKey}`]:
        admin.firestore.FieldValue.delete(),
      buddyRequestsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (action === 'accept') {
      ownerUpdate.buddyPhoneNumbers =
        admin.firestore.FieldValue.arrayUnion(otherPhone);
      ownerUpdate.buddiesUpdatedAt =
        admin.firestore.FieldValue.serverTimestamp();
      otherUpdate.buddyPhoneNumbers =
        admin.firestore.FieldValue.arrayUnion(ownerPhone);
      otherUpdate.buddiesUpdatedAt =
        admin.firestore.FieldValue.serverTimestamp();
    }
    transaction.set(ownerRef, ownerUpdate, { merge: true });
    transaction.set(otherRef, otherUpdate, { merge: true });
  });
  return { status: action === 'accept' ? 'accepted' : 'declined' };
});

// Public discovery uses a server allow-list so private participant, safety,
// and route-planning fields never cross the trust boundary. Full documents
// remain readable only by their participants and administrators.
exports.listUpcomingHikePreviews = onCall(
  {},
  async (request) => {
    const { phoneNumber, uid } = authenticatedPhoneFor(
      request,
      'Sign in to find upcoming hikes.'
    );
    const requestedHikeId = String(request.data?.hikeId || '').trim();
    if (requestedHikeId && !validFirestoreDocumentId(requestedHikeId)) {
      throw new HttpsError('invalid-argument', 'The upcoming hike is invalid.');
    }

    const db = admin.firestore();
    const userSnapshot = await db.collection('users').doc(uid).get();
    const user = userSnapshot.data() || {};
    if (
      !userSnapshot.exists
      || user.accountDisabled === true
      || user.status === 'disabled'
    ) {
      throw new HttpsError('permission-denied', 'Your account is unavailable.');
    }

    let documents;
    if (requestedHikeId) {
      const snapshot = await db.collection('upcomingHikes')
        .doc(requestedHikeId).get();
      documents = snapshot.exists ? [snapshot] : [];
    } else {
      const cutoff = new Date(Date.now() - 15 * 60 * 1000).toISOString();
      const snapshot = await db.collection('upcomingHikes')
        .where('departureTimeLocal', '>=', cutoff)
        .orderBy('departureTimeLocal')
        .limit(200)
        .get();
      documents = snapshot.docs;
    }

    const previewRows = documents
      .map((document) => {
        const hike = document.data() || {};
        const launchHasStarted = Boolean(
          String(hike.teamHikeSessionId || '').trim()
          || hike.teamLaunchLinkedAt
          || hike.teamLaunchLinkedAtLocal
          || (Array.isArray(hike.startedParticipantPhones)
            && hike.startedParticipantPhones.length > 0)
        );
        const preview = launchHasStarted
          ? null
          : buildUpcomingHikePreview(
              document.id,
              hike,
              phoneNumber
            );
        return preview ? { document, preview } : null;
      })
      .filter((hike) => hike !== null);
    const requestSnapshots = previewRows.length === 0
      ? []
      : await db.getAll(
          ...previewRows.map(({ document }) => db
            .collection('upcomingHikeJoinRequests')
            .doc(joinRequestDocumentId(document.id, phoneNumber)))
        );
    const hikes = previewRows.map(({ preview }, index) => {
      const request = requestSnapshots[index]?.data() || {};
      const requestStatus = String(request.status || '').trim();
      return {
        ...preview,
        ...(requestStatus ? { joinRequestStatus: requestStatus } : {}),
      };
    });
    return { hikes };
  }
);

// Joining changes another user's upcoming-hike document, so membership and
// chat creation are performed together by trusted server code. The caller's
// phone number is always derived from the verified Firebase token.
exports.joinUpcomingHike = onCall({}, async (request) => {
  const ownerPhone = authenticatedPhoneClaim(request);
  const uid = String(request.auth?.uid || '');
  const hikeId = String(request.data?.hikeId || '').trim();
  if (
    !uid
    || uid !== userDocumentIdForPhone(ownerPhone)
    || !/^\+[1-9]\d{7,14}$/.test(ownerPhone)
  ) {
    throw new HttpsError('unauthenticated', 'Sign in to join this hike.');
  }
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(hikeId)) {
    throw new HttpsError('invalid-argument', 'The upcoming hike is invalid.');
  }

  const db = admin.firestore();
  const hikeReference = db.collection('upcomingHikes').doc(hikeId);
  const userReference = db.collection('users').doc(uid);
  const chatReference = db.collection('groupChats').doc(`hike_${hikeId}`);
  const messageReference = chatReference
    .collection('messages')
    .doc(`joined_${phoneKeyFor(ownerPhone)}`);

  const result = await db.runTransaction(async (transaction) => {
    const [hikeSnapshot, userSnapshot, chatSnapshot] = await Promise.all([
      transaction.get(hikeReference),
      transaction.get(userReference),
      transaction.get(chatReference),
    ]);
    if (!hikeSnapshot.exists) {
      throw new HttpsError('not-found', 'This upcoming hike is no longer available.');
    }
    if (!userSnapshot.exists) {
      throw new HttpsError('unauthenticated', 'Your account is no longer available.');
    }
    const hike = hikeSnapshot.data() || {};
    const user = userSnapshot.data() || {};
    if (
      hike.isDeleted === true
      || user.accountDisabled === true
      || user.status === 'disabled'
    ) {
      throw new HttpsError('failed-precondition', 'This upcoming hike is no longer available.');
    }
    const launchHasStarted = Boolean(
      String(hike.teamHikeSessionId || '').trim()
      || hike.teamLaunchLinkedAt
      || hike.teamLaunchLinkedAtLocal
      || (Array.isArray(hike.startedParticipantPhones)
        && hike.startedParticipantPhones.some(
          (phone) => Boolean(String(phone || '').trim())
        ))
    );
    if (launchHasStarted) {
      throw new HttpsError(
        'failed-precondition',
        'This hike has already started and its participant roster is closed.'
      );
    }
    const departureMillis = dateMillis(
      hike.departureTimeLocal || hike.departureTime
    );
    if (
      !Number.isFinite(departureMillis)
      || departureMillis + 15 * 60 * 1000 <= Date.now()
    ) {
      throw new HttpsError('failed-precondition', 'This upcoming hike has already ended.');
    }

    const creatorPhone = String(hike.creatorPhone || '').trim();
    const hikeSessionId = String(hike.sessionId || hikeId).trim();
    if (
      !/^\+[1-9]\d{7,14}$/.test(creatorPhone)
      || !hikeSessionId
      || hikeSessionId !== hikeId
    ) {
      throw new HttpsError('failed-precondition', 'This upcoming hike is incomplete.');
    }
    const participantPhones = [
      creatorPhone,
      ...(Array.isArray(hike.participantPhones) ? hike.participantPhones : []),
    ]
      .map((phone) => String(phone || '').trim())
      .filter((phone) => /^\+[1-9]\d{7,14}$/.test(phone));
    const uniquePhones = [...new Set(participantPhones)];
    const alreadyJoined = uniquePhones.includes(ownerPhone);
    if (
      !alreadyJoined
      && (
        effectiveUpcomingHikeType(hike) === 'solo'
        || String(hike.joinPolicy || 'open') !== 'open'
      )
    ) {
      throw new HttpsError(
        'failed-precondition',
        'Send a join request and wait for the host to approve it.'
      );
    }
    if (!alreadyJoined) {
      uniquePhones.push(ownerPhone);
    }
    if (uniquePhones.length > 50) {
      throw new HttpsError('resource-exhausted', 'This hike has reached its participant limit.');
    }

    const nowIso = new Date().toISOString();
    const userProfile = user.profile && typeof user.profile === 'object'
      ? user.profile
      : {};
    const displayName = String(
      user.username || userProfile.username || `Hiker ${phoneKeyFor(ownerPhone).slice(-4)}`
    ).slice(0, 80);
    const chat = chatSnapshot.data() || {};
    const participantNames =
      chat.participantNames && typeof chat.participantNames === 'object'
        ? { ...chat.participantNames }
        : {};
    participantNames[phoneKeyFor(ownerPhone)] = displayName;

    transaction.set(
      hikeReference,
      {
        participantPhones: uniquePhones,
        participantCount: uniquePhones.length,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: nowIso,
      },
      { merge: true }
    );
    transaction.set(
      chatReference,
      {
        hikeSessionId,
        trailName: String(hike.trailName || 'Group hike').slice(0, 160),
        participantPhones: uniquePhones,
        participantNames,
        creatorPhone,
        chatType: 'group',
        departureTimeLocal: new Date(departureMillis).toISOString(),
        ...(!alreadyJoined && !String(chat.customName || '').trim()
          ? {
              requiresHostNaming: true,
              latestJoinedName: displayName,
              teamFormedAtLocal: String(chat.teamFormedAtLocal || nowIso),
            }
          : {}),
        ...(!chatSnapshot.exists ? { createdAtLocal: nowIso } : {}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: nowIso,
      },
      { merge: true }
    );
    if (!alreadyJoined) {
      transaction.set(messageReference, {
        chatId: chatReference.id,
        senderPhone: ownerPhone,
        senderName: displayName,
        text: `${displayName} joined the hike`,
        sentAtLocal: nowIso,
        isSystemMessage: true,
        seenBy: uniquePhones,
      });
    }
    return { alreadyJoined, chatId: chatReference.id };
  });

  return { joined: true, ...result };
});

exports.requestToJoinUpcomingHike = onCall({}, async (request) => {
  const { phoneNumber: requesterPhone, uid } = authenticatedPhoneFor(
    request,
    'Sign in to request to join this hike.'
  );
  const hikeId = String(request.data?.hikeId || '').trim();
  if (!validFirestoreDocumentId(hikeId)) {
    throw new HttpsError('invalid-argument', 'The upcoming hike is invalid.');
  }

  const db = admin.firestore();
  const requestId = joinRequestDocumentId(hikeId, requesterPhone);
  const requestReference = db.collection('upcomingHikeJoinRequests').doc(requestId);
  const hikeReference = db.collection('upcomingHikes').doc(hikeId);
  const userReference = db.collection('users').doc(uid);
  const rateReference = db.collection('upcomingHikeJoinRequestRateLimits').doc(uid);
  return db.runTransaction(async (transaction) => {
    const [hikeSnapshot, userSnapshot, requestSnapshot, rateSnapshot] =
      await Promise.all([
        transaction.get(hikeReference),
        transaction.get(userReference),
        transaction.get(requestReference),
        transaction.get(rateReference),
      ]);
    const hike = hikeSnapshot.data() || {};
    const user = userSnapshot.data() || {};
    if (!hikeSnapshot.exists) {
      return { requestId, status: 'expired', reason: 'hike_removed' };
    }
    if (
      !userSnapshot.exists
      || user.accountDisabled === true
      || user.status === 'disabled'
    ) {
      throw new HttpsError('permission-denied', 'Your account is unavailable.');
    }
    const unavailableReason = upcomingHikeUnavailableReason(hike);
    if (unavailableReason) {
      return { requestId, status: 'expired', reason: unavailableReason };
    }
    const hostPhone = String(hike.creatorPhone || '').trim();
    const participants = Array.isArray(hike.participantPhones)
      ? hike.participantPhones.map((phone) => String(phone || '').trim())
      : [];
    if (hostPhone === requesterPhone || participants.includes(requesterPhone)) {
      return { requestId, status: 'accepted', reason: 'already_participating' };
    }
    if (
      effectiveUpcomingHikeType(hike) !== 'solo'
      && String(hike.joinPolicy || 'open') === 'open'
    ) {
      throw new HttpsError(
        'failed-precondition',
        'This is a group hike and can be joined directly.'
      );
    }
    if (!/^\+[1-9]\d{7,14}$/.test(hostPhone)) {
      throw new HttpsError('failed-precondition', 'This hike host is unavailable.');
    }
    if (requestSnapshot.exists) {
      const lifecycle = joinRequestLifecycle(requestSnapshot.data() || {}, hike);
      return { requestId, ...lifecycle };
    }

    const profile = canonicalChatProfile(requesterPhone, user);
    const nowIso = new Date().toISOString();
    transaction.create(requestReference, {
      requestId,
      hikeId,
      trailName: String(hike.trailName || 'Upcoming hike').trim().slice(0, 160),
      departureTimeLocal: String(hike.departureTimeLocal || ''),
      hostPhone,
      requesterPhone,
      requesterUserId: uid,
      requesterName: profile.name,
      requesterPhotoURL: profile.photoURL,
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAtLocal: nowIso,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAtLocal: nowIso,
    });
    assertWindowRate(transaction, rateReference, rateSnapshot, {
      limit: 10,
      windowMillis: 60 * 60 * 1000,
      message: 'Too many join requests were sent. Try again later.',
    });
    return { requestId, status: 'pending', reason: '' };
  });
});

function upcomingHikeJoinRequestResponse(requestId, request, hike, lifecycle) {
  return {
    requestId,
    hikeId: String(request?.hikeId || ''),
    status: lifecycle.status,
    reason: lifecycle.reason,
    requesterName: String(request?.requesterName || 'A hiker').slice(0, 80),
    trailName: String(hike?.trailName || request?.trailName || 'Upcoming hike')
      .slice(0, 160),
    departureTimeLocal: String(
      hike?.departureTimeLocal || request?.departureTimeLocal || ''
    ),
    needsJoinPolicyChoice: lifecycle.needsJoinPolicyChoice === true,
  };
}

async function publicHikerDetails(db, userId) {
  if (!validFirestoreDocumentId(userId)) return {};
  const [userDocument, achievementDocuments, historyDocuments] =
    await Promise.all([
      db.collection('users').doc(userId).get(),
      db.collection('userAchievements').where('userId', '==', userId)
        .limit(50).get(),
      db.collection('hikeSessions').where('userId', '==', userId)
        .limit(100).get(),
    ]);
  const publicProfile = userDocument.exists
    ? publicProfileFromUserDocument(userDocument)
    : null;
  if (!publicProfile) return {};
  const { phoneNumber: _privatePhoneNumber, ...profile } = publicProfile;
  const achievements = achievementDocuments.docs
    .map((document) => document.data() || {})
    .filter((achievement) => achievement.isUnlocked === true)
    .map((achievement) => ({
      id: String(achievement.achievementId || '').slice(0, 200),
      title: String(achievement.achievementTitle || 'Achievement').slice(0, 160),
      points: Math.max(0, Number(achievement.pointsAwarded || 0)),
      awardedAtLocal: String(achievement.awardedAtLocal || ''),
    }))
    .sort((left, right) => String(right.awardedAtLocal || '')
      .localeCompare(String(left.awardedAtLocal || '')))
    .slice(0, 12);
  const hikeHistory = historyDocuments.docs
    .filter((document) => String(document.data()?.status || '') === 'completed')
    .map((document) => hikeHistorySummaryData(document.id, document.data() || {}))
    .sort((left, right) => String(right.endedAtLocal || '')
      .localeCompare(String(left.endedAtLocal || '')))
    .slice(0, 5)
    .map((hike) => ({
      trailName: String(hike.trailName || 'Hike').slice(0, 160),
      endedAtLocal: String(hike.endedAtLocal || ''),
      recordedDistanceKm: boundedNumber(hike.recordedDistanceKm, 0, 1000, 0),
      durationSeconds: Math.round(boundedNumber(hike.durationSeconds, 0, 604800, 0)),
      hikeType: String(hike.hikeType || 'solo') === 'team' ? 'team' : 'solo',
    }));
  return { profile, achievements, hikeHistory };
}

exports.loadUpcomingHikeJoinRequest = onCall({}, async (request) => {
  const { phoneNumber: hostPhone } = authenticatedPhoneFor(
    request,
    'Sign in to review this join request.'
  );
  const requestId = String(request.data?.requestId || '').trim();
  if (!/^join_[a-f0-9]{48}$/.test(requestId)) {
    throw new HttpsError('invalid-argument', 'The join request link is invalid.');
  }
  const db = admin.firestore();
  const requestSnapshot = await db
    .collection('upcomingHikeJoinRequests')
    .doc(requestId)
    .get();
  if (!requestSnapshot.exists) {
    return { requestId, status: 'expired', reason: 'request_missing' };
  }
  const joinRequest = requestSnapshot.data() || {};
  if (String(joinRequest.hostPhone || '') !== hostPhone) {
    throw new HttpsError(
      'permission-denied',
      'This join request belongs to a different hike host.'
    );
  }
  const hikeSnapshot = await db
    .collection('upcomingHikes')
    .doc(String(joinRequest.hikeId || ''))
    .get();
  const hike = hikeSnapshot.exists ? hikeSnapshot.data() || {} : null;
  const lifecycle = joinRequestLifecycle(joinRequest, hike);
  if (lifecycle.status === 'expired' && String(joinRequest.status) === 'pending') {
    await requestSnapshot.ref.set(
      {
        status: 'expired',
        expiredReason: lifecycle.reason,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: new Date().toISOString(),
      },
      { merge: true }
    );
  }
  const response = upcomingHikeJoinRequestResponse(
    requestId,
    joinRequest,
    hike,
    lifecycle
  );
  const details = await publicHikerDetails(
    db,
    String(joinRequest.requesterUserId || '')
  );
  return { ...response, ...details };
});

exports.loadPublicHikerProfile = onCall({}, async (request) => {
  authenticatedPhoneFor(request, 'Sign in to view hiker profiles.');
  const userId = String(request.data?.userId || '').trim();
  const phoneNumber = String(request.data?.phoneNumber || '').trim();
  const resolvedUserId = validFirestoreDocumentId(userId)
    ? userId
    : /^\+[1-9]\d{7,14}$/.test(phoneNumber)
      ? userDocumentIdForPhone(phoneNumber)
      : '';
  if (!resolvedUserId) {
    throw new HttpsError('invalid-argument', 'The hiker profile is invalid.');
  }
  return publicHikerDetails(admin.firestore(), resolvedUserId);
});

exports.resolveUpcomingHikeJoinRequest = onCall({}, async (request) => {
  const { phoneNumber: hostPhone } = authenticatedPhoneFor(
    request,
    'Sign in to respond to this join request.'
  );
  const requestId = String(request.data?.requestId || '').trim();
  const action = String(request.data?.action || '').trim();
  if (!/^join_[a-f0-9]{48}$/.test(requestId) || !['accept', 'reject'].includes(action)) {
    throw new HttpsError('invalid-argument', 'The join request response is invalid.');
  }
  const db = admin.firestore();
  const requestReference = db.collection('upcomingHikeJoinRequests').doc(requestId);
  return db.runTransaction(async (transaction) => {
    const requestSnapshot = await transaction.get(requestReference);
    if (!requestSnapshot.exists) {
      return { requestId, status: 'expired', reason: 'request_missing' };
    }
    const joinRequest = requestSnapshot.data() || {};
    if (String(joinRequest.hostPhone || '') !== hostPhone) {
      throw new HttpsError(
        'permission-denied',
        'Only the hike host can respond to this request.'
      );
    }
    const hikeId = String(joinRequest.hikeId || '').trim();
    const requesterPhone = String(joinRequest.requesterPhone || '').trim();
    const hikeReference = db.collection('upcomingHikes').doc(hikeId);
    const userReference = db
      .collection('users')
      .doc(userDocumentIdForPhone(requesterPhone));
    const chatReference = db.collection('groupChats').doc(`hike_${hikeId}`);
    const [hikeSnapshot, userSnapshot, chatSnapshot] = await Promise.all([
      transaction.get(hikeReference),
      transaction.get(userReference),
      transaction.get(chatReference),
    ]);
    const hike = hikeSnapshot.exists ? hikeSnapshot.data() || {} : null;
    const lifecycle = joinRequestLifecycle(joinRequest, hike);
    if (lifecycle.status !== 'pending') {
      return upcomingHikeJoinRequestResponse(
        requestId,
        joinRequest,
        hike,
        lifecycle
      );
    }
    const unavailableReason = upcomingHikeUnavailableReason(hike);
    if (unavailableReason) {
      transaction.set(
        requestReference,
        {
          status: 'expired',
          expiredReason: unavailableReason,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAtLocal: new Date().toISOString(),
        },
        { merge: true }
      );
      return upcomingHikeJoinRequestResponse(
        requestId,
        joinRequest,
        hike,
        { status: 'expired', reason: unavailableReason }
      );
    }
    const nowIso = new Date().toISOString();
    if (action === 'reject') {
      transaction.set(
        requestReference,
        {
          status: 'rejected',
          resolvedByPhone: hostPhone,
          resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
          resolvedAtLocal: nowIso,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAtLocal: nowIso,
        },
        { merge: true }
      );
      return upcomingHikeJoinRequestResponse(
        requestId,
        joinRequest,
        hike,
        { status: 'rejected', reason: 'rejected' }
      );
    }
    if (!userSnapshot.exists) {
      throw new HttpsError('failed-precondition', 'This hiker is no longer available.');
    }
    const participantPhones = [
      hostPhone,
      ...(Array.isArray(hike.participantPhones) ? hike.participantPhones : []),
    ]
      .map((phone) => String(phone || '').trim())
      .filter((phone) => /^\+[1-9]\d{7,14}$/.test(phone));
    const uniquePhones = [...new Set(participantPhones)];
    if (!uniquePhones.includes(requesterPhone)) uniquePhones.push(requesterPhone);
    if (uniquePhones.length > 50) {
      throw new HttpsError('resource-exhausted', 'This hike has reached its participant limit.');
    }
    const requesterProfile = canonicalChatProfile(
      requesterPhone,
      userSnapshot.data() || {}
    );
    const chat = chatSnapshot.data() || {};
    const participantNames = chat.participantNames
      && typeof chat.participantNames === 'object'
      ? { ...chat.participantNames }
      : {};
    participantNames[phoneKeyFor(requesterPhone)] = requesterProfile.name;
    const wasSoloHike = effectiveUpcomingHikeType(hike) === 'solo';
    transaction.set(
      hikeReference,
      {
        hikeType: 'team',
        joinPolicy: String(hike.joinPolicy || 'approval') === 'open'
          ? 'open'
          : 'approval',
        draft: {
          ...(hike.draft && typeof hike.draft === 'object' ? hike.draft : {}),
          hikeType: 'team',
        },
        participantPhones: uniquePhones,
        participantCount: uniquePhones.length,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: nowIso,
      },
      { merge: true }
    );
    transaction.set(
      chatReference,
      {
        hikeSessionId: hikeId,
        trailName: String(hike.trailName || 'Group hike').slice(0, 160),
        participantPhones: uniquePhones,
        participantNames,
        creatorPhone: hostPhone,
        chatType: 'group',
        departureTimeLocal: String(hike.departureTimeLocal || ''),
        ...(!String(chat.customName || '').trim()
          ? {
              requiresHostNaming: true,
              latestJoinedName: requesterProfile.name,
              teamFormedAtLocal: String(chat.teamFormedAtLocal || nowIso),
            }
          : {}),
        ...(!chatSnapshot.exists
          ? {
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              createdAtLocal: nowIso,
            }
          : {}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: nowIso,
      },
      { merge: true }
    );
    transaction.set(chatReference.collection('messages').doc(`joined_${phoneKeyFor(requesterPhone)}`), {
      chatId: chatReference.id,
      senderPhone: requesterPhone,
      senderName: requesterProfile.name,
      text: `${requesterProfile.name} joined the hike`,
      sentAtLocal: nowIso,
      isSystemMessage: true,
      seenBy: uniquePhones,
    });
    transaction.set(
      requestReference,
      {
        status: 'accepted',
        resolvedByPhone: hostPhone,
        resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
        resolvedAtLocal: nowIso,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: nowIso,
      },
      { merge: true }
    );
    return upcomingHikeJoinRequestResponse(
      requestId,
      joinRequest,
      { ...hike, hikeType: 'team' },
      {
        status: 'accepted',
        reason: 'accepted',
        needsJoinPolicyChoice: wasSoloHike,
      }
    );
  });
});

exports.setUpcomingHikeJoinPolicy = onCall({}, async (request) => {
  const { phoneNumber: hostPhone } = authenticatedPhoneFor(
    request,
    'Sign in to update this hike.'
  );
  const hikeId = String(request.data?.hikeId || '').trim();
  const joinPolicy = String(request.data?.joinPolicy || '').trim();
  if (!validFirestoreDocumentId(hikeId) || !['approval', 'open'].includes(joinPolicy)) {
    throw new HttpsError('invalid-argument', 'The join setting is invalid.');
  }
  const reference = admin.firestore().collection('upcomingHikes').doc(hikeId);
  await admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists || snapshot.data()?.isDeleted === true) {
      throw new HttpsError('not-found', 'This upcoming hike is no longer available.');
    }
    const hike = snapshot.data() || {};
    if (String(hike.creatorPhone || '') !== hostPhone) {
      throw new HttpsError('permission-denied', 'Only the hike host can change this setting.');
    }
    if (upcomingHikeUnavailableReason(hike)) {
      throw new HttpsError('failed-precondition', 'This hike can no longer be changed.');
    }
    transaction.set(reference, {
      joinPolicy,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAtLocal: new Date().toISOString(),
    }, { merge: true });
  });
  return { updated: true, joinPolicy };
});

exports.remindUpcomingHikeHost = onCall(
  { secrets: [greenApiInstanceId, greenApiToken] },
  async (request) => {
    const { phoneNumber: participantPhone } = authenticatedPhoneFor(
      request,
      'Sign in to remind the hike host.'
    );
    const hikeId = String(request.data?.hikeId || '').trim();
    if (!validFirestoreDocumentId(hikeId)) {
      throw new HttpsError('invalid-argument', 'The upcoming hike is invalid.');
    }
    const db = admin.firestore();
    const reference = db.collection('upcomingHikes').doc(hikeId);
    const claim = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists || snapshot.data()?.isDeleted === true) {
        throw new HttpsError('not-found', 'This upcoming hike is no longer available.');
      }
      const hike = snapshot.data() || {};
      const hostPhone = String(hike.creatorPhone || '').trim();
      const participants = Array.isArray(hike.participantPhones)
        ? hike.participantPhones.map((phone) => String(phone || '').trim())
        : [];
      if (hostPhone === participantPhone || !participants.includes(participantPhone)) {
        throw new HttpsError('permission-denied', 'Only joined participants can remind the host.');
      }
      const departureMillis = dateMillis(hike.departureTimeLocal || hike.departureTime);
      const now = Date.now();
      if (
        !Number.isFinite(departureMillis)
        || now < departureMillis - 15 * 60 * 1000
        || now >= departureMillis + 15 * 60 * 1000
      ) {
        throw new HttpsError('failed-precondition', 'Host reminders are available near departure time.');
      }
      const previousPhones = Array.isArray(hike.departureReminderPhones)
        ? hike.departureReminderPhones
          .map((phone) => String(phone || '').trim())
          .filter((phone) => /^\+[1-9]\d{7,14}$/.test(phone))
        : [];
      const uniquePhones = [...new Set(previousPhones)];
      if (uniquePhones.includes(participantPhone) || uniquePhones.length >= 3) {
        return {
          send: false,
          reminderCount: Math.min(3, uniquePhones.length),
          alreadySent: uniquePhones.includes(participantPhone),
        };
      }
      uniquePhones.push(participantPhone);
      transaction.set(reference, {
        departureReminderPhones: uniquePhones,
        departureReminderCount: uniquePhones.length,
        lastDepartureReminderAt: admin.firestore.FieldValue.serverTimestamp(),
        lastDepartureReminderAtLocal: new Date(now).toISOString(),
      }, { merge: true });
      return {
        send: true,
        reminderCount: uniquePhones.length,
        hostPhone,
        trailName: String(hike.trailName || 'your hike').slice(0, 100),
      };
    });
    if (!claim.send) return claim;

    let fcmSent = false;
    try {
      const host = await db.collection('users')
        .doc(userDocumentIdForPhone(claim.hostPhone)).get();
      const tokens = latestFcmTokensForUser(host.data() || {});
      if (tokens.length > 0) {
        const delivery = await admin.messaging().sendEachForMulticast({
          tokens,
          notification: {
            title: 'Your hikers are ready',
            body: `A participant is waiting for ${claim.trailName} to start.`,
          },
          data: {
            type: 'upcoming_hike_host_reminder',
            upcomingHikeId: hikeId,
            deepLink: `hikercircle://upcoming-hike/view?upcomingHikeId=${encodeURIComponent(hikeId)}`,
          },
          android: { priority: 'high' },
          apns: { headers: { 'apns-priority': '10' }, payload: { aps: { sound: 'default' } } },
        });
        fcmSent = delivery.successCount > 0;
      }
    } catch (error) {
      logger.error(`Upcoming hike host reminder FCM failed for ${hikeId}`, error);
    }
    let whatsAppSent = false;
    try {
      const credentials = greenApiCredentials();
      const response = await fetch(greenApiEndpoint('sendMessage', credentials), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          chatId: `${claim.hostPhone.replace(/\D/g, '')}@c.us`,
          message: `HikerCircle reminder: participants are waiting for ${claim.trailName}. Please open the app to start team readiness.`,
        }),
        signal: AbortSignal.timeout(12 * 1000),
      });
      const data = await response.json().catch(() => null);
      whatsAppSent = response.ok && Boolean(greenApiMessageId(data));
    } catch (error) {
      logger.error(`Upcoming hike host reminder WhatsApp failed for ${hikeId}`, error);
    }
    return {
      reminderCount: claim.reminderCount,
      alreadySent: false,
      fcmSent,
      whatsAppSent,
    };
  }
);

exports.openUpcomingHikeJoinRequest = onRequest((request, response) => {
  const requestId = String(request.query.requestId || '').trim();
  if (!/^join_[a-f0-9]{48}$/.test(requestId)) {
    response.status(400).send('This HikerCircle join-request link is invalid.');
    return;
  }
  const deepLink = `hikercircle://upcoming-hike/join-request?requestId=${requestId}`;
  response.set('Cache-Control', 'no-store');
  response.set('Content-Type', 'text/html; charset=utf-8');
  response.status(200).send(`<!doctype html>
<html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="0;url=${deepLink}">
<title>Open HikerCircle</title></head>
<body style="font-family:system-ui;text-align:center;padding:48px 20px">
<h1>Opening HikerCircle…</h1>
<p><a href="${deepLink}">Tap here if the app does not open</a></p>
<script>window.location.replace(${JSON.stringify(deepLink)});</script>
</body></html>`);
});

exports.notifyHostAboutUpcomingHikeJoinRequest = onDocumentCreated(
  {
    document: 'upcomingHikeJoinRequests/{requestId}',
    secrets: [greenApiInstanceId, greenApiToken],
  },
  async (event) => {
    const joinRequest = await claimAtMostOnceDelivery(event.data.ref, {
      claimPrefix: 'hostNotificationDelivery',
      processedFields: ['hostNotificationProcessedAtLocal'],
    });
    if (!joinRequest) return;
    const requestId = String(event.params.requestId || '');
    const hostPhone = String(joinRequest.hostPhone || '').trim();
    const requesterPhone = String(joinRequest.requesterPhone || '').trim();
    const hikeId = String(joinRequest.hikeId || '').trim();
    if (
      requestId !== String(joinRequest.requestId || '')
      || !/^join_[a-f0-9]{48}$/.test(requestId)
      || !/^\+[1-9]\d{7,14}$/.test(hostPhone)
      || !/^\+[1-9]\d{7,14}$/.test(requesterPhone)
      || !validFirestoreDocumentId(hikeId)
      || String(joinRequest.status || '') !== 'pending'
    ) {
      await event.data.ref.set(
        {
          hostNotificationStatus: 'failed',
          hostNotificationError: 'invalid_request',
          hostNotificationProcessedAtLocal: new Date().toISOString(),
        },
        { merge: true }
      );
      return;
    }
    const db = admin.firestore();
    const hikeSnapshot = await db.collection('upcomingHikes').doc(hikeId).get();
    const hike = hikeSnapshot.exists ? hikeSnapshot.data() || {} : null;
    const lifecycle = joinRequestLifecycle(joinRequest, hike);
    if (lifecycle.status !== 'pending') {
      await event.data.ref.set(
        {
          hostNotificationStatus: 'skipped',
          hostNotificationError: lifecycle.reason,
          hostNotificationProcessedAtLocal: new Date().toISOString(),
        },
        { merge: true }
      );
      return;
    }

    const requesterName = String(joinRequest.requesterName || 'A hiker')
      .trim().slice(0, 80);
    const trailName = String(hike.trailName || joinRequest.trailName || 'your hike')
      .trim().slice(0, 100);
    const deepLink =
      `hikercircle://upcoming-hike/join-request?requestId=${encodeURIComponent(requestId)}`;
    const reviewUrl =
      'https://us-central1-hiker-circle.cloudfunctions.net/'
      + `openUpcomingHikeJoinRequest?requestId=${encodeURIComponent(requestId)}`;

    let fcmStatus = 'no_token';
    let fcmSuccessCount = 0;
    let fcmFailureCount = 0;
    try {
      const hostSnapshot = await db
        .collection('users')
        .doc(userDocumentIdForPhone(hostPhone))
        .get();
      const tokenList = latestFcmTokensForUser(hostSnapshot.data() || {});
      if (tokenList.length > 0) {
        for (let index = 0; index < tokenList.length; index += 500) {
          const delivery = await admin.messaging().sendEachForMulticast({
            tokens: tokenList.slice(index, index + 500),
            notification: {
              title: 'Hike join request',
              body: `${requesterName || 'A hiker'} wants to join ${trailName}.`,
            },
            data: {
              type: 'upcoming_hike_join_request',
              requestId,
              upcomingHikeId: hikeId,
              deepLink,
            },
            android: { priority: 'high' },
            apns: {
              headers: { 'apns-priority': '10' },
              payload: { aps: { sound: 'default' } },
            },
          });
          fcmSuccessCount += delivery.successCount;
          fcmFailureCount += delivery.failureCount;
        }
        fcmStatus = fcmFailureCount === 0 ? 'sent' : 'partial';
      }
    } catch (error) {
      fcmStatus = 'delivery_uncertain';
      logger.error(`Join-request FCM delivery ${requestId} failed`, {
        errorCode: String(error?.code || error?.name || ''),
      });
    }

    let whatsAppStatus = 'failed';
    let whatsAppMessageId = '';
    let whatsAppError = '';
    try {
      const credentials = greenApiCredentials();
      const recipientDigits = hostPhone.replace(/\D/g, '');
      const providerResponse = await fetch(
        greenApiEndpoint('sendInteractiveButtons', credentials),
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            chatId: `${recipientDigits}@c.us`,
            header: 'HikerCircle join request',
            body: `${requesterName || 'A hiker'} wants to join ${trailName}.`,
            footer: 'Open HikerCircle to accept or decline.',
            buttons: [
              {
                type: 'url',
                buttonId: 'review_join_request',
                buttonText: 'Review request',
                url: reviewUrl,
              },
            ],
          }),
          signal: AbortSignal.timeout(12 * 1000),
        }
      );
      const responseData = await providerResponse.json().catch(() => null);
      whatsAppMessageId = greenApiMessageId(responseData);
      if (providerResponse.ok && whatsAppMessageId) {
        whatsAppStatus = 'sent';
      } else {
        whatsAppError = `provider_http_${providerResponse.status}`;
      }
    } catch (error) {
      whatsAppStatus = providerFailureWasDefinitelyUnsent(error)
        ? 'failed'
        : 'delivery_uncertain';
      whatsAppError = String(error?.code || error?.name || 'provider_error')
        .slice(0, 120);
      logger.error(`Join-request WhatsApp delivery ${requestId} failed`, {
        errorCode: whatsAppError,
      });
    }

    await event.data.ref.set(
      {
        hostNotificationStatus:
          fcmStatus === 'sent' && whatsAppStatus === 'sent' ? 'sent' : 'partial',
        hostFcmStatus: fcmStatus,
        hostFcmSuccessCount: fcmSuccessCount,
        hostFcmFailureCount: fcmFailureCount,
        hostWhatsAppStatus: whatsAppStatus,
        ...(whatsAppMessageId ? { hostWhatsAppMessageId: whatsAppMessageId } : {}),
        ...(whatsAppError ? { hostWhatsAppError: whatsAppError } : {}),
        hostNotificationProcessedAt:
          admin.firestore.FieldValue.serverTimestamp(),
        hostNotificationProcessedAtLocal: new Date().toISOString(),
      },
      { merge: true }
    );
  }
);

function defaultFormedHikeGroupName(chat) {
  const departureMillis = dateMillis(
    chat.departureTimeLocal || chat.departureTime || chat.createdAtLocal
  );
  const date = new Date(Number.isFinite(departureMillis) ? departureMillis : Date.now());
  const timeZone = String(chat.timeZone || 'Asia/Kuala_Lumpur').trim();
  let parts;
  try {
    parts = new Intl.DateTimeFormat('en-GB', {
      timeZone,
      day: '2-digit',
      month: 'short',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    }).formatToParts(date);
  } catch (_) {
    parts = new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Asia/Kuala_Lumpur',
      day: '2-digit',
      month: 'short',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    }).formatToParts(date);
  }
  const part = (type) => String(parts.find((value) => value.type === type)?.value || '');
  const rawLocation = String(chat.trailName || 'Hike')
    .replace(/\s+/g, ' ')
    .trim() || 'Hike';
  const prefix = `${part('day')}${part('month')} ${part('hour')}:${part('minute')} `;
  const suffix = ' Group';
  const location = rawLocation.slice(0, Math.max(1, 60 - prefix.length - suffix.length)).trim();
  return `${prefix}${location}${suffix}`;
}

exports.markFormedHikeGroupNamingPromptShown = onCall({}, async (request) => {
  const { phoneNumber: ownerPhone } = authenticatedPhoneFor(
    request,
    'Sign in to prepare this group chat.'
  );
  const chatId = String(request.data?.chatId || '').trim();
  const requestedDefaultName = String(request.data?.defaultName || '')
    .replace(/\s+/g, ' ')
    .trim();
  if (!validFirestoreDocumentId(chatId)) {
    throw new HttpsError('invalid-argument', 'The group chat is invalid.');
  }
  const db = admin.firestore();
  const chatReference = db.collection('groupChats').doc(chatId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(chatReference);
    if (!snapshot.exists) {
      throw new HttpsError('not-found', 'This group chat is no longer available.');
    }
    const chat = snapshot.data() || {};
    if (
      String(chat.chatType || 'group') === 'direct'
      || String(chat.creatorPhone || '').trim() !== ownerPhone
    ) {
      throw new HttpsError('permission-denied', 'Only the hike host can name this group.');
    }
    if (chat.hikeEndedAtLocal || chat.isDeleted === true) {
      const fallback = String(chat.customName || '').trim()
        || defaultFormedHikeGroupName(chat);
      transaction.set(chatReference, {
        customName: fallback,
        requiresHostNaming: false,
        namingPromptShown: true,
        namingPromptActive: false,
        nameSource: String(chat.customName || '').trim() ? 'host' : 'automatic',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: new Date().toISOString(),
      }, { merge: true });
      return;
    }
    const fallback = requestedDefaultName.length >= 2 && requestedDefaultName.length <= 60
      ? requestedDefaultName
      : defaultFormedHikeGroupName(chat);
    transaction.set(chatReference, {
      customName: String(chat.customName || '').trim() || fallback,
      requiresHostNaming: false,
      namingPromptShown: true,
      namingPromptActive: true,
      nameSource: String(chat.customName || '').trim() ? 'host' : 'automatic',
      namingPromptShownAt: admin.firestore.FieldValue.serverTimestamp(),
      namingPromptShownAtLocal: new Date().toISOString(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAtLocal: new Date().toISOString(),
    }, { merge: true });
  });
  return { prepared: true, chatId };
});

exports.loadAchievementLeaderboard = onCall({}, async (request) => {
  const { uid } = authenticatedPhoneFor(
    request,
    'Sign in to view the hiking leaderboard.'
  );
  const period = String(request.data?.period || 'month') === 'year'
    ? 'year'
    : 'month';
  const now = new Date();
  const start = period === 'year'
    ? new Date(Date.UTC(now.getUTCFullYear(), 0, 1))
    : new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const snapshot = await admin.firestore()
    .collection('userAchievements')
    .where('isUnlocked', '==', true)
    .limit(5000)
    .get();
  const pointsByUser = new Map();
  for (const document of snapshot.docs) {
    const row = document.data() || {};
    const awardedAt = dateMillis(row.awardedAt || row.awardedAtLocal);
    if (!Number.isFinite(awardedAt) || awardedAt < start.getTime()) continue;
    const userId = String(row.userId || '').trim();
    if (!userId) continue;
    const points = Math.max(0, Number(row.pointsAwarded || 0));
    pointsByUser.set(userId, (pointsByUser.get(userId) || 0) + points);
  }
  const ranked = [...pointsByUser.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 50);
  const userReferences = ranked.map(([userId]) =>
    admin.firestore().collection('users').doc(userId)
  );
  const users = userReferences.length > 0
    ? await admin.firestore().getAll(...userReferences)
    : [];
  const profiles = new Map(users.map((document) => [document.id, document.data() || {}]));
  return {
    period,
    startsAtLocal: start.toISOString(),
    currentUserId: uid,
    entries: ranked.map(([userId, points], index) => {
      const profile = profiles.get(userId) || {};
      const username = String(
        profile.username || profile.displayName || profile.handle || 'Hiker'
      ).replace(/^@/, '').trim();
      return {
        rank: index + 1,
        userId,
        displayName: username || 'Hiker',
        photoURL: String(profile.photoURL || '').trim(),
        points: Math.floor(points),
        isCurrentUser: userId === uid,
      };
    }),
  };
});

exports.nameFormedHikeGroupChat = onCall({}, async (request) => {
  const { phoneNumber: ownerPhone } = authenticatedPhoneFor(
    request,
    'Sign in to name this group chat.'
  );
  const chatId = String(request.data?.chatId || '').trim();
  const customName = String(request.data?.name || '')
    .replace(/\s+/g, ' ')
    .trim();
  if (!validFirestoreDocumentId(chatId)) {
    throw new HttpsError('invalid-argument', 'The group chat is invalid.');
  }
  if (customName.length < 2 || customName.length > 60) {
    throw new HttpsError(
      'invalid-argument',
      'Enter a group chat name between 2 and 60 characters.'
    );
  }

  const db = admin.firestore();
  const chatReference = db.collection('groupChats').doc(chatId);
  const messageReference = chatReference.collection('messages').doc('group_named');
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(chatReference);
    if (!snapshot.exists) {
      throw new HttpsError('not-found', 'This group chat is no longer available.');
    }
    const chat = snapshot.data() || {};
    const participantPhones = Array.isArray(chat.participantPhones)
      ? chat.participantPhones
        .map((phone) => String(phone || '').trim())
        .filter((phone) => /^\+[1-9]\d{7,14}$/.test(phone))
      : [];
    if (
      String(chat.chatType || 'group') === 'direct'
      || String(chat.creatorPhone || '').trim() !== ownerPhone
      || participantPhones.length < 2
    ) {
      throw new HttpsError(
        'permission-denied',
        'Only the hike host can name this newly formed group.'
      );
    }
    const existingName = String(chat.customName || '').trim();
    if (existingName && chat.namingPromptActive !== true) {
      if (existingName === customName) return;
      throw new HttpsError(
        'failed-precondition',
        'This group chat has already been named.'
      );
    }

    const nowIso = new Date().toISOString();
    const participantNames = chat.participantNames
      && typeof chat.participantNames === 'object'
      ? chat.participantNames
      : {};
    const hostName = String(
      participantNames[phoneKeyFor(ownerPhone)] || 'Hike host'
    ).trim().slice(0, 80);
    const systemText = `Group named ${customName}`;
    transaction.set(
      chatReference,
      {
        customName,
        requiresHostNaming: false,
        namingPromptShown: true,
        namingPromptActive: false,
        nameSource: 'host',
        hostNamingFinalizedAt: admin.firestore.FieldValue.serverTimestamp(),
        hostNamingFinalizedAtLocal: nowIso,
        namedAt: admin.firestore.FieldValue.serverTimestamp(),
        namedAtLocal: nowIso,
        lastMessage: systemText,
        lastMessageAtLocal: nowIso,
        lastMessageSenderPhone: 'system',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: nowIso,
      },
      { merge: true }
    );
    transaction.set(messageReference, {
      chatId,
      senderPhone: ownerPhone,
      senderName: hostName || 'Hike host',
      text: systemText,
      sentAtLocal: nowIso,
      isSystemMessage: true,
      seenBy: [ownerPhone],
    });
  });

  return { named: true, chatId, customName };
});

function publicProfileFromUserDocument(document) {
  const data = document.data() || {};
  if (data.accountDisabled === true || data.status === 'disabled') {
    return null;
  }
  const profile = data.profile && typeof data.profile === 'object'
    ? data.profile
    : {};
  const phoneNumber = String(data.phoneNumber || '').trim();
  if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
    return null;
  }
  const points = Math.max(0, Number(data.achievementPoints || 0));
  const username = String(data.username || profile.username || 'Hiker')
    .trim()
    .slice(0, 80);
  const photoURL = String(
    data.photoURL || data.profilePhotoURL || profile.photoURL || ''
  ).trim().slice(0, 2000);
  return {
    userId: document.id,
    phoneNumber,
    displayName: username || 'Hiker',
    handle: `@hiker${phoneKeyFor(phoneNumber).slice(-4)}`,
    photoURL,
    gender: String(profile.gender || '').slice(0, 40),
    hikerExperience: String(profile.hikerExperience || '').slice(0, 80),
    hikeFrequency: String(profile.hikeFrequency || '').slice(0, 80),
    residentialLocation: String(profile.residentialLocation || '').slice(0, 160),
    achievementPoints: Number.isFinite(points) ? Math.floor(points) : 0,
    hikerLevel: Math.max(1, Number(data.hikerLevel || 1)),
    hikerLevelName: String(data.hikerLevelName || '').slice(0, 80),
  };
}

// User documents contain authentication hashes, device bindings, emergency
// contacts, and push tokens. Mobile clients receive only this explicit public
// projection instead of being allowed to read other users' full documents.
exports.getPublicProfiles = onCall({}, async (request) => {
  const ownerPhone = authenticatedPhoneClaim(request);
  const uid = String(request.auth?.uid || '');
  if (
    !uid
    || uid !== userDocumentIdForPhone(ownerPhone)
    || !/^\+[1-9]\d{7,14}$/.test(ownerPhone)
  ) {
    throw new HttpsError('unauthenticated', 'Sign in to view hiker profiles.');
  }

  const db = admin.firestore();
  const requestedPhones = Array.isArray(request.data?.phoneNumbers)
    ? request.data.phoneNumbers
        .map((phone) => String(phone || '').trim())
        .filter((phone) => /^\+[1-9]\d{7,14}$/.test(phone))
    : [];
  const requestedUserIds = Array.isArray(request.data?.userIds)
    ? request.data.userIds
        .map((value) => String(value || '').trim())
        .filter((value) => /^[^/]{1,200}$/.test(value))
    : [];
  const phoneNumber = String(request.data?.phoneNumber || '').trim();
  const userId = String(request.data?.userId || '').trim();
  let documents;
  if (requestedPhones.length > 0) {
    const uniquePhones = [...new Set(requestedPhones)].slice(0, 50);
    documents = await db.getAll(
      ...uniquePhones.map((phone) =>
        db.collection('users').doc(userDocumentIdForPhone(phone))
      )
    );
  } else if (requestedUserIds.length > 0) {
    const uniqueUserIds = [...new Set(requestedUserIds)].slice(0, 50);
    documents = await db.getAll(
      ...uniqueUserIds.map((value) => db.collection('users').doc(value))
    );
  } else if (/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
    documents = [
      await db.collection('users').doc(userDocumentIdForPhone(phoneNumber)).get(),
    ];
  } else if (/^[^/]{1,200}$/.test(userId)) {
    documents = [await db.collection('users').doc(userId).get()];
  } else {
    const requestedLimit = Number(request.data?.limit || 80);
    const limit = Number.isFinite(requestedLimit)
      ? Math.max(1, Math.min(80, Math.floor(requestedLimit)))
      : 80;
    documents = (await db.collection('users').limit(limit).get()).docs;
  }
  const profiles = documents
    .filter((document) => document.exists)
    .map(publicProfileFromUserDocument)
    .filter((profile) => profile !== null);
  return { profiles };
});

const teamHikeActionLimits = Object.freeze({
  create: [5, 60 * 60 * 1000],
  read: [120, 10 * 60 * 1000],
  accept: [20, 60 * 60 * 1000],
  ready: [30, 60 * 60 * 1000],
  removePending: [10, 60 * 60 * 1000],
  cancel: [10, 60 * 60 * 1000],
  activate: [30, 60 * 60 * 1000],
  attach: [40, 60 * 60 * 1000],
  location: [360, 10 * 60 * 1000],
  ping: [20, 10 * 60 * 1000],
  respond: [60, 60 * 60 * 1000],
  end: [20, 60 * 60 * 1000],
  pathDeviation: [8, 60 * 60 * 1000],
});

function authenticatedPhoneFor(request, message) {
  const phoneNumber = authenticatedPhoneClaim(request);
  const uid = String(request.auth?.uid || '');
  if (
    !uid
    || uid !== userDocumentIdForPhone(phoneNumber)
    || !/^\+[1-9]\d{7,14}$/.test(phoneNumber)
  ) {
    throw new HttpsError('unauthenticated', message);
  }
  return { phoneNumber, uid };
}

function validFirestoreDocumentId(value) {
  const id = String(value || '').trim();
  return id.length > 0
    && id.length <= 200
    && !id.includes('/')
    && !/[\u0000-\u001f]/.test(id);
}

function sanitizedPlainValue(value, depth = 0) {
  if (depth > 10) {
    return null;
  }
  if (value === null || typeof value === 'boolean') {
    return value;
  }
  if (typeof value === 'string') {
    // Encoded trail polylines can legitimately exceed ordinary text-field
    // limits; the enclosing draft/document size checks remain the boundary.
    return value.slice(0, 120000);
  }
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : 0;
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate().toISOString();
  }
  if (value instanceof admin.firestore.GeoPoint) {
    return { latitude: value.latitude, longitude: value.longitude };
  }
  if (Array.isArray(value)) {
    return value
      .slice(0, 500)
      .map((entry) => sanitizedPlainValue(entry, depth + 1));
  }
  if (value && typeof value === 'object') {
    const result = {};
    for (const [key, entry] of Object.entries(value).slice(0, 250)) {
      if (
        key === '__proto__'
        || key === 'prototype'
        || key === 'constructor'
      ) {
        continue;
      }
      result[String(key).slice(0, 160)] = sanitizedPlainValue(
        entry,
        depth + 1
      );
    }
    return result;
  }
  return null;
}

function boundedNumber(value, minimum, maximum, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return fallback;
  }
  return Math.max(minimum, Math.min(maximum, number));
}

function teamBuddyFromUser(phoneNumber, user, isHost, index) {
  const profile = user?.profile && typeof user.profile === 'object'
    ? user.profile
    : {};
  const key = phoneKeyFor(phoneNumber);
  const fallbackColors = [
    0xff7c3aed,
    0xff0ea5e9,
    0xffec4899,
    0xff14b8a6,
    0xfff97316,
    0xff8b5cf6,
    0xff06b6d4,
    0xffd946ef,
    0xfff43f5e,
    0xfff59e0b,
  ];
  const name = String(
    user?.username || profile.username || `Hiker ${key.slice(-4)}`
  ).trim().slice(0, 80) || 'Trail buddy';
  const photoURL = String(
    user?.photoURL || user?.profilePhotoURL || profile.photoURL || ''
  ).trim().slice(0, 2000);
  return {
    name,
    handle: `@hiker${key.slice(-4)}`,
    phoneNumber,
    role: isHost ? 'Host' : 'Teammate',
    ...(photoURL ? { photoURL } : {}),
    avatarColorValue: isHost
      ? 0xff34a853
      : fallbackColors[index % fallbackColors.length],
  };
}

function sanitizedTeamDraft(rawDraft, trailData, buddies, options = {}) {
  const draft = rawDraft && typeof rawDraft === 'object' && !Array.isArray(rawDraft)
    ? rawDraft
    : {};
  const serialized = JSON.stringify(draft);
  if (!serialized || Buffer.byteLength(serialized, 'utf8') > 180000) {
    throw new HttpsError('invalid-argument', 'The team hike plan is too large.');
  }
  const departureMillis = dateMillis(draft.departureTime);
  const arrivalMillis = dateMillis(draft.expectedArrivalTime);
  const returnMillis = dateMillis(draft.expectedReturnTime);
  const nowMillis = Date.now();
  const pastDepartureToleranceMillis = boundedNumber(
    options.pastDepartureToleranceMillis,
    0,
    30 * 24 * 60 * 60 * 1000,
    12 * 60 * 60 * 1000
  );
  const maximumHikeDurationMillis = boundedNumber(
    options.maximumHikeDurationMillis,
    60 * 60 * 1000,
    30 * 24 * 60 * 60 * 1000,
    7 * 24 * 60 * 60 * 1000
  );
  if (
    !Number.isFinite(departureMillis)
    || !Number.isFinite(arrivalMillis)
    || !Number.isFinite(returnMillis)
    || departureMillis < nowMillis - pastDepartureToleranceMillis
    || departureMillis > nowMillis + 14 * 24 * 60 * 60 * 1000
    || arrivalMillis < departureMillis
    || returnMillis < arrivalMillis
    || returnMillis > departureMillis + maximumHikeDurationMillis
  ) {
    throw new HttpsError('invalid-argument', 'The team hike timing is invalid.');
  }
  const fall = draft.fallDetectionSettings
    && typeof draft.fallDetectionSettings === 'object'
    ? draft.fallDetectionSettings
    : {};
  const customCheckpoints = Array.isArray(draft.customCheckpoints)
    ? draft.customCheckpoints
        .slice(0, 200)
        .map((checkpoint) => sanitizedPlainValue(checkpoint))
        .filter((checkpoint) => {
          const latitude = Number(checkpoint?.latitude);
          const longitude = Number(checkpoint?.longitude);
          return Number.isFinite(latitude)
            && latitude >= -90
            && latitude <= 90
            && Number.isFinite(longitude)
            && longitude >= -180
            && longitude <= 180;
        })
    : [];
  return {
    hikeType: 'team',
    trail: sanitizedPlainValue(trailData),
    startPointName: String(draft.startPointName || '').trim().slice(0, 160),
    destinationName: String(draft.destinationName || '').trim().slice(0, 160),
    departureTime: new Date(departureMillis).toISOString(),
    expectedArrivalTime: new Date(arrivalMillis).toISOString(),
    expectedReturnTime: new Date(returnMillis).toISOString(),
    safetyCheckInIntervalSeconds: Math.round(
      boundedNumber(draft.safetyCheckInIntervalSeconds, 60, 86400, 1800)
    ),
    locationRecordingIntervalSeconds: Math.round(
      boundedNumber(draft.locationRecordingIntervalSeconds, 5, 60, 30)
    ),
    emergencyContactNames: Array.isArray(draft.emergencyContactNames)
      ? draft.emergencyContactNames
          .slice(0, 10)
          .map((name) => String(name || '').trim().slice(0, 80))
          .filter((name) => name)
      : [],
    shareLiveLocation: draft.shareLiveLocation === true,
    fallDetectionEnabled: draft.fallDetectionEnabled === true,
    fallDetectionSettings: {
      sensorSensitivity: boundedNumber(fall.sensorSensitivity, 1, 10, 5),
      fallResponseDurationSeconds: Math.round(
        boundedNumber(fall.fallResponseDurationSeconds, 5, 600, 30)
      ),
      longestRestDurationSeconds: Math.round(
        boundedNumber(fall.longestRestDurationSeconds, 30, 7200, 180)
      ),
    },
    pathDeviationEnabled: draft.pathDeviationEnabled === true,
    offlinePhysicalAlertEnabled: draft.offlinePhysicalAlertEnabled === true,
    duressEnabled: draft.duressEnabled === true,
    completedChecklistItems: Array.isArray(draft.completedChecklistItems)
      ? draft.completedChecklistItems
          .slice(0, 50)
          .map((item) => String(item || '').slice(0, 100))
      : [],
    teamBuddies: buddies,
    ...(customCheckpoints.length > 0 ? { customCheckpoints } : {}),
  };
}

function sharedHikePlan(rawDraft, trailData, buddies, options = {}) {
  const sanitized = sanitizedTeamDraft(rawDraft, trailData, buddies, options);
  return projectSharedHikePlan(sanitized);
}

function projectedLegacySharedHikePlan(rawDraft) {
  const draft = rawDraft && typeof rawDraft === 'object' && !Array.isArray(rawDraft)
    ? sanitizedPlainValue(rawDraft)
    : {};
  return projectSharedHikePlan(draft);
}

function canonicalSharedPlanFromUpcoming(upcoming, fallbackTrail, buddies) {
  const stored = projectedLegacySharedHikePlan(upcoming?.draft);
  const departureTime = stored.departureTime
    ?? upcoming?.departureTimeLocal
    ?? upcoming?.departureTime;
  const departureMillis = dateMillis(departureTime);
  const durationMinutes = boundedNumber(
    upcoming?.durationMinutes,
    1,
    43200,
    1
  );
  const expectedArrivalTime = stored.expectedArrivalTime
    ?? upcoming?.expectedArrivalTimeLocal
    ?? upcoming?.expectedArrivalTime
    ?? (Number.isFinite(departureMillis)
      ? new Date(departureMillis + durationMinutes * 60 * 1000).toISOString()
      : undefined);
  return projectSharedHikePlan({
    ...stored,
    hikeType: 'team',
    trail: stored.trail && typeof stored.trail === 'object'
      ? stored.trail
      : fallbackTrail,
    startPointName: stored.startPointName ?? upcoming?.startPointName ?? '',
    destinationName:
      stored.destinationName ?? upcoming?.destinationName ?? '',
    departureTime,
    expectedArrivalTime,
    expectedReturnTime: stored.expectedReturnTime
      ?? upcoming?.expectedReturnTimeLocal
      ?? upcoming?.expectedReturnTime,
    teamBuddies: buddies,
  });
}

function mergeSharedPlanWithCallerSafety(sharedPlan, callerDraft) {
  const shared = sharedPlan && typeof sharedPlan === 'object'
    && !Array.isArray(sharedPlan)
    ? sharedPlan
    : {};
  const personal = callerDraft && typeof callerDraft === 'object'
    && !Array.isArray(callerDraft)
    ? callerDraft
    : {};
  return {
    ...personal,
    hikeType: shared.hikeType,
    trail: shared.trail,
    startPointName: shared.startPointName,
    destinationName: shared.destinationName,
    departureTime: shared.departureTime,
    expectedArrivalTime: shared.expectedArrivalTime,
    expectedReturnTime: shared.expectedReturnTime,
    teamBuddies: shared.teamBuddies,
    ...(Array.isArray(shared.customCheckpoints)
      ? { customCheckpoints: shared.customCheckpoints }
      : { customCheckpoints: [] }),
  };
}

function teamParticipantPhone(participant) {
  return String(
    participant?.phoneNumber || participant?.buddy?.phoneNumber || ''
  ).trim();
}

function validTeamParticipants(team) {
  return Array.isArray(team?.participants)
    ? team.participants.filter((participant) =>
        /^\+[1-9]\d{7,14}$/.test(teamParticipantPhone(participant))
      )
    : [];
}

function teamSessionForCallable(id, team) {
  return sanitizedPlainValue({
    ...team,
    teamHikeSessionId: id,
    createdAt: undefined,
    updatedAt: undefined,
  });
}

function teamRateReference(db, uid, action) {
  return db.collection('teamHikeActionRateLimits').doc(`${uid}_${action}`);
}

function assertTeamActionRate(transaction, reference, snapshot, action) {
  const [limit, windowMillis] = teamHikeActionLimits[action] || [20, 3600000];
  const data = snapshot.data() || {};
  const nowMillis = Date.now();
  const previousStart = Number(data.windowStartedAtMillis || 0);
  const inWindow = nowMillis - previousStart < windowMillis;
  const actionCount = inWindow ? Number(data.actionCount || 0) : 0;
  if (actionCount >= limit) {
    throw new HttpsError(
      'resource-exhausted',
      'Too many team hike updates were submitted. Try again shortly.'
    );
  }
  transaction.set(
    reference,
    {
      windowStartedAtMillis: inWindow ? previousStart : nowMillis,
      actionCount: actionCount + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

function teamOutboxPayload({ type, recipientPhone, senderPhone, teamId, nowIso }) {
  const deepLink = type === 'team_hike_ping'
    ? `hikercircle://team-hike/ping?teamSessionId=${encodeURIComponent(teamId)}`
    : `hikercircle://team-hike/join?teamSessionId=${encodeURIComponent(teamId)}`;
  return {
    type,
    recipientPhoneNumber: recipientPhone,
    senderPhoneNumber: senderPhone,
    teamHikeSessionId: teamId,
    status: 'pending',
    attemptCount: 0,
    data: { type, teamHikeSessionId: teamId, deepLink },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAtLocal: nowIso,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAtLocal: nowIso,
  };
}

function queueTeamOutbox(
  transaction,
  db,
  { type, recipientPhone, senderPhone, teamId, nowIso }
) {
  if (
    !/^\+[1-9]\d{7,14}$/.test(recipientPhone)
    || !/^\+[1-9]\d{7,14}$/.test(senderPhone)
  ) {
    return;
  }
  transaction.set(
    db.collection('fcmOutbox').doc(),
    teamOutboxPayload({ type, recipientPhone, senderPhone, teamId, nowIso })
  );
}

function validTeamSafetySettings(raw) {
  if (
    !raw
    || typeof raw !== 'object'
    || raw.liveLocationSharing !== true
    || raw.pathDeviationAlerts !== true
    || raw.teammateSeparationAlerts !== true
  ) {
    throw new HttpsError(
      'failed-precondition',
      'Complete the required team safety settings before marking ready.'
    );
  }
  return {
    liveLocationSharing: true,
    pathDeviationAlerts: true,
    teammateSeparationAlerts: true,
    fallDetectionEnabled: raw.fallDetectionEnabled !== false,
    sensorSensitivity: boundedNumber(raw.sensorSensitivity, 1, 10, 5),
    responseCountdownSeconds: Math.round(
      boundedNumber(raw.responseCountdownSeconds, 5, 600, 30)
    ),
    fallResponseDurationSeconds: Math.round(
      boundedNumber(raw.fallResponseDurationSeconds, 5, 600, 30)
    ),
    longestRestDurationSeconds: Math.round(
      boundedNumber(raw.longestRestDurationSeconds, 30, 7200, 180)
    ),
    enhancedIsolationProtection: raw.enhancedIsolationProtection === true,
    separationDistanceMeters: boundedNumber(
      raw.separationDistanceMeters,
      50,
      1000,
      150
    ),
    isolationGraceSeconds: Math.round(
      boundedNumber(raw.isolationGraceSeconds, 30, 1800, 180)
    ),
    automaticTeamCheckPing: raw.automaticTeamCheckPing !== false,
  };
}

function haversineMeters(first, second) {
  const toRadians = (degrees) => degrees * Math.PI / 180;
  const latitude1 = toRadians(Number(first.latitude));
  const latitude2 = toRadians(Number(second.latitude));
  const latitudeDelta = latitude2 - latitude1;
  const longitudeDelta = toRadians(
    Number(second.longitude) - Number(first.longitude)
  );
  const a = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos(latitude1)
      * Math.cos(latitude2)
      * Math.sin(longitudeDelta / 2) ** 2;
  const boundedA = Math.max(0, Math.min(1, a));
  return 6371000 * 2 * Math.atan2(
    Math.sqrt(boundedA),
    Math.sqrt(1 - boundedA)
  );
}

function canonicalChatProfile(phoneNumber, user) {
  const profile = user?.profile && typeof user.profile === 'object'
    ? user.profile
    : {};
  const key = phoneKeyFor(phoneNumber);
  const name = String(
    user?.username || profile.username || `Hiker ${key.slice(-4)}`
  ).trim().slice(0, 80) || 'Hiker';
  const photoURL = String(
    user?.photoURL || user?.profilePhotoURL || profile.photoURL || ''
  ).trim().slice(0, 2000);
  return { name, photoURL };
}

function assertWindowRate(
  transaction,
  reference,
  snapshot,
  { limit, windowMillis, message }
) {
  const data = snapshot.data() || {};
  const nowMillis = Date.now();
  const previousStart = Number(data.windowStartedAtMillis || 0);
  const inWindow = nowMillis - previousStart < windowMillis;
  const actionCount = inWindow ? Number(data.actionCount || 0) : 0;
  if (actionCount >= limit) {
    throw new HttpsError('resource-exhausted', message);
  }
  transaction.set(
    reference,
    {
      windowStartedAtMillis: inWindow ? previousStart : nowMillis,
      actionCount: actionCount + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

function canonicalTrailSnapshot(trailId, trail) {
  return {
    ...sanitizedPlainValue(trail || {}),
    trailId,
    name: String(trail?.name || 'Trail').trim().slice(0, 160) || 'Trail',
  };
}

function activeHikeDocumentData({
  sessionId,
  uid,
  phoneNumber,
  draft,
  startedAtMillis,
  sourceUpcomingHikeId = '',
  teamHikeSessionId = '',
}) {
  const nowIso = new Date().toISOString();
  const startedAtIso = new Date(startedAtMillis).toISOString();
  const fall = draft.fallDetectionSettings || {};
  return {
    sessionId,
    userId: uid,
    userPhoneNumber: phoneNumber,
    ...(sourceUpcomingHikeId ? { sourceUpcomingHikeId } : {}),
    ...(teamHikeSessionId ? { teamHikeSessionId } : {}),
    status: 'active',
    hikeType: String(draft.hikeType || 'solo') === 'team' ? 'team' : 'solo',
    teamBuddies: Array.isArray(draft.teamBuddies) ? draft.teamBuddies : [],
    trailId: String(draft.trail?.trailId || ''),
    trailName: String(draft.trail?.name || 'Trail').slice(0, 160),
    trail: draft.trail,
    checkpoints: Array.isArray(draft.customCheckpoints)
      ? draft.customCheckpoints
      : Array.isArray(draft.trail?.checkpoints)
        ? draft.trail.checkpoints
        : [],
    startPointName: String(draft.startPointName || '').slice(0, 160),
    destinationName: String(draft.destinationName || '').slice(0, 160),
    plannedStartTimeLocal: draft.departureTime,
    expectedArrivalTimeLocal: draft.expectedArrivalTime,
    expectedReturnTimeLocal: draft.expectedReturnTime,
    safetyCheckInIntervalSeconds: draft.safetyCheckInIntervalSeconds,
    safetyCheckInIntervalMinutes: Math.max(
      1,
      Math.round(Number(draft.safetyCheckInIntervalSeconds || 1800) / 60)
    ),
    locationRecordingIntervalSeconds: draft.locationRecordingIntervalSeconds,
    locationRecordingIntervalMinutes: Math.max(
      1,
      Math.round(Number(draft.locationRecordingIntervalSeconds || 30) / 60)
    ),
    emergencyContactNames: draft.emergencyContactNames,
    shareLiveLocation: draft.shareLiveLocation === true,
    fallDetectionEnabled: draft.fallDetectionEnabled === true,
    fallDetectionSensorSensitivity: fall.sensorSensitivity,
    fallDetectionResponseDurationSeconds: fall.fallResponseDurationSeconds,
    fallDetectionLongestRestDurationSeconds: fall.longestRestDurationSeconds,
    fallDetectionStillnessDurationSeconds: fall.fallResponseDurationSeconds,
    pathDeviationEnabled: draft.pathDeviationEnabled === true,
    offlinePhysicalAlertEnabled: draft.offlinePhysicalAlertEnabled === true,
    duressEnabled: draft.duressEnabled === true,
    completedChecklistItems: Array.isArray(draft.completedChecklistItems)
      ? draft.completedChecklistItems
      : [],
    monitoringExpected: true,
    monitoringLifecycleState: 'active',
    startedAt: admin.firestore.Timestamp.fromMillis(startedAtMillis),
    startedAtLocal: startedAtIso,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAtLocal: startedAtIso,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAtLocal: nowIso,
  };
}

async function ensureTeamChatDocument(
  db,
  teamId,
  team,
  { newlyJoinedName = '' } = {}
) {
  const participants = validTeamParticipants(team);
  const participantPhones = participants.map(teamParticipantPhone);
  if (participantPhones.length === 0) {
    return;
  }
  const participantNames = {};
  const participantPhotoURLs = {};
  for (const participant of participants) {
    const phone = teamParticipantPhone(participant);
    const buddy = participant.buddy && typeof participant.buddy === 'object'
      ? participant.buddy
      : {};
    participantNames[phoneKeyFor(phone)] = String(
      buddy.name || `Hiker ${phoneKeyFor(phone).slice(-4)}`
    ).trim().slice(0, 80);
    const photoURL = String(buddy.photoURL || '').trim().slice(0, 2000);
    if (photoURL) {
      participantPhotoURLs[phoneKeyFor(phone)] = photoURL;
    }
  }
  const chatReference = db.collection('groupChats').doc(`team_${teamId}`);
  const now = new Date();
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(chatReference);
    const existing = snapshot.data() || {};
    const safeJoinedName = String(newlyJoinedName || '').trim().slice(0, 80);
    const shouldRequestHostNaming = Boolean(
      safeJoinedName && !String(existing.customName || '').trim()
    );
    const phase = String(team.phase || '');
    const shouldArchive = phase === 'completed' && !existing.hikeEndedAtLocal;
    transaction.set(
      chatReference,
      {
        hikeSessionId: String(team.activeHikeSessionId || ''),
        teamHikeSessionId: teamId,
        trailName: String(team.trailName || team.draft?.trail?.name || 'Team hike')
          .trim().slice(0, 160),
        participantPhones,
        participantNames,
        participantPhotoURLs,
        creatorPhone: String(team.hostPhoneNumber || participantPhones[0]),
        chatType: 'group',
        departureTimeLocal: String(
          team.plannedStartTimeLocal || team.draft?.departureTime || ''
        ),
        ...(shouldRequestHostNaming
          ? {
              requiresHostNaming: true,
              latestJoinedName: safeJoinedName,
              teamFormedAtLocal: String(existing.teamFormedAtLocal || now.toISOString()),
            }
          : {}),
        ...(!snapshot.exists
          ? {
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              createdAtLocal: String(team.createdAtLocal || now.toISOString()),
            }
          : {}),
        ...(shouldArchive
          ? {
              customName: String(existing.customName || '').trim()
                || defaultFormedHikeGroupName({
                  ...existing,
                  trailName: String(
                    team.trailName || team.draft?.trail?.name || 'Hike'
                  ),
                  departureTimeLocal: String(
                    team.plannedStartTimeLocal || team.draft?.departureTime || ''
                  ),
                }),
              requiresHostNaming: false,
              namingPromptShown: true,
              namingPromptActive: false,
              hikeEndedAtLocal: now.toISOString(),
              chatRemovesAtLocal: admin.firestore.FieldValue.delete(),
              closureReason: 'team_hike_completed',
              isDeleted: false,
              lastMessage:
                'Team hike completed. This chat is saved with your hike history.',
              lastMessageAtLocal: now.toISOString(),
              lastMessageSenderPhone: 'system',
            }
          : {}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: now.toISOString(),
      },
      { merge: true }
    );
    if (shouldArchive) {
      transaction.set(chatReference.collection('messages').doc('team_closed'), {
        chatId: chatReference.id,
        senderPhone: String(team.hostPhoneNumber || participantPhones[0]),
        senderName: 'HikerCircle',
        text: 'Team hike completed. This chat is saved with your hike history.',
        sentAtLocal: now.toISOString(),
        isSystemMessage: true,
        seenBy: participantPhones,
      });
    }
  });
}

exports.scheduleUpcomingHike = onCall(
  {},
  async (request) => {
    const { phoneNumber: ownerPhone, uid } = authenticatedPhoneFor(
      request,
      'Sign in to schedule a hike.'
    );
    const rawDraft = request.data?.draft;
    const requestedJoinPolicy = String(request.data?.joinPolicy || 'approval');
    const creationKey = String(request.data?.creationKey || '').trim();
    const trailId = String(rawDraft?.trail?.trailId || '').trim();
    if (
      !/^[A-Za-z0-9_-]{8,240}$/.test(creationKey)
      || !validFirestoreDocumentId(trailId)
    ) {
      throw new HttpsError('invalid-argument', 'The hike schedule is invalid.');
    }
    const requestedPhones = Array.isArray(rawDraft?.teamBuddies)
      ? rawDraft.teamBuddies
          .map((buddy) => String(buddy?.phoneNumber || '').trim())
          .filter((phone) => phone !== ownerPhone)
      : [];
    if (
      requestedPhones.length > 10
      || requestedPhones.some((phone) => !/^\+[1-9]\d{7,14}$/.test(phone))
    ) {
      throw new HttpsError('invalid-argument', 'The selected hiking buddies are invalid.');
    }
    const invitedPhones = [...new Set(requestedPhones)];
    const db = admin.firestore();
    const hash = crypto
      .createHash('sha256')
      .update(`${uid}:${creationKey}`)
      .digest('hex');
    const hikeReference = db
      .collection('upcomingHikes')
      .doc(`upcoming_${hash.slice(0, 40)}`);
    const chatReference = db
      .collection('groupChats')
      .doc(`hike_${hikeReference.id}`);
    const userReference = db.collection('users').doc(uid);
    const trailReference = db.collection('trails').doc(trailId);
    const rateReference = db.collection('upcomingHikeRateLimits').doc(uid);
    const inviteeReferences = invitedPhones.map((phone) =>
      db.collection('users').doc(userDocumentIdForPhone(phone))
    );

    const result = await db.runTransaction(async (transaction) => {
      const snapshots = await Promise.all([
        transaction.get(userReference),
        transaction.get(trailReference),
        transaction.get(rateReference),
        transaction.get(hikeReference),
        transaction.get(chatReference),
        ...inviteeReferences.map((reference) => transaction.get(reference)),
      ]);
      const ownerSnapshot = snapshots[0];
      const trailSnapshot = snapshots[1];
      const rateSnapshot = snapshots[2];
      const existingHikeSnapshot = snapshots[3];
      const existingChatSnapshot = snapshots[4];
      const inviteeSnapshots = snapshots.slice(5);
      if (!ownerSnapshot.exists) {
        throw new HttpsError('unauthenticated', 'Your account is unavailable.');
      }
      const owner = ownerSnapshot.data() || {};
      if (owner.accountDisabled === true || owner.status === 'disabled') {
        throw new HttpsError('permission-denied', 'Your account is unavailable.');
      }
      if (!trailSnapshot.exists) {
        throw new HttpsError('not-found', 'This trail is no longer available.');
      }
      if (existingHikeSnapshot.exists) {
        const existing = existingHikeSnapshot.data() || {};
        if (
          String(existing.creatorUserId || '') !== uid
          || String(existing.creationKeyHash || '') !== hash
        ) {
          throw new HttpsError('already-exists', 'This schedule request conflicts.');
        }
        return { hikeId: hikeReference.id, created: false };
      }
      const buddyPhones = new Set(
        (Array.isArray(owner.buddyPhoneNumbers) ? owner.buddyPhoneNumbers : [])
          .map((phone) => String(phone || '').trim())
      );
      inviteeSnapshots.forEach((snapshot, index) => {
        const invitedUser = snapshot.data() || {};
        if (
          !snapshot.exists
          || invitedUser.accountDisabled === true
          || invitedUser.status === 'disabled'
          || !buddyPhones.has(invitedPhones[index])
        ) {
          throw new HttpsError(
            'failed-precondition',
            'One of the selected hiking buddies is no longer available.'
          );
        }
      });
      const trail = canonicalTrailSnapshot(trailId, trailSnapshot.data() || {});
      const buddies = inviteeSnapshots.map((snapshot, index) =>
        teamBuddyFromUser(invitedPhones[index], snapshot.data() || {}, false, index)
      );
      const isGroupHike =
        String(rawDraft?.hikeType || '') === 'team' || invitedPhones.length > 0;
      const draft = {
        ...sharedHikePlan(rawDraft, trail, buddies),
        hikeType: isGroupHike ? 'team' : 'solo',
      };
      const departureMillis = dateMillis(draft.departureTime);
      if (
        !Number.isFinite(departureMillis)
        || departureMillis < Date.now() - 2 * 60 * 1000
      ) {
        throw new HttpsError('invalid-argument', 'Choose a future departure time.');
      }
      const nowIso = new Date().toISOString();
      const ownerProfile = canonicalChatProfile(ownerPhone, owner);
      const participantPhones = [ownerPhone, ...invitedPhones];
      const participantNames = {
        [phoneKeyFor(ownerPhone)]: ownerProfile.name,
      };
      const participantPhotoURLs = {};
      if (ownerProfile.photoURL) {
        participantPhotoURLs[phoneKeyFor(ownerPhone)] = ownerProfile.photoURL;
      }
      inviteeSnapshots.forEach((snapshot, index) => {
        const phone = invitedPhones[index];
        const profile = canonicalChatProfile(phone, snapshot.data() || {});
        participantNames[phoneKeyFor(phone)] = profile.name;
        if (profile.photoURL) {
          participantPhotoURLs[phoneKeyFor(phone)] = profile.photoURL;
        }
      });
      const hike = {
        sessionId: hikeReference.id,
        trailId,
        trailName: trail.name,
        latitude: boundedNumber(trail.latitude, -90, 90, 0),
        longitude: boundedNumber(trail.longitude, -180, 180, 0),
        area: String(trail.area || '').slice(0, 160),
        state: String(trail.state || '').slice(0, 160),
        country: String(trail.country || '').slice(0, 160),
        distanceKm: boundedNumber(trail.distanceKm, 0, 1000, 0),
        durationMinutes: Math.round(
          boundedNumber(trail.estimatedDurationMinutes, 1, 43200, 1)
        ),
        difficulty: String(trail.difficulty || '').slice(0, 80),
        startPointName: draft.startPointName,
        destinationName: draft.destinationName,
        departureTimeLocal: draft.departureTime,
        expectedArrivalTimeLocal: draft.expectedArrivalTime,
        expectedReturnTimeLocal: draft.expectedReturnTime,
        hikeType: draft.hikeType,
        joinPolicy: isGroupHike && requestedJoinPolicy === 'open'
          ? 'open'
          : 'approval',
        participantCount: participantPhones.length,
        participantPhones,
        creatorPhone: ownerPhone,
        creatorUserId: uid,
        creatorName: ownerProfile.name,
        creationKeyHash: hash,
        notificationRadiusKm: 20,
        sharedHikePlanPrivacyVersion: SHARED_HIKE_PLAN_PRIVACY_VERSION,
        draft,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAtLocal: nowIso,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: nowIso,
      };
      transaction.create(hikeReference, hike);
      if (participantPhones.length > 1) {
        transaction.set(
          chatReference,
          {
            hikeSessionId: hikeReference.id,
            trailName: trail.name,
            participantPhones,
            participantNames,
            participantPhotoURLs,
            creatorPhone: ownerPhone,
            chatType: 'group',
            departureTimeLocal: draft.departureTime,
            ...(!existingChatSnapshot.exists
              ? {
                  createdAt: admin.firestore.FieldValue.serverTimestamp(),
                  createdAtLocal: nowIso,
                }
              : {}),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAtLocal: nowIso,
          },
          { merge: true }
        );
      }
      assertWindowRate(transaction, rateReference, rateSnapshot, {
        limit: 5,
        windowMillis: 60 * 60 * 1000,
        message: 'Too many hikes were scheduled. Try again later.',
      });
      return { hikeId: hikeReference.id, created: true };
    });
    return result;
  }
);

exports.openDirectChat = onCall(
  {},
  async (request) => {
    const { phoneNumber: callerPhone, uid } = authenticatedPhoneFor(
      request,
      'Sign in to start a private conversation.'
    );
    const otherPhone = String(request.data?.otherPhoneNumber || '').trim();
    if (
      !/^\+[1-9]\d{7,14}$/.test(otherPhone)
      || phoneKeyFor(otherPhone) === phoneKeyFor(callerPhone)
    ) {
      throw new HttpsError('invalid-argument', 'Choose another hiker.');
    }
    const keys = [phoneKeyFor(callerPhone), phoneKeyFor(otherPhone)].sort();
    const chatId = `direct_${keys.join('_')}`;
    const db = admin.firestore();
    const chatReference = db.collection('groupChats').doc(chatId);
    const callerReference = db.collection('users').doc(uid);
    const otherReference = db
      .collection('users')
      .doc(userDocumentIdForPhone(otherPhone));
    const rateReference = db
      .collection('directChatActionRateLimits')
      .doc(uid);
    const chat = await db.runTransaction(async (transaction) => {
      const [callerSnapshot, otherSnapshot, chatSnapshot, rateSnapshot] =
        await Promise.all([
          transaction.get(callerReference),
          transaction.get(otherReference),
          transaction.get(chatReference),
          transaction.get(rateReference),
        ]);
      if (!callerSnapshot.exists || !otherSnapshot.exists) {
        throw new HttpsError('not-found', 'This hiker is no longer available.');
      }
      const caller = callerSnapshot.data() || {};
      const other = otherSnapshot.data() || {};
      if (
        caller.accountDisabled === true
        || caller.status === 'disabled'
        || other.accountDisabled === true
        || other.status === 'disabled'
      ) {
        throw new HttpsError('failed-precondition', 'This hiker is unavailable.');
      }
      const existing = chatSnapshot.data() || {};
      if (chatSnapshot.exists && String(existing.chatType || '') !== 'direct') {
        throw new HttpsError('already-exists', 'This chat id is already in use.');
      }
      const callerProfile = canonicalChatProfile(callerPhone, caller);
      const otherProfile = canonicalChatProfile(otherPhone, other);
      const participantNames = {
        [phoneKeyFor(callerPhone)]: callerProfile.name,
        [phoneKeyFor(otherPhone)]: otherProfile.name,
      };
      const participantPhotoURLs = {};
      if (callerProfile.photoURL) {
        participantPhotoURLs[phoneKeyFor(callerPhone)] = callerProfile.photoURL;
      }
      if (otherProfile.photoURL) {
        participantPhotoURLs[phoneKeyFor(otherPhone)] = otherProfile.photoURL;
      }
      const nowIso = new Date().toISOString();
      const patch = {
        hikeSessionId: '',
        trailName: 'Private chat',
        chatType: 'direct',
        participantPhones: [callerPhone, otherPhone],
        participantNames,
        participantPhotoURLs,
        creatorPhone: chatSnapshot.exists
          ? String(existing.creatorPhone || callerPhone)
          : callerPhone,
        isDeleted: false,
        ...(!chatSnapshot.exists
          ? {
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              createdAtLocal: nowIso,
            }
          : {}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: nowIso,
      };
      transaction.set(chatReference, patch, { merge: true });
      assertWindowRate(transaction, rateReference, rateSnapshot, {
        limit: 30,
        windowMillis: 60 * 60 * 1000,
        message: 'Too many chat actions were requested. Try again later.',
      });
      return { ...existing, ...patch, createdAtLocal: existing.createdAtLocal || nowIso };
    });
    return { chatId, chat: sanitizedPlainValue(chat) };
  }
);

exports.deleteChatForUser = onCall(
  {},
  async (request) => {
    const { phoneNumber: callerPhone, uid } = authenticatedPhoneFor(
      request,
      'Sign in to leave this conversation.'
    );
    const chatId = String(request.data?.chatId || '').trim();
    if (!validFirestoreDocumentId(chatId)) {
      throw new HttpsError('invalid-argument', 'The chat is invalid.');
    }
    const db = admin.firestore();
    const chatReference = db.collection('groupChats').doc(chatId);
    const rateReference = db
      .collection('directChatActionRateLimits')
      .doc(uid);
    await db.runTransaction(async (transaction) => {
      const [chatSnapshot, rateSnapshot] = await Promise.all([
        transaction.get(chatReference),
        transaction.get(rateReference),
      ]);
      if (!chatSnapshot.exists) {
        return;
      }
      const chat = chatSnapshot.data() || {};
      const participants = Array.isArray(chat.participantPhones)
        ? chat.participantPhones.map((phone) => String(phone || '').trim())
        : [];
      if (!participants.includes(callerPhone)) {
        return;
      }
      const teamId = String(chat.teamHikeSessionId || '').trim();
      if (teamId) {
        const teamSnapshot = await transaction.get(
          db.collection('teamHikeSessions').doc(teamId)
        );
        const phase = String(teamSnapshot.data()?.phase || '');
        if (teamSnapshot.exists && phase !== 'completed') {
          throw new HttpsError(
            'failed-precondition',
            'An active team safety chat cannot be left before the hike ends.'
          );
        }
      }
      const remaining = participants.filter((phone) => phone !== callerPhone);
      const callerUser = await transaction.get(db.collection('users').doc(uid));
      const displayName = canonicalChatProfile(
        callerPhone,
        callerUser.data() || {}
      ).name;
      const nowIso = new Date().toISOString();
      transaction.set(
        chatReference,
        {
          participantPhones: remaining,
          isDeleted: remaining.length === 0,
          lastMessage: `${displayName} left the conversation`,
          lastMessageAtLocal: nowIso,
          lastMessageSenderPhone: 'system',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAtLocal: nowIso,
        },
        { merge: true }
      );
      transaction.set(
        chatReference.collection('messages').doc(`left_${phoneKeyFor(callerPhone)}`),
        {
          chatId,
          senderPhone: callerPhone,
          senderName: 'HikerCircle',
          text: `${displayName} left the conversation`,
          sentAtLocal: nowIso,
          isSystemMessage: true,
          seenBy: remaining,
        }
      );
      assertWindowRate(transaction, rateReference, rateSnapshot, {
        limit: 30,
        windowMillis: 60 * 60 * 1000,
        message: 'Too many chat actions were requested. Try again later.',
      });
    });
    return { left: true };
  }
);

exports.startActiveHikeSession = onCall(
  {},
  async (request) => {
    const { phoneNumber, uid } = authenticatedPhoneFor(
      request,
      'Sign in to start hike tracking.'
    );
    const rawDraft = request.data?.draft;
    const trailId = String(rawDraft?.trail?.trailId || '').trim();
    const sourceUpcomingHikeId = String(
      request.data?.sourceUpcomingHikeId || ''
    ).trim();
    const teamHikeSessionId = String(
      request.data?.teamHikeSessionId || ''
    ).trim();
    const creationKey = String(request.data?.creationKey || '').trim();
    if (
      !validFirestoreDocumentId(trailId)
      || !/^[A-Za-z0-9_-]{8,240}$/.test(creationKey)
      || (sourceUpcomingHikeId && !validFirestoreDocumentId(sourceUpcomingHikeId))
      || (teamHikeSessionId && !validFirestoreDocumentId(teamHikeSessionId))
    ) {
      throw new HttpsError('invalid-argument', 'The active hike request is invalid.');
    }
    const identityKey = sourceUpcomingHikeId
      ? `upcoming:${sourceUpcomingHikeId}`
      : teamHikeSessionId
        ? `team:${teamHikeSessionId}`
        : `offline:${creationKey}`;
    const sessionHash = crypto
      .createHash('sha256')
      .update(`${uid}:${identityKey}`)
      .digest('hex');
    const sessionId = `hike_${sessionHash.slice(0, 48)}`;
    const db = admin.firestore();
    const sessionReference = db.collection('hikeSessions').doc(sessionId);
    const terminalReference = db
      .collection('hikeSessionTerminalStates')
      .doc(sessionId);
    const userReference = db.collection('users').doc(uid);
    const trailReference = db.collection('trails').doc(trailId);
    const rateReference = db.collection('activeHikeStartRateLimits').doc(uid);
    const upcomingReference = sourceUpcomingHikeId
      ? db.collection('upcomingHikes').doc(sourceUpcomingHikeId)
      : null;
    const teamReference = teamHikeSessionId
      ? db.collection('teamHikeSessions').doc(teamHikeSessionId)
      : null;
    const startedAtMillis = dateMillis(request.data?.startedAtLocal);
    const safeStartedAtMillis = Number.isFinite(startedAtMillis)
      && startedAtMillis <= Date.now() + 5 * 60 * 1000
      && startedAtMillis >= Date.now() - 30 * 24 * 60 * 60 * 1000
      ? startedAtMillis
      : Date.now();

    const result = await db.runTransaction(async (transaction) => {
      const baseSnapshots = await Promise.all([
        transaction.get(userReference),
        transaction.get(trailReference),
        transaction.get(rateReference),
        transaction.get(sessionReference),
        transaction.get(terminalReference),
        ...(upcomingReference ? [transaction.get(upcomingReference)] : []),
        ...(teamReference ? [transaction.get(teamReference)] : []),
      ]);
      const userSnapshot = baseSnapshots[0];
      const trailSnapshot = baseSnapshots[1];
      const rateSnapshot = baseSnapshots[2];
      const existingSession = baseSnapshots[3];
      const terminalSnapshot = baseSnapshots[4];
      let index = 5;
      const upcomingSnapshot = upcomingReference ? baseSnapshots[index++] : null;
      const teamSnapshot = teamReference ? baseSnapshots[index] : null;
      if (!userSnapshot.exists || !trailSnapshot.exists) {
        throw new HttpsError('failed-precondition', 'Your hike data is unavailable.');
      }
      const user = userSnapshot.data() || {};
      if (user.accountDisabled === true || user.status === 'disabled') {
        throw new HttpsError('permission-denied', 'Your account is unavailable.');
      }
      let sourceUpcoming = null;
      if (upcomingReference) {
        if (!upcomingSnapshot?.exists) {
          throw new HttpsError(
            'not-found',
            'This scheduled hike is no longer available.'
          );
        }
        sourceUpcoming = upcomingSnapshot.data() || {};
        const sourceParticipantPhones = [
          String(sourceUpcoming.creatorPhone || ''),
          ...(Array.isArray(sourceUpcoming.participantPhones)
            ? sourceUpcoming.participantPhones
            : []),
        ]
          .map((phone) => String(phone || '').trim())
          .filter((phone) => /^\+[1-9]\d{7,14}$/.test(phone));
        const uniqueSourceParticipants = [...new Set(sourceParticipantPhones)];
        if (
          String(sourceUpcoming.trailId || '') !== trailId
          || !uniqueSourceParticipants.includes(phoneNumber)
          || sourceUpcoming.isDeleted === true
        ) {
          throw new HttpsError(
            'permission-denied',
            'You cannot start this scheduled hike.'
          );
        }
        const linkedTeamId = String(
          sourceUpcoming.teamHikeSessionId || ''
        ).trim();
        if (uniqueSourceParticipants.length > 1) {
          if (!teamHikeSessionId || linkedTeamId !== teamHikeSessionId) {
            throw new HttpsError(
              'failed-precondition',
              'Launch the scheduled team roster before starting tracking.'
            );
          }
          if (!teamSnapshot?.exists) {
            throw new HttpsError(
              'failed-precondition',
              'The scheduled team launch is unavailable.'
            );
          }
          const linkedTeam = teamSnapshot.data() || {};
          const callerIsLinkedParticipant = validTeamParticipants(linkedTeam)
            .some(
              (participant) => teamParticipantPhone(participant) === phoneNumber
            );
          if (
            String(linkedTeam.phase || '') !== 'active'
            || String(linkedTeam.sourceUpcomingHikeId || '')
              !== sourceUpcomingHikeId
            || String(linkedTeam.trailId || '') !== trailId
            || !callerIsLinkedParticipant
          ) {
            throw new HttpsError(
              'permission-denied',
              'This team launch does not belong to the scheduled hike participant.'
            );
          }
        } else if (teamHikeSessionId || linkedTeamId) {
          throw new HttpsError(
            'failed-precondition',
            'This solo scheduled hike is not linked to a team launch.'
          );
        }
      }
      if (existingSession.exists) {
        const existing = existingSession.data() || {};
        const canAdoptLegacyTeamSource = legacyActiveHikeCanAdoptTeamSource(
          existing,
          sourceUpcomingHikeId,
          teamHikeSessionId
        );
        if (
          String(existing.userId || '') !== uid
          || String(existing.userPhoneNumber || '') !== phoneNumber
        ) {
          throw new HttpsError('permission-denied', 'This hike belongs to another user.');
        }
        if (
          String(existing.trailId || '') !== trailId
          || (
            String(existing.sourceUpcomingHikeId || '') !== sourceUpcomingHikeId
            && !canAdoptLegacyTeamSource
          )
          || String(existing.teamHikeSessionId || '') !== teamHikeSessionId
        ) {
          throw new HttpsError(
            'already-exists',
            'This hike start key is already associated with different hike data.'
          );
        }
        if (['completed', 'abandoned'].includes(String(existing.status || ''))) {
          throw new HttpsError('failed-precondition', 'This hike has already ended.');
        }
        if (canAdoptLegacyTeamSource) {
          transaction.set(
            sessionReference,
            {
              sourceUpcomingHikeId,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAtLocal: new Date().toISOString(),
            },
            { merge: true }
          );
          if (upcomingReference && upcomingSnapshot?.exists) {
            transaction.set(
              upcomingReference,
              {
                startedParticipantPhones:
                  admin.firestore.FieldValue.arrayUnion(phoneNumber),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAtLocal: new Date().toISOString(),
              },
              { merge: true }
            );
          }
        }
        return { sessionId, created: false };
      }
      if (terminalSnapshot.exists) {
        throw new HttpsError('failed-precondition', 'This hike has already ended.');
      }
      let canonicalRawDraft = rawDraft;
      if (upcomingReference) {
        canonicalRawDraft = sourceUpcoming.draft
          ? mergeSharedPlanWithCallerSafety(sourceUpcoming.draft, rawDraft)
          : rawDraft;
      }
      let teamParticipants = [];
      if (teamReference) {
        if (!teamSnapshot?.exists) {
          throw new HttpsError('not-found', 'This team hike no longer exists.');
        }
        const team = teamSnapshot.data() || {};
        teamParticipants = validTeamParticipants(team);
        if (
          String(team.phase || '') !== 'active'
          || String(team.trailId || team.draft?.trail?.trailId || '') !== trailId
          || !teamSourceMatchesRequest(team, sourceUpcomingHikeId)
          || !teamParticipants.some(
            (participant) => teamParticipantPhone(participant) === phoneNumber
          )
        ) {
          throw new HttpsError('failed-precondition', 'This team hike is not ready to track.');
        }
        const teamPlan = team.draft?.trail
          ? team.draft
          : canonicalRawDraft;
        canonicalRawDraft = mergeSharedPlanWithCallerSafety(
          teamPlan,
          rawDraft
        );
      }
      const trail = canonicalTrailSnapshot(trailId, trailSnapshot.data() || {});
      const buddies = teamParticipants
        .filter((participant) => teamParticipantPhone(participant) !== phoneNumber)
        .map((participant) => sanitizedPlainValue(participant.buddy || {}));
      const draft = {
        ...sanitizedTeamDraft(canonicalRawDraft, trail, buddies, {
          pastDepartureToleranceMillis: 30 * 24 * 60 * 60 * 1000,
          maximumHikeDurationMillis: 30 * 24 * 60 * 60 * 1000,
        }),
        hikeType: teamHikeSessionId || buddies.length > 0 ? 'team' : 'solo',
      };
      transaction.create(
        sessionReference,
        activeHikeDocumentData({
          sessionId,
          uid,
          phoneNumber,
          draft,
          startedAtMillis: safeStartedAtMillis,
          sourceUpcomingHikeId,
          teamHikeSessionId,
        })
      );
      if (upcomingReference) {
        transaction.set(
          upcomingReference,
          {
            startedParticipantPhones:
              admin.firestore.FieldValue.arrayUnion(phoneNumber),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAtLocal: new Date().toISOString(),
          },
          { merge: true }
        );
      }
      if (teamReference) {
        const team = teamSnapshot.data() || {};
        const sessionIds = team.activeHikeSessionIdsByPhone
          && typeof team.activeHikeSessionIdsByPhone === 'object'
          ? { ...team.activeHikeSessionIdsByPhone }
          : {};
        sessionIds[phoneKeyFor(phoneNumber)] = sessionId;
        transaction.set(
          teamReference,
          {
            activeHikeSessionIdsByPhone: sessionIds,
            ...(String(team.hostPhoneNumber || '') === phoneNumber
              ? { activeHikeSessionId: sessionId }
              : {}),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAtLocal: new Date().toISOString(),
          },
          { merge: true }
        );
      }
      assertWindowRate(transaction, rateReference, rateSnapshot, {
        limit: 12,
        windowMillis: 24 * 60 * 60 * 1000,
        message: 'Too many hike sessions were started today.',
      });
      return { sessionId, created: true };
    });
    return result;
  }
);

exports.ensureActiveHikeSessionInCloud = onCall(
  {},
  async (request) => {
    const { phoneNumber, uid } = authenticatedPhoneFor(
      request,
      'Sign in to restore hike tracking.'
    );
    const requestedSessionId = String(request.data?.sessionId || '').trim();
    const rawDraft = request.data?.draft;
    const trailId = String(rawDraft?.trail?.trailId || '').trim();
    const sourceUpcomingHikeId = String(
      request.data?.sourceUpcomingHikeId || ''
    ).trim();
    const teamHikeSessionId = String(
      request.data?.teamHikeSessionId || ''
    ).trim();
    if (
      !validFirestoreDocumentId(requestedSessionId)
      || !validFirestoreDocumentId(trailId)
      || (sourceUpcomingHikeId
        && !validFirestoreDocumentId(sourceUpcomingHikeId))
      || (teamHikeSessionId && !validFirestoreDocumentId(teamHikeSessionId))
    ) {
      throw new HttpsError('invalid-argument', 'The saved hike is invalid.');
    }
    const isOfflineLocalSession = /^session_[0-9]{13}$/.test(requestedSessionId);
    const recoveryIdentityKey = sourceUpcomingHikeId
      ? `upcoming:${sourceUpcomingHikeId}`
      : teamHikeSessionId
        ? `team:${teamHikeSessionId}`
        : `offline:${requestedSessionId}`;
    const sessionId = isOfflineLocalSession
      ? `hike_${crypto
          .createHash('sha256')
          .update(`${uid}:${recoveryIdentityKey}`)
          .digest('hex')
          .slice(0, 48)}`
      : requestedSessionId;
    const db = admin.firestore();
    const sessionReference = db.collection('hikeSessions').doc(sessionId);
    const terminalReference = db
      .collection('hikeSessionTerminalStates')
      .doc(sessionId);
    const userReference = db.collection('users').doc(uid);
    const trailReference = db.collection('trails').doc(trailId);
    const rateReference = db.collection('hikeSessionRecoveryRateLimits').doc(uid);
    const upcomingReference = sourceUpcomingHikeId
      ? db.collection('upcomingHikes').doc(sourceUpcomingHikeId)
      : null;
    const teamReference = teamHikeSessionId
      ? db.collection('teamHikeSessions').doc(teamHikeSessionId)
      : null;
    const startedAtMillis = dateMillis(request.data?.startedAtLocal);
    if (
      !Number.isFinite(startedAtMillis)
      || startedAtMillis > Date.now() + 5 * 60 * 1000
      || (
        isOfflineLocalSession
        && Math.abs(
          startedAtMillis - Number(requestedSessionId.slice('session_'.length))
        ) > 10 * 60 * 1000
      )
    ) {
      throw new HttpsError('invalid-argument', 'The saved hike start time is invalid.');
    }
    const result = await db.runTransaction(async (transaction) => {
      const snapshots = await Promise.all([
        transaction.get(sessionReference),
        transaction.get(terminalReference),
        transaction.get(userReference),
        transaction.get(trailReference),
        transaction.get(rateReference),
        ...(upcomingReference ? [transaction.get(upcomingReference)] : []),
        ...(teamReference ? [transaction.get(teamReference)] : []),
      ]);
      const existingSnapshot = snapshots[0];
      const terminalSnapshot = snapshots[1];
      const userSnapshot = snapshots[2];
      const trailSnapshot = snapshots[3];
      const rateSnapshot = snapshots[4];
      let snapshotIndex = 5;
      const upcomingSnapshot = upcomingReference
        ? snapshots[snapshotIndex++]
        : null;
      const teamSnapshot = teamReference ? snapshots[snapshotIndex] : null;
      if (!userSnapshot.exists) {
        throw new HttpsError('failed-precondition', 'The saved hike cannot be restored.');
      }
      const user = userSnapshot.data() || {};
      if (user.accountDisabled === true || user.status === 'disabled') {
        throw new HttpsError('permission-denied', 'Your account is unavailable.');
      }
      const existingForSourceValidation = existingSnapshot.data() || {};
      const existingStatusForSourceValidation = String(
        existingForSourceValidation.status || ''
      );
      const needsActiveSourceValidation = Boolean(
        upcomingReference
        && !terminalSnapshot.exists
        && (
          !existingSnapshot.exists
          || existingStatusForSourceValidation === 'active'
        )
      );
      let sourceUpcoming = null;
      if (needsActiveSourceValidation) {
        if (!upcomingSnapshot?.exists) {
          throw new HttpsError(
            'failed-precondition',
            'The scheduled hike for this saved session is unavailable.'
          );
        }
        sourceUpcoming = upcomingSnapshot.data() || {};
        const sourceParticipantPhones = [
          String(sourceUpcoming.creatorPhone || ''),
          ...(Array.isArray(sourceUpcoming.participantPhones)
            ? sourceUpcoming.participantPhones
            : []),
        ]
          .map((phone) => String(phone || '').trim())
          .filter((phone) => /^\+[1-9]\d{7,14}$/.test(phone));
        const uniqueSourceParticipants = [...new Set(sourceParticipantPhones)];
        if (
          String(sourceUpcoming.sessionId || sourceUpcomingHikeId)
            !== sourceUpcomingHikeId
          || String(sourceUpcoming.trailId || '') !== trailId
          || !uniqueSourceParticipants.includes(phoneNumber)
        ) {
          throw new HttpsError(
            'permission-denied',
            'You cannot restore this scheduled hike.'
          );
        }
        const linkedTeamId = String(
          sourceUpcoming.teamHikeSessionId || ''
        ).trim();
        if (uniqueSourceParticipants.length > 1) {
          if (!teamHikeSessionId || linkedTeamId !== teamHikeSessionId) {
            throw new HttpsError(
              'failed-precondition',
              'The scheduled team roster must be launched before recovery.'
            );
          }
          if (!teamSnapshot?.exists) {
            throw new HttpsError(
              'failed-precondition',
              'The scheduled team launch is unavailable.'
            );
          }
          const linkedTeam = teamSnapshot.data() || {};
          const callerIsLinkedParticipant = validTeamParticipants(linkedTeam)
            .some(
              (participant) => teamParticipantPhone(participant) === phoneNumber
            );
          if (
            String(linkedTeam.sourceUpcomingHikeId || '')
              !== sourceUpcomingHikeId
            || String(linkedTeam.trailId || linkedTeam.draft?.trail?.trailId || '')
              !== trailId
            || !callerIsLinkedParticipant
          ) {
            throw new HttpsError(
              'permission-denied',
              'This team launch does not belong to the saved hike participant.'
            );
          }
        } else if (teamHikeSessionId || linkedTeamId) {
          throw new HttpsError(
            'failed-precondition',
            'This solo scheduled hike is not linked to a team launch.'
          );
        }
      }
      if (existingSnapshot.exists) {
        const existing = existingSnapshot.data() || {};
        const canAdoptLegacyTeamSource =
          String(existing.status || '') === 'active'
          && legacyActiveHikeCanAdoptTeamSource(
            existing,
            sourceUpcomingHikeId,
            teamHikeSessionId
          );
        if (
          String(existing.userId || '') !== uid
          || String(existing.userPhoneNumber || '') !== phoneNumber
        ) {
          throw new HttpsError('permission-denied', 'This hike belongs to another user.');
        }
        if (
          String(existing.trailId || '') !== trailId
          || (
            String(existing.sourceUpcomingHikeId || '') !== sourceUpcomingHikeId
            && !canAdoptLegacyTeamSource
          )
          || String(existing.teamHikeSessionId || '') !== teamHikeSessionId
        ) {
          throw new HttpsError(
            'failed-precondition',
            'The saved hike data does not match the cloud session.'
          );
        }
        const status = String(existing.status || '');
        if (!['active', 'completed', 'abandoned'].includes(status)) {
          throw new HttpsError(
            'failed-precondition',
            'The saved hike has an invalid cloud state.'
          );
        }
        if (canAdoptLegacyTeamSource) {
          transaction.set(
            sessionReference,
            {
              sourceUpcomingHikeId,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAtLocal: new Date().toISOString(),
            },
            { merge: true }
          );
          if (upcomingReference && upcomingSnapshot?.exists) {
            transaction.set(
              upcomingReference,
              {
                startedParticipantPhones:
                  admin.firestore.FieldValue.arrayUnion(phoneNumber),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAtLocal: new Date().toISOString(),
              },
              { merge: true }
            );
          }
        }
        if (
          status === 'active'
          && startedAtMillis < Date.now() - 30 * 24 * 60 * 60 * 1000
        ) {
          const nowIso = new Date().toISOString();
          transaction.set(
            sessionReference,
            {
              status: 'abandoned',
              monitoringExpected: false,
              monitoringLifecycleState: 'abandoned',
              abandonedAt: admin.firestore.FieldValue.serverTimestamp(),
              abandonedAtLocal: nowIso,
              abandonmentReason: 'recovery_window_expired',
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAtLocal: nowIso,
            },
            { merge: true }
          );
          transaction.set(
            terminalReference,
            {
              sessionId,
              userId: uid,
              userPhoneNumber: phoneNumber,
              status: 'abandoned',
              recordedAt: admin.firestore.FieldValue.serverTimestamp(),
              recordedAtLocal: nowIso,
            },
            { merge: true }
          );
          return {
            sessionId,
            sourceLocalSessionId:
              isOfflineLocalSession ? requestedSessionId : '',
            ensured: false,
            terminal: true,
            status: 'abandoned',
          };
        }
        if (status === 'active' && teamReference) {
          if (!teamSnapshot?.exists) {
            throw new HttpsError(
              'failed-precondition',
              'The team hike for this active session is unavailable.'
            );
          }
          const team = teamSnapshot.data() || {};
          if (
            String(team.trailId || team.draft?.trail?.trailId || '') !== trailId
            || !teamSourceMatchesRequest(team, sourceUpcomingHikeId)
          ) {
            throw new HttpsError(
              'failed-precondition',
              'The team hike no longer matches this active hike.'
            );
          }
          const callerParticipant = validTeamParticipants(team).find(
            (participant) => teamParticipantPhone(participant) === phoneNumber
          );
          if (!callerParticipant) {
            throw new HttpsError(
              'permission-denied',
              'You are no longer a participant in this team hike.'
            );
          }
          const teamPhase = String(team.phase || '');
          const participantStatus = String(callerParticipant.status || '');
          if (teamPhase === 'completed' || participantStatus === 'ended') {
            const nowIso = new Date().toISOString();
            transaction.set(
              sessionReference,
              {
                status: 'abandoned',
                monitoringExpected: false,
                monitoringLifecycleState: 'abandoned',
                abandonedAt: admin.firestore.FieldValue.serverTimestamp(),
                abandonedAtLocal: nowIso,
                abandonmentReason: 'team_session_no_longer_active',
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAtLocal: nowIso,
              },
              { merge: true }
            );
            transaction.set(
              terminalReference,
              {
                sessionId,
                userId: uid,
                userPhoneNumber: phoneNumber,
                status: 'abandoned',
                recordedAt: admin.firestore.FieldValue.serverTimestamp(),
                recordedAtLocal: nowIso,
              },
              { merge: true }
            );
            return {
              sessionId,
              sourceLocalSessionId:
                isOfflineLocalSession ? requestedSessionId : '',
              ensured: false,
              terminal: true,
              status: 'abandoned',
            };
          }
          if (
            teamPhase !== 'active'
            || !['joined', 'ready', 'active', 'offline'].includes(
              participantStatus
            )
          ) {
            throw new HttpsError(
              'failed-precondition',
              'The team hike is not active for this accepted participant.'
            );
          }
        }
        return {
          sessionId,
          sourceLocalSessionId: isOfflineLocalSession ? requestedSessionId : '',
          ensured: status === 'active',
          terminal: status === 'completed' || status === 'abandoned',
          status,
        };
      }
      if (terminalSnapshot.exists) {
        const terminal = terminalSnapshot.data() || {};
        if (
          (terminal.userId && String(terminal.userId) !== uid)
          || (terminal.userPhoneNumber
            && String(terminal.userPhoneNumber) !== phoneNumber)
        ) {
          throw new HttpsError(
            'permission-denied',
            'This hike belongs to another user.'
          );
        }
        const terminalStatus = String(terminal.status || 'completed');
        if (!['completed', 'abandoned'].includes(terminalStatus)) {
          throw new HttpsError(
            'failed-precondition',
            'The saved hike has an invalid terminal state.'
          );
        }
        return {
          sessionId,
          sourceLocalSessionId: isOfflineLocalSession ? requestedSessionId : '',
          ensured: false,
          terminal: true,
          status: terminalStatus,
        };
      }
      if (!isOfflineLocalSession) {
        throw new HttpsError(
          'failed-precondition',
          'The cloud hike is missing and cannot be recreated from this session id.'
        );
      }
      if (startedAtMillis < Date.now() - 30 * 24 * 60 * 60 * 1000) {
        throw new HttpsError(
          'failed-precondition',
          'The saved hike is too old to restore.'
        );
      }
      if (!trailSnapshot.exists) {
        throw new HttpsError('failed-precondition', 'The saved hike cannot be restored.');
      }
      let buddies = [];
      let canonicalRawDraft = rawDraft;
      if (sourceUpcoming) {
        canonicalRawDraft = sourceUpcoming.draft
          ? mergeSharedPlanWithCallerSafety(sourceUpcoming.draft, rawDraft)
          : rawDraft;
      }
      if (teamReference) {
        const team = teamSnapshot?.data() || {};
        const participants = validTeamParticipants(team);
        const callerParticipant = participants.find(
          (participant) => teamParticipantPhone(participant) === phoneNumber
        );
        if (
          !teamSnapshot?.exists
          || String(team.trailId || team.draft?.trail?.trailId || '') !== trailId
          || !teamSourceMatchesRequest(team, sourceUpcomingHikeId)
        ) {
          throw new HttpsError(
            'failed-precondition',
            'The saved team hike is unavailable.'
          );
        }
        if (!callerParticipant) {
          throw new HttpsError(
            'permission-denied',
            'You are not a participant in this team hike.'
          );
        }
        if (
          String(team.phase || '') === 'completed'
          || String(callerParticipant.status || '') === 'ended'
        ) {
          return {
            sessionId,
            sourceLocalSessionId: requestedSessionId,
            ensured: false,
            terminal: true,
            status: 'completed',
          };
        }
        if (
          String(team.phase || '') !== 'active'
          || String(team.trailId || team.draft?.trail?.trailId || '') !== trailId
          || !['joined', 'ready', 'active', 'offline'].includes(
            String(callerParticipant.status || '')
          )
        ) {
          throw new HttpsError(
            'failed-precondition',
            'The team hike is not active for this accepted participant.'
          );
        }
        buddies = participants
          .filter((participant) => teamParticipantPhone(participant) !== phoneNumber)
          .map((participant) => sanitizedPlainValue(participant.buddy || {}));
        canonicalRawDraft = mergeSharedPlanWithCallerSafety(
          team.draft?.trail ? team.draft : rawDraft,
          rawDraft
        );
      }
      const trail = canonicalTrailSnapshot(trailId, trailSnapshot.data() || {});
      const draft = {
        ...sanitizedTeamDraft(canonicalRawDraft, trail, buddies, {
          pastDepartureToleranceMillis: 30 * 24 * 60 * 60 * 1000,
          maximumHikeDurationMillis: 30 * 24 * 60 * 60 * 1000,
        }),
        hikeType: teamHikeSessionId || buddies.length > 0 ? 'team' : 'solo',
      };
      transaction.create(
        sessionReference,
        {
          ...activeHikeDocumentData({
            sessionId,
            uid,
            phoneNumber,
            draft,
            startedAtMillis,
            sourceUpcomingHikeId,
            teamHikeSessionId,
          }),
          sourceLocalSessionId: requestedSessionId,
        }
      );
      if (upcomingReference && upcomingSnapshot?.exists) {
        transaction.set(
          upcomingReference,
          {
            startedParticipantPhones:
              admin.firestore.FieldValue.arrayUnion(phoneNumber),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAtLocal: new Date().toISOString(),
          },
          { merge: true }
        );
      }
      if (teamReference) {
        const team = teamSnapshot.data() || {};
        const sessionIds = team.activeHikeSessionIdsByPhone
          && typeof team.activeHikeSessionIdsByPhone === 'object'
          ? { ...team.activeHikeSessionIdsByPhone }
          : {};
        sessionIds[phoneKeyFor(phoneNumber)] = sessionId;
        transaction.set(
          teamReference,
          {
            activeHikeSessionIdsByPhone: sessionIds,
            ...(String(team.hostPhoneNumber || '') === phoneNumber
              ? { activeHikeSessionId: sessionId }
              : {}),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAtLocal: new Date().toISOString(),
          },
          { merge: true }
        );
      }
      assertWindowRate(transaction, rateReference, rateSnapshot, {
        limit: 6,
        windowMillis: 24 * 60 * 60 * 1000,
        message: 'Too many saved hikes were restored today.',
      });
      return {
        sessionId,
        sourceLocalSessionId: requestedSessionId,
        ensured: true,
        terminal: false,
        status: 'active',
      };
    });
    return result;
  }
);

function completedHikeSummaryData({
  sessionId,
  trailName,
  startedAtMillis,
  endedAtMillis,
  rawSummary,
}) {
  const summary = rawSummary && typeof rawSummary === 'object'
    && !Array.isArray(rawSummary)
    ? rawSummary
    : {};
  const durationSeconds = Math.max(
    0,
    Math.round((endedAtMillis - startedAtMillis) / 1000)
  );
  const durationMinutes = Math.floor(durationSeconds / 60);
  const distanceKm = boundedNumber(summary.distanceKm, 0, 5000, 0);
  const checkIns = Math.round(boundedNumber(summary.checkIns, 0, 100000, 0));
  const manualPins = Math.round(
    boundedNumber(summary.manualPins, 0, 100000, 0)
  );
  const routePointCount = Math.round(
    boundedNumber(summary.routePointCount, 0, 1000000, 0)
  );
  const batteryStartPercent = Math.round(
    boundedNumber(summary.batteryStartPercent, 0, 100, 0)
  );
  const batteryEndPercent = Math.round(
    boundedNumber(summary.batteryEndPercent, 0, 100, 0)
  );
  const safeTrailName = String(trailName || 'Trail').trim().slice(0, 160)
    || 'Trail';
  const insights = [
    `${routePointCount} valid GPS points were reported for this hike.`,
    `${checkIns} safety check-ins and ${manualPins} pinned locations were recorded.`,
    `Battery changed from ${batteryStartPercent}% to ${batteryEndPercent}%.`,
  ];
  const hours = Math.floor(durationSeconds / 3600);
  const minutes = Math.floor((durationSeconds % 3600) / 60);
  const seconds = durationSeconds % 60;
  const durationText = hours > 0
    ? `${hours}h ${minutes}m ${seconds}s`
    : minutes > 0
      ? `${minutes}m ${seconds}s`
      : `${seconds}s`;
  return {
    sessionId,
    trailName: safeTrailName,
    startedAtLocal: new Date(startedAtMillis).toISOString(),
    endedAtLocal: new Date(endedAtMillis).toISOString(),
    durationMinutes,
    durationSeconds,
    distanceKm,
    checkIns,
    manualPins,
    routePointCount,
    batteryStartPercent,
    batteryEndPercent,
    insights,
    shareText: [
      `Hike summary: ${safeTrailName}`,
      `Distance: ${distanceKm.toFixed(2)} km`,
      `Duration: ${durationText}`,
      `Check-ins: ${checkIns}`,
      `Pinned locations: ${manualPins}`,
      `Battery: ${batteryStartPercent}% to ${batteryEndPercent}%`,
    ].join('\n'),
  };
}

// Completion is server-authoritative so an offline hike can reconnect and
// finish even when its active cloud document was never created. Offline local
// IDs are remapped into a caller-scoped deterministic namespace to prevent
// another account from pre-claiming a predictable document ID.
exports.completeActiveHikeSession = onCall(
  {},
  async (request) => {
    const { phoneNumber, uid } = authenticatedPhoneFor(
      request,
      'Sign in to complete hike tracking.'
    );
    const requestedSessionId = String(request.data?.sessionId || '').trim();
    const rawDraft = request.data?.draft;
    const trailId = String(rawDraft?.trail?.trailId || '').trim();
    const sourceUpcomingHikeId = String(
      request.data?.sourceUpcomingHikeId || ''
    ).trim();
    const teamHikeSessionId = String(
      request.data?.teamHikeSessionId || ''
    ).trim();
    if (
      !validFirestoreDocumentId(requestedSessionId)
      || !validFirestoreDocumentId(trailId)
      || (sourceUpcomingHikeId
        && !validFirestoreDocumentId(sourceUpcomingHikeId))
      || (teamHikeSessionId && !validFirestoreDocumentId(teamHikeSessionId))
    ) {
      throw new HttpsError('invalid-argument', 'The completed hike is invalid.');
    }
    const isOfflineLocalSession = /^session_[0-9]{13}$/.test(requestedSessionId);
    const completionIdentityKey = sourceUpcomingHikeId
      ? `upcoming:${sourceUpcomingHikeId}`
      : teamHikeSessionId
        ? `team:${teamHikeSessionId}`
        : `offline:${requestedSessionId}`;
    const sessionId = isOfflineLocalSession
      ? `hike_${crypto
          .createHash('sha256')
          .update(`${uid}:${completionIdentityKey}`)
          .digest('hex')
          .slice(0, 48)}`
      : requestedSessionId;
    const startedAtMillis = dateMillis(request.data?.startedAtLocal);
    const endedAtMillis = dateMillis(request.data?.endedAtLocal);
    if (
      !Number.isFinite(startedAtMillis)
      || !Number.isFinite(endedAtMillis)
      || startedAtMillis > endedAtMillis
      || (
        isOfflineLocalSession
        && Math.abs(
          startedAtMillis - Number(requestedSessionId.slice('session_'.length))
        ) > 10 * 60 * 1000
      )
    ) {
      throw new HttpsError('invalid-argument', 'The hike completion time is invalid.');
    }

    const db = admin.firestore();
    const sessionReference = db.collection('hikeSessions').doc(sessionId);
    const terminalReference = db
      .collection('hikeSessionTerminalStates')
      .doc(sessionId);
    const userReference = db.collection('users').doc(uid);
    const trailReference = db.collection('trails').doc(trailId);
    const rateReference = db.collection('hikeCompletionRateLimits').doc(uid);
    const teamReference = teamHikeSessionId
      ? db.collection('teamHikeSessions').doc(teamHikeSessionId)
      : null;

    const result = await db.runTransaction(async (transaction) => {
      const snapshots = await Promise.all([
        transaction.get(sessionReference),
        transaction.get(terminalReference),
        transaction.get(userReference),
        transaction.get(trailReference),
        transaction.get(rateReference),
        ...(teamReference ? [transaction.get(teamReference)] : []),
      ]);
      const existingSnapshot = snapshots[0];
      const terminalSnapshot = snapshots[1];
      const userSnapshot = snapshots[2];
      const trailSnapshot = snapshots[3];
      const rateSnapshot = snapshots[4];
      const teamSnapshot = teamReference ? snapshots[5] : null;
      if (!userSnapshot.exists) {
        throw new HttpsError(
          'failed-precondition',
          'The completed hike data is unavailable.'
        );
      }
      const user = userSnapshot.data() || {};
      if (user.accountDisabled === true || user.status === 'disabled') {
        throw new HttpsError('permission-denied', 'Your account is unavailable.');
      }

      const existing = existingSnapshot.data() || {};
      const canAdoptLegacyTeamSource = legacyActiveHikeCanAdoptTeamSource(
        existing,
        sourceUpcomingHikeId,
        teamHikeSessionId
      );
      if (existingSnapshot.exists) {
        if (
          String(existing.userId || '') !== uid
          || String(existing.userPhoneNumber || '') !== phoneNumber
        ) {
          throw new HttpsError('permission-denied', 'This hike belongs to another user.');
        }
        if (
          String(existing.trailId || '') !== trailId
          || (
            String(existing.sourceUpcomingHikeId || '') !== sourceUpcomingHikeId
            && !canAdoptLegacyTeamSource
          )
          || String(existing.teamHikeSessionId || '') !== teamHikeSessionId
        ) {
          throw new HttpsError(
            'failed-precondition',
            'The completed hike does not match its cloud session.'
          );
        }
      } else if (!isOfflineLocalSession && !terminalSnapshot.exists) {
        throw new HttpsError(
          'failed-precondition',
          'The cloud hike is missing and cannot be recreated from this session id.'
        );
      }

      const terminal = terminalSnapshot.data() || {};
      if (
        terminalSnapshot.exists
        && (
          (terminal.userId && String(terminal.userId) !== uid)
          || (terminal.userPhoneNumber
            && String(terminal.userPhoneNumber) !== phoneNumber)
        )
      ) {
        throw new HttpsError('permission-denied', 'This hike belongs to another user.');
      }
      const existingStatus = String(
        terminal.status || existing.status || ''
      );
      if (['completed', 'abandoned'].includes(existingStatus)) {
        return {
          sessionId,
          sourceLocalSessionId: isOfflineLocalSession ? requestedSessionId : '',
          completed: existingStatus === 'completed',
          terminal: true,
          status: existingStatus,
        };
      }
      const transactionNowMillis = Date.now();
      if (
        !trailSnapshot.exists
        || endedAtMillis > transactionNowMillis + 5 * 60 * 1000
        || startedAtMillis < transactionNowMillis - 30 * 24 * 60 * 60 * 1000
        || endedAtMillis - startedAtMillis > 30 * 24 * 60 * 60 * 1000
      ) {
        throw new HttpsError(
          'invalid-argument',
          'The hike completion time or trail is invalid.'
        );
      }
      if (existingSnapshot.exists && existingStatus !== 'active') {
        throw new HttpsError('failed-precondition', 'This hike cannot be completed.');
      }

      let buddies = [];
      let canonicalRawDraft = rawDraft;
      if (teamReference) {
        const team = teamSnapshot?.data() || {};
        const participants = validTeamParticipants(team);
        const callerParticipant = participants.find(
          (participant) => teamParticipantPhone(participant) === phoneNumber
        );
        if (
          !teamSnapshot?.exists
          || String(team.trailId || team.draft?.trail?.trailId || '') !== trailId
          || !teamSourceMatchesRequest(team, sourceUpcomingHikeId)
          || !callerParticipant
          || !['joined', 'ready', 'active', 'offline', 'ended'].includes(
            String(callerParticipant.status || '')
          )
        ) {
          throw new HttpsError(
            'failed-precondition',
            'This completed hike does not belong to an accepted team participant.'
          );
        }
        buddies = participants
          .filter((participant) => teamParticipantPhone(participant) !== phoneNumber)
          .map((participant) => sanitizedPlainValue(participant.buddy || {}));
        canonicalRawDraft = mergeSharedPlanWithCallerSafety(
          team.draft?.trail ? team.draft : rawDraft,
          rawDraft
        );
      }
      const trail = canonicalTrailSnapshot(trailId, trailSnapshot.data() || {});
      const draft = {
        ...sanitizedTeamDraft(canonicalRawDraft, trail, buddies, {
          pastDepartureToleranceMillis: 30 * 24 * 60 * 60 * 1000,
          maximumHikeDurationMillis: 30 * 24 * 60 * 60 * 1000,
        }),
        hikeType: teamHikeSessionId || buddies.length > 0 ? 'team' : 'solo',
      };
      const summaryReport = completedHikeSummaryData({
        sessionId,
        trailName: trail.name,
        startedAtMillis,
        endedAtMillis,
        rawSummary: request.data?.summary,
      });
      const nowIso = new Date().toISOString();
      const completionPatch = {
        status: 'completed',
        monitoringExpected: false,
        monitoringLifecycleState: 'completed',
        endedAt: admin.firestore.FieldValue.serverTimestamp(),
        endedAtLocal: new Date(endedAtMillis).toISOString(),
        distanceKm: summaryReport.distanceKm,
        durationMinutes: summaryReport.durationMinutes,
        checkIns: summaryReport.checkIns,
        manualPins: summaryReport.manualPins,
        routePointCount: summaryReport.routePointCount,
        summaryReport,
        ...(sourceUpcomingHikeId ? { sourceUpcomingHikeId } : {}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: nowIso,
      };
      if (existingSnapshot.exists) {
        transaction.set(
          sessionReference,
          {
            ...completionPatch,
            monitoringFcmToken: admin.firestore.FieldValue.delete(),
          },
          { merge: true }
        );
      } else {
        transaction.create(sessionReference, {
          ...activeHikeDocumentData({
            sessionId,
            uid,
            phoneNumber,
            draft,
            startedAtMillis,
            sourceUpcomingHikeId,
            teamHikeSessionId,
          }),
          sourceLocalSessionId: requestedSessionId,
          ...completionPatch,
        });
      }
      transaction.set(
        terminalReference,
        {
          sessionId,
          userId: uid,
          userPhoneNumber: phoneNumber,
          status: 'completed',
          recordedAt: admin.firestore.FieldValue.serverTimestamp(),
          recordedAtLocal: nowIso,
        },
        { merge: true }
      );
      assertWindowRate(transaction, rateReference, rateSnapshot, {
        limit: 30,
        windowMillis: 24 * 60 * 60 * 1000,
        message: 'Too many hike completions were synchronized today.',
      });
      return {
        sessionId,
        sourceLocalSessionId: isOfflineLocalSession ? requestedSessionId : '',
        completed: true,
        terminal: true,
        status: 'completed',
      };
    });

    if (teamHikeSessionId && result.terminal === true) {
      await updateTeamParticipantForHike(
        {
          teamHikeSessionId,
          userId: uid,
          userPhoneNumber: phoneNumber,
        },
        'ended'
      );
    }
    if (result.status === 'completed') {
      await applyAchievementMetricServer({
        userId: uid,
        metricKey: 'hike_completed',
        eventKey: `hike-completed:${sessionId}`,
      });
    }
    return result;
  }
);

// Ratings are accepted only for a server-confirmed completed hike. The review
// document is keyed by session so retries replace the same vote, and the trail
// aggregate is updated atomically with the review.
exports.submitCompletedHikeRating = onCall({}, async (request) => {
  const { uid } = authenticatedPhoneFor(
    request,
    'Sign in to rate a completed hike.'
  );
  const sessionId = String(request.data?.sessionId || '').trim();
  const trailId = String(request.data?.trailId || '').trim();
  const rating = Number(request.data?.rating);
  const comment = String(request.data?.comment || '').trim();
  if (
    !validFirestoreDocumentId(sessionId)
    || !validFirestoreDocumentId(trailId)
    || !validRating(rating)
    || comment.length > 500
  ) {
    throw new HttpsError(
      'invalid-argument',
      'Choose 1 to 5 stars and keep the optional comment under 500 characters.'
    );
  }

  const db = admin.firestore();
  const sessionReference = db.collection('hikeSessions').doc(sessionId);
  const trailReference = db.collection('trails').doc(trailId);
  const reviewReference = trailReference.collection('ratings').doc(sessionId);

  return db.runTransaction(async (transaction) => {
    const [sessionSnapshot, trailSnapshot, reviewSnapshot] = await Promise.all([
      transaction.get(sessionReference),
      transaction.get(trailReference),
      transaction.get(reviewReference),
    ]);
    const session = sessionSnapshot.data() || {};
    if (
      !sessionSnapshot.exists
      || String(session.userId || '') !== uid
      || String(session.trailId || '') !== trailId
      || String(session.status || '') !== 'completed'
    ) {
      throw new HttpsError(
        'failed-precondition',
        'Only a completed hike can be rated.'
      );
    }
    if (!trailSnapshot.exists) {
      throw new HttpsError('not-found', 'This trail is no longer available.');
    }

    const review = reviewSnapshot.data() || {};
    const aggregate = trailRatingAggregate(
      trailSnapshot.data() || {},
      reviewSnapshot.exists ? review.rating : null,
      rating
    );
    const nowIso = new Date().toISOString();
    transaction.set(
      reviewReference,
      {
        sessionId,
        trailId,
        userId: uid,
        rating,
        comment,
        ...(reviewSnapshot.exists
          ? {}
          : { createdAt: admin.firestore.FieldValue.serverTimestamp() }),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: nowIso,
      },
      { merge: true }
    );
    transaction.update(trailReference, {
      ...aggregate,
      ratingUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ratingUpdatedAtLocal: nowIso,
    });
    return aggregate;
  });
});

// Hike history is served through owner-authorized callables instead of broad
// client queries. This keeps session IDs, route telemetry, and safety records
// private even if another account learns a document ID.
exports.listMyHikeHistory = onCall({}, async (request) => {
  const { uid } = authenticatedPhoneFor(
    request,
    'Sign in to view your hike history.'
  );
  const requestedLimit = Number(request.data?.limit || 100);
  const limit = Math.round(boundedNumber(requestedLimit, 1, 200, 100));
  const snapshot = await admin.firestore()
    .collection('hikeSessions')
    .where('userId', '==', uid)
    .limit(500)
    .get();
  const hikes = snapshot.docs
    .filter((document) => String(document.data()?.status || '') === 'completed')
    .map((document) => hikeHistorySummaryData(document.id, document.data() || {}))
    .sort((left, right) => String(right.endedAtLocal || '')
      .localeCompare(String(left.endedAtLocal || '')))
    .slice(0, limit);
  return { hikes };
});

exports.loadMyHikeHistoryDetail = onCall({}, async (request) => {
  const { phoneNumber, uid } = authenticatedPhoneFor(
    request,
    'Sign in to view this hike.'
  );
  const sessionId = String(request.data?.sessionId || '').trim();
  if (!validFirestoreDocumentId(sessionId)) {
    throw new HttpsError('invalid-argument', 'The hike history entry is invalid.');
  }
  const db = admin.firestore();
  const sessionReference = db.collection('hikeSessions').doc(sessionId);
  const sessionSnapshot = await sessionReference.get();
  const session = sessionSnapshot.data() || {};
  if (
    !sessionSnapshot.exists
    || String(session.userId || '') !== uid
    || String(session.userPhoneNumber || '') !== phoneNumber
  ) {
    throw new HttpsError('not-found', 'This hike is not in your history.');
  }
  if (String(session.status || '') !== 'completed') {
    throw new HttpsError('failed-precondition', 'This hike has not been completed.');
  }
  const trailId = String(session.trailId || '').trim();
  const teamHikeSessionId = String(session.teamHikeSessionId || '').trim();
  const sourceUpcomingHikeId = String(session.sourceUpcomingHikeId || '').trim();
  const chatReferences = [
    ...(validFirestoreDocumentId(teamHikeSessionId)
      ? [db.collection('groupChats').doc(`team_${teamHikeSessionId}`)] : []),
    ...(validFirestoreDocumentId(sourceUpcomingHikeId)
      ? [db.collection('groupChats').doc(`hike_${sourceUpcomingHikeId}`)] : []),
  ];
  const [
    captureSnapshot,
    checkInSnapshot,
    locationSnapshot,
    ratingSnapshot,
    chatSnapshots,
    teamSessionsSnapshot,
    teamSnapshot,
  ] =
    await Promise.all([
      db.collection('hikeRouteCaptures').doc(sessionId).get(),
      db.collection('checkIns').where('sessionId', '==', sessionId).limit(1000).get(),
      db.collection('localLocationPoints')
        .where('sessionId', '==', sessionId).limit(5000).get(),
      trailId
        ? db.collection('trails').doc(trailId).collection('ratings').doc(sessionId).get()
        : Promise.resolve(null),
      chatReferences.length > 0 ? db.getAll(...chatReferences) : Promise.resolve([]),
      validFirestoreDocumentId(teamHikeSessionId)
        ? db.collection('hikeSessions')
          .where('teamHikeSessionId', '==', teamHikeSessionId).limit(50).get()
        : Promise.resolve(null),
      validFirestoreDocumentId(teamHikeSessionId)
        ? db.collection('teamHikeSessions').doc(teamHikeSessionId).get()
        : Promise.resolve(null),
    ]);
  const groupChatId = (chatSnapshots || []).find((snapshot) => {
    if (!snapshot.exists) return false;
    const chat = snapshot.data() || {};
    return chat.isDeleted !== true
      && Array.isArray(chat.participantPhones)
      && chat.participantPhones.includes(phoneNumber);
  })?.id || '';
  const participantNames = new Map();
  const teamParticipants = Array.isArray(teamSnapshot?.data()?.participants)
    ? teamSnapshot.data().participants : [];
  teamParticipants.forEach((participant) => {
    const buddy = participant?.buddy || {};
    const phone = String(participant?.phoneNumber || buddy.phoneNumber || '').trim();
    const name = String(buddy.name || buddy.username || buddy.displayName || '').trim();
    if (phone && name) participantNames.set(phone, name);
  });
  const teamSessionDocs = teamSessionsSnapshot?.docs
    ?.filter((document) => String(document.data()?.status || '') === 'completed') || [];
  const teamCaptureSnapshots = teamSessionDocs.length > 0
    ? await db.getAll(...teamSessionDocs.map((document) =>
      db.collection('hikeRouteCaptures').doc(document.id)))
    : [];
  const memberTracks = teamSessionDocs.map((document, index) => {
    const memberSession = document.data() || {};
    const memberPhone = String(memberSession.userPhoneNumber || '').trim();
    const isCurrentUser = document.id === sessionId || memberPhone === phoneNumber;
    return {
      name: participantNames.get(memberPhone)
        || (isCurrentUser ? 'You' : `Hiker ${index + 1}`),
      isCurrentUser,
      routePoints: teamCaptureSnapshots[index]?.data()?.routePoints || [],
    };
  });
  return {
    detail: hikeHistoryDetailData({
      sessionId,
      session,
      capture: captureSnapshot.data() || {},
      checkIns: checkInSnapshot.docs.map((document) => document.data() || {}),
      locationPoints: locationSnapshot.docs.map((document) => document.data() || {}),
      rating: ratingSnapshot?.data() || null,
      groupChatId,
      memberTracks,
    }),
  };
});

exports.recordActiveHikeCheckIn = onCall(
  {},
  async (request) => {
    const { phoneNumber, uid } = authenticatedPhoneFor(
      request,
      'Sign in to record a hike check-in.'
    );
    const sessionId = String(request.data?.sessionId || '').trim();
    const idempotencyKey = String(request.data?.idempotencyKey || '').trim();
    if (
      !validFirestoreDocumentId(sessionId)
      || !/^[A-Za-z0-9_-]{8,200}$/.test(idempotencyKey)
    ) {
      throw new HttpsError('invalid-argument', 'The hike check-in is invalid.');
    }
    const rawLocation = request.data?.location;
    let location;
    if (rawLocation != null) {
      const latitude = Number(rawLocation.latitude);
      const longitude = Number(rawLocation.longitude);
      const accuracyMeters = Number(rawLocation.accuracyMeters);
      if (
        !Number.isFinite(latitude)
        || latitude < -90
        || latitude > 90
        || !Number.isFinite(longitude)
        || longitude < -180
        || longitude > 180
        || (rawLocation.accuracyMeters != null
          && (!Number.isFinite(accuracyMeters)
            || accuracyMeters < 0
            || accuracyMeters > 500))
      ) {
        throw new HttpsError('invalid-argument', 'The check-in location is invalid.');
      }
      location = {
        latitude,
        longitude,
        ...(rawLocation.accuracyMeters != null ? { accuracyMeters } : {}),
      };
    }
    const batteryLevel = request.data?.batteryLevel == null
      ? null
      : Math.round(boundedNumber(request.data.batteryLevel, 0, 100, 0));
    const db = admin.firestore();
    const hikeReference = db.collection('hikeSessions').doc(sessionId);
    const checkInId = crypto
      .createHash('sha256')
      .update(`${uid}:${sessionId}:${idempotencyKey}`)
      .digest('hex');
    const checkInReference = db.collection('checkIns').doc(`checkin_${checkInId}`);
    const result = await db.runTransaction(async (transaction) => {
      const [hikeSnapshot, checkInSnapshot] = await Promise.all([
        transaction.get(hikeReference),
        transaction.get(checkInReference),
      ]);
      if (checkInSnapshot.exists) {
        return { recorded: true, duplicate: true };
      }
      if (!hikeSnapshot.exists) {
        throw new HttpsError('not-found', 'This active hike no longer exists.');
      }
      const hike = hikeSnapshot.data() || {};
      if (
        String(hike.userId || '') !== uid
        || String(hike.userPhoneNumber || '') !== phoneNumber
        || String(hike.status || '') !== 'active'
      ) {
        throw new HttpsError('failed-precondition', 'This hike is no longer active.');
      }
      const nowMillis = Date.now();
      const previousMillis = dateMillis(
        hike.lastCheckInAt || hike.lastCheckInAtLocal
      );
      const minimumSpacingMillis = Math.min(
        5 * 60 * 1000,
        Math.max(
          60 * 1000,
          Number(hike.safetyCheckInIntervalSeconds || 60) * 1000
        )
      );
      if (
        Number.isFinite(previousMillis)
        && nowMillis - previousMillis < minimumSpacingMillis
      ) {
        throw new HttpsError(
          'resource-exhausted',
          'A safety check-in was already recorded recently.'
        );
      }
      const nowIso = new Date(nowMillis).toISOString();
      transaction.create(checkInReference, {
        checkInId: checkInReference.id,
        sessionId,
        userId: uid,
        userPhoneNumber: phoneNumber,
        trailId: String(hike.trailId || ''),
        status: 'safe',
        ...(batteryLevel != null ? { batteryLevel } : {}),
        ...(location ? { location } : {}),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAtLocal: nowIso,
      });
      transaction.set(
        hikeReference,
        {
          lastCheckInStatus: 'safe',
          lastCheckInAt: admin.firestore.FieldValue.serverTimestamp(),
          lastCheckInAtLocal: nowIso,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAtLocal: nowIso,
        },
        { merge: true }
      );
      return { recorded: true, duplicate: false };
    });
    return result;
  }
);

exports.createTeamHikeSession = onCall({}, async (request) => {
  const { phoneNumber: ownerPhone, uid } = authenticatedPhoneFor(
    request,
    'Sign in to create a team hike.'
  );
  const rawDraft = request.data?.draft;
  const creationKey = String(request.data?.creationKey || '').trim();
  const sourceUpcomingHikeId = String(
    request.data?.sourceUpcomingHikeId || ''
  ).trim();
  if (
    !/^[A-Za-z0-9_-]{8,240}$/.test(creationKey)
    || (sourceUpcomingHikeId
      && !validFirestoreDocumentId(sourceUpcomingHikeId))
  ) {
    throw new HttpsError('invalid-argument', 'The team hike request is invalid.');
  }
  const trailId = String(rawDraft?.trail?.trailId || '').trim();
  if (!validFirestoreDocumentId(trailId)) {
    throw new HttpsError('invalid-argument', 'Select a valid trail first.');
  }
  const requestedPhones = Array.isArray(request.data?.invitedPhoneNumbers)
    ? request.data.invitedPhoneNumbers.map((phone) => String(phone || '').trim())
    : [];
  const maximumInvitees = sourceUpcomingHikeId ? 49 : 10;
  if (
    requestedPhones.length === 0
    || requestedPhones.length > maximumInvitees
    || requestedPhones.some((phone) => !/^\+[1-9]\d{7,14}$/.test(phone))
  ) {
    throw new HttpsError(
      'invalid-argument',
      sourceUpcomingHikeId
        ? 'A scheduled team hike can include up to 50 hikers.'
        : 'Choose between one and ten valid hiking buddies.'
    );
  }
  const invitedPhones = [...new Set(requestedPhones)]
    .filter((phone) => phone !== ownerPhone);
  if (invitedPhones.length === 0 || invitedPhones.length > maximumInvitees) {
    throw new HttpsError(
      'invalid-argument',
      'Choose at least one other hiking buddy.'
    );
  }

  const db = admin.firestore();
  const ownerReference = db.collection('users').doc(uid);
  const trailReference = db.collection('trails').doc(trailId);
  const upcomingReference = sourceUpcomingHikeId
    ? db.collection('upcomingHikes').doc(sourceUpcomingHikeId)
    : null;
  const inviteeReferences = invitedPhones.map((phone) =>
    db.collection('users').doc(userDocumentIdForPhone(phone))
  );
  const creationKeyHash = crypto
    .createHash('sha256')
    .update(
      sourceUpcomingHikeId
        ? `${ownerPhone}:upcoming:${sourceUpcomingHikeId}`
        : `${ownerPhone}:${creationKey}`
    )
    .digest('hex');
  const sessionReference = db
    .collection('teamHikeSessions')
    .doc(`team_${creationKeyHash.slice(0, 40)}`);
  const rateReference = teamRateReference(db, uid, 'create');

  const team = await db.runTransaction(async (transaction) => {
    const snapshots = await Promise.all([
      transaction.get(ownerReference),
      transaction.get(trailReference),
      transaction.get(rateReference),
      transaction.get(sessionReference),
      ...(upcomingReference ? [transaction.get(upcomingReference)] : []),
      ...inviteeReferences.map((reference) => transaction.get(reference)),
    ]);
    const ownerSnapshot = snapshots[0];
    const trailSnapshot = snapshots[1];
    const rateSnapshot = snapshots[2];
    const existingSessionSnapshot = snapshots[3];
    const upcomingSnapshot = upcomingReference ? snapshots[4] : null;
    const inviteeSnapshots = snapshots.slice(upcomingReference ? 5 : 4);
    if (!ownerSnapshot.exists) {
      throw new HttpsError('unauthenticated', 'Your account is unavailable.');
    }
    if (!trailSnapshot.exists) {
      throw new HttpsError('not-found', 'This trail is no longer available.');
    }
    const owner = ownerSnapshot.data() || {};
    if (owner.accountDisabled === true || owner.status === 'disabled') {
      throw new HttpsError('permission-denied', 'Your account is unavailable.');
    }
    let resumeExistingScheduledLaunch = false;
    if (existingSessionSnapshot.exists) {
      const existing = existingSessionSnapshot.data() || {};
      if (
        String(existing.hostPhoneNumber || '') !== ownerPhone
        || String(existing.creationKeyHash || '') !== creationKeyHash
        || String(existing.sourceUpcomingHikeId || '') !== sourceUpcomingHikeId
      ) {
        throw new HttpsError('already-exists', 'This team hike request conflicts.');
      }
      if (upcomingSnapshot?.exists) {
        const linkedTeamId = String(
          upcomingSnapshot.data()?.teamHikeSessionId || ''
        ).trim();
        if (linkedTeamId && linkedTeamId !== sessionReference.id) {
          throw new HttpsError(
            'already-exists',
            'This scheduled hike is linked to a different team launch.'
          );
        }
        resumeExistingScheduledLaunch = scheduledTeamLaunchCanResume(
          existing,
          upcomingSnapshot.data() || {},
          sessionReference.id,
          sourceUpcomingHikeId
        );
      }
      if (!resumeExistingScheduledLaunch) {
        return existing;
      }
    }
    let sourceUpcoming = null;
    if (upcomingReference) {
      if (!upcomingSnapshot?.exists) {
        throw new HttpsError(
          'not-found',
          'This scheduled hike is no longer available.'
        );
      }
      sourceUpcoming = upcomingSnapshot.data() || {};
      if (
        String(sourceUpcoming.creatorPhone || '') !== ownerPhone
        || String(sourceUpcoming.creatorUserId || '') !== uid
        || String(sourceUpcoming.sessionId || sourceUpcomingHikeId)
          !== sourceUpcomingHikeId
      ) {
        throw new HttpsError(
          'permission-denied',
          'Only the scheduled hike host can create its team launch.'
        );
      }
      if (
        sourceUpcoming.isDeleted === true
        || String(sourceUpcoming.trailId || '') !== trailId
      ) {
        throw new HttpsError(
          'failed-precondition',
          'This scheduled hike is no longer available.'
        );
      }
      const departureMillis = dateMillis(
        sourceUpcoming.departureTimeLocal
          || sourceUpcoming.departureTime
          || sourceUpcoming.draft?.departureTime
      );
      if (
        !Number.isFinite(departureMillis)
        || departureMillis + 15 * 60 * 1000 <= Date.now()
      ) {
        throw new HttpsError(
          'failed-precondition',
          'This scheduled hike has already ended.'
        );
      }
      const linkedTeamId = String(
        sourceUpcoming.teamHikeSessionId || ''
      ).trim();
      const trackingStarted = Array.isArray(
        sourceUpcoming.startedParticipantPhones
      ) && sourceUpcoming.startedParticipantPhones.some(
        (phone) => Boolean(String(phone || '').trim())
      );
      const launchWasLinked = Boolean(
        sourceUpcoming.teamLaunchLinkedAt
        || sourceUpcoming.teamLaunchLinkedAtLocal
      );
      const isSameResumableLink = Boolean(
        resumeExistingScheduledLaunch
        && linkedTeamId === sessionReference.id
        && !trackingStarted
      );
      if (
        (linkedTeamId || launchWasLinked || trackingStarted)
        && !isSameResumableLink
      ) {
        throw new HttpsError(
          'failed-precondition',
          'This scheduled hike launch has already been consumed.'
        );
      }
      const sourceParticipantPhones = [
        ownerPhone,
        ...(Array.isArray(sourceUpcoming.participantPhones)
          ? sourceUpcoming.participantPhones
          : []),
      ]
        .map((phone) => String(phone || '').trim())
        .filter((phone) => /^\+[1-9]\d{7,14}$/.test(phone));
      const expectedInvitees = [
        ...new Set(sourceParticipantPhones),
      ].filter((phone) => phone !== ownerPhone);
      if (
        expectedInvitees.length === 0
        || expectedInvitees.length > 49
        || expectedInvitees.length !== invitedPhones.length
        || expectedInvitees.some((phone) => !invitedPhones.includes(phone))
      ) {
        throw new HttpsError(
          'failed-precondition',
          'Refresh this scheduled hike before launching its current participant roster.'
        );
      }
    }
    const buddyPhones = new Set(
      (Array.isArray(owner.buddyPhoneNumbers) ? owner.buddyPhoneNumbers : [])
        .map((phone) => String(phone || '').trim())
    );
    inviteeSnapshots.forEach((snapshot, index) => {
      const invitedUser = snapshot.data() || {};
      if (
        !snapshot.exists
        || invitedUser.accountDisabled === true
        || invitedUser.status === 'disabled'
        || (!sourceUpcomingHikeId && !buddyPhones.has(invitedPhones[index]))
      ) {
        throw new HttpsError(
          'failed-precondition',
          'One of the selected hiking buddies is no longer available.'
        );
      }
    });

    const nowIso = new Date().toISOString();
    const hostBuddy = teamBuddyFromUser(ownerPhone, owner, true, 0);
    const invitedBuddies = inviteeSnapshots.map((snapshot, index) =>
      teamBuddyFromUser(
        invitedPhones[index],
        snapshot.data() || {},
        false,
        index
      )
    );
    const allBuddies = [hostBuddy, ...invitedBuddies];
    const trailData = {
      ...sanitizedPlainValue(trailSnapshot.data() || {}),
      trailId,
      name: String(trailSnapshot.data()?.name || 'Trail').trim().slice(0, 160),
    };
    const requestedSharedPlan = sharedHikePlan(
      rawDraft,
      trailData,
      invitedBuddies
    );
    let draft = requestedSharedPlan;
    if (sourceUpcoming) {
      const canonicalSourcePlan = canonicalSharedPlanFromUpcoming(
        sourceUpcoming,
        trailData,
        invitedBuddies
      );
      const canonicalTrail = canonicalSourcePlan.trail
        && typeof canonicalSourcePlan.trail === 'object'
        && !Array.isArray(canonicalSourcePlan.trail)
        ? canonicalSourcePlan.trail
        : trailData;
      draft = sharedHikePlan(
        canonicalSourcePlan,
        canonicalTrail,
        invitedBuddies
      );
      if (!sharedRouteAndTimingMatch(requestedSharedPlan, draft)) {
        throw new HttpsError(
          'failed-precondition',
          'The team launch plan no longer matches the scheduled route and timing.'
        );
      }
    }
    const participants = allBuddies.map((buddy, index) => ({
      buddy,
      phoneNumber: buddy.phoneNumber,
      status: index === 0 ? 'joined' : 'invited',
      isHost: index === 0,
      isLeader: false,
      progressMeters: 0,
      invitedAtLocal: nowIso,
      ...(index === 0 ? { joinedAtLocal: nowIso } : {}),
      updatedAtLocal: nowIso,
      separationAlertActive: false,
    }));
    const result = {
      teamHikeSessionId: sessionReference.id,
      activeHikeSessionId: '',
      hostPhoneNumber: ownerPhone,
      hostUserId: uid,
      creationKeyHash,
      ...(sourceUpcomingHikeId ? { sourceUpcomingHikeId } : {}),
      sharedHikePlanPrivacyVersion: SHARED_HIKE_PLAN_PRIVACY_VERSION,
      trailId,
      trailName: trailData.name,
      phase: 'inviting',
      countdownSeconds: 5,
      participants,
      participantPhoneNumbers: [ownerPhone, ...invitedPhones],
      draft,
      startPointName: draft.startPointName,
      destinationName: draft.destinationName,
      plannedStartTimeLocal: draft.departureTime,
      expectedArrivalTimeLocal: draft.expectedArrivalTime,
      expectedReturnTimeLocal: draft.expectedReturnTime,
      createdAtLocal: nowIso,
      updatedAtLocal: nowIso,
    };
    const persistedResult = {
      ...result,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (resumeExistingScheduledLaunch) {
      transaction.set(sessionReference, persistedResult);
    } else {
      transaction.create(sessionReference, persistedResult);
    }
    if (upcomingReference) {
      transaction.update(upcomingReference, {
        teamHikeSessionId: sessionReference.id,
        teamLaunchLinkedAt: admin.firestore.FieldValue.serverTimestamp(),
        teamLaunchLinkedAtLocal: nowIso,
        hikeType: 'team',
        draft,
        sharedHikePlanPrivacyVersion: SHARED_HIKE_PLAN_PRIVACY_VERSION,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: nowIso,
      });
    }
    for (const invitedPhone of invitedPhones) {
      queueTeamOutbox(transaction, db, {
        type: 'team_hike_invite',
        recipientPhone: invitedPhone,
        senderPhone: ownerPhone,
        teamId: sessionReference.id,
        nowIso,
      });
    }
    assertTeamActionRate(
      transaction,
      rateReference,
      rateSnapshot,
      'create'
    );
    return result;
  });

  await ensureTeamChatDocument(db, sessionReference.id, team);
  return { teamSession: teamSessionForCallable(sessionReference.id, team) };
});

exports.manageTeamHikeSession = onCall({}, async (request) => {
  const { phoneNumber: callerPhone, uid } = authenticatedPhoneFor(
    request,
    'Sign in to update this team hike.'
  );
  const action = String(request.data?.action || '').trim();
  const allowedActions = new Set(Object.keys(teamHikeActionLimits));
  allowedActions.delete('create');
  if (!allowedActions.has(action)) {
    throw new HttpsError('invalid-argument', 'The team hike action is invalid.');
  }
  const teamId = String(request.data?.teamHikeSessionId || '').trim();
  if (!validFirestoreDocumentId(teamId)) {
    throw new HttpsError('invalid-argument', 'The team hike session is invalid.');
  }
  const needsHike = new Set(['attach', 'location', 'end', 'pathDeviation'])
    .has(action);
  const activeHikeSessionId = needsHike
    ? String(request.data?.activeHikeSessionId || '').trim()
    : '';
  if (needsHike && !validFirestoreDocumentId(activeHikeSessionId)) {
    throw new HttpsError('invalid-argument', 'The active hike is invalid.');
  }

  let safetySettings;
  if (action === 'ready') {
    safetySettings = validTeamSafetySettings(request.data?.safetySettings);
  }
  const targetPhone = action === 'ping'
    ? String(request.data?.participantPhoneNumber || '').trim()
    : '';
  if (action === 'ping' && !/^\+[1-9]\d{7,14}$/.test(targetPhone)) {
    throw new HttpsError('invalid-argument', 'Choose a valid teammate.');
  }
  let submittedLocation;
  let submittedProgress = 0;
  if (action === 'location') {
    const latitude = Number(request.data?.latitude);
    const longitude = Number(request.data?.longitude);
    const accuracyMeters = Number(request.data?.accuracyMeters);
    submittedProgress = Number(request.data?.progressMeters || 0);
    if (
      !Number.isFinite(latitude)
      || latitude < -90
      || latitude > 90
      || !Number.isFinite(longitude)
      || longitude < -180
      || longitude > 180
      || !Number.isFinite(accuracyMeters)
      || accuracyMeters < 0
      || accuracyMeters > 250
      || !Number.isFinite(submittedProgress)
      || submittedProgress < 0
      || submittedProgress > 2000000
    ) {
      throw new HttpsError('invalid-argument', 'The team location is invalid.');
    }
    submittedLocation = { latitude, longitude, accuracyMeters };
  }
  let pathDeviation;
  if (action === 'pathDeviation') {
    const latitude = Number(request.data?.latitude);
    const longitude = Number(request.data?.longitude);
    const distanceMeters = Number(request.data?.distanceMeters);
    if (
      !Number.isFinite(latitude)
      || latitude < -90
      || latitude > 90
      || !Number.isFinite(longitude)
      || longitude < -180
      || longitude > 180
      || !Number.isFinite(distanceMeters)
      || distanceMeters < 0
      || distanceMeters > 100000
    ) {
      throw new HttpsError('invalid-argument', 'The route warning is invalid.');
    }
    pathDeviation = { latitude, longitude, distanceMeters };
  }

  const db = admin.firestore();
  const teamReference = db.collection('teamHikeSessions').doc(teamId);
  const userReference = db.collection('users').doc(uid);
  const rateReference = teamRateReference(db, uid, action);
  const hikeReference = needsHike
    ? db.collection('hikeSessions').doc(activeHikeSessionId)
    : null;

  const result = await db.runTransaction(async (transaction) => {
    const snapshots = await Promise.all([
      transaction.get(teamReference),
      transaction.get(userReference),
      transaction.get(rateReference),
      ...(hikeReference ? [transaction.get(hikeReference)] : []),
    ]);
    const teamSnapshot = snapshots[0];
    const userSnapshot = snapshots[1];
    const rateSnapshot = snapshots[2];
    const hikeSnapshot = hikeReference ? snapshots[3] : null;
    if (!teamSnapshot.exists) {
      throw new HttpsError('not-found', 'Team hike session was not found.');
    }
    if (!userSnapshot.exists) {
      throw new HttpsError('unauthenticated', 'Your account is unavailable.');
    }
    const callerUser = userSnapshot.data() || {};
    if (callerUser.accountDisabled === true || callerUser.status === 'disabled') {
      throw new HttpsError('permission-denied', 'Your account is unavailable.');
    }
    const team = teamSnapshot.data() || {};
    const originalParticipants = validTeamParticipants(team);
    const callerIndex = originalParticipants.findIndex(
      (participant) => teamParticipantPhone(participant) === callerPhone
    );
    if (callerIndex < 0) {
      throw new HttpsError(
        'permission-denied',
        'You are not a participant in this team hike.'
      );
    }
    const hostPhone = String(team.hostPhoneNumber || '').trim();
    const isHost = callerPhone === hostPhone;
    const now = new Date();
    const nowIso = now.toISOString();
    let participants = originalParticipants.map((participant) => ({
      ...participant,
      buddy: participant?.buddy && typeof participant.buddy === 'object'
        ? { ...participant.buddy }
        : { phoneNumber: teamParticipantPhone(participant) },
      phoneNumber: teamParticipantPhone(participant),
    }));
    let phase = String(team.phase || 'inviting');
    let didChange = false;
    let newlyJoinedName = '';
    let everyoneEnded = phase === 'completed';
    const teamPatch = {};
    if (action === 'read') {
      const storedPhones = Array.isArray(team.participantPhoneNumbers)
        ? team.participantPhoneNumbers.map((phone) => String(phone || '').trim())
        : [];
      const normalizedPhones = participants.map(teamParticipantPhone);
      didChange = storedPhones.length !== normalizedPhones.length
        || normalizedPhones.some((phone) => !storedPhones.includes(phone))
        || originalParticipants.some(
          (participant) => String(participant?.phoneNumber || '').trim()
            !== teamParticipantPhone(participant)
        );
    } else if (action === 'accept') {
      const trailId = String(team.trailId || '').trim();
      if (!validFirestoreDocumentId(trailId)) {
        throw new HttpsError(
          'failed-precondition',
          'The trail for this invitation is invalid.'
        );
      }
      const trailSnapshot = await transaction.get(
        db.collection('trails').doc(trailId)
      );
      if (!trailSnapshot.exists) {
        throw new HttpsError(
          'failed-precondition',
          'The trail for this invitation is no longer available.'
        );
      }
    }

    if (needsHike) {
      if (!hikeSnapshot?.exists) {
        throw new HttpsError('not-found', 'The active hike was not found.');
      }
      const hike = hikeSnapshot.data() || {};
      if (
        String(hike.userPhoneNumber || hike.phoneNumber || '') !== callerPhone
        || String(hike.teamHikeSessionId || '') !== teamId
      ) {
        throw new HttpsError(
          'permission-denied',
          'This active hike does not belong to your team account.'
        );
      }
      const hikeStatus = String(hike.status || '');
      if (
        action !== 'end'
        && hikeStatus !== 'active'
      ) {
        throw new HttpsError(
          'failed-precondition',
          'This hike is no longer actively tracking.'
        );
      }
      if (
        action === 'end'
        && hikeStatus !== 'completed'
      ) {
        throw new HttpsError(
          'failed-precondition',
          'Complete the active hike before ending team tracking.'
        );
      }
    }

    if (action === 'accept') {
      if (phase === 'completed' || phase === 'active') {
        throw new HttpsError(
          'failed-precondition',
          'This team hike can no longer accept invitations.'
        );
      }
      const participant = participants[callerIndex];
      if (participant.status === 'ended') {
        throw new HttpsError('failed-precondition', 'This invitation has ended.');
      }
      if (participant.status === 'invited') {
        const canonicalBuddy = teamBuddyFromUser(
          callerPhone,
          callerUser,
          isHost,
          callerIndex
        );
        participants[callerIndex] = {
          ...participant,
          buddy: canonicalBuddy,
          phoneNumber: callerPhone,
          status: 'joined',
          joinedAtLocal: participant.joinedAtLocal || nowIso,
          updatedAtLocal: nowIso,
        };
        newlyJoinedName = String(canonicalBuddy.name || '').trim().slice(0, 80);
        didChange = true;
        queueTeamOutbox(transaction, db, {
          type: 'team_hike_invite_accepted',
          recipientPhone: hostPhone,
          senderPhone: callerPhone,
          teamId,
          nowIso,
        });
      }
      phase = participants.some((participant) => participant.status === 'invited')
        ? 'inviting'
        : 'readyCheck';
    } else if (action === 'ready') {
      if (phase === 'active' || phase === 'completed') {
        throw new HttpsError(
          'failed-precondition',
          'This team hike has already started.'
        );
      }
      const participant = participants[callerIndex];
      if (!['joined', 'ready'].includes(String(participant.status || ''))) {
        throw new HttpsError(
          'failed-precondition',
          'Accept the invitation before marking ready.'
        );
      }
      const canonicalBuddy = teamBuddyFromUser(
        callerPhone,
        callerUser,
        isHost,
        callerIndex
      );
      participants[callerIndex] = {
        ...participant,
        buddy: canonicalBuddy,
        phoneNumber: callerPhone,
        status: 'ready',
        joinedAtLocal: participant.joinedAtLocal || nowIso,
        readyAtLocal: nowIso,
        updatedAtLocal: nowIso,
        safetySettings,
      };
      didChange = true;
      const hasPending = participants.some(
        (item) => item.status === 'invited'
      );
      const everyoneReady = participants.length > 0
        && participants.every((item) => ['ready', 'active'].includes(item.status));
      if (everyoneReady && phase !== 'countdown') {
        phase = 'countdown';
        teamPatch.countdownStartedAtLocal = nowIso;
        queueTeamOutboxForParticipants(
          transaction,
          db,
          participants,
          'team_hike_countdown',
          hostPhone,
          teamId,
          nowIso
        );
      } else if (!everyoneReady) {
        phase = hasPending ? 'inviting' : 'readyCheck';
      }
    } else if (action === 'removePending') {
      if (!isHost) {
        throw new HttpsError(
          'permission-denied',
          'Only the host can remove pending invitations.'
        );
      }
      if (phase === 'active' || phase === 'completed') {
        throw new HttpsError(
          'failed-precondition',
          'The participant list can no longer be changed.'
        );
      }
      const nextParticipants = participants.filter(
        (participant) => participant.status !== 'invited'
      );
      didChange = nextParticipants.length !== participants.length;
      participants = nextParticipants;
      const everyoneReady = participants.length > 0
        && participants.every((item) => ['ready', 'active'].includes(item.status));
      if (everyoneReady) {
        if (phase !== 'countdown') {
          phase = 'countdown';
          teamPatch.countdownStartedAtLocal = nowIso;
          didChange = true;
          queueTeamOutboxForParticipants(
            transaction,
            db,
            participants,
            'team_hike_countdown',
            hostPhone,
            teamId,
            nowIso
          );
        }
      } else {
        didChange = didChange || phase !== 'readyCheck';
        phase = 'readyCheck';
      }
    } else if (action === 'cancel') {
      if (!isHost) {
        throw new HttpsError(
          'permission-denied',
          'Only the host can cancel this team hike.'
        );
      }
      if (phase === 'active') {
        throw new HttpsError(
          'failed-precondition',
          'End the active hike instead of cancelling its launch.'
        );
      }
      if (phase !== 'completed') {
        participants = participants.map((participant) => ({
          ...participant,
          status: 'ended',
          updatedAtLocal: nowIso,
        }));
        phase = 'completed';
        teamPatch.endedAtLocal = nowIso;
        everyoneEnded = true;
        didChange = true;
        queueTeamOutboxForParticipants(
          transaction,
          db,
          participants,
          'team_hike_completed',
          hostPhone,
          teamId,
          nowIso
        );
      }
    } else if (action === 'activate') {
      if (phase !== 'active') {
        const everyoneReady = participants.length > 0
          && participants.every((item) => ['ready', 'active'].includes(item.status));
        const countdownStarted = dateMillis(team.countdownStartedAtLocal);
        const countdownSeconds = Math.round(
          boundedNumber(team.countdownSeconds, 3, 120, 5)
        );
        if (
          phase !== 'countdown'
          || !everyoneReady
          || !Number.isFinite(countdownStarted)
          || Date.now() < countdownStarted + countdownSeconds * 1000
        ) {
          throw new HttpsError(
            'failed-precondition',
            'Wait for the shared start countdown to finish.'
          );
        }
        participants = participants.map((participant) => ({
          ...participant,
          status: ['ready', 'active'].includes(participant.status)
            ? 'active'
            : participant.status,
          updatedAtLocal: nowIso,
        }));
        phase = 'active';
        teamPatch.startedAtLocal = team.startedAtLocal || nowIso;
        didChange = true;
        queueTeamOutboxForParticipants(
          transaction,
          db,
          participants,
          'team_hike_started',
          hostPhone,
          teamId,
          nowIso
        );
      }
    } else if (action === 'attach') {
      if (phase !== 'active') {
        throw new HttpsError(
          'failed-precondition',
          'Wait for the team hike to start before attaching tracking.'
        );
      }
      const sessionIds = team.activeHikeSessionIdsByPhone
        && typeof team.activeHikeSessionIdsByPhone === 'object'
        ? { ...team.activeHikeSessionIdsByPhone }
        : {};
      sessionIds[phoneKeyFor(callerPhone)] = activeHikeSessionId;
      teamPatch.activeHikeSessionIdsByPhone = sessionIds;
      if (isHost) {
        teamPatch.activeHikeSessionId = activeHikeSessionId;
      }
      didChange = true;
    } else if (action === 'location') {
      if (phase !== 'active') {
        throw new HttpsError('failed-precondition', 'The team hike is not active.');
      }
      const participant = participants[callerIndex];
      if (participant.status === 'ended') {
        throw new HttpsError('failed-precondition', 'Your team hike has ended.');
      }
      const previousLocation = participant.latestLocation;
      const previousUpdatedMillis = dateMillis(
        participant.locationUpdatedAtLocal
      );
      if (
        previousLocation
        && Number.isFinite(Number(previousLocation.latitude))
        && Number.isFinite(Number(previousLocation.longitude))
        && Number.isFinite(previousUpdatedMillis)
      ) {
        const elapsedSeconds = Math.max(
          0,
          (Date.now() - previousUpdatedMillis) / 1000
        );
        const jumpMeters = haversineMeters(previousLocation, submittedLocation);
        const previousAccuracy = boundedNumber(
          previousLocation.accuracyMeters,
          0,
          250,
          0
        );
        const plausibleJumpMeters = Math.max(
          300,
          elapsedSeconds * 25 + previousAccuracy + submittedLocation.accuracyMeters
        );
        if (
          elapsedSeconds <= 2 * 60
          && Number.isFinite(jumpMeters)
          && jumpMeters > plausibleJumpMeters
        ) {
          throw new HttpsError(
            'invalid-argument',
            'The new team location is an implausible GPS jump.'
          );
        }
      }
      const plannedDistanceMeters = boundedNumber(
        team?.draft?.trail?.distanceKm,
        0,
        1000,
        0
      ) * 1000;
      const progressLimit = Math.min(
        500000,
        Math.max(5000, plannedDistanceMeters * 3)
      );
      participants[callerIndex] = {
        ...participant,
        status: 'active',
        latestLocation: { ...submittedLocation, capturedAtLocal: nowIso },
        progressMeters: Math.min(submittedProgress, progressLimit),
        locationUpdatedAtLocal: nowIso,
        updatedAtLocal: nowIso,
      };
      const activeFreshParticipants = participants.filter((item) => {
        const updatedMillis = dateMillis(item.locationUpdatedAtLocal);
        return item.status === 'active'
          && item.latestLocation
          && Number.isFinite(updatedMillis)
          && Math.abs(Date.now() - updatedMillis) <= 2 * 60 * 1000;
      });
      let leaderPhone = '';
      let leaderProgress = -1;
      for (const item of activeFreshParticipants) {
        const progress = boundedNumber(item.progressMeters, 0, 2000000, 0);
        if (progress > leaderProgress) {
          leaderPhone = teamParticipantPhone(item);
          leaderProgress = progress;
        }
      }
      const newlyIsolated = [];
      participants = participants.map((participant) => {
        const phone = teamParticipantPhone(participant);
        let next = { ...participant, isLeader: phone === leaderPhone };
        const updatedMillis = dateMillis(next.locationUpdatedAtLocal);
        if (
          next.status !== 'active'
          || !next.latestLocation
          || !Number.isFinite(updatedMillis)
          || Math.abs(Date.now() - updatedMillis) > 2 * 60 * 1000
          || participants.length < 2
        ) {
          return next;
        }
        const distances = activeFreshParticipants
          .filter((other) => teamParticipantPhone(other) !== phone)
          .map((other) => haversineMeters(next.latestLocation, other.latestLocation))
          .filter((distance) => Number.isFinite(distance));
        const nearestDistance = distances.length > 0
          ? Math.min(...distances)
          : Number.POSITIVE_INFINITY;
        const settings = next.safetySettings
          && typeof next.safetySettings === 'object'
          ? next.safetySettings
          : {};
        const threshold = boundedNumber(
          settings.separationDistanceMeters,
          50,
          1000,
          150
        );
        const graceSeconds = boundedNumber(
          settings.isolationGraceSeconds,
          30,
          1800,
          180
        );
        if (!Number.isFinite(nearestDistance) || nearestDistance <= threshold) {
          next = {
            ...next,
            isolatedSinceLocal: null,
            separationAlertActive: false,
          };
          return next;
        }
        const isolatedSinceMillis = dateMillis(next.isolatedSinceLocal);
        const isolatedSinceLocal = Number.isFinite(isolatedSinceMillis)
          ? new Date(isolatedSinceMillis).toISOString()
          : nowIso;
        const shouldAlert = next.separationAlertActive !== true
          && Date.now() - dateMillis(isolatedSinceLocal) >= graceSeconds * 1000;
        next = {
          ...next,
          isolatedSinceLocal,
          separationAlertActive: next.separationAlertActive === true || shouldAlert,
        };
        if (shouldAlert) {
          newlyIsolated.push(next);
        }
        return next;
      });
      if (newlyIsolated.length > 0) {
        for (const recipient of participants) {
          queueTeamOutbox(transaction, db, {
            type: 'team_hike_separation_alert',
            recipientPhone: teamParticipantPhone(recipient),
            senderPhone: hostPhone,
            teamId,
            nowIso,
          });
        }
        teamPatch.lastSeparationAlertPhoneNumber =
          teamParticipantPhone(newlyIsolated[0]);
        teamPatch.lastSeparationAlertPhoneNumbers = newlyIsolated
          .map(teamParticipantPhone)
          .filter(Boolean);
        teamPatch.lastSeparationAlertAtLocal = nowIso;
      }
      didChange = true;
    } else if (action === 'ping') {
      if (phase !== 'active') {
        throw new HttpsError('failed-precondition', 'The team hike is not active.');
      }
      if (
        !['joined', 'ready', 'active', 'offline'].includes(
          String(participants[callerIndex].status || '')
        )
      ) {
        throw new HttpsError(
          'failed-precondition',
          'You cannot ping teammates from this session.'
        );
      }
      if (targetPhone === callerPhone) {
        throw new HttpsError('invalid-argument', 'Choose another teammate.');
      }
      const targetIndex = participants.findIndex(
        (participant) => teamParticipantPhone(participant) === targetPhone
      );
      if (
        targetIndex < 0
        || !['joined', 'ready', 'active', 'offline'].includes(
          String(participants[targetIndex].status || '')
        )
      ) {
        throw new HttpsError('failed-precondition', 'This teammate cannot be pinged.');
      }
      participants[targetIndex] = {
        ...participants[targetIndex],
        lastPingAtLocal: nowIso,
        lastPingSenderPhone: callerPhone,
        updatedAtLocal: nowIso,
      };
      queueTeamOutbox(transaction, db, {
        type: 'team_hike_ping',
        recipientPhone: targetPhone,
        senderPhone: callerPhone,
        teamId,
        nowIso,
      });
      didChange = true;
    } else if (action === 'respond') {
      if (phase !== 'active') {
        throw new HttpsError('failed-precondition', 'The team hike is not active.');
      }
      const participant = participants[callerIndex];
      if (participant.status === 'ended') {
        throw new HttpsError('failed-precondition', 'Your team hike has ended.');
      }
      const lastPingMillis = dateMillis(participant.lastPingAtLocal);
      const lastOkMillis = dateMillis(participant.lastOkAtLocal);
      if (
        !Number.isFinite(lastPingMillis)
        || Date.now() - lastPingMillis > 60 * 60 * 1000
        || (Number.isFinite(lastOkMillis) && lastOkMillis >= lastPingMillis)
      ) {
        throw new HttpsError(
          'failed-precondition',
          'There is no recent team ping to answer.'
        );
      }
      const requestedRecipient = String(participant.lastPingSenderPhone || '');
      const responseRecipient = participants.some(
        (item) => teamParticipantPhone(item) === requestedRecipient
      ) ? requestedRecipient : hostPhone;
      participants[callerIndex] = {
        ...participant,
        status: 'active',
        lastOkAtLocal: nowIso,
        lastPingSenderPhone: '',
        updatedAtLocal: nowIso,
      };
      queueTeamOutbox(transaction, db, {
        type: 'team_hike_ping_ok',
        recipientPhone: responseRecipient,
        senderPhone: callerPhone,
        teamId,
        nowIso,
      });
      didChange = true;
    } else if (action === 'end') {
      if (phase !== 'active' && phase !== 'completed') {
        throw new HttpsError(
          'failed-precondition',
          'The team hike has not started.'
        );
      }
      if (phase !== 'completed') {
        const participant = participants[callerIndex];
        participants[callerIndex] = {
          ...participant,
          status: 'ended',
          updatedAtLocal: nowIso,
        };
        everyoneEnded = participants.length > 0
          && participants.every((item) => item.status === 'ended');
        if (everyoneEnded) {
          phase = 'completed';
          teamPatch.endedAtLocal = nowIso;
          queueTeamOutboxForParticipants(
            transaction,
            db,
            participants,
            'team_hike_completed',
            hostPhone,
            teamId,
            nowIso
          );
        }
        didChange = true;
      }
    } else if (action === 'pathDeviation') {
      if (phase !== 'active') {
        throw new HttpsError('failed-precondition', 'The team hike is not active.');
      }
      const warning = {
        phoneNumber: callerPhone,
        coordinate: {
          latitude: pathDeviation.latitude,
          longitude: pathDeviation.longitude,
        },
        distanceMeters: pathDeviation.distanceMeters,
        detectedAtLocal: nowIso,
      };
      transaction.set(
        hikeReference,
        {
          lastPathDeviation: warning,
          lastPathDeviationAt: admin.firestore.FieldValue.serverTimestamp(),
          lastPathDeviationAtLocal: nowIso,
          pathDeviationAlertCount: admin.firestore.FieldValue.increment(1),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      teamPatch.lastPathDeviation = warning;
      teamPatch.lastPathDeviationAtLocal = nowIso;
      for (const recipient of participants) {
        queueTeamOutbox(transaction, db, {
          type: 'team_hike_path_deviation',
          recipientPhone: teamParticipantPhone(recipient),
          senderPhone: callerPhone,
          teamId,
          nowIso,
        });
      }
      didChange = true;
    }

    const nextTeam = {
      ...team,
      ...teamPatch,
      phase,
      participants,
      participantPhoneNumbers: participants.map(teamParticipantPhone),
      updatedAtLocal: nowIso,
    };
    if (didChange) {
      transaction.set(
        teamReference,
        {
          ...teamPatch,
          phase,
          participants,
          participantPhoneNumbers: participants.map(teamParticipantPhone),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAtLocal: nowIso,
        },
        { merge: true }
      );
    }
    assertTeamActionRate(
      transaction,
      rateReference,
      rateSnapshot,
      action
    );
    return {
      teamSession: teamSessionForCallable(teamId, nextTeam),
      everyoneEnded,
      newlyJoinedName,
    };
  });

  await ensureTeamChatDocument(db, teamId, result.teamSession, {
    newlyJoinedName: result.newlyJoinedName,
  });
  const { newlyJoinedName: _newlyJoinedName, ...publicResult } = result;
  return publicResult;
});

function queueTeamOutboxForParticipants(
  transaction,
  db,
  participants,
  type,
  senderPhone,
  teamId,
  nowIso
) {
  for (const participant of participants) {
    queueTeamOutbox(transaction, db, {
      type,
      recipientPhone: teamParticipantPhone(participant),
      senderPhone,
      teamId,
      nowIso,
    });
  }
}

exports.cleanExpiredTeamHikeInvitations = onSchedule(
  'every 30 minutes',
  async () => {
    const db = admin.firestore();
    const snapshot = await db
      .collection('teamHikeSessions')
      .where('phase', 'in', ['inviting', 'readyCheck', 'countdown'])
      .limit(200)
      .get();
    let cleanedCount = 0;
    for (const document of snapshot.docs) {
      const initial = document.data() || {};
      const expectedReturnMillis = dateMillis(
        initial.expectedReturnTimeLocal || initial?.draft?.expectedReturnTime
      );
      const createdMillis = dateMillis(
        initial.createdAtLocal || initial.createdAt || document.createTime
      );
      const expiresAtMillis = Number.isFinite(expectedReturnMillis)
        ? expectedReturnMillis + 12 * 60 * 60 * 1000
        : createdMillis + 7 * 24 * 60 * 60 * 1000;
      if (!Number.isFinite(expiresAtMillis) || Date.now() <= expiresAtMillis) {
        continue;
      }
      const cleanedTeam = await db.runTransaction(async (transaction) => {
        const freshSnapshot = await transaction.get(document.ref);
        const team = freshSnapshot.data() || {};
        if (
          !freshSnapshot.exists
          || !['inviting', 'readyCheck', 'countdown'].includes(
            String(team.phase || '')
          )
        ) {
          return null;
        }
        const participants = validTeamParticipants(team).map((participant) => ({
          ...participant,
          status: 'ended',
          updatedAtLocal: new Date().toISOString(),
        }));
        const nowIso = new Date().toISOString();
        const patch = {
          phase: 'completed',
          participants,
          participantPhoneNumbers: participants.map(teamParticipantPhone),
          completionReason: 'invitation_expired',
          endedAtLocal: nowIso,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAtLocal: nowIso,
        };
        transaction.set(document.ref, patch, { merge: true });
        queueTeamOutboxForParticipants(
          transaction,
          db,
          participants,
          'team_hike_completed',
          String(team.hostPhoneNumber || ''),
          document.id,
          nowIso
        );
        return { ...team, ...patch };
      });
      if (cleanedTeam) {
        await ensureTeamChatDocument(db, document.id, cleanedTeam);
        cleanedCount += 1;
      }
    }
    logger.log(`Closed ${cleanedCount} expired team hike invitations.`);
  }
);

const MFA_RP_ID = 'hiker-circle.web.app';
const MFA_RP_NAME = 'HikerCircle';
const MFA_ANDROID_DEBUG_ORIGIN =
  'android:apk-key-hash:c2_Q42iNskcmRLKzED1Ke-bFrNfc30IJjrcMJ_Tell4';
const MFA_EXPECTED_ORIGINS = Object.freeze([
  `https://${MFA_RP_ID}`,
  MFA_ANDROID_DEBUG_ORIGIN,
]);
let simpleWebAuthnModulePromise;

function simpleWebAuthn() {
  simpleWebAuthnModulePromise ||= import('@simplewebauthn/server');
  return simpleWebAuthnModulePromise;
}

function mfaSessionReference(token) {
  return admin.firestore().collection('mfaLoginSessions').doc(
    opaqueTokenDigest(token)
  );
}

function validMfaToken(token) {
  return /^[A-Za-z0-9_-]{40,100}$/.test(String(token || ''));
}

function validMfaChallengeId(challengeId) {
  return /^[A-Za-z0-9_-]{20,100}$/.test(String(challengeId || ''));
}

async function readUsableMfaSession(token, { enrollmentOnly = false } = {}) {
  if (!validMfaToken(token)) {
    throw new HttpsError('invalid-argument', 'The verification session is invalid.');
  }
  const reference = mfaSessionReference(token);
  const snapshot = await reference.get();
  const session = snapshot.data() || {};
  if (
    !snapshot.exists
    || session.consumed === true
    || Date.now() > Number(session.expiresAtMillis || 0)
  ) {
    throw new HttpsError(
      'deadline-exceeded',
      'This verification session has expired. Start the WhatsApp verification again.'
    );
  }
  if (enrollmentOnly && session.enrollmentRequired !== true) {
    throw new HttpsError(
      'failed-precondition',
      'This session is not authorized to bind a new security method.'
    );
  }
  const phoneNumber = String(session.phoneNumber || '');
  const userId = String(session.userId || '');
  if (
    !/^\+[1-9]\d{7,14}$/.test(phoneNumber)
    || userId !== userDocumentIdForPhone(phoneNumber)
  ) {
    throw new HttpsError('internal', 'The verification session is corrupted.');
  }
  return { reference, snapshot, session, phoneNumber, userId };
}

async function factorDocumentsForUser(userId) {
  const snapshot = await admin.firestore()
    .collection('users')
    .doc(userId)
    .collection('authFactors')
    .get();
  return snapshot.docs.filter((document) => document.data()?.enabled !== false);
}

async function decrementMfaChallengeAttempt(reference) {
  return admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists || snapshot.data()?.consumed === true) return 0;
    const remaining = Math.max(0, Number(snapshot.data()?.attemptsRemaining || 0) - 1);
    transaction.set(reference, { attemptsRemaining: remaining }, { merge: true });
    return remaining;
  });
}

function factorMethods(documents) {
  return [...new Set(documents.map((document) => String(document.data()?.type || '')))]
    .filter((type) => type === 'totp' || type === 'passkey')
    .sort();
}

async function resolveMfaEnrollmentContext(request) {
  if (request.auth?.uid) {
    const phoneNumber = authenticatedPhoneClaim(request);
    const userId = String(request.auth.uid);
    if (
      !/^\+[1-9]\d{7,14}$/.test(phoneNumber)
      || userId !== userDocumentIdForPhone(phoneNumber)
    ) {
      throw new HttpsError('unauthenticated', 'Sign in again before changing security methods.');
    }
    const currentFactors = await factorDocumentsForUser(userId);
    if (currentFactors.length > 0 && !recentMfaAuthentication(request)) {
      throw new HttpsError(
        'failed-precondition',
        'For your safety, sign in again before adding another security method.'
      );
    }
    return {
      source: 'authenticated',
      contextKey: `authenticated:${userId}`,
      phoneNumber,
      userId,
      sessionReference: null,
    };
  }
  const token = String(request.data?.mfaToken || '').trim();
  const resolved = await readUsableMfaSession(token, { enrollmentOnly: true });
  return {
    source: 'pre_authentication',
    contextKey: `session:${opaqueTokenDigest(token)}`,
    phoneNumber: resolved.phoneNumber,
    userId: resolved.userId,
    sessionReference: resolved.reference,
  };
}

function recentMfaAuthentication(request) {
  const authTimeSeconds = Number(request.auth?.token?.auth_time || 0);
  return request.auth?.token?.mfa === true
    && authTimeSeconds > 0
    && Date.now() / 1000 - authTimeSeconds <= 10 * 60;
}

async function createMfaCustomToken({ userId, phoneNumber, method }) {
  const userSnapshot = await admin.firestore().collection('users').doc(userId).get();
  const user = userSnapshot.data() || {};
  const nowIso = new Date().toISOString();
  await userSnapshot.ref.set({
    firebaseUid: userId,
    lastSignedInAt: admin.firestore.FieldValue.serverTimestamp(),
    lastSignedInAtLocal: nowIso,
    lastMfaAt: admin.firestore.FieldValue.serverTimestamp(),
    lastMfaAtLocal: nowIso,
  }, { merge: true });
  return admin.auth().createCustomToken(userId, {
    phoneNumber,
    isAdmin: isAdminUser(user),
    verificationProvider: `whatsapp_${method}`,
    mfa: true,
    mfaMethod: method,
    mfaAt: nowIso,
  });
}

async function persistEnrolledFactor({
  context,
  factorId,
  factor,
  achievementType,
}) {
  const db = admin.firestore();
  const userReference = db.collection('users').doc(context.userId);
  const factorReference = userReference.collection('authFactors').doc(factorId);
  const existingFactors = await factorDocumentsForUser(context.userId);
  if (existingFactors.some((document) => document.id === factorId)) {
    throw new HttpsError('already-exists', 'This security method is already bound.');
  }
  const nextMethods = [...new Set([...factorMethods(existingFactors), factor.type])].sort();
  const nowIso = new Date().toISOString();
  await db.runTransaction(async (transaction) => {
    const reads = await Promise.all([
      transaction.get(factorReference),
      transaction.get(userReference),
      ...(context.sessionReference
        ? [transaction.get(context.sessionReference)]
        : []),
    ]);
    const currentFactor = reads[0];
    const currentUser = reads[1];
    if (currentFactor.exists && currentFactor.data()?.enabled !== false) {
      throw new HttpsError('already-exists', 'This security method is already bound.');
    }
    if (context.sessionReference) {
      const sessionSnapshot = reads[2];
      const session = sessionSnapshot.data() || {};
      if (
        !sessionSnapshot.exists
        || session.consumed === true
        || Date.now() > Number(session.expiresAtMillis || 0)
      ) {
        throw new HttpsError('deadline-exceeded', 'The verification session has expired.');
      }
      transaction.set(context.sessionReference, {
        consumed: true,
        consumedAt: admin.firestore.FieldValue.serverTimestamp(),
        completedMethod: factor.type,
      }, { merge: true });
    }
    transaction.set(factorReference, {
      ...factor,
      enabled: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAtLocal: nowIso,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAtLocal: nowIso,
    });
    transaction.set(userReference, {
      phoneNumber: context.phoneNumber,
      firebaseUid: context.userId,
      mfaRequired: true,
      mfaFactorCount: existingFactors.length + 1,
      mfaMethods: nextMethods,
      mfaUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      mfaUpdatedAtLocal: nowIso,
      ...(
        context.source === 'pre_authentication' && !currentUser.exists
          ? {
              requiresOnboarding: true,
              profileSetupCompleted: false,
              onboardingVersion: 1,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              createdAtLocal: nowIso,
            }
          : {}
      ),
    }, { merge: true });
  });
  await applyAchievementMetricServer({
    userId: context.userId,
    metricKey: 'security_factor_type_bound',
    eventKey: `security-factor-type:${context.userId}:${achievementType}`,
    condition: 'Bind Authenticator and a passkey',
  });
  if (!context.sessionReference) {
    return { enrolled: true, methods: nextMethods };
  }
  const customToken = await createMfaCustomToken({
    userId: context.userId,
    phoneNumber: context.phoneNumber,
    method: factor.type,
  });
  return {
    enrolled: true,
    methods: nextMethods,
    customToken,
    phoneNumber: context.phoneNumber,
  };
}

exports.getMfaStatus = onCall({}, async (request) => {
  const phoneNumber = authenticatedPhoneClaim(request);
  const userId = String(request.auth?.uid || '');
  if (!phoneNumber || userId !== userDocumentIdForPhone(phoneNumber)) {
    throw new HttpsError('unauthenticated', 'Sign in to view security methods.');
  }
  const factors = await factorDocumentsForUser(userId);
  return {
    required: factors.length > 0,
    factorCount: factors.length,
    methods: factorMethods(factors),
    factors: factors.map((document) => ({
      id: document.id,
      type: String(document.data()?.type || ''),
      label: String(document.data()?.label || ''),
      createdAtLocal: String(document.data()?.createdAtLocal || ''),
    })),
    canRemove: factors.length > 1,
  };
});

exports.beginTotpEnrollment = onCall(
  { secrets: [mfaTotpEncryptionKey] },
  async (request) => {
    const context = await resolveMfaEnrollmentContext(request);
    const factors = await factorDocumentsForUser(context.userId);
    if (factorMethods(factors).includes('totp')) {
      throw new HttpsError('already-exists', 'Authenticator is already bound.');
    }
    const secret = generateTotpSecret();
    const challengeId = randomOpaqueToken(24);
    const expiresAtMillis = Date.now() + MFA_CHALLENGE_TTL_MILLIS;
    await admin.firestore().collection('mfaEnrollmentChallenges').doc(challengeId).set({
      kind: 'totp',
      contextKey: context.contextKey,
      userId: context.userId,
      phoneNumber: context.phoneNumber,
      encryptedSecret: encryptTotpSecret(secret, mfaTotpEncryptionKey.value()),
      attemptsRemaining: 5,
      consumed: false,
      expiresAtMillis,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {
      challengeId,
      secret,
      otpauthUri: otpauthUri({ secret, phoneNumber: context.phoneNumber }),
      expiresAtMillis,
    };
  }
);

exports.finishTotpEnrollment = onCall(
  { secrets: [mfaTotpEncryptionKey] },
  async (request) => {
    const context = await resolveMfaEnrollmentContext(request);
    const challengeId = String(request.data?.challengeId || '').trim();
    const code = String(request.data?.code || '').trim();
    if (!validMfaChallengeId(challengeId) || !/^\d{6}$/.test(code)) {
      throw new HttpsError('invalid-argument', 'Enter the current 6-digit Authenticator code.');
    }
    const reference = admin.firestore().collection('mfaEnrollmentChallenges').doc(challengeId);
    const snapshot = await reference.get();
    const challenge = snapshot.data() || {};
    if (
      !snapshot.exists
      || challenge.kind !== 'totp'
      || challenge.contextKey !== context.contextKey
      || challenge.consumed === true
      || Date.now() > Number(challenge.expiresAtMillis || 0)
    ) {
      throw new HttpsError('deadline-exceeded', 'This Authenticator setup has expired. Start again.');
    }
    const attemptsRemaining = Number(challenge.attemptsRemaining || 0);
    if (attemptsRemaining <= 0) {
      throw new HttpsError('permission-denied', 'Too many incorrect codes. Start setup again.');
    }
    const secret = decryptTotpSecret(
      challenge.encryptedSecret,
      mfaTotpEncryptionKey.value()
    );
    const verification = verifyTotp({ secret, code, window: 1 });
    if (!verification.valid) {
      await reference.set({ attemptsRemaining: attemptsRemaining - 1 }, { merge: true });
      throw new HttpsError('permission-denied', 'The Authenticator code is incorrect.');
    }
    await reference.set({
      consumed: true,
      consumedAt: admin.firestore.FieldValue.serverTimestamp(),
      encryptedSecret: admin.firestore.FieldValue.delete(),
    }, { merge: true });
    return persistEnrolledFactor({
      context,
      factorId: 'totp',
      achievementType: 'totp',
      factor: {
        type: 'totp',
        label: 'Authenticator app',
        encryptedSecret: encryptTotpSecret(secret, mfaTotpEncryptionKey.value()),
        algorithm: 'SHA1',
        digits: 6,
        periodSeconds: 30,
        lastUsedStep: verification.step,
      },
    });
  }
);

exports.beginPasskeyEnrollment = onCall({}, async (request) => {
  const context = await resolveMfaEnrollmentContext(request);
  const factors = await factorDocumentsForUser(context.userId);
  const passkeys = factors.filter((document) => document.data()?.type === 'passkey');
  const { generateRegistrationOptions } = await simpleWebAuthn();
  const options = await generateRegistrationOptions({
    rpName: MFA_RP_NAME,
    rpID: MFA_RP_ID,
    userID: new Uint8Array(Buffer.from(context.userId, 'utf8')),
    userName: context.phoneNumber,
    userDisplayName: `Hiker ${context.phoneNumber.slice(-4)}`,
    attestationType: 'none',
    excludeCredentials: passkeys.map((document) => ({
      id: String(document.data()?.credentialId || ''),
      transports: Array.isArray(document.data()?.transports)
        ? document.data().transports
        : undefined,
    })),
    authenticatorSelection: {
      residentKey: 'required',
      userVerification: 'required',
    },
    supportedAlgorithmIDs: [-7, -257],
    timeout: 60_000,
  });
  const challengeId = randomOpaqueToken(24);
  const expiresAtMillis = Date.now() + MFA_CHALLENGE_TTL_MILLIS;
  await admin.firestore().collection('mfaEnrollmentChallenges').doc(challengeId).set({
    kind: 'passkey',
    contextKey: context.contextKey,
    userId: context.userId,
    phoneNumber: context.phoneNumber,
    webAuthnChallenge: options.challenge,
    attemptsRemaining: 5,
    consumed: false,
    expiresAtMillis,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { challengeId, options, expiresAtMillis };
});

exports.finishPasskeyEnrollment = onCall({}, async (request) => {
  const context = await resolveMfaEnrollmentContext(request);
  const challengeId = String(request.data?.challengeId || '').trim();
  const response = request.data?.response;
  if (!validMfaChallengeId(challengeId) || !response || typeof response !== 'object') {
    throw new HttpsError('invalid-argument', 'The passkey response is invalid.');
  }
  const reference = admin.firestore().collection('mfaEnrollmentChallenges').doc(challengeId);
  const snapshot = await reference.get();
  const challenge = snapshot.data() || {};
  if (
    !snapshot.exists
    || challenge.kind !== 'passkey'
    || challenge.contextKey !== context.contextKey
    || challenge.consumed === true
    || Date.now() > Number(challenge.expiresAtMillis || 0)
  ) {
    throw new HttpsError('deadline-exceeded', 'This passkey setup has expired. Start again.');
  }
  if (Number(challenge.attemptsRemaining || 0) <= 0) {
    throw new HttpsError('permission-denied', 'Too many failed passkey attempts. Start again.');
  }
  let verification;
  try {
    const { verifyRegistrationResponse } = await simpleWebAuthn();
    verification = await verifyRegistrationResponse({
      response,
      expectedChallenge: String(challenge.webAuthnChallenge || ''),
      expectedOrigin: MFA_EXPECTED_ORIGINS,
      expectedRPID: MFA_RP_ID,
      requireUserVerification: true,
    });
  } catch (error) {
    await decrementMfaChallengeAttempt(reference);
    logger.warn('Passkey registration verification failed', {
      userId: context.userId,
      errorName: String(error?.name || ''),
    });
    throw new HttpsError('permission-denied', 'The passkey could not be verified. Try again.');
  }
  if (!verification.verified || !verification.registrationInfo?.credential) {
    throw new HttpsError('permission-denied', 'The passkey could not be verified.');
  }
  const info = verification.registrationInfo;
  const credential = info.credential;
  const factorId = `passkey_${crypto.createHash('sha256')
    .update(String(credential.id))
    .digest('hex')
    .slice(0, 32)}`;
  await reference.set({
    consumed: true,
    consumedAt: admin.firestore.FieldValue.serverTimestamp(),
    webAuthnChallenge: admin.firestore.FieldValue.delete(),
  }, { merge: true });
  return persistEnrolledFactor({
    context,
    factorId,
    achievementType: 'passkey',
    factor: {
      type: 'passkey',
      label: String(request.data?.label || 'Passkey').trim().slice(0, 80) || 'Passkey',
      credentialId: String(credential.id),
      publicKey: Buffer.from(credential.publicKey).toString('base64'),
      counter: Number(credential.counter || 0),
      transports: Array.isArray(credential.transports) ? credential.transports : [],
      credentialDeviceType: String(info.credentialDeviceType || ''),
      credentialBackedUp: info.credentialBackedUp === true,
      aaguid: String(info.aaguid || ''),
    },
  });
});

exports.verifyTotpLogin = onCall(
  { secrets: [mfaTotpEncryptionKey] },
  async (request) => {
    const token = String(request.data?.mfaToken || '').trim();
    const code = String(request.data?.code || '').trim();
    if (!/^\d{6}$/.test(code)) {
      throw new HttpsError('invalid-argument', 'Enter the current 6-digit Authenticator code.');
    }
    const resolved = await readUsableMfaSession(token);
    const factorReference = admin.firestore()
      .collection('users').doc(resolved.userId)
      .collection('authFactors').doc('totp');
    const result = await admin.firestore().runTransaction(async (transaction) => {
      const [sessionSnapshot, factorSnapshot] = await Promise.all([
        transaction.get(resolved.reference),
        transaction.get(factorReference),
      ]);
      const session = sessionSnapshot.data() || {};
      const factor = factorSnapshot.data() || {};
      if (
        !sessionSnapshot.exists
        || session.consumed === true
        || Date.now() > Number(session.expiresAtMillis || 0)
      ) {
        return { error: 'expired' };
      }
      if (!factorSnapshot.exists || factor.enabled === false || factor.type !== 'totp') {
        return { error: 'missing' };
      }
      const attemptsRemaining = Number(session.attemptsRemaining || 0);
      if (attemptsRemaining <= 0) return { error: 'locked' };
      const secret = decryptTotpSecret(
        factor.encryptedSecret,
        mfaTotpEncryptionKey.value()
      );
      const verification = verifyTotp({
        secret,
        code,
        window: 1,
        lastUsedStep: Number(factor.lastUsedStep ?? -1),
      });
      if (!verification.valid) {
        transaction.set(resolved.reference, {
          attemptsRemaining: attemptsRemaining - 1,
        }, { merge: true });
        return { error: 'incorrect' };
      }
      transaction.set(factorReference, {
        lastUsedStep: verification.step,
        lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      transaction.set(resolved.reference, {
        consumed: true,
        consumedAt: admin.firestore.FieldValue.serverTimestamp(),
        completedMethod: 'totp',
      }, { merge: true });
      return { verified: true };
    });
    if (!result.verified) {
      const messages = {
        expired: 'This verification session has expired.',
        missing: 'Authenticator is not bound to this account.',
        locked: 'Too many incorrect attempts. Start login again.',
        incorrect: 'The Authenticator code is incorrect or was already used.',
      };
      throw new HttpsError(
        result.error === 'expired' ? 'deadline-exceeded' : 'permission-denied',
        messages[result.error] || 'Authenticator verification failed.'
      );
    }
    const customToken = await createMfaCustomToken({
      userId: resolved.userId,
      phoneNumber: resolved.phoneNumber,
      method: 'totp',
    });
    return { customToken, phoneNumber: resolved.phoneNumber };
  }
);

exports.beginPasskeyLogin = onCall({}, async (request) => {
  const token = String(request.data?.mfaToken || '').trim();
  const resolved = await readUsableMfaSession(token);
  const factors = (await factorDocumentsForUser(resolved.userId))
    .filter((document) => document.data()?.type === 'passkey');
  if (factors.length === 0) {
    throw new HttpsError('failed-precondition', 'No passkey is bound to this account.');
  }
  const { generateAuthenticationOptions } = await simpleWebAuthn();
  const options = await generateAuthenticationOptions({
    rpID: MFA_RP_ID,
    allowCredentials: factors.map((document) => ({
      id: String(document.data()?.credentialId || ''),
      transports: Array.isArray(document.data()?.transports)
        ? document.data().transports
        : undefined,
    })),
    userVerification: 'required',
    timeout: 60_000,
  });
  const challengeId = randomOpaqueToken(24);
  const expiresAtMillis = Date.now() + MFA_CHALLENGE_TTL_MILLIS;
  await admin.firestore().collection('mfaAuthenticationChallenges').doc(challengeId).set({
    sessionDigest: opaqueTokenDigest(token),
    userId: resolved.userId,
    webAuthnChallenge: options.challenge,
    attemptsRemaining: 5,
    consumed: false,
    expiresAtMillis,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { challengeId, options, expiresAtMillis };
});

exports.finishPasskeyLogin = onCall({}, async (request) => {
  const token = String(request.data?.mfaToken || '').trim();
  const challengeId = String(request.data?.challengeId || '').trim();
  const response = request.data?.response;
  const resolved = await readUsableMfaSession(token);
  if (!validMfaChallengeId(challengeId) || !response || typeof response !== 'object') {
    throw new HttpsError('invalid-argument', 'The passkey response is invalid.');
  }
  const challengeReference = admin.firestore()
    .collection('mfaAuthenticationChallenges').doc(challengeId);
  const challengeSnapshot = await challengeReference.get();
  const challenge = challengeSnapshot.data() || {};
  if (
    !challengeSnapshot.exists
    || challenge.userId !== resolved.userId
    || challenge.sessionDigest !== opaqueTokenDigest(token)
    || challenge.consumed === true
    || Date.now() > Number(challenge.expiresAtMillis || 0)
  ) {
    throw new HttpsError('deadline-exceeded', 'This passkey request has expired. Start again.');
  }
  if (Number(challenge.attemptsRemaining || 0) <= 0) {
    throw new HttpsError('permission-denied', 'Too many failed passkey attempts. Start login again.');
  }
  const credentialId = String(response.id || '');
  const factors = await factorDocumentsForUser(resolved.userId);
  const factorDocument = factors.find(
    (document) => document.data()?.type === 'passkey'
      && String(document.data()?.credentialId || '') === credentialId
  );
  if (!factorDocument) {
    throw new HttpsError('permission-denied', 'This passkey is not bound to the account.');
  }
  const factor = factorDocument.data();
  let verification;
  try {
    const { verifyAuthenticationResponse } = await simpleWebAuthn();
    verification = await verifyAuthenticationResponse({
      response,
      expectedChallenge: String(challenge.webAuthnChallenge || ''),
      expectedOrigin: MFA_EXPECTED_ORIGINS,
      expectedRPID: MFA_RP_ID,
      requireUserVerification: true,
      credential: {
        id: credentialId,
        publicKey: new Uint8Array(Buffer.from(String(factor.publicKey || ''), 'base64')),
        counter: Number(factor.counter || 0),
        transports: Array.isArray(factor.transports) ? factor.transports : [],
      },
    });
  } catch (error) {
    await decrementMfaChallengeAttempt(challengeReference);
    logger.warn('Passkey authentication verification failed', {
      userId: resolved.userId,
      errorName: String(error?.name || ''),
    });
    throw new HttpsError('permission-denied', 'The passkey could not be verified.');
  }
  if (!verification.verified) {
    throw new HttpsError('permission-denied', 'The passkey could not be verified.');
  }
  await admin.firestore().runTransaction(async (transaction) => {
    const [freshChallenge, freshSession, freshFactor] = await Promise.all([
      transaction.get(challengeReference),
      transaction.get(resolved.reference),
      transaction.get(factorDocument.ref),
    ]);
    if (
      freshChallenge.data()?.consumed === true
      || freshSession.data()?.consumed === true
      || Number(freshFactor.data()?.counter || 0) !== Number(factor.counter || 0)
    ) {
      throw new HttpsError('already-exists', 'This passkey response was already used.');
    }
    transaction.set(challengeReference, {
      consumed: true,
      consumedAt: admin.firestore.FieldValue.serverTimestamp(),
      webAuthnChallenge: admin.firestore.FieldValue.delete(),
    }, { merge: true });
    transaction.set(resolved.reference, {
      consumed: true,
      consumedAt: admin.firestore.FieldValue.serverTimestamp(),
      completedMethod: 'passkey',
    }, { merge: true });
    transaction.set(factorDocument.ref, {
      counter: Number(verification.authenticationInfo?.newCounter || 0),
      lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  const customToken = await createMfaCustomToken({
    userId: resolved.userId,
    phoneNumber: resolved.phoneNumber,
    method: 'passkey',
  });
  return { customToken, phoneNumber: resolved.phoneNumber };
});

exports.removeMfaFactor = onCall({}, async (request) => {
  const phoneNumber = authenticatedPhoneClaim(request);
  const userId = String(request.auth?.uid || '');
  const factorId = String(request.data?.factorId || '').trim();
  if (
    userId !== userDocumentIdForPhone(phoneNumber)
    || !validFirestoreDocumentId(factorId)
  ) {
    throw new HttpsError('unauthenticated', 'Sign in again before changing security methods.');
  }
  if (!recentMfaAuthentication(request)) {
    throw new HttpsError(
      'failed-precondition',
      'For your safety, sign in again before removing a security method.'
    );
  }
  const factors = await factorDocumentsForUser(userId);
  const target = factors.find((document) => document.id === factorId);
  if (!target) throw new HttpsError('not-found', 'This security method no longer exists.');
  if (factors.length <= 1) {
    throw new HttpsError(
      'failed-precondition',
      'At least one Authenticator or passkey method must remain bound.'
    );
  }
  const remaining = factors.filter((document) => document.id !== factorId);
  const nowIso = new Date().toISOString();
  const batch = admin.firestore().batch();
  batch.delete(target.ref);
  batch.set(admin.firestore().collection('users').doc(userId), {
    mfaRequired: true,
    mfaFactorCount: remaining.length,
    mfaMethods: factorMethods(remaining),
    mfaUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    mfaUpdatedAtLocal: nowIso,
  }, { merge: true });
  await batch.commit();
  return { removed: true, factorCount: remaining.length, methods: factorMethods(remaining) };
});

exports.cleanExpiredMfaArtifacts = onSchedule(
  { schedule: 'every 24 hours', timeoutSeconds: 120 },
  async () => {
    const db = admin.firestore();
    const now = Date.now();
    const collections = [
      'mfaLoginSessions',
      'mfaEnrollmentChallenges',
      'mfaAuthenticationChallenges',
    ];
    let deleted = 0;
    for (const collectionName of collections) {
      while (true) {
        const snapshot = await db.collection(collectionName)
          .where('expiresAtMillis', '<', now)
          .limit(400)
          .get();
        if (snapshot.empty) break;
        const batch = db.batch();
        for (const document of snapshot.docs) batch.delete(document.ref);
        await batch.commit();
        deleted += snapshot.size;
        if (snapshot.size < 400) break;
      }
    }
    logger.log('Expired MFA artifacts removed.', { deleted });
  }
);

exports.verifyGreenApiLoginCode = onCall(
  { secrets: [greenApiToken] },
  async (request) => {
    const challengeId = String(request.data?.challengeId || '').trim();
    const code = String(request.data?.code || '').trim();
    if (!/^[a-f0-9]{64}$/.test(challengeId) || !/^\d{6}$/.test(code)) {
      throw new HttpsError('invalid-argument', 'Enter the 6-digit code.');
    }

    const challengeReference = admin
      .firestore()
      .collection('greenApiLoginChallenges')
      .doc(challengeId);
    const verification = await admin.firestore().runTransaction(
      async (transaction) => {
        const snapshot = await transaction.get(challengeReference);
        const challenge = snapshot.data();
        if (!snapshot.exists || !challenge) {
          return {
            errorCode: 'not-found',
            errorMessage:
              'This WhatsApp verification request no longer exists.',
          };
        }
        if (
          challenge.consumed === true ||
          Date.now() > Number(challenge.expiresAtMillis || 0)
        ) {
          return {
            errorCode: 'deadline-exceeded',
            errorMessage: 'The WhatsApp verification code has expired.',
          };
        }
        const attemptsRemaining = Number(challenge.attemptsRemaining || 0);
        if (attemptsRemaining <= 0) {
          return {
            errorCode: 'permission-denied',
            errorMessage: 'Too many incorrect attempts. Request a new code.',
          };
        }

        const expected = Buffer.from(String(challenge.codeHash || ''), 'hex');
        const candidateHash = crypto
          .createHmac('sha256', greenApiToken.value())
          .update(`${challengeId}:${code}`)
          .digest();
        const matches =
          expected.length === candidateHash.length &&
          crypto.timingSafeEqual(expected, candidateHash);
        if (!matches) {
          transaction.update(challengeReference, {
            attemptsRemaining: attemptsRemaining - 1,
          });
          return {
            errorCode: 'permission-denied',
            errorMessage: 'The WhatsApp verification code is incorrect.',
          };
        }

        transaction.update(challengeReference, {
          consumed: true,
          verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          codeHash: admin.firestore.FieldValue.delete(),
        });
        return { phoneNumber: String(challenge.phoneNumber || '') };
      }
    );
    if (verification.errorCode) {
      throw new HttpsError(
        verification.errorCode,
        verification.errorMessage
      );
    }
    const phoneNumber = verification.phoneNumber;
    if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
      throw new HttpsError('internal', 'Invalid phone number on record.');
    }
    const userId = userDocumentIdForPhone(phoneNumber);
    const userSnapshot = await admin.firestore().collection('users').doc(userId).get();
    const factors = await factorDocumentsForUser(userId);
    const methods = factorMethods(factors);
    const mfaToken = randomOpaqueToken(32);
    const expiresAtMillis = Date.now() + MFA_SESSION_TTL_MILLIS;
    await mfaSessionReference(mfaToken).set({
      userId,
      phoneNumber,
      whatsappChallengeId: challengeId,
      whatsappVerified: true,
      enrollmentRequired: methods.length === 0,
      methods,
      attemptsRemaining: 8,
      consumed: false,
      expiresAtMillis,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAtLocal: new Date().toISOString(),
    });
    return {
      mfaToken,
      phoneNumber,
      methods,
      enrollmentRequired: methods.length === 0,
      isNewAccount: !userSnapshot.exists,
      expiresAtMillis,
    };
  }
);

exports.registerWithGreenApiAndPassword = onCall(
  { secrets: [greenApiToken] },
  async (request) => {
    throw new HttpsError(
      'failed-precondition',
      'This legacy registration path is disabled. Verify WhatsApp and bind Authenticator or a passkey.'
    );
    /* c8 ignore start -- retained temporarily for rolling-client compatibility */
    const challengeId = String(request.data?.challengeId || '').trim();
    const code = String(request.data?.code || '').trim();
    const password = String(request.data?.password || '');
    if (
      !/^[a-f0-9]{64}$/.test(challengeId) ||
      !/^\d{6}$/.test(code) ||
      password.length < 8
    ) {
      throw new HttpsError(
        'invalid-argument',
        'Enter the 6-digit code and a strong password (min 8 characters).'
      );
    }

    const challengeReference = admin
      .firestore()
      .collection('greenApiLoginChallenges')
      .doc(challengeId);
    const verification = await admin.firestore().runTransaction(
      async (transaction) => {
        const snapshot = await transaction.get(challengeReference);
        const challenge = snapshot.data();
        if (!snapshot.exists || !challenge) {
          return {
            errorCode: 'not-found',
            errorMessage:
              'This WhatsApp verification request no longer exists.',
          };
        }
        if (
          challenge.consumed === true ||
          Date.now() > Number(challenge.expiresAtMillis || 0)
        ) {
          return {
            errorCode: 'deadline-exceeded',
            errorMessage: 'The WhatsApp verification code has expired.',
          };
        }
        const attemptsRemaining = Number(challenge.attemptsRemaining || 0);
        if (attemptsRemaining <= 0) {
          return {
            errorCode: 'permission-denied',
            errorMessage: 'Too many incorrect attempts. Request a new code.',
          };
        }

        const expected = Buffer.from(String(challenge.codeHash || ''), 'hex');
        const candidateHash = crypto
          .createHmac('sha256', greenApiToken.value())
          .update(`${challengeId}:${code}`)
          .digest();
        const matches =
          expected.length === candidateHash.length &&
          crypto.timingSafeEqual(expected, candidateHash);
        if (!matches) {
          transaction.update(challengeReference, {
            attemptsRemaining: attemptsRemaining - 1,
          });
          return {
            errorCode: 'permission-denied',
            errorMessage: 'The WhatsApp verification code is incorrect.',
          };
        }

        transaction.update(challengeReference, {
          consumed: true,
          verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          codeHash: admin.firestore.FieldValue.delete(),
        });
        return { phoneNumber: String(challenge.phoneNumber || '') };
      }
    );
    if (verification.errorCode) {
      throw new HttpsError(
        verification.errorCode,
        verification.errorMessage
      );
    }
    const phoneNumber = verification.phoneNumber;
    if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
      throw new HttpsError('internal', 'Invalid phone number on record.');
    }

    const userId = userDocumentIdForPhone(phoneNumber);
    const passwordHash = await argon2.hash(password, {
      type: argon2.argon2id,
    });

    const now = new Date();
    await admin
      .firestore()
      .collection('users')
      .doc(userId)
      .set(
        {
          phoneNumber,
          passwordHash,
          requiresOnboarding: true,
          profileSetupCompleted: false,
          onboardingVersion: 1,
          firebaseUid: userId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAtLocal: now.toISOString(),
          lastSignedInAt: admin.firestore.FieldValue.serverTimestamp(),
          lastSignedInAtLocal: now.toISOString(),
        },
        { merge: true }
      );

    const customToken = await admin.auth().createCustomToken(userId, {
      phoneNumber,
      verificationProvider: 'green_api_password',
    });
    return { customToken, phoneNumber };
    /* c8 ignore stop */
  }
);

const SAFETY_QUESTIONS = [
  "What is the name of your first pet?",
  "What city were you born in?",
  "What is your mother's maiden name?",
  "What was the name of your first school?",
  "What is your favorite book?",
  "What is the name of your best childhood friend?",
  "What was the make and model of your first car?",
  "What is the name of the street you grew up on?",
  "What is your favorite food?",
  "What year did you graduate high school?",
  "What is the name of your favorite teacher?",
  "What is your dream travel destination?",
  "What is your favorite movie?",
  "What is your favourite colour?",
  "What is your father's middle name?",
];

exports.registerSafetyQuestions = onCall(
  {},
  async (request) => {
    const phoneNumber = authenticatedPhoneClaim(request);
    if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
      throw new HttpsError(
        'unauthenticated',
        'You must be signed in to set safety questions.'
      );
    }

    const q1 = String(request.data?.q1 || '').trim();
    const a1 = String(request.data?.a1 || '');
    const q2 = String(request.data?.q2 || '').trim();
    const a2 = String(request.data?.a2 || '');

    if (!SAFETY_QUESTIONS.includes(q1) || !SAFETY_QUESTIONS.includes(q2) || q1 === q2) {
      throw new HttpsError(
        'invalid-argument',
        'Select two different safety questions from the list.'
      );
    }
    if (a1.length < 2 || a2.length < 2) {
      throw new HttpsError(
        'invalid-argument',
        'Each answer must be at least 2 characters.'
      );
    }

    const userId = userDocumentIdForPhone(phoneNumber);
    const a1Hash = await argon2.hash(a1.toLowerCase(), { type: argon2.argon2id });
    const a2Hash = await argon2.hash(a2.toLowerCase(), { type: argon2.argon2id });

    await admin
      .firestore()
      .collection('users')
      .doc(userId)
      .set(
        {
          safetyQuestions: {
            q1,
            a1Hash,
            q2,
            a2Hash,
          },
        },
        { merge: true }
      );

    return { success: true };
  }
);

exports.sendPasswordResetCode = onCall(
  { secrets: [greenApiInstanceId, greenApiToken] },
  async (request) => {
    const phoneNumber = String(request.data?.phoneNumber || '').trim();
    if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
      throw new HttpsError(
        'invalid-argument',
        'Enter a valid international phone number.'
      );
    }

    const userId = userDocumentIdForPhone(phoneNumber);
    try {
      await admin.auth().getUser(userId);
    } catch (authError) {
      if (authError.code === 'auth/user-not-found') {
        throw new HttpsError(
          'not-found',
          'This phone number is not registered in the system.'
        );
      }
      throw new HttpsError(
        'internal',
        'Unable to verify account. Please try again.'
      );
    }

    const userSnapshot = await admin
      .firestore()
      .collection('users')
      .doc(userId)
      .get();
    const user = userSnapshot.data() || {};
    if (!user.passwordHash) {
      throw new HttpsError(
        'failed-precondition',
        'This account does not have a password set.'
      );
    }
    if (user.accountDisabled === true || user.status === 'disabled') {
      throw new HttpsError(
        'permission-denied',
        'This HikerCircle account has been disabled.'
      );
    }

    let credentials;
    try {
      credentials = await requireGreenApiReady();
    } catch (error) {
      logger.error(
        'GreenAPI password reset readiness failed',
        greenApiReadinessLog(error)
      );
      throw greenApiReadinessHttpsError(error);
    }

    const challengeId = crypto
      .createHash('sha256')
      .update(`reset_${phoneNumber}`)
      .digest('hex');
    const challengeReference = admin
      .firestore()
      .collection('passwordResetChallenges')
      .doc(challengeId);
    const code = crypto.randomInt(0, 1000000).toString().padStart(6, '0');
    const expiresAtMillis = Date.now() + 5 * 60 * 1000;
    const codeHash = crypto
      .createHmac('sha256', greenApiToken.value())
      .update(`${challengeId}:${code}`)
      .digest('hex');
    await reserveOtpChallenge({
      reference: challengeReference,
      phoneNumber,
      codeHash,
      expiresAtMillis,
      cooldownMessage: 'Wait one minute before requesting another code.',
    });
    const digitsOnly = phoneNumber.replace(/\D/g, '');
    let response;
    try {
      response = await fetch(
        greenApiEndpoint('sendMessage', credentials),
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            chatId: `${digitsOnly}@c.us`,
            message:
              `Your HikerCircle password reset code is ${code}. ` +
              'It expires in 5 minutes.',
          }),
          signal: AbortSignal.timeout(12 * 1000),
        }
      );
    } catch (error) {
      logger.error('GreenAPI password reset transport failed', {
        challengeId,
        errorName: String(error?.name || ''),
        errorCode: providerTransportErrorCode(error),
      });
      if (providerFailureWasDefinitelyUnsent(error)) {
        await markOtpDeliveryFailed(challengeReference, error);
      } else {
        await markOtpDeliveryUncertain(challengeReference, error);
      }
      throw new HttpsError(
        'unavailable',
        'WhatsApp verification is temporarily unavailable.'
      );
    }
    if (!response.ok) {
      logger.error('GreenAPI password reset message failed', {
        status: response.status,
        challengeId,
      });
      if (classifySosProviderHttpFailure(response.status).deliveryUncertain) {
        await markOtpDeliveryUncertain(
          challengeReference,
          `HTTP ${response.status}`
        );
      } else {
        await markOtpDeliveryFailed(challengeReference, `HTTP ${response.status}`);
      }
      throw new HttpsError(
        'unavailable',
        'WhatsApp verification is temporarily unavailable.'
      );
    }
    const responseData = await response.json().catch(() => null);
    const providerMessageId = greenApiMessageId(responseData);
    if (!providerMessageId) {
      logger.error(
        'GreenAPI password reset response did not include idMessage',
        { challengeId }
      );
      await markOtpDeliveryUncertain(
        challengeReference,
        'Missing provider message id'
      );
      throw new HttpsError(
        'unavailable',
        'WhatsApp accepted the request but delivery could not be confirmed. Wait one minute before trying again.'
      );
    }
    await challengeReference.set(
      {
        deliveryState: 'sent',
        providerMessageId: providerMessageId.slice(0, 240),
        deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return { challengeId, expiresAtMillis };
  }
);

exports.verifyPasswordResetOtp = onCall(
  { secrets: [greenApiToken] },
  async (request) => {
    const challengeId = String(request.data?.challengeId || '').trim();
    const code = String(request.data?.code || '').trim();
    if (!/^[a-f0-9]{64}$/.test(challengeId) || !/^\d{6}$/.test(code)) {
      throw new HttpsError('invalid-argument', 'Enter the 6-digit code.');
    }

    const challengeReference = admin
      .firestore()
      .collection('passwordResetChallenges')
      .doc(challengeId);
    const verification = await admin.firestore().runTransaction(
      async (transaction) => {
        const snapshot = await transaction.get(challengeReference);
        const challenge = snapshot.data();
        if (!snapshot.exists || !challenge) {
          return {
            errorCode: 'not-found',
            errorMessage: 'This verification request no longer exists.',
          };
        }
        if (
          challenge.consumed === true ||
          Date.now() > Number(challenge.expiresAtMillis || 0)
        ) {
          return {
            errorCode: 'deadline-exceeded',
            errorMessage: 'The verification code has expired.',
          };
        }
        const attemptsRemaining = Number(challenge.attemptsRemaining || 0);
        if (attemptsRemaining <= 0) {
          return {
            errorCode: 'permission-denied',
            errorMessage: 'Too many incorrect attempts. Request a new code.',
          };
        }

        const expected = Buffer.from(String(challenge.codeHash || ''), 'hex');
        const candidateHash = crypto
          .createHmac('sha256', greenApiToken.value())
          .update(`${challengeId}:${code}`)
          .digest();
        const matches =
          expected.length === candidateHash.length &&
          crypto.timingSafeEqual(expected, candidateHash);
        if (!matches) {
          transaction.update(challengeReference, {
            attemptsRemaining: attemptsRemaining - 1,
          });
          return {
            errorCode: 'permission-denied',
            errorMessage: 'The verification code is incorrect.',
          };
        }

        transaction.update(challengeReference, {
          consumed: true,
          verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          codeHash: admin.firestore.FieldValue.delete(),
        });
        return { phoneNumber: String(challenge.phoneNumber || '') };
      }
    );
    if (verification.errorCode) {
      throw new HttpsError(
        verification.errorCode,
        verification.errorMessage
      );
    }
    const phoneNumber = verification.phoneNumber;
    if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
      throw new HttpsError('internal', 'Invalid phone number on record.');
    }

    const userId = userDocumentIdForPhone(phoneNumber);
    const userSnapshot = await admin
      .firestore()
      .collection('users')
      .doc(userId)
      .get();
    const user = userSnapshot.data() || {};
    const questions = user.safetyQuestions;
    const hasQuestions =
      questions && questions.q1 && questions.q2 && questions.a1Hash && questions.a2Hash;

    let questionField = null;
    let questionText = null;
    if (hasQuestions) {
      const fields = ['q1', 'q2'];
      const shuffled = fields.sort(() => Math.random() - 0.5);
      const chosenField = shuffled[0];
      questionField = chosenField;
      questionText = questions[chosenField];
    }

    const resetToken = crypto.randomBytes(32).toString('hex');
    const resetExpiresAt = Date.now() + 10 * 60 * 1000;
    await admin
      .firestore()
      .collection('passwordResetSessions')
      .doc(resetToken)
      .set({
        phoneNumber,
        challengeId,
        verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        used: false,
        expiresAtMillis: resetExpiresAt,
        safetyQuestionField: questionField,
        skipQuestion: !hasQuestions,
        attemptsRemaining: 3,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    return {
      resetToken,
      questionField,
      questionText,
      skipQuestion: !hasQuestions,
      expiresAtMillis: resetExpiresAt,
    };
  }
);

exports.checkSafetyAnswer = onCall(
  {},
  async (request) => {
    const resetToken = String(request.data?.resetToken || '').trim();
    const answer = String(request.data?.answer || '');

    if (resetToken.length < 10) {
      throw new HttpsError('invalid-argument', 'Invalid reset token.');
    }
    if (!answer || answer.length < 2) {
      throw new HttpsError('invalid-argument', 'Please enter your safety answer.');
    }

    const sessionRef = admin
      .firestore()
      .collection('passwordResetSessions')
      .doc(resetToken);
    const result = await admin.firestore().runTransaction(async (transaction) => {
      const snapshot = await transaction.get(sessionRef);
      const session = snapshot.data();
      if (!snapshot.exists || !session) {
        return { errorCode: 'not-found', errorMessage: 'Reset session not found. Start the password reset again.' };
      }
      if (session.used === true) {
        return { errorCode: 'already-exists', errorMessage: 'This reset session has already been used.' };
      }
      if (Date.now() > Number(session.expiresAtMillis || 0)) {
        return { errorCode: 'deadline-exceeded', errorMessage: 'The reset session has expired. Start again.' };
      }
      if (session.skipQuestion === true) {
        return { valid: true };
      }

      const phoneNumber = String(session.phoneNumber || '');
      const userId = userDocumentIdForPhone(phoneNumber);
      const userSnapshot = await transaction.get(
        admin.firestore().collection('users').doc(userId)
      );
      const user = userSnapshot.data() || {};
      const questions = user.safetyQuestions;
      if (!questions) {
        return { errorCode: 'failed-precondition', errorMessage: 'Safety questions not found.' };
      }

      const questionField = String(session.safetyQuestionField || 'q1');
      const answerField = questionField === 'q1' ? 'a1Hash' : 'a2Hash';
      const storedHash = questions[answerField];

      if (!storedHash) {
        return { errorCode: 'failed-precondition', errorMessage: 'Safety question data is corrupted.' };
      }

      let answerValid;
      try {
        answerValid = await argon2.verify(storedHash, answer.toLowerCase());
      } catch (_) {
        return { errorCode: 'internal', errorMessage: 'Answer verification failed. Try again.' };
      }
      if (!answerValid) {
        const remaining = Number(session.attemptsRemaining || 0) - 1;
        if (remaining <= 0) {
          transaction.update(sessionRef, { used: true, attemptsRemaining: 0 });
          return { errorCode: 'permission-denied', errorMessage: 'Too many incorrect answers. Start the password reset again.' };
        }
        transaction.update(sessionRef, { attemptsRemaining: remaining });
        return { errorCode: 'permission-denied', errorMessage: 'The answer is incorrect.' };
      }

      return { valid: true };
    });

    if (result.errorCode) {
      throw new HttpsError(result.errorCode, result.errorMessage);
    }
    return { valid: true };
  }
);

exports.resetPassword = onCall(
  {},
  async (request) => {
    const resetToken = String(request.data?.resetToken || '').trim();
    const answer = String(request.data?.answer || '');
    const newPassword = String(request.data?.newPassword || '');

    if (resetToken.length < 10) {
      throw new HttpsError('invalid-argument', 'Invalid reset token.');
    }
    if (newPassword.length < 8) {
      throw new HttpsError('invalid-argument', 'New password must be at least 8 characters.');
    }

    const sessionRef = admin
      .firestore()
      .collection('passwordResetSessions')
      .doc(resetToken);
    const result = await admin.firestore().runTransaction(async (transaction) => {
      const snapshot = await transaction.get(sessionRef);
      const session = snapshot.data();
      if (!snapshot.exists || !session) {
        return { errorCode: 'not-found', errorMessage: 'Reset session not found. Start the password reset again.' };
      }
      if (session.used === true) {
        return { errorCode: 'already-exists', errorMessage: 'This reset session has already been used.' };
      }
      if (Date.now() > Number(session.expiresAtMillis || 0)) {
        return { errorCode: 'deadline-exceeded', errorMessage: 'The reset session has expired. Start again.' };
      }

      const phoneNumber = String(session.phoneNumber || '');
      const userId = userDocumentIdForPhone(phoneNumber);

      if (!session.skipQuestion) {
        if (!answer || answer.length < 2) {
          return { errorCode: 'invalid-argument', errorMessage: 'Answer must be at least 2 characters.' };
        }
        const userSnapshot = await transaction.get(
          admin.firestore().collection('users').doc(userId)
        );
        const user = userSnapshot.data() || {};
        const questions = user.safetyQuestions;
        if (!questions) {
          return { errorCode: 'failed-precondition', errorMessage: 'Safety questions not found.' };
        }

        const questionField = String(session.safetyQuestionField || 'q1');
        const answerField = questionField === 'q1' ? 'a1Hash' : 'a2Hash';
        const storedHash = questions[answerField];

        if (!storedHash) {
          return { errorCode: 'failed-precondition', errorMessage: 'Safety question data is corrupted.' };
        }

        let answerValid;
        try {
          answerValid = await argon2.verify(storedHash, answer.toLowerCase());
        } catch (_) {
          return { errorCode: 'internal', errorMessage: 'Answer verification failed. Try again.' };
        }
        if (!answerValid) {
          const remaining = Number(session.attemptsRemaining || 0) - 1;
          if (remaining <= 0) {
            transaction.update(sessionRef, { used: true, attemptsRemaining: 0 });
            return { errorCode: 'permission-denied', errorMessage: 'Too many incorrect answers. Start the password reset again.' };
          }
          transaction.update(sessionRef, { attemptsRemaining: remaining });
          return { errorCode: 'permission-denied', errorMessage: 'The answer is incorrect.' };
        }
      }

      const passwordHash = await argon2.hash(newPassword, { type: argon2.argon2id });
      transaction.update(
        admin.firestore().collection('users').doc(userId),
        { passwordHash }
      );
      transaction.update(sessionRef, { used: true });
      return { success: true };
    });

    if (result.errorCode) {
      throw new HttpsError(result.errorCode, result.errorMessage);
    }
    return { success: true };
  }
);

exports.loginWithPassword = onCall({}, async (request) => {
  throw new HttpsError(
    'failed-precondition',
    'Password-only login is disabled. Sign in with WhatsApp and your security method.'
  );
  /* c8 ignore start -- retained temporarily for rolling-client compatibility */
  const phoneNumber = String(request.data?.phoneNumber || '').trim();
  if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
    throw new HttpsError(
      'invalid-argument',
      'Enter a valid international phone number.'
    );
  }
  const password = String(request.data?.password || '');
  if (!password) {
    throw new HttpsError('invalid-argument', 'Enter your password.');
  }

  const userId = userDocumentIdForPhone(phoneNumber);
  const userRef = admin.firestore().collection('users').doc(userId);

  const now = new Date();
  const cooldownResult = await admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(userRef);
    if (!snapshot.exists) {
      return { errorCode: 'not-found', errorMessage: 'No account found with this phone number. Please sign up first.' };
    }
    const user = snapshot.data() || {};

    // Check cooldown
    const cooldownUntil = user.loginCooldownUntil;
    if (cooldownUntil) {
      const cooldownMillis =
        typeof cooldownUntil.toDate === 'function'
          ? cooldownUntil.toDate().getTime()
          : Date.parse(String(cooldownUntil));
      if (Number.isFinite(cooldownMillis) && cooldownMillis > now.getTime()) {
        const expiryDate = new Date(cooldownMillis);
        const day = String(expiryDate.getDate()).padStart(2, '0');
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        const month = months[expiryDate.getMonth()];
        const year = expiryDate.getFullYear();
        const hours = expiryDate.getHours();
        const minutes = String(expiryDate.getMinutes()).padStart(2, '0');
        const ampm = hours >= 12 ? 'PM' : 'AM';
        const hour12 = hours % 12 || 12;
        const formatted = `${day} ${month} ${year}, ${hour12}:${minutes} ${ampm}`;
        return {
          errorCode: 'resource-exhausted',
          errorMessage: `Login is temporary disabled as there are too many attempts at ${formatted}. Please retry later.`,
          cooldownExpiresAtMillis: cooldownMillis,
        };
      }
    }

    // Check account
    if (user.accountDisabled === true || user.status === 'disabled') {
      return { errorCode: 'permission-denied', errorMessage: 'This HikerCircle account has been disabled.' };
    }

    const storedHash = user.passwordHash;
    if (!storedHash) {
      return { errorCode: 'unauthenticated', errorMessage: 'This account does not have a password set. Please sign up via GreenAPI.' };
    }

    let passwordValid;
    try {
      passwordValid = await argon2.verify(storedHash, password);
    } catch (_) {
      return { errorCode: 'internal', errorMessage: 'Password verification failed. Please try again.' };
    }

    if (!passwordValid) {
      const attempts = (user.loginFailedAttempts || 0) + 1;
      const updates = { loginFailedAttempts: attempts };
      if (attempts >= 5) {
        const cooldownUntilDate = new Date(now.getTime() + 30 * 60 * 1000);
        updates.loginCooldownUntil = cooldownUntilDate;
        updates.loginFailedAttempts = 0;
      }
      transaction.update(userRef, updates);
      return { errorCode: 'permission-denied', errorMessage: 'The password is incorrect.' };
    }

    // Success: reset attempts
    transaction.update(userRef, {
      loginFailedAttempts: 0,
      loginCooldownUntil: admin.firestore.FieldValue.delete(),
      lastSignedInAt: admin.firestore.FieldValue.serverTimestamp(),
      lastSignedInAtLocal: now.toISOString(),
    });
    return { success: true, user };
  });

  if (cooldownResult.errorCode) {
    throw new HttpsError(cooldownResult.errorCode, cooldownResult.errorMessage);
  }

  const user = cooldownResult.user;
  const isAdmin = isAdminUser(user);
  const customToken = await admin.auth().createCustomToken(userId, {
    phoneNumber,
    isAdmin,
    verificationProvider: 'password',
  });
  return { customToken, phoneNumber };
  /* c8 ignore stop */
});

exports.linkPasswordToAccount = onCall({}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError(
      'unauthenticated',
      'You must be signed in to set a password.'
    );
  }
  const phoneNumber = authenticatedPhoneClaim(request);
  if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
    throw new HttpsError(
      'unauthenticated',
      'No verified phone number found. Sign in again.'
    );
  }
  const password = String(request.data?.password || '');
  const username = String(request.data?.username || '').trim();
  if (password.length < 8) {
    throw new HttpsError(
      'invalid-argument',
      'Password must be at least 8 characters.'
    );
  }
  if (!username || username.length < 3 || username.length > 24) {
    throw new HttpsError(
      'invalid-argument',
      'Username must be between 3 and 24 characters.'
    );
  }

  const userId = userDocumentIdForPhone(phoneNumber);
  const passwordHash = await argon2.hash(password, {
    type: argon2.argon2id,
  });

  const now = new Date();
  await admin
    .firestore()
    .collection('users')
    .doc(userId)
    .set(
      {
        phoneNumber,
        passwordHash,
        username,
        requiresOnboarding: true,
        profileSetupCompleted: false,
        onboardingVersion: 1,
        firebaseUid: userId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAtLocal: now.toISOString(),
        lastSignedInAt: admin.firestore.FieldValue.serverTimestamp(),
        lastSignedInAtLocal: now.toISOString(),
      },
      { merge: true }
    );

  const customToken = await admin.auth().createCustomToken(userId, {
    phoneNumber,
    username,
    verificationProvider: 'green_api_password',
  });
  return { customToken, phoneNumber };
});

exports.authenticateAppSession = onCall({}, async (request) => {
  throw new HttpsError(
    'failed-precondition',
    'Saved-device recovery requires a fresh WhatsApp and second-factor sign-in.'
  );
  /* c8 ignore start -- retained temporarily for rolling-client compatibility */
  const phoneNumber = String(request.data?.phoneNumber || '').trim();
  const appInstanceId = String(request.data?.appInstanceId || '').trim();
  if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber) || appInstanceId.length < 20) {
    throw new HttpsError(
      'invalid-argument',
      'The saved HikerCircle credentials are invalid.'
    );
  }

  const userId = userDocumentIdForPhone(phoneNumber);
  // This callable is the recovery path when Firebase Auth has lost its local
  // token, so requiring request.auth here makes recovery impossible. App Check
  // authenticates the genuine mobile app and the cryptographically-random,
  // device-bound appInstanceId below authenticates the saved device session.
  // If Firebase Auth is already present, never allow a different signed-in
  // account to use another device's bound credential.
  if (
    request.auth
    && (
      request.auth.uid !== userId
      || authenticatedPhoneClaim(request) !== phoneNumber
    )
  ) {
    throw new HttpsError(
      'unauthenticated',
      'The signed-in Firebase account does not match the saved HikerCircle login.'
    );
  }
  const userDocument = await admin
    .firestore()
    .collection('users')
    .doc(userId)
    .get();
  if (!userDocument.exists) {
    throw new HttpsError(
      'unauthenticated',
      'This HikerCircle account no longer exists.'
    );
  }

  const user = userDocument.data() || {};
  const boundAppInstanceId = String(user.boundAppInstanceId || '');
  if (!boundAppInstanceId || boundAppInstanceId !== appInstanceId) {
    throw new HttpsError(
      'permission-denied',
      'This account is bound to another device. Sign in again.'
    );
  }
  if (user.accountDisabled === true || user.status === 'disabled') {
    throw new HttpsError(
      'permission-denied',
      'This HikerCircle account has been disabled.'
    );
  }

  const isAdmin = isAdminUser(user);
  const customToken = await admin.auth().createCustomToken(userId, {
    phoneNumber,
    isAdmin,
    appInstanceId,
  });
  await userDocument.ref.set(
    {
      firebaseUid: userId,
      lastFirebaseAuthenticatedAt:
        admin.firestore.FieldValue.serverTimestamp(),
      lastFirebaseAuthenticatedAtLocal: new Date().toISOString(),
    },
    { merge: true }
  );
  return { customToken, userId };
  /* c8 ignore stop */
});

// ─── Weather ────────────────────────────────────────────────────

const WMO_MAP = {
  0: 'Clear sky',
  1: 'Mainly clear',
  2: 'Partly cloudy',
  3: 'Overcast',
  45: 'Foggy',
  48: 'Depositing rime fog',
  51: 'Light drizzle',
  53: 'Moderate drizzle',
  55: 'Dense drizzle',
  56: 'Light freezing drizzle',
  57: 'Dense freezing drizzle',
  61: 'Slight rain',
  63: 'Moderate rain',
  65: 'Heavy rain',
  66: 'Light freezing rain',
  67: 'Heavy freezing rain',
  71: 'Slight snow',
  73: 'Moderate snow',
  75: 'Heavy snow',
  77: 'Snow grains',
  80: 'Slight rain showers',
  81: 'Moderate rain showers',
  82: 'Violent rain showers',
  85: 'Slight snow showers',
  86: 'Heavy snow showers',
  95: 'Thunderstorm',
  96: 'Thunderstorm with slight hail',
  99: 'Thunderstorm with heavy hail',
};

function wmoSummary(code) {
  return WMO_MAP[code] || 'Unknown';
}

exports.fetchWeatherForAllTrails = onSchedule(
  { schedule: 'every 60 minutes', timeoutSeconds: 540 },
  async (event) => {
    const db = admin.firestore();
    const trailsSnapshot = await db.collection('trails').get();

    if (trailsSnapshot.empty) {
      logger.log('No trails found.');
      return;
    }

    let batch = db.batch();
    let pendingBatchWrites = 0;
    let updatedCount = 0;

    for (const doc of trailsSnapshot.docs) {
      const data = doc.data();
      const latitude = data.latitude;
      const longitude = data.longitude;

      if (
        !Number.isFinite(latitude)
        || latitude < -90
        || latitude > 90
        || !Number.isFinite(longitude)
        || longitude < -180
        || longitude > 180
      ) {
        continue;
      }

      try {
        const url = new URL('https://api.open-meteo.com/v1/forecast');
        url.searchParams.set('latitude', latitude.toFixed(4));
        url.searchParams.set('longitude', longitude.toFixed(4));
        url.searchParams.set(
          'current',
          'temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,uv_index'
        );
        url.searchParams.set(
          'daily',
          'temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code'
        );
        url.searchParams.set(
          'hourly',
          'temperature_2m,precipitation_probability,weather_code'
        );
        url.searchParams.set('timezone', 'auto');
        url.searchParams.set('forecast_hours', '12');

        const response = await fetch(url.toString(), {
          signal: AbortSignal.timeout(12 * 1000),
        });
        if (!response.ok) {
          logger.warn(
            `OpenMeteo ${response.status} for trail ${doc.id}`
          );
          continue;
        }

        const body = await response.json().catch(() => null);
        if (!body || typeof body !== 'object' || Array.isArray(body)) {
          logger.warn(`OpenMeteo returned invalid data for trail ${doc.id}`);
          continue;
        }
        const weather = buildWeatherFromApi(body);

        batch.update(doc.ref, { weather });
        pendingBatchWrites++;
        updatedCount++;
        if (pendingBatchWrites >= 400) {
          await batch.commit();
          batch = db.batch();
          pendingBatchWrites = 0;
        }
      } catch (error) {
        logger.error(`Failed to fetch weather for trail ${doc.id}:`, error);
      }
    }

    if (pendingBatchWrites > 0) {
      await batch.commit();
    }

    logger.log(`Updated weather for ${updatedCount} trails.`);
  }
);

function buildWeatherFromApi(body) {
  const current = body.current || {};
  const daily = body.daily || {};
  const hourly = body.hourly || {};

  const currentTemp = current.temperature_2m;
  const currentCode = current.weather_code || 0;
  const tempMax = Array.isArray(daily.temperature_2m_max)
    ? daily.temperature_2m_max[0]
    : currentTemp;
  const tempMin = Array.isArray(daily.temperature_2m_min)
    ? daily.temperature_2m_min[0]
    : currentTemp;
  const precipProb = Array.isArray(daily.precipitation_probability_max)
    ? daily.precipitation_probability_max[0]
    : 0;
  const dailyCodes = Array.isArray(daily.weather_code)
    ? daily.weather_code[0]
    : currentCode;

  const maxTemp = typeof tempMax === 'number' ? tempMax : 0;
  const minTemp = typeof tempMin === 'number' ? tempMin : 0;
  const dailyCode = typeof dailyCodes === 'number' ? dailyCodes : 0;
  const rainProb =
    typeof precipProb === 'number'
      ? Math.max(0, Math.min(100, Math.round(precipProb)))
      : 0;

  const now = new Date();
  const hourlyTimes = hourly.time || [];
  const hourlyTemps = hourly.temperature_2m || [];
  const hourlyCodes = hourly.weather_code || [];
  const hourlyPrecipProbs = hourly.precipitation_probability || [];
  const hourlyForecast = [];
  let started = false;

  for (let i = 0; i < hourlyTimes.length && hourlyForecast.length < 24; i++) {
    const timeStr = hourlyTimes[i];
    const temp = hourlyTemps[i];
    const code = hourlyCodes[i];

    if (typeof timeStr !== 'string' || typeof temp !== 'number' || typeof code !== 'number') {
      continue;
    }

    const time = new Date(timeStr);
    if (isNaN(time.getTime())) continue;

    if (!started) {
      if (time <= now) continue;
      started = true;
    }

    const precip =
      Array.isArray(hourlyPrecipProbs) && i < hourlyPrecipProbs.length
        ? hourlyPrecipProbs[i]
        : 0;

    hourlyForecast.push({
      timeLocal: time.toISOString(),
      temperature: temp,
      precipitationProbability:
        typeof precip === 'number'
          ? Math.max(0, Math.min(100, Math.round(precip)))
          : 0,
      weatherCode: code,
    });
  }

  return {
    summary: wmoSummary(dailyCode),
    temperatureRange: `${Math.round(minTemp)} °C - ${Math.round(maxTemp)} °C`,
    rainProbability: rainProb,
    cachedAtLocal: new Date().toISOString(),
    humidity:
      typeof current.relative_humidity_2m === 'number'
        ? current.relative_humidity_2m
        : null,
    windSpeed:
      typeof current.wind_speed_10m === 'number'
        ? current.wind_speed_10m
        : null,
    uvIndex:
      typeof current.uv_index === 'number' ? current.uv_index : null,
    feelsLike:
      typeof current.apparent_temperature === 'number'
        ? current.apparent_temperature
        : null,
    hourlyForecast:
      hourlyForecast.length > 0 ? hourlyForecast : null,
  };
}

exports.fetchWeatherForTrail = onCall(
  {},
  async (request) => {
    authenticatedPhoneFor(request, 'Sign in to refresh trail weather.');
    const trailId = String(request.data?.trailId || '').trim();
    if (!validFirestoreDocumentId(trailId)) {
      throw new HttpsError('invalid-argument', 'The trail id is invalid.');
    }

    const db = admin.firestore();
    const doc = await db.collection('trails').doc(trailId).get();

    if (!doc.exists) {
      throw new HttpsError('not-found', 'This trail no longer exists.');
    }

    const data = doc.data();
    const latitude = data.latitude;
    const longitude = data.longitude;

    if (
      !Number.isFinite(latitude)
      || latitude < -90
      || latitude > 90
      || !Number.isFinite(longitude)
      || longitude < -180
      || longitude > 180
    ) {
      throw new HttpsError(
        'failed-precondition',
        'This trail has no valid weather coordinates.'
      );
    }

    const url = new URL('https://api.open-meteo.com/v1/forecast');
    url.searchParams.set('latitude', latitude.toFixed(4));
    url.searchParams.set('longitude', longitude.toFixed(4));
    url.searchParams.set(
      'current',
      'temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,uv_index'
    );
    url.searchParams.set(
      'daily',
      'temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code'
    );
    url.searchParams.set(
      'hourly',
      'temperature_2m,precipitation_probability,weather_code'
    );
    url.searchParams.set('timezone', 'auto');
    url.searchParams.set('forecast_hours', '12');

    let response;
    try {
      response = await fetch(url.toString(), {
        signal: AbortSignal.timeout(12 * 1000),
      });
    } catch (error) {
      logger.warn('OpenMeteo callable transport failed', {
        trailId,
        errorName: String(error?.name || ''),
      });
      throw new HttpsError(
        'unavailable',
        'Trail weather is temporarily unavailable.'
      );
    }
    if (!response.ok) {
      logger.warn('OpenMeteo callable returned an error', {
        trailId,
        status: response.status,
      });
      throw new HttpsError(
        'unavailable',
        'Trail weather is temporarily unavailable.'
      );
    }

    const body = await response.json().catch(() => null);
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      throw new HttpsError(
        'data-loss',
        'The weather service returned invalid data.'
      );
    }
    const weather = buildWeatherFromApi(body);

    await db.collection('trails').doc(trailId).update({ weather });

    logger.log(`Fetched and saved weather for trail ${trailId}`);

    return { weather };
  }
);

// ─── Notifications ──────────────────────────────────────────────

async function claimAtMostOnceDelivery(
  reference,
  { claimPrefix, processedFields = [] }
) {
  const claimField = `${claimPrefix}ClaimedAt`;
  const claimLocalField = `${claimPrefix}ClaimedAtLocal`;
  return admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const data = snapshot.data() || {};
    if (
      !snapshot.exists
      || data[claimField]
      || data[claimLocalField]
      || processedFields.some((field) => data[field] != null)
    ) {
      return null;
    }
    transaction.set(
      reference,
      {
        [claimField]: admin.firestore.FieldValue.serverTimestamp(),
        [claimLocalField]: new Date().toISOString(),
      },
      { merge: true }
    );
    return data;
  });
}

async function claimFcmOutboxDelivery(reference) {
  return admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const payload = snapshot.data() || {};
    if (!snapshot.exists || String(payload.status || 'pending') !== 'pending') {
      return null;
    }
    transaction.set(
      reference,
      {
        status: 'sending',
        deliveryClaimedAt: admin.firestore.FieldValue.serverTimestamp(),
        deliveryClaimedAtLocal: new Date().toISOString(),
        attemptCount: admin.firestore.FieldValue.increment(1),
      },
      { merge: true }
    );
    return payload;
  });
}

async function sendActiveHikeReopenReminder(
  sessionRef,
  sessionData,
  reason
) {
  const claimedSession = await admin.firestore().runTransaction(
    async (transaction) => {
      const snapshot = await transaction.get(sessionRef);
      const current = snapshot.data() || {};
      const token = String(current.monitoringFcmToken || '').trim();
      if (
        !snapshot.exists
        || String(current.status || '') !== 'active'
        || current.monitoringExpected !== true
        || !token
      ) {
        return null;
      }
      const nowMillis = Date.now();
      const recentCandidates = [
        dateMillis(current.lastMonitoringReminderAt),
        dateMillis(current.lastMonitoringReminderAtLocal),
        dateMillis(current.lastMonitoringReminderClaimedAt),
        dateMillis(current.lastMonitoringReminderClaimedAtLocal),
      ].filter(Number.isFinite);
      if (
        recentCandidates.length > 0
        && nowMillis - Math.max(...recentCandidates) < 10 * 60 * 1000
      ) {
        return null;
      }
      transaction.set(
        sessionRef,
        {
          lastMonitoringReminderClaimedAt:
            admin.firestore.FieldValue.serverTimestamp(),
          lastMonitoringReminderClaimedAtLocal:
            new Date(nowMillis).toISOString(),
          lastMonitoringReminderReason: reason,
        },
        { merge: true }
      );
      return current;
    }
  );
  if (!claimedSession) {
    return false;
  }
  const token = String(claimedSession?.monitoringFcmToken || '').trim();
  if (!token) {
    logger.warn(`No FCM token for active hike ${sessionRef.id}.`);
    return false;
  }

  try {
    await admin.messaging().send({
      token,
      notification: {
        title: 'Hike monitoring stopped',
        body:
          'HikerCircle was terminated or stopped reporting during your active hike. Reopen it now to restore wellbeing monitoring.',
      },
      data: {
        type: 'active_hike_monitoring_stopped',
        sessionId: sessionRef.id,
        deepLink: `hikercircle://hike/active?sessionId=${encodeURIComponent(
          sessionRef.id
        )}`,
        reason,
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'hiker_circle_active_hike',
          priority: 'high',
        },
      },
      apns: {
        headers: {
          'apns-priority': '10',
        },
        payload: {
          aps: {
            sound: 'default',
            'interruption-level': 'time-sensitive',
          },
        },
      },
    });
    await sessionRef.set(
      {
        lastMonitoringReminderAt:
          admin.firestore.FieldValue.serverTimestamp(),
        lastMonitoringReminderAtLocal: new Date().toISOString(),
        lastMonitoringReminderReason: reason,
        lastMonitoringReminderDeliveryStatus: 'sent',
      },
      { merge: true }
    );
    return true;
  } catch (error) {
    await sessionRef.set(
      {
        lastMonitoringReminderDeliveryStatus: 'delivery_uncertain',
        lastMonitoringReminderError: String(
          error?.code || error?.name || 'fcm_transport_error'
        ).slice(0, 160),
      },
      { merge: true }
    ).catch(() => undefined);
    logger.error(
      `Unable to send active hike reminder for ${sessionRef.id}:`,
      error
    );
    return false;
  }
}

function distanceKm(firstLatitude, firstLongitude, secondLatitude, secondLongitude) {
  const radians = (degrees) => (degrees * Math.PI) / 180;
  const latitudeDelta = radians(secondLatitude - firstLatitude);
  const longitudeDelta = radians(secondLongitude - firstLongitude);
  const firstLatitudeRadians = radians(firstLatitude);
  const secondLatitudeRadians = radians(secondLatitude);
  const value =
    Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(firstLatitudeRadians) *
      Math.cos(secondLatitudeRadians) *
      Math.sin(longitudeDelta / 2) ** 2;
  const boundedValue = Math.max(0, Math.min(1, value));
  return 6371 * 2 * Math.asin(Math.sqrt(boundedValue));
}

function dateMillis(value) {
  if (value && typeof value.toDate === 'function') {
    return value.toDate().getTime();
  }
  if (typeof value === 'string') {
    return Date.parse(value);
  }
  if (typeof value === 'number') {
    return value;
  }
  return Number.NaN;
}

function shouldAbandonInactiveHike(hike, nowMillis) {
  const heartbeatCandidates = [
    dateMillis(hike.monitoringHeartbeatAt),
    dateMillis(hike.monitoringHeartbeatAtLocal),
    dateMillis(hike.updatedAt),
    dateMillis(hike.updatedAtLocal),
    dateMillis(hike.startedAt),
    dateMillis(hike.startedAtLocal),
  ].filter(Number.isFinite);
  const latestActivityMillis = heartbeatCandidates.length > 0
    ? Math.max(...heartbeatCandidates)
    : Number.NaN;
  if (
    !Number.isFinite(latestActivityMillis)
    || nowMillis - latestActivityMillis < 30 * 60 * 1000
  ) {
    return false;
  }
  const expectedReturnMillis = dateMillis(
    hike.expectedReturnTime || hike.expectedReturnTimeLocal
  );
  if (Number.isFinite(expectedReturnMillis)) {
    return nowMillis > expectedReturnMillis + 12 * 60 * 60 * 1000;
  }
  const startedMillis = dateMillis(
    hike.startedAt || hike.startedAtLocal || hike.createdAt || hike.createdAtLocal
  );
  return Number.isFinite(startedMillis)
    && nowMillis - startedMillis > 7 * 24 * 60 * 60 * 1000;
}

function formatAppLocalClock(date) {
  return new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Singapore',
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  })
    .format(date)
    .replace(' ', '');
}

async function sendGroupChatSystemMessage(db, chatDoc, text) {
  const chat = chatDoc.data() || {};
  const participantPhones = Array.isArray(chat.participantPhones)
    ? chat.participantPhones.map((phone) => String(phone || '')).filter(Boolean)
    : [];
  const now = new Date();
  const messageRef = chatDoc.ref.collection('messages').doc();
  await messageRef.set({
    chatId: chatDoc.id,
    senderPhone: String(chat.creatorPhone || 'system'),
    senderName: 'HikerCircle',
    text,
    sentAtLocal: now.toISOString(),
    isSystemMessage: true,
    seenBy: participantPhones,
  });
}

async function startGroupChatClosure(db, chatDoc, reason, messagePrefix) {
  const chat = chatDoc.data() || {};
  if (chat.isDeleted === true || chat.chatRemovesAtLocal) {
    return false;
  }
  const now = new Date();
  const removesAt = new Date(now.getTime() + 60 * 60 * 1000);
  await chatDoc.ref.set(
    {
      customName: String(chat.customName || '').trim()
        || defaultFormedHikeGroupName(chat),
      requiresHostNaming: false,
      namingPromptShown: true,
      namingPromptActive: false,
      hikeEndedAtLocal: now.toISOString(),
      chatRemovesAtLocal: removesAt.toISOString(),
      closureReason: reason,
      isDeleted: false,
      lastMessage: `${messagePrefix} (${formatAppLocalClock(removesAt)})`,
      lastMessageAtLocal: now.toISOString(),
      lastMessageSenderPhone: 'system',
      closureNoticeSentAt:
        admin.firestore.FieldValue.serverTimestamp(),
      closureNoticeSentAtLocal: now.toISOString(),
    },
    { merge: true }
  );
  await sendGroupChatSystemMessage(
    db,
    chatDoc,
    `${messagePrefix} (${formatAppLocalClock(removesAt)})`
  );
  return true;
}

function groupChatMessagePreview(message) {
  const text = String(message.text || '').replace(/\s+/g, ' ').trim();
  if (text) {
    return text.length > 120 ? `${text.slice(0, 117)}...` : text;
  }
  const type = String(message.attachment?.type || '');
  if (type === 'image') {
    return 'Photo';
  }
  if (type === 'video') {
    return 'Video';
  }
  if (type === 'document') {
    return 'Document';
  }
  return 'New message';
}

async function ensureAchievementDefinitions() {
  const db = admin.firestore();
  const entries = Object.entries(achievementSeedDefinitions);
  await db.runTransaction(async (transaction) => {
    const references = entries.map(([id]) => db.collection('achievements').doc(id));
    const snapshots = await Promise.all(
      references.map((reference) => transaction.get(reference))
    );
    const nowIso = new Date().toISOString();
    snapshots.forEach((snapshot, index) => {
      if (snapshot.exists) {
        return;
      }
      const [achievementId, definition] = entries[index];
      transaction.create(references[index], {
        achievementId,
        ...definition,
        rewardsSafeBehaviour: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAtLocal: nowIso,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: nowIso,
      });
    });
  });
}

function hikerLevelForPoints(points) {
  const normalized = Math.max(0, Math.floor(Number(points || 0)));
  const tiers = [
    [5500, 7, 'HikerCircle Elite'],
    [3500, 6, 'Mountain Guardian'],
    [2200, 5, 'Trail Expert'],
    [1200, 4, 'Summit Seeker'],
    [600, 3, 'Trekker'],
    [250, 2, 'Pathfinder'],
    [0, 1, 'Trailhead'],
  ];
  const tier = tiers.find(([minimum]) => normalized >= minimum) || tiers.at(-1);
  return {
    number: tier[1],
    name: tier[2],
    badgeLabel: `Lv. ${tier[1]} ${tier[2]}`,
  };
}

function serverEventReceiptId(prefix, ...values) {
  return crypto
    .createHash('sha256')
    .update([prefix, ...values].join(':'))
    .digest('hex');
}

async function applyAchievementMetricServer({
  userId,
  metricKey,
  eventKey,
  increment = 1,
  condition = '',
}) {
  if (
    !validFirestoreDocumentId(userId)
    || !/^[a-z0-9_]{1,80}$/.test(String(metricKey || ''))
    || !eventKey
    || !Number.isInteger(increment)
    || increment < 1
    || increment > 1000
  ) {
    return;
  }
  await ensureAchievementDefinitions();
  const db = admin.firestore();
  const definitions = await db
    .collection('achievements')
    .where('metricKey', '==', metricKey)
    .get();
  for (const definitionDocument of definitions.docs) {
    const achievementId = definitionDocument.id;
    const definitionReference = definitionDocument.ref;
    const progressReference = db
      .collection('userAchievements')
      .doc(`${userId}_${achievementId}`);
    const userReference = db.collection('users').doc(userId);
    const receiptReference = db
      .collection('achievementEventReceipts')
      .doc(serverEventReceiptId('achievement', eventKey, userId, achievementId));
    await db.runTransaction(async (transaction) => {
      const [receipt, definitionSnapshot, progressSnapshot, userSnapshot] =
        await Promise.all([
          transaction.get(receiptReference),
          transaction.get(definitionReference),
          transaction.get(progressReference),
          transaction.get(userReference),
        ]);
      if (receipt.exists) {
        return;
      }
      const nowIso = new Date().toISOString();
      const definition = definitionSnapshot.data() || {};
      if (
        !definitionSnapshot.exists
        || definition.isActive === false
        || !userSnapshot.exists
      ) {
        transaction.create(receiptReference, {
          eventKey: String(eventKey).slice(0, 500),
          userId,
          achievementId,
          applied: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAtLocal: nowIso,
        });
        return;
      }
      const existing = progressSnapshot.data() || {};
      const rewardType = String(definition.rewardType || '') === 'cumulative'
        ? 'cumulative'
        : 'one_time';
      const targetCount = rewardType === 'one_time'
        ? 1
        : Math.max(1, Math.min(1000000000, Number(definition.targetCount || 1)));
      const wasUnlocked = existing.isUnlocked === true
        || existing.awardedAt != null
        || existing.awardedAtLocal != null;
      const previousProgress = Math.max(
        0,
        Math.min(targetCount, Number(existing.progressCount || 0))
      );
      const nextProgress = wasUnlocked || rewardType === 'one_time'
        ? targetCount
        : Math.min(targetCount, previousProgress + increment);
      const isUnlocked = wasUnlocked || nextProgress >= targetCount;
      const newlyUnlocked = !wasUnlocked && isUnlocked;
      const rewardPoints = Math.max(
        0,
        Math.min(1000000000, Number(definition.rewardPoints || 0))
      );
      transaction.set(
        progressReference,
        {
          userAchievementId: progressReference.id,
          userId,
          achievementId,
          achievementTitle: String(definition.title || '').slice(0, 160),
          rewardType,
          metricKey,
          targetCount,
          progressCount: nextProgress,
          isUnlocked,
          ...(condition ? { condition: String(condition).slice(0, 500) } : {}),
          ...(newlyUnlocked
            ? {
                pointsAwarded: rewardPoints,
                awardedAt: admin.firestore.FieldValue.serverTimestamp(),
                awardedAtLocal: nowIso,
              }
            : {}),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAtLocal: nowIso,
        },
        { merge: true }
      );
      if (newlyUnlocked) {
        const currentPoints = Math.max(
          0,
          Number(userSnapshot.data()?.achievementPoints || 0)
        );
        const totalPoints = currentPoints + rewardPoints;
        const level = hikerLevelForPoints(totalPoints);
        transaction.set(
          userReference,
          {
            achievementPoints: totalPoints,
            hikerLevel: level.number,
            hikerLevelName: level.name,
            hikerLevelBadge: level.badgeLabel,
            achievementSummaryUpdatedAt:
              admin.firestore.FieldValue.serverTimestamp(),
            achievementSummaryUpdatedAtLocal: nowIso,
          },
          { merge: true }
        );
      }
      transaction.create(receiptReference, {
        eventKey: String(eventKey).slice(0, 500),
        userId,
        achievementId,
        applied: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAtLocal: nowIso,
      });
    });
  }
}

exports.manageAchievementDefinition = onCall(
  {},
  async (request) => {
    const { uid } = authenticatedPhoneFor(
      request,
      'Sign in to manage achievements.'
    );
    const action = String(request.data?.action || '').trim();
    if (action === 'seed') {
      await ensureAchievementDefinitions();
      return { seeded: true };
    }
    const userSnapshot = await admin
      .firestore()
      .collection('users')
      .doc(uid)
      .get();
    if (!userSnapshot.exists || !isAdminUser(userSnapshot.data() || {})) {
      throw new HttpsError('permission-denied', 'Administrator access is required.');
    }
    const db = admin.firestore();
    if (action === 'setActive') {
      const achievementId = String(request.data?.achievementId || '').trim();
      if (!validFirestoreDocumentId(achievementId)) {
        throw new HttpsError('invalid-argument', 'The achievement is invalid.');
      }
      await db.collection('achievements').doc(achievementId).set(
        {
          isActive: request.data?.isActive === true,
          updatedByAdminId: uid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAtLocal: new Date().toISOString(),
        },
        { merge: true }
      );
      return { achievementId };
    }
    if (action !== 'save') {
      throw new HttpsError('invalid-argument', 'The achievement action is invalid.');
    }
    const raw = request.data?.achievement;
    const title = String(raw?.title || '').trim().slice(0, 160);
    const requirement = String(raw?.condition || '').trim().slice(0, 500);
    const metricKey = String(raw?.metricKey || '').trim();
    if (!title || !requirement || !/^[a-z0-9_]{1,80}$/.test(metricKey)) {
      throw new HttpsError(
        'invalid-argument',
        'Title, requirement, and a valid metric are required.'
      );
    }
    const requestedId = String(request.data?.achievementId || '').trim();
    if (requestedId && !validFirestoreDocumentId(requestedId)) {
      throw new HttpsError('invalid-argument', 'The achievement id is invalid.');
    }
    const achievementId = requestedId || `achievement_${crypto.randomBytes(12).toString('hex')}`;
    const reference = db.collection('achievements').doc(achievementId);
    const existing = await reference.get();
    const rewardType = String(raw?.rewardType || '') === 'cumulative'
      ? 'cumulative'
      : 'one_time';
    const nowIso = new Date().toISOString();
    await reference.set(
      {
        achievementId,
        title,
        condition: requirement,
        category: String(raw?.category || 'Hiking').trim().slice(0, 80) || 'Hiking',
        iconName: String(raw?.iconName || 'emoji_events').trim().slice(0, 80),
        rewardPoints: Math.round(boundedNumber(raw?.rewardPoints, 1, 1000000, 1)),
        rewardType,
        metricKey,
        targetCount: rewardType === 'one_time'
          ? 1
          : Math.round(boundedNumber(raw?.targetCount, 1, 1000000000, 1)),
        isActive: raw?.isActive !== false,
        sortOrder: Math.round(boundedNumber(raw?.sortOrder, -100000, 100000, 0)),
        accentColorValue: Math.round(
          boundedNumber(raw?.accentColorValue, 0, 0xffffffff, 0xff34a853)
        ),
        rewardsSafeBehaviour: true,
        updatedByAdminId: uid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: nowIso,
        ...(!existing.exists
          ? {
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              createdAtLocal: nowIso,
            }
          : {}),
      },
      { merge: true }
    );
    return { achievementId };
  }
);

// Keep the deployed function name so a normal Functions deployment replaces
// the legacy trigger that awarded preparation badges from an ordinary hike
// start. No preparation metric is emitted until the backend has authoritative
// offline-map and full-checklist evidence.
exports.awardAchievementsForStartedHike = onDocumentCreated(
  'hikeSessions/{sessionId}',
  async () => undefined
);

exports.recordHikeTerminalStateAndAchievements = onDocumentUpdated(
  'hikeSessions/{sessionId}',
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    const beforeStatus = String(before.status || '');
    const afterStatus = String(after.status || '');
    if (
      beforeStatus === afterStatus
      || !['completed', 'abandoned'].includes(afterStatus)
    ) {
      return;
    }
    const userId = String(after.userId || '');
    const phoneNumber = String(after.userPhoneNumber || '');
    if (userId !== userDocumentIdForPhone(phoneNumber)) {
      return;
    }
    const nowIso = new Date().toISOString();
    await admin.firestore().collection('hikeSessionTerminalStates')
      .doc(event.params.sessionId)
      .set({
        sessionId: event.params.sessionId,
        userId,
        userPhoneNumber: phoneNumber,
        status: afterStatus,
        recordedAt: admin.firestore.FieldValue.serverTimestamp(),
        recordedAtLocal: nowIso,
      }, { merge: true });
    await updateTeamParticipantForHike(after, 'ended');
    if (afterStatus !== 'completed') {
      return;
    }
    await applyAchievementMetricServer({
      userId,
      metricKey: 'hike_completed',
      eventKey: `hike-completed:${event.params.sessionId}`,
    });
  }
);

exports.awardAchievementForCompletedTeamHike = onDocumentUpdated(
  'teamHikeSessions/{teamId}',
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    const participants = validTeamParticipants(after);
    if (
      String(before.phase || '') !== 'active'
      || String(after.phase || '') !== 'completed'
      || !Number.isFinite(dateMillis(after.startedAtLocal))
      || after.lastSeparationAlertAt
      || after.lastSeparationAlertAtLocal
      || participants.length === 0
      || !participants.every(
        (participant) => String(participant.status || '') === 'ended'
      )
    ) {
      return;
    }
    const phones = [
      ...new Set(participants.map(teamParticipantPhone).filter(Boolean)),
    ];
    const sessionIdsByPhone = after.activeHikeSessionIdsByPhone
      && typeof after.activeHikeSessionIdsByPhone === 'object'
      && !Array.isArray(after.activeHikeSessionIdsByPhone)
      ? after.activeHikeSessionIdsByPhone
      : {};
    const sessionIds = phones.map(
      (phoneNumber) => String(sessionIdsByPhone[phoneKeyFor(phoneNumber)] || '')
    );
    if (sessionIds.some((sessionId) => !validFirestoreDocumentId(sessionId))) {
      return;
    }
    const db = admin.firestore();
    const hikeSnapshots = await db.getAll(
      ...sessionIds.map((sessionId) => db.collection('hikeSessions').doc(sessionId))
    );
    const allHikesCompleted = hikeSnapshots.every((snapshot, index) => {
      const hike = snapshot.data() || {};
      return snapshot.exists
        && String(hike.status || '') === 'completed'
        && String(hike.userPhoneNumber || '') === phones[index]
        && String(hike.teamHikeSessionId || '') === event.params.teamId;
    });
    if (!allHikesCompleted) {
      return;
    }
    await Promise.all(
      phones.map((phoneNumber) => {
        const userId = userDocumentIdForPhone(phoneNumber);
        return applyAchievementMetricServer({
          userId,
          metricKey: 'team_hike_completed',
          eventKey: `team-hike-completed:${event.params.teamId}:${userId}`,
        });
      })
    );
  }
);

exports.preserveDeletedHikeTerminalState = onDocumentDeleted(
  'hikeSessions/{sessionId}',
  async (event) => {
    const hike = event.data.data() || {};
    const status = String(hike.status || '');
    if (!['completed', 'abandoned'].includes(status)) {
      return;
    }
    await admin.firestore().collection('hikeSessionTerminalStates')
      .doc(event.params.sessionId)
      .set({
        sessionId: event.params.sessionId,
        userId: String(hike.userId || ''),
        userPhoneNumber: String(hike.userPhoneNumber || ''),
        status,
        recordedAt: admin.firestore.FieldValue.serverTimestamp(),
        recordedAtLocal: new Date().toISOString(),
      }, { merge: true });
  }
);

exports.awardAchievementForCheckIn = onDocumentCreated(
  'checkIns/{checkInId}',
  async (event) => {
    const checkIn = event.data.data() || {};
    const userId = String(checkIn.userId || '');
    const phoneNumber = String(checkIn.userPhoneNumber || '');
    if (
      userId !== userDocumentIdForPhone(phoneNumber)
      || String(checkIn.status || '') !== 'safe'
    ) {
      return;
    }
    await applyAchievementMetricServer({
      userId,
      metricKey: 'check_in_completed',
      eventKey: `check-in:${event.params.checkInId}`,
    });
  }
);

exports.awardAchievementForCommunityPost = onDocumentCreated(
  'communityPosts/{postId}',
  async (event) => {
    const post = event.data.data() || {};
    const userId = String(post.authorId || '');
    const phoneNumber = String(post.authorPhoneNumber || '');
    if (
      userId !== userDocumentIdForPhone(phoneNumber)
      || String(post.visibility || '') !== 'public'
    ) {
      return;
    }
    await applyAchievementMetricServer({
      userId,
      metricKey: 'community_post_created',
      eventKey: `community-post:${event.params.postId}`,
    });
  }
);

exports.awardAchievementForApprovedHazard = onDocumentUpdated(
  'hazardReports/{hazardId}',
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    if (
      String(before.status || '') === 'verified'
      || String(after.status || '') !== 'verified'
    ) {
      return;
    }
    const userId = String(after.reportedBy || '');
    const phoneNumber = String(after.reportedByPhoneNumber || '');
    if (userId !== userDocumentIdForPhone(phoneNumber)) {
      return;
    }
    await applyAchievementMetricServer({
      userId,
      metricKey: 'hazard_report_approved',
      eventKey: `hazard-approved:${event.params.hazardId}`,
    });
  }
);

exports.incrementCommunityCommentCount = onDocumentCreated(
  'communityPosts/{postId}/comments/{commentId}',
  async (event) => {
    const db = admin.firestore();
    const postReference = db.collection('communityPosts').doc(event.params.postId);
    const receiptReference = db
      .collection('communityCounterEventReceipts')
      .doc(serverEventReceiptId(
        'comment-created',
        event.id || '',
        event.params.postId,
        event.params.commentId
      ));
    await db.runTransaction(async (transaction) => {
      const [postSnapshot, receiptSnapshot] = await Promise.all([
        transaction.get(postReference),
        transaction.get(receiptReference),
      ]);
      if (receiptSnapshot.exists) {
        return;
      }
      const nowIso = new Date().toISOString();
      if (postSnapshot.exists) {
        transaction.set(
          postReference,
          {
            commentCount: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAtLocal: nowIso,
          },
          { merge: true }
        );
      }
      transaction.create(receiptReference, {
        eventType: 'comment_created',
        postId: event.params.postId,
        commentId: event.params.commentId,
        applied: postSnapshot.exists,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAtLocal: nowIso,
      });
    });
  }
);

exports.decrementCommunityCommentCount = onDocumentDeleted(
  'communityPosts/{postId}/comments/{commentId}',
  async (event) => {
    const db = admin.firestore();
    const postReference = db.collection('communityPosts').doc(event.params.postId);
    const receiptReference = db
      .collection('communityCounterEventReceipts')
      .doc(serverEventReceiptId(
        'comment-deleted',
        event.id || '',
        event.params.postId,
        event.params.commentId
      ));
    await db.runTransaction(async (transaction) => {
      const [postSnapshot, receiptSnapshot] = await Promise.all([
        transaction.get(postReference),
        transaction.get(receiptReference),
      ]);
      if (receiptSnapshot.exists) {
        return;
      }
      const nowIso = new Date().toISOString();
      if (postSnapshot.exists) {
        const current = Math.max(
          0,
          Number(postSnapshot.data()?.commentCount || 0)
        );
        transaction.set(
          postReference,
          {
            commentCount: Math.max(0, current - 1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAtLocal: nowIso,
          },
          { merge: true }
        );
      }
      transaction.create(receiptReference, {
        eventType: 'comment_deleted',
        postId: event.params.postId,
        commentId: event.params.commentId,
        applied: postSnapshot.exists,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAtLocal: nowIso,
      });
    });
  }
);

exports.notifyGroupMembersAboutMessage = onDocumentCreated(
  'groupChats/{chatId}/messages/{messageId}',
  async (event) => {
    const message = event.data.data() || {};
    if (message.isSystemMessage === true) {
      return;
    }
    const claimedNotification = await claimAtMostOnceDelivery(event.data.ref, {
      claimPrefix: 'notificationDelivery',
      processedFields: [
        'notificationProcessedAt',
        'notificationProcessedAtLocal',
      ],
    });
    const shouldAttemptNotification = claimedNotification !== null;

    const chatReference = event.data.ref.parent.parent;
    if (!chatReference) {
      return;
    }
    const chatSnapshot = await chatReference.get();
    const chat = chatSnapshot.data() || {};
    const chatRemovesAt = dateMillis(chat.chatRemovesAtLocal);
    if (
      chat.isDeleted === true ||
      (Number.isFinite(chatRemovesAt) && chatRemovesAt <= Date.now())
    ) {
      return;
    }
    const senderPhone = String(message.senderPhone || '');
    const senderPhoneDigits = phoneKeyFor(senderPhone);
    const participantPhones = [
      ...new Set(
        (Array.isArray(chat.participantPhones)
          ? chat.participantPhones
          : []
        )
          .map((phone) => String(phone || ''))
          .filter((phone) => {
            if (!phone) return false;
            if (phoneKeyFor(phone) === senderPhoneDigits) return false;
            return true;
          })
      ),
    ];
    if (participantPhones.length === 0) {
      return;
    }

    const db = admin.firestore();
    const userReferences = participantPhones.map((phone) =>
      db.collection('users').doc(phone.replace(/\//g, '_'))
    );
    const userSnapshots = await db.getAll(...userReferences);
    const tokens = new Set();
    let eligibleUsers = 0;
    const now = Date.now();

    for (const userSnapshot of userSnapshots) {
      if (!userSnapshot.exists) {
        continue;
      }
      const user = userSnapshot.data() || {};
      if (user.groupChatNotificationsEnabled === false) {
        continue;
      }
      const mutedChats =
        user.groupChatMutedUntil &&
        typeof user.groupChatMutedUntil === 'object'
          ? user.groupChatMutedUntil
          : {};
      const mutedUntil = dateMillis(mutedChats[event.params.chatId]);
      if (Number.isFinite(mutedUntil) && mutedUntil > now) {
        continue;
      }

      const validTokens = latestFcmTokensForUser(user);
      if (validTokens.length === 0) {
        continue;
      }
      eligibleUsers++;
      for (const token of validTokens) {
        tokens.add(token);
      }
    }

    const tokenList = [...tokens];
    const deepLink =
      `hikercircle://group-chat/view?chatId=` +
      encodeURIComponent(event.params.chatId);
    let successCount = 0;
    let failureCount = 0;
    let notificationDeliveryStatus = tokenList.length === 0
      ? 'no_token'
      : 'sent';
    let notificationDeliveryError = '';
    if (shouldAttemptNotification) {
      try {
        for (let index = 0; index < tokenList.length; index += 500) {
          const response = await admin.messaging().sendEachForMulticast({
            tokens: tokenList.slice(index, index + 500),
            notification: {
              title:
                chat.chatType === 'direct'
                  ? String(message.senderName || 'New private message')
                  : `${message.senderName || 'A hiker'} - ${
                      chat.trailName || 'Group chat'
                    }`,
              body: groupChatMessagePreview(message),
            },
            data: {
              type: 'group_chat_message',
              chatId: event.params.chatId,
              messageId: event.params.messageId,
              deepLink,
            },
            android: {
              priority: 'high',
              notification: {
                priority: 'high',
              },
            },
            apns: {
              headers: {
                'apns-priority': '10',
              },
              payload: {
                aps: {
                  sound: 'default',
                },
              },
            },
          });
          successCount += response.successCount;
          failureCount += response.failureCount;
        }
        if (failureCount > 0) {
          notificationDeliveryStatus = successCount > 0 ? 'partial' : 'failed';
        }
      } catch (error) {
        notificationDeliveryStatus = 'delivery_uncertain';
        notificationDeliveryError = String(
          error?.code || error?.name || 'fcm_transport_error'
        ).slice(0, 160);
        logger.error(
          `Group chat notification ${event.params.messageId} is uncertain`,
          {
            errorName: String(error?.name || ''),
            errorCode: String(error?.code || ''),
          },
        );
      }
    }

    // Fallback: ensure chat document has lastMessage metadata so
    // recipient circle page snapshot listeners fire with the update
    // even if the sender's client-side .set(merge:true) failed.
    await chatReference.set(
      {
        lastMessage: String(message.text || message.attachmentType || ''),
        lastMessageAtLocal: String(
          message.sentAtLocal || new Date().toISOString()
        ),
        lastMessageSenderPhone: String(message.senderPhone || ''),
      },
      { merge: true }
    );

    // Use a transaction to atomically read lastReadAt and increment unreadCount.
    // This eliminates the race where markGroupChatAsRead (unreadCount = 0,
    // lastReadAt = now) commits between the re-read and the update — the
    // transaction retries with the latest data, ensuring we never increment
    // for messages the user has already seen.
    const messageTimeMs = new Date(
      message.sentAtLocal || message.createdAt || new Date().toISOString()
    ).getTime();
    await db.runTransaction(async (transaction) => {
      const [freshChatSnapshot, freshMessageSnapshot] = await Promise.all([
        transaction.get(chatReference),
        transaction.get(event.data.ref),
      ]);
      if (freshMessageSnapshot.data()?.unreadProcessedAt) {
        return;
      }
      const freshChat = freshChatSnapshot.data() || {};
      const unreadUpdates = {};
      for (const phone of participantPhones) {
        const phoneKey = phoneKeyFor(phone);
        if (!phoneKey || phoneKey === senderPhoneDigits) {
          continue;
        }
        const lastReadAt =
          freshChat.lastReadAt && freshChat.lastReadAt[phoneKey];
        const lastReadAtMs = lastReadAt
          ? new Date(lastReadAt).getTime()
          : 0;
        if (messageTimeMs > lastReadAtMs) {
          unreadUpdates[`unreadCount.${phoneKey}`] =
            admin.firestore.FieldValue.increment(1);
        }
      }
      if (Object.keys(unreadUpdates).length > 0) {
        transaction.update(chatReference, unreadUpdates);
      }
      transaction.set(
        event.data.ref,
        {
          unreadProcessedAt: admin.firestore.FieldValue.serverTimestamp(),
          unreadProcessedAtLocal: new Date().toISOString(),
        },
        { merge: true }
      );
    });

    if (shouldAttemptNotification) {
      await event.data.ref.set(
        {
          notificationEligibleUsers: eligibleUsers,
          notificationTokenCount: tokenList.length,
          notificationSuccessCount: successCount,
          notificationFailureCount: failureCount,
          notificationDeliveryStatus,
          ...(notificationDeliveryError
            ? { notificationDeliveryError }
            : {}),
          notificationProcessedAt:
            admin.firestore.FieldValue.serverTimestamp(),
          notificationProcessedAtLocal: new Date().toISOString(),
        },
        { merge: true }
      );
      logger.log(
        `Group chat ${event.params.chatId} message ${event.params.messageId}: ${successCount} notifications sent, ${failureCount} failed.`
      );
    }
  }
);

exports.deliverFcmOutboxMessage = onDocumentCreated(
  'fcmOutbox/{messageId}',
  async (event) => {
    const payload = await claimFcmOutboxDelivery(event.data.ref);
    if (!payload) return;
    const type = String(payload.type || '');
    const recipientPhone = String(payload.recipientPhoneNumber || '');
    const senderPhone = String(payload.senderPhoneNumber || '');
    const teamHikeSessionId = String(payload.teamHikeSessionId || '');
    const allowedTypes = new Set([
      'team_hike_invite',
      'team_hike_invite_accepted',
      'team_hike_countdown',
      'team_hike_started',
      'team_hike_ping',
      'team_hike_ping_ok',
      'team_hike_completed',
      'team_hike_separation_alert',
      'team_hike_path_deviation',
    ]);
    if (
      !allowedTypes.has(type)
      || !/^\+[1-9]\d{7,14}$/.test(recipientPhone)
      || !/^\+[1-9]\d{7,14}$/.test(senderPhone)
      || !teamHikeSessionId
    ) {
      await event.data.ref.set(
        { status: 'failed', error: 'Invalid or unsupported outbox payload' },
        { merge: true }
      );
      return;
    }

    const teamSnapshot = await admin
      .firestore()
      .collection('teamHikeSessions')
      .doc(teamHikeSessionId)
      .get();
    const team = teamSnapshot.data() || {};
    const hostPhone = String(team.hostPhoneNumber || '');
    const participantPhones = new Set(
      (Array.isArray(team.participants) ? team.participants : [])
        .map(teamParticipantPhone)
        .filter((phone) => phone)
    );
    const senderIsParticipant = participantPhones.has(senderPhone);
    const recipientIsParticipant = participantPhones.has(recipientPhone);
    const hostOnlyTypes = new Set([
      'team_hike_invite',
      'team_hike_countdown',
      'team_hike_started',
      'team_hike_completed',
      'team_hike_separation_alert',
    ]);
    const authorized =
      teamSnapshot.exists
      && recipientIsParticipant
      && (
        (hostOnlyTypes.has(type) && senderPhone === hostPhone)
        || (type === 'team_hike_invite_accepted'
          && senderIsParticipant
          && recipientPhone === hostPhone)
        || (type === 'team_hike_ping'
          && senderIsParticipant
          && recipientIsParticipant)
        || (type === 'team_hike_ping_ok'
          && senderIsParticipant
          && recipientIsParticipant)
        || (type === 'team_hike_path_deviation'
          && senderIsParticipant
          && recipientIsParticipant)
      );
    if (!authorized) {
      await event.data.ref.set(
        { status: 'failed', error: 'Sender is not authorized for this team message' },
        { merge: true }
      );
      return;
    }

    const trailName = String(team.trailName || 'your team hike').slice(0, 100);
    const templates = {
      team_hike_invite: ['Team hike invite', `You were invited to ${trailName}.`],
      team_hike_invite_accepted: ['Buddy joined', 'A buddy joined your team hike.'],
      team_hike_countdown: ['Team hike starting', `${trailName} is ready to start.`],
      team_hike_started: ['Team hike started', `${trailName} is now actively tracking.`],
      team_hike_ping: ['Team check ping', 'Your hiking team is asking for an OK response.'],
      team_hike_ping_ok: ['Buddy responded OK', 'A teammate confirmed that they are OK.'],
      team_hike_completed: ['Team hike completed', `${trailName} has ended.`],
      team_hike_separation_alert: [
        'Teammate separation alert',
        'Open HikerCircle to check your team positions.',
      ],
      team_hike_path_deviation: [
        'Team route warning',
        'A teammate may be off the planned trail. Open the team map.',
      ],
    };
    const [notificationTitle, notificationBody] = templates[type];
    const safeDeepLink = type === 'team_hike_ping'
      ? `hikercircle://team-hike/ping?teamSessionId=${encodeURIComponent(teamHikeSessionId)}`
      : `hikercircle://team-hike/join?teamSessionId=${encodeURIComponent(teamHikeSessionId)}`;
    const userSnapshot = await admin
      .firestore()
      .collection('users')
      .doc(recipientPhone.replace(/\//g, '_'))
      .get();
    const user = userSnapshot.data() || {};
    const tokenList = latestFcmTokensForUser(user);
    if (tokenList.length === 0) {
      await event.data.ref.set(
        {
          status: 'no_token',
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          processedAtLocal: new Date().toISOString(),
        },
        { merge: true }
      );
      return;
    }
    const data = {
      type,
      teamHikeSessionId,
      deepLink: safeDeepLink,
    };
    let successCount = 0;
    let failureCount = 0;
    try {
      for (let index = 0; index < tokenList.length; index += 500) {
        const response = await admin.messaging().sendEachForMulticast({
          tokens: tokenList.slice(index, index + 500),
          notification: {
            title: notificationTitle,
            body: notificationBody,
          },
          data,
          android: { priority: 'high' },
          apns: {
            headers: { 'apns-priority': '10' },
            payload: { aps: { sound: 'default' } },
          },
        });
        successCount += response.successCount;
        failureCount += response.failureCount;
      }
    } catch (error) {
      await event.data.ref.set(
        {
          status: 'delivery_uncertain',
          successCount,
          failureCount,
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          processedAtLocal: new Date().toISOString(),
          error: String(error?.code || error?.name || 'fcm_transport_error')
            .slice(0, 160),
        },
        { merge: true }
      );
      logger.error(`FCM outbox delivery ${event.params.messageId} is uncertain`, {
        errorName: String(error?.name || ''),
        errorCode: String(error?.code || ''),
      });
      return;
    }
    await event.data.ref.set(
      {
        status: failureCount === 0 ? 'sent' : 'partial',
        successCount,
        failureCount,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        processedAtLocal: new Date().toISOString(),
      },
      { merge: true }
    );
  }
);

exports.notifyNearbyHikersAboutUpcomingHike = onDocumentCreated(
  'upcomingHikes/{hikeId}',
  async (event) => {
    const hike = await claimAtMostOnceDelivery(event.data.ref, {
      claimPrefix: 'nearbyNotificationDelivery',
      processedFields: [
        'nearbyNotificationSentAt',
        'nearbyNotificationSentAtLocal',
      ],
    });
    if (!hike) return;
    const hikeLatitude = Number(hike.latitude);
    const hikeLongitude = Number(hike.longitude);
    if (!Number.isFinite(hikeLatitude) || !Number.isFinite(hikeLongitude)) {
      logger.warn(`Upcoming hike ${event.params.hikeId} has no coordinates.`);
      return;
    }

    const radiusKm = 20;
    const creatorPhone = String(hike.creatorPhone || '');
    const participantPhones = new Set(
      Array.isArray(hike.participantPhones) ? hike.participantPhones : []
    );
    const usersSnapshot = await admin.firestore().collection('users').get();
    const tokens = new Set();
    let nearbyUserCount = 0;

    for (const userDocument of usersSnapshot.docs) {
      const user = userDocument.data() || {};
      const profile =
        user.profile && typeof user.profile === 'object' ? user.profile : {};
      const latitude = Number(
        profile.residentialLatitude ?? user.residentialLatitude
      );
      const longitude = Number(
        profile.residentialLongitude ?? user.residentialLongitude
      );
      const phoneNumber = String(user.phoneNumber || '');
      if (
        !Number.isFinite(latitude) ||
        !Number.isFinite(longitude) ||
        phoneNumber === creatorPhone ||
        participantPhones.has(phoneNumber) ||
        distanceKm(hikeLatitude, hikeLongitude, latitude, longitude) > radiusKm
      ) {
        continue;
      }

      const validTokens = latestFcmTokensForUser(user);
      if (validTokens.length === 0) {
        continue;
      }
      nearbyUserCount++;
      for (const token of validTokens) {
        tokens.add(token);
      }
    }

    const tokenList = [...tokens];
    let successCount = 0;
    let failureCount = 0;
    const deepLink =
      `hikercircle://upcoming-hike/view?upcomingHikeId=` +
      encodeURIComponent(event.params.hikeId);
    let deliveryStatus = tokenList.length === 0 ? 'no_token' : 'sent';
    let deliveryError = '';
    try {
      for (let index = 0; index < tokenList.length; index += 500) {
        const response = await admin.messaging().sendEachForMulticast({
          tokens: tokenList.slice(index, index + 500),
          notification: {
            title: 'Upcoming hike near you',
            body: `${hike.trailName || 'A hike'} in ${
              hike.area || 'your area'
            } is open to join.`,
          },
          data: {
            type: 'nearby_upcoming_hike',
            upcomingHikeId: event.params.hikeId,
            deepLink,
          },
          android: {
            priority: 'high',
            notification: {
              channelId: 'hiker_circle_upcoming_hikes',
              priority: 'high',
            },
          },
          apns: {
            headers: {
              'apns-priority': '10',
            },
            payload: {
              aps: {
                sound: 'default',
              },
            },
          },
        });
        successCount += response.successCount;
        failureCount += response.failureCount;
      }
      if (failureCount > 0) {
        deliveryStatus = successCount > 0 ? 'partial' : 'failed';
      }
    } catch (error) {
      deliveryStatus = 'delivery_uncertain';
      deliveryError = String(
        error?.code || error?.name || 'fcm_transport_error'
      ).slice(0, 160);
      logger.error(`Nearby notification ${event.params.hikeId} is uncertain`, {
        errorName: String(error?.name || ''),
        errorCode: String(error?.code || ''),
      });
    }

    await event.data.ref.set(
      {
        nearbyNotificationRadiusKm: radiusKm,
        nearbyNotificationEligibleUsers: nearbyUserCount,
        nearbyNotificationTokenCount: tokenList.length,
        nearbyNotificationSuccessCount: successCount,
        nearbyNotificationFailureCount: failureCount,
        nearbyNotificationDeliveryStatus: deliveryStatus,
        ...(deliveryError ? { nearbyNotificationDeliveryError: deliveryError } : {}),
        nearbyNotificationSentAt:
          admin.firestore.FieldValue.serverTimestamp(),
        nearbyNotificationSentAtLocal: new Date().toISOString(),
      },
      { merge: true }
    );
    logger.log(
      `Upcoming hike ${event.params.hikeId}: ${successCount} nearby notifications sent, ${failureCount} failed.`
    );
  }
);

exports.sendReminderOnActiveHikeTerminationSignal = onDocumentUpdated(
  'hikeSessions/{sessionId}',
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    if (
      after.status !== 'active' ||
      after.monitoringExpected !== true ||
      !after.terminationSignalNonce ||
      after.terminationSignalNonce === before.terminationSignalNonce
    ) {
      return;
    }
    await sendActiveHikeReopenReminder(
      event.data.after.ref,
      after,
      'app_detached'
    );
  }
);

function upcomingHikeReminderWindowLabel(minutesUntil) {
  const minutes = Math.max(1, Math.round(Number(minutesUntil) || 1));
  if (minutes >= 1440 && minutes % 1440 === 0) {
    const days = minutes / 1440;
    return `${days} day${days === 1 ? '' : 's'}`;
  }
  if (minutes >= 60 && minutes % 60 === 0) {
    const hours = minutes / 60;
    return `${hours} hour${hours === 1 ? '' : 's'}`;
  }
  return `${minutes} minute${minutes === 1 ? '' : 's'}`;
}

async function sendUpcomingHikeReminderToPhone(
  db,
  hikeId,
  hike,
  phoneNumber,
  minutesUntil
) {
  const phone = String(phoneNumber || '').trim();
  if (!phone) {
    return { successCount: 0, failureCount: 0, skipped: true };
  }
  const userSnapshot = await db
    .collection('users')
    .doc(userDocumentIdForPhone(phone))
    .get();
  if (!userSnapshot.exists) {
    return { successCount: 0, failureCount: 0, skipped: true };
  }
  const tokenList = latestFcmTokensForUser(userSnapshot.data() || {});
  if (tokenList.length === 0) {
    return { successCount: 0, failureCount: 0, skipped: true };
  }

  const creatorPhone = String(hike.creatorPhone || '');
  const isHost = phoneKeyFor(phone) === phoneKeyFor(creatorPhone);
  const trailName = String(hike.trailName || 'your hike');
  const windowLabel = upcomingHikeReminderWindowLabel(minutesUntil);
  const deepLink =
    `hikercircle://upcoming-hike/view?upcomingHikeId=` +
    encodeURIComponent(hikeId);
  let successCount = 0;
  let failureCount = 0;
  for (let index = 0; index < tokenList.length; index += 500) {
    const response = await admin.messaging().sendEachForMulticast({
      tokens: tokenList.slice(index, index + 500),
      notification: {
        title: isHost ? 'Prepare to start your hike' : 'Upcoming hike reminder',
        body: isHost
          ? `${trailName} starts in about ${windowLabel}. Open HikerCircle to prepare.`
          : `${trailName} starts in about ${windowLabel}. Get ready to join.`,
      },
      data: {
        type: 'upcoming_hike_reminder',
        upcomingHikeId: hikeId,
        deepLink,
        role: isHost ? 'host' : 'participant',
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'hiker_circle_upcoming_hikes',
          priority: 'high',
        },
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: { aps: { sound: 'default' } },
      },
    });
    successCount += response.successCount;
    failureCount += response.failureCount;
  }
  return { successCount, failureCount, skipped: false };
}

async function claimUpcomingHikeReminder({
  db,
  hikeReference,
  hikeId,
  hike,
  phoneNumber,
  departureMillis,
  nowMillis,
}) {
  const userId = userDocumentIdForPhone(phoneNumber);
  const preferenceReference = hikeReference
    .collection('reminderPreferences')
    .doc(userId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(preferenceReference);
    if (!snapshot.exists && (
      hike.reminder30SentAt
      || hike.reminder30SentAtLocal
      || hike.reminder30ClaimedAt
      || hike.reminder30ClaimedAtLocal
    )) {
      return null;
    }
    const rawPreference = snapshot.data() || {};
    const due = upcomingHikeReminderDue({
      rawPreference,
      departureMillis,
      nowMillis,
      legacy: !snapshot.exists,
    });
    if (!due.due) return null;

    const lastClaimedMillis = dateMillis(
      rawPreference.deliveryClaimedAtLocal
      || rawPreference.deliveryClaimedAt
    );
    if (
      Number.isFinite(lastClaimedMillis)
      && nowMillis - lastClaimedMillis < 10 * 60 * 1000
    ) {
      return null;
    }
    const nextSentCount = (due.sentCount || 0) + 1;
    transaction.set(
      preferenceReference,
      {
        ...due.preference,
        hikeId,
        ownerUserId: userId,
        ownerPhoneNumber: phoneNumber,
        departureTimeLocal: new Date(departureMillis).toISOString(),
        deliveryClaimedAt: admin.firestore.FieldValue.serverTimestamp(),
        deliveryClaimedAtLocal: new Date(nowMillis).toISOString(),
        deliveryClaimSequence: nextSentCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: new Date(nowMillis).toISOString(),
      },
      { merge: true }
    );
    return {
      preferenceReference,
      minutesUntil: due.minutesUntil,
      nextSentCount,
    };
  });
}

// Legacy scheduled/team documents may predate the shared-plan projection and
// contain a member's emergency settings or checklist. Progress cursors keep
// both reads and writes bounded; 399 document updates plus the state document
// remain below Firestore's 500-write batch ceiling (and the requested 400 cap).
exports.redactLegacySharedHikeDrafts = onSchedule(
  'every 15 minutes',
  async () => {
    const db = admin.firestore();
    const stateReference = db
      .collection('maintenanceState')
      .doc('sharedHikePlanPrivacyV1');
    const stateSnapshot = await stateReference.get();
    const state = stateSnapshot.data() || {};
    if (state.upcomingComplete === true && state.teamComplete === true) {
      return;
    }

    const batch = db.batch();
    const statePatch = {};
    let documentWriteCount = 0;
    let scannedCount = 0;

    const processCollection = async ({
      collectionName,
      cursorField,
      completeField,
    }) => {
      if (state[completeField] === true || documentWriteCount >= 399) {
        return;
      }
      const pageLimit = 399 - documentWriteCount;
      let query = db
        .collection(collectionName)
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(pageLimit);
      const cursor = String(state[cursorField] || '').trim();
      if (cursor) {
        query = query.startAfter(cursor);
      }
      const snapshot = await query.get();
      let lastProcessedId = cursor;
      for (const document of snapshot.docs) {
        const data = document.data() || {};
        const rawDraft = data.draft;
        const storedPrivacyVersion = Number(
          data.sharedHikePlanPrivacyVersion
        );
        const needsVersionUpgrade = !Number.isFinite(storedPrivacyVersion)
          || storedPrivacyVersion < SHARED_HIKE_PLAN_PRIVACY_VERSION;
        const needsMigration =
          needsVersionUpgrade
          || sharedHikePlanNeedsRedaction(rawDraft);
        if (needsMigration) {
          const patch = {
            sharedHikePlanPrivacyVersion: needsVersionUpgrade
              ? SHARED_HIKE_PLAN_PRIVACY_VERSION
              : storedPrivacyVersion,
            sharedHikePlanRedactedAt:
              admin.firestore.FieldValue.serverTimestamp(),
            sharedHikePlanRedactedAtLocal: new Date().toISOString(),
          };
          if (
            rawDraft
            && typeof rawDraft === 'object'
            && !Array.isArray(rawDraft)
          ) {
            // update() replaces the top-level draft map, so omitted personal
            // keys are deleted instead of surviving a recursive merge.
            patch.draft = projectedLegacySharedHikePlan(rawDraft);
          } else if (rawDraft != null) {
            // A malformed legacy value cannot contain a usable shared plan.
            // Delete it so the cursor does not leave an unredacted value behind.
            patch.draft = admin.firestore.FieldValue.delete();
          }
          batch.update(document.ref, patch);
          documentWriteCount += 1;
        }
        scannedCount += 1;
        lastProcessedId = document.id;
      }
      statePatch[cursorField] = lastProcessedId;
      statePatch[completeField] = snapshot.size < pageLimit;
    };

    await processCollection({
      collectionName: 'upcomingHikes',
      cursorField: 'upcomingCursor',
      completeField: 'upcomingComplete',
    });
    const upcomingIsComplete = state.upcomingComplete === true
      || statePatch.upcomingComplete === true;
    if (upcomingIsComplete && documentWriteCount < 399) {
      await processCollection({
        collectionName: 'teamHikeSessions',
        cursorField: 'teamCursor',
        completeField: 'teamComplete',
      });
    }

    batch.set(
      stateReference,
      {
        migrationVersion: SHARED_HIKE_PLAN_PRIVACY_VERSION,
        ...statePatch,
        lastRunScannedCount: scannedCount,
        lastRunDocumentWriteCount: documentWriteCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtLocal: new Date().toISOString(),
      },
      { merge: true }
    );
    await batch.commit();
    logger.log(
      `Shared hike draft privacy migration scanned ${scannedCount} and redacted ${documentWriteCount} documents.`
    );
  }
);

exports.processUpcomingHikeLifecycle = onSchedule(
  'every 5 minutes',
  async () => {
    const db = admin.firestore();
    const now = Date.now();
    const expiredBefore = now - 60 * 60 * 1000;
    const snapshot = await db.collection('upcomingHikes').get();

    let hiddenCount = 0;
    let reminderHikeCount = 0;
    let reminderSuccessCount = 0;
    let reminderFailureCount = 0;

    for (const document of snapshot.docs) {
      const hike = document.data() || {};
      if (hike.isDeleted === true) {
        continue;
      }
      const departureMillis = dateMillis(
        hike.departureTimeLocal || hike.departureTime
      );
      if (!Number.isFinite(departureMillis)) {
        continue;
      }

      if (departureMillis <= expiredBefore) {
        await document.ref.set(
          {
            isDeleted: true,
            deletedReason: 'departure_time_expired',
            deletedAt: admin.firestore.FieldValue.serverTimestamp(),
            deletedAtLocal: new Date(now).toISOString(),
          },
          { merge: true }
        );
        hiddenCount++;
        continue;
      }

      const phones = new Set();
      const creatorPhone = String(hike.creatorPhone || '').trim();
      if (creatorPhone) {
        phones.add(creatorPhone);
      }
      if (Array.isArray(hike.participantPhones)) {
        for (const phone of hike.participantPhones) {
          const normalized = String(phone || '').trim();
          if (normalized) {
            phones.add(normalized);
          }
        }
      }
      if (phones.size === 0) {
        continue;
      }

      let hikeHadDueReminder = false;
      for (const phone of phones) {
        const claim = await claimUpcomingHikeReminder({
          db,
          hikeReference: document.ref,
          hikeId: document.id,
          hike,
          phoneNumber: phone,
          departureMillis,
          nowMillis: now,
        });
        if (!claim) continue;
        hikeHadDueReminder = true;
        const result = await sendUpcomingHikeReminderToPhone(
          db,
          document.id,
          hike,
          phone,
          claim.minutesUntil
        );
        reminderSuccessCount += result.successCount;
        reminderFailureCount += result.failureCount;
        await claim.preferenceReference.set(
          {
            sentCount: claim.nextSentCount,
            lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
            lastSentAtLocal: new Date(now).toISOString(),
            lastDeliveryStatus: result.skipped
              ? 'no_registered_device'
              : result.failureCount > 0 && result.successCount === 0
                ? 'failed'
                : result.failureCount > 0
                  ? 'partial'
                  : 'sent',
            lastDeliverySuccessCount: result.successCount,
            lastDeliveryFailureCount: result.failureCount,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAtLocal: new Date(now).toISOString(),
          },
          { merge: true }
        );
      }
      if (hikeHadDueReminder) reminderHikeCount++;
    }

    logger.log(
      `Upcoming hike lifecycle: hidden ${hiddenCount}, reminded ${reminderHikeCount} hikes, ${reminderSuccessCount} sent, ${reminderFailureCount} failed.`
    );
  }
);

exports.cleanExpiredUpcomingHikes = onSchedule('every 60 minutes', async () => {
  const db = admin.firestore();
  const expiredBefore = Date.now() - 15 * 60 * 1000;
  const snapshot = await db.collection('upcomingHikes').get();
  let deletedCount = 0;

  for (const document of snapshot.docs) {
    const hike = document.data() || {};
    const departureMillis = dateMillis(
      hike.departureTimeLocal || hike.departureTime
    );
    if (!Number.isFinite(departureMillis) || departureMillis > expiredBefore) {
      continue;
    }

    await document.ref.delete();
    deletedCount++;
  }

  logger.log(`Deleted ${deletedCount} expired upcoming hike documents.`);
});

exports.checkActiveHikeMonitoringHeartbeats = onSchedule(
  'every 1 minutes',
  async () => {
    const snapshot = await admin
      .firestore()
      .collection('hikeSessions')
      .where('status', '==', 'active')
      .get();
    const staleBefore = Date.now() - 5 * 60 * 1000;
    let reminderCount = 0;

    for (const document of snapshot.docs) {
      const data = document.data();
      if (data.monitoringExpected !== true) {
        continue;
      }

      const heartbeat = data.monitoringHeartbeatAt;
      const heartbeatMillis =
        heartbeat && typeof heartbeat.toDate === 'function'
          ? heartbeat.toDate().getTime()
          : Date.parse(data.monitoringHeartbeatAtLocal || '');
      if (!Number.isFinite(heartbeatMillis) || heartbeatMillis >= staleBefore) {
        continue;
      }

      // Re-read the document to verify the hike is still active and not completed.
      const freshSnapshot = await document.ref.get();
      const freshData = freshSnapshot.data();
      if (!freshData || freshData.status !== 'active') {
        continue;
      }

      await updateTeamParticipantForHike(freshData, 'offline');

      if (
        await sendActiveHikeReopenReminder(
          document.ref,
          freshData,
          'heartbeat_stale'
        )
      ) {
        reminderCount++;
      }
    }
    logger.log(`Sent ${reminderCount} stale hike monitoring reminders.`);
  }
);

// ─── Stale Hike Session Cleaner ──────────────────────────────────
// Runs every 15 minutes to find and clean up hike sessions that are stuck
// in 'active' status but no longer have an active monitoring loop.

// Scheduled safety check-ins are driven by the backend so reminders still
// arrive when Flutter timers are suspended in the background.
exports.sendScheduledActiveHikeCheckIns = onSchedule(
  'every 1 minutes',
  async () => {
    const snapshot = await admin
      .firestore()
      .collection('hikeSessions')
      .where('status', '==', 'active')
      .get();
    const now = Date.now();
    let sentCount = 0;

    for (const document of snapshot.docs) {
      const claimedHike = await admin.firestore().runTransaction(
        async (transaction) => {
          const freshSnapshot = await transaction.get(document.ref);
          const hike = freshSnapshot.data() || {};
          const token = String(hike.monitoringFcmToken || '').trim();
          if (
            !freshSnapshot.exists
            || String(hike.status || '') !== 'active'
            || !token
          ) {
            return null;
          }
          const configuredSeconds = Number(
            hike.safetyCheckInIntervalSeconds
              || Number(hike.safetyCheckInIntervalMinutes || 0) * 60
          );
          if (!Number.isFinite(configuredSeconds) || configuredSeconds < 60) {
            return null;
          }
          const intervalMillis =
            Math.min(configuredSeconds, 6 * 60 * 60) * 1000;
          const anchorCandidates = [
            dateMillis(hike.lastCheckInAt),
            dateMillis(hike.lastCheckInAtLocal),
            dateMillis(hike.startedAt),
            dateMillis(hike.startedAtLocal),
          ].filter(Number.isFinite);
          const anchorMillis = anchorCandidates.length > 0
            ? Math.max(...anchorCandidates)
            : Number.NaN;
          if (
            !Number.isFinite(anchorMillis)
            || now - anchorMillis < intervalMillis
          ) {
            return null;
          }
          const reminderCandidates = [
            dateMillis(hike.lastScheduledCheckInReminderAt),
            dateMillis(hike.lastScheduledCheckInReminderAtLocal),
            dateMillis(hike.lastScheduledCheckInReminderClaimedAt),
            dateMillis(hike.lastScheduledCheckInReminderClaimedAtLocal),
          ].filter(Number.isFinite);
          if (
            reminderCandidates.length > 0
            && now - Math.max(...reminderCandidates) < 10 * 60 * 1000
          ) {
            return null;
          }
          transaction.set(
            document.ref,
            {
              lastScheduledCheckInReminderClaimedAt:
                admin.firestore.FieldValue.serverTimestamp(),
              lastScheduledCheckInReminderClaimedAtLocal:
                new Date(now).toISOString(),
            },
            { merge: true }
          );
          return hike;
        }
      );
      const token = String(claimedHike?.monitoringFcmToken || '').trim();
      if (!token) {
        continue;
      }

      try {
        const deepLink =
          `hikercircle://hike/check-in?sessionId=${encodeURIComponent(document.id)}`;
        await admin.messaging().send({
          token,
          notification: {
            title: 'Scheduled hike check-in',
            body: 'Confirm that you are safe. Open HikerCircle to check in.',
          },
          data: {
            type: 'active_hike_scheduled_check_in',
            sessionId: document.id,
            deepLink,
          },
          android: {
            priority: 'high',
            notification: {
              channelId: 'hiker_circle_active_hike',
              priority: 'high',
            },
          },
          apns: {
            headers: { 'apns-priority': '10' },
            payload: { aps: { sound: 'default' } },
          },
        });
        await document.ref.set(
          {
            lastScheduledCheckInReminderAt:
              admin.firestore.FieldValue.serverTimestamp(),
            lastScheduledCheckInReminderAtLocal: new Date(now).toISOString(),
            lastScheduledCheckInReminderDeliveryStatus: 'sent',
          },
          { merge: true }
        );
        sentCount++;
      } catch (error) {
        await document.ref.set(
          {
            lastScheduledCheckInReminderDeliveryStatus:
              'delivery_uncertain',
            lastScheduledCheckInReminderError: String(
              error?.code || error?.name || 'fcm_transport_error'
            ).slice(0, 160),
          },
          { merge: true }
        ).catch(() => undefined);
        logger.error(
          `Unable to send check-in reminder for ${document.id}:`,
          error
        );
      }
    }
    logger.log(`Sent ${sentCount} scheduled active-hike check-in reminders.`);
  }
);

exports.cleanStaleHikeSessions = onSchedule('every 15 minutes', async () => {
  const snapshot = await admin
    .firestore()
    .collection('hikeSessions')
    .where('status', '==', 'active')
    .get();

  let cleanedCount = 0;
  const now = Date.now();

  for (const document of snapshot.docs) {
    const data = document.data();
    if (!shouldAbandonInactiveHike(data, now)) {
      continue;
    }
    const didAbandon = await admin.firestore().runTransaction(
      async (transaction) => {
        const freshSnapshot = await transaction.get(document.ref);
        const fresh = freshSnapshot.data() || {};
        if (
          !freshSnapshot.exists
          || String(fresh.status || '') !== 'active'
          || !shouldAbandonInactiveHike(fresh, Date.now())
        ) {
          return false;
        }
        const nowIso = new Date().toISOString();
        transaction.set(
          document.ref,
          {
            status: 'abandoned',
            monitoringExpected: false,
            monitoringLifecycleState: 'abandoned',
            abandonedAt: admin.firestore.FieldValue.serverTimestamp(),
            abandonedAtLocal: nowIso,
            abandonmentReason: 'heartbeat_stale_past_expected_return_grace',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAtLocal: nowIso,
          },
          { merge: true }
        );
        return true;
      }
    );
    if (!didAbandon) {
      continue;
    }
    await updateTeamParticipantForHike(data, 'ended');
    cleanedCount++;
    logger.log(`Cleaned stale hike session ${document.id} after its return grace.`);
  }

  logger.log(`Cleaned ${cleanedCount} stale hike sessions.`);
});

exports.cleanExpiredGroupChats = onSchedule('every 60 minutes', async () => {
  const db = admin.firestore();
  const now = Date.now();
  const nowIso = new Date(now).toISOString();
  const orphanThreshold = now - 60 * 60 * 1000;

  const snapshot = await db
    .collection('groupChats')
    .where('chatType', '==', 'group')
    .get();

  let deletedCount = 0;
  let noticeCount = 0;

  for (const document of snapshot.docs) {
    const chat = document.data() || {};
    if (chat.isDeleted === true) {
      continue;
    }

    const removesAt = dateMillis(chat.chatRemovesAtLocal);
    if (Number.isFinite(removesAt) && removesAt <= now) {
      await document.ref.set(
        {
          isDeleted: true,
          deletedAt: admin.firestore.FieldValue.serverTimestamp(),
          deletedAtLocal: nowIso,
        },
        { merge: true }
      );
      deletedCount++;
      continue;
    }

    if (chat.chatRemovesAtLocal || chat.hikeEndedAtLocal) {
      continue;
    }

    const createdAt = dateMillis(chat.createdAtLocal || chat.createdAt);
    if (!Number.isFinite(createdAt) || createdAt > orphanThreshold) {
      continue;
    }

    const hikeSessionId = String(chat.hikeSessionId || '').trim();
    const teamHikeSessionId = String(chat.teamHikeSessionId || '').trim();
    let hasAssociatedHike = false;

    if (hikeSessionId) {
      const [upcomingSnapshot, activeSnapshot, sourcedActiveSnapshot] = await Promise.all([
        db.collection('upcomingHikes').doc(hikeSessionId).get(),
        db.collection('hikeSessions').doc(hikeSessionId).get(),
        db.collection('hikeSessions')
          .where('sourceUpcomingHikeId', '==', hikeSessionId)
          .limit(20)
          .get(),
      ]);
      hasAssociatedHike = upcomingSnapshot.exists
        || activeSnapshot.exists
        || sourcedActiveSnapshot.docs.some(
          (snapshot) => String(snapshot.data()?.status || '') === 'active'
        );
    }

    if (!hasAssociatedHike && teamHikeSessionId) {
      const teamSnapshot = await db
        .collection('teamHikeSessions')
        .doc(teamHikeSessionId)
        .get();
      hasAssociatedHike = teamSnapshot.exists;
    }

    if (hasAssociatedHike) {
      continue;
    }

    const started = await startGroupChatClosure(
      db,
      document,
      'no_upcoming_hike',
      'No upcoming hike is associated to this chat, chat will be ended and removed on'
    );
    if (started) {
      noticeCount++;
    }
  }

  logger.log(
    `Group chat cleaner marked ${deletedCount} deleted and started ${noticeCount} closure notices.`
  );
});

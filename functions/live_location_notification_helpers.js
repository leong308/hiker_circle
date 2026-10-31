// Emergency-contact live-location notices validate share identity and use deterministic dispatch IDs.
'use strict';

const crypto = require('crypto');
const { formatSosDateTime } = require('./sos_dispatch_helpers');
const {SHIRT_COLORS, normalizeShirtColor} = require('./hike_shirt_color');

class LiveLocationNotificationValidationError extends Error {}

function normalizeLine(value, maxLength) {
  return String(value || '')
    .replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029\u202a-\u202e\u2066-\u2069]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, maxLength);
}

// parseLiveLocationNotificationRequest: Validate the share/contact request before any message can be dispatched.
function parseLiveLocationNotificationRequest(data) {
  const payload = data && typeof data === 'object' && !Array.isArray(data)
    ? data
    : {};
  const sessionId = String(payload.sessionId || '').trim();
  const shareId = String(payload.shareId || '').trim();
  const standalone = payload.mode === 'standalone';
  if (
    (payload.mode != null && payload.mode !== 'hike' && !standalone)
    || (standalone ? payload.sessionId != null : !/^[A-Za-z0-9_-]{8,240}$/.test(sessionId))
    || !/^[A-Za-z0-9_-]{8,240}$/.test(shareId)
  ) {
    throw new LiveLocationNotificationValidationError(
      'The live location notification request is invalid.'
    );
  }
  return standalone ? { mode: 'standalone', shareId } : { sessionId, shareId };
}

// liveLocationDispatchDocumentId: Use deterministic share/contact identity so retries cannot create a second notice.
function liveLocationDispatchDocumentId(uid, sessionId, recipientPhone) {
  return crypto
    .createHash('sha256')
    .update(`${uid}:${sessionId}:${recipientPhone}`)
    .digest('hex');
}

function composeLiveLocationStartMessage({
  hikerName,
  ownerPhone,
  trailName,
  startedAt,
  shareUrl,
  shirtColor,
}) {
  const safeName = normalizeLine(hikerName, 80) || 'A HikerCircle user';
  const safeTrail = normalizeLine(trailName, 160) || 'a hike';
  const safePhone = normalizeLine(ownerPhone, 24);
  const safeStartedAt = normalizeLine(startedAt, 120) || 'just now';
  const safeShareUrl = String(shareUrl || '').trim();
  if (!/^https:\/\/hiker-circle\.web\.app\/live-location\?share=[A-Za-z0-9_-]{8,240}$/.test(safeShareUrl)) {
    throw new LiveLocationNotificationValidationError(
      'The live location link is invalid.'
    );
  }
  return [
    '🥾 *HikerCircle hike started*',
    '',
    `${safeName} has started ${safeTrail}.`,
    safePhone ? `Hiker phone: ${safePhone}` : '',
    `Started: ${safeStartedAt}`,
    normalizeShirtColor(shirtColor) ? `Shirt colour: ${SHIRT_COLORS[shirtColor]}` : '',
    '',
    '📍 Follow their live location:',
    safeShareUrl,
    '',
    'This is an automatic safety update, not an SOS alert. The link stops when the hike ends or its current expiry time is reached. Sharing the link again renews it for 24 hours.',
  ].filter((line) => line !== '').join('\n');
}

// Original server-owned share creation is stable across activation retries and GPS updates.
// Shares created before the explicit start field use their initial 24-hour expiry.
function originalLiveLocationStartedAtMillis({ share, user, expiresAtMillis, nowMillis = Date.now() }) {
  const millis = (value) => {
    if (value && typeof value.toMillis === 'function') return value.toMillis();
    if (value && typeof value.toDate === 'function') return value.toDate().getTime();
    return typeof value === 'number' ? value : typeof value === 'string' ? Date.parse(value) : NaN;
  };
  const candidates = [
    share.createdAtLocal,
    share.createdAt,
    user.liveLocationStartedAt,
    user.liveLocationStartedAtLocal,
    expiresAtMillis - 24 * 3600000,
  ];
  const started = candidates.map(millis).find((value) =>
    Number.isFinite(value) && value > 0 && value <= nowMillis && value < expiresAtMillis);
  if (started === undefined) {
    throw new LiveLocationNotificationValidationError('The original live location start time is unavailable.');
  }
  return started;
}

function composeStandaloneLiveLocationStartMessage({
  hikerName,
  ownerPhone,
  startedAtMillis,
  preferredTimeZone,
  shareUrl,
}) {
  const safeName = normalizeLine(hikerName, 80) || 'A HikerCircle user';
  const safePhone = normalizeLine(ownerPhone, 24);
  const safeShareUrl = String(shareUrl || '').trim();
  if (!/^https:\/\/hiker-circle\.web\.app\/live-location\?share=[A-Za-z0-9_-]{8,240}$/.test(safeShareUrl)
      || !Number.isFinite(startedAtMillis)) {
    throw new LiveLocationNotificationValidationError('The live location notice is invalid.');
  }
  return [
    '📍 *HikerCircle Live Location*',
    `${safeName} has started sharing live location.`,
    safePhone ? `Hiker phone: ${safePhone}` : '',
    `Started: ${formatSosDateTime(startedAtMillis, preferredTimeZone)}`,
    'Follow their live location:',
    safeShareUrl,
    'This is an automatic safety update, not an SOS alert. The link stops when location sharing is turned off or its current expiry time is reached. Sharing the link again renews it for 24 hours.',
  ].filter(Boolean).join('\n');
}

module.exports = {
  LiveLocationNotificationValidationError,
  composeLiveLocationStartMessage,
  composeStandaloneLiveLocationStartMessage,
  liveLocationDispatchDocumentId,
  parseLiveLocationNotificationRequest,
  originalLiveLocationStartedAtMillis,
};

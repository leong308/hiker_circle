'use strict';

const crypto = require('crypto');

class LiveLocationNotificationValidationError extends Error {}

function normalizeLine(value, maxLength) {
  return String(value || '')
    .replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029\u202a-\u202e\u2066-\u2069]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, maxLength);
}

function parseLiveLocationNotificationRequest(data) {
  const payload = data && typeof data === 'object' && !Array.isArray(data)
    ? data
    : {};
  const sessionId = String(payload.sessionId || '').trim();
  const shareId = String(payload.shareId || '').trim();
  if (
    !/^[A-Za-z0-9_-]{8,240}$/.test(sessionId)
    || !/^[A-Za-z0-9_-]{8,240}$/.test(shareId)
  ) {
    throw new LiveLocationNotificationValidationError(
      'The live location notification request is invalid.'
    );
  }
  return { sessionId, shareId };
}

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
    '',
    '📍 Follow their live location:',
    safeShareUrl,
    '',
    'This is an automatic safety update, not an SOS alert. The link stops when the hike ends or expires after 24 hours.',
  ].filter((line) => line !== '').join('\n');
}

module.exports = {
  LiveLocationNotificationValidationError,
  composeLiveLocationStartMessage,
  liveLocationDispatchDocumentId,
  parseLiveLocationNotificationRequest,
};

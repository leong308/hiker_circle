// SOS payload validation, message composition, and deterministic dispatch hashes protect emergency delivery semantics.
'use strict';

const crypto = require('crypto');
const {SHIRT_COLORS, normalizeShirtColor} = require('./hike_shirt_color');

const SOS_MODES = new Set([
  'manual',
  'medical',
  'fall_stillness',
  'prolonged_stillness',
  'duress',
  'test',
]);

const SOS_TRIGGER_SOURCES = new Set([
  'mobile_phone',
  'emergency_button',
  'automatic_detection',
]);

const DEFAULT_SOS_TIME_ZONE = 'Asia/Singapore';

const SOS_REASONS = Object.freeze({
  medical: 'Medical help was requested from HikerCircle.',
  fall_stillness:
    'A possible fall followed by stillness was detected and escalated.',
  prolonged_stillness:
    'Location and phone movement remained still beyond the selected safe rest time.',
  duress:
    'A silent duress SOS was triggered. Avoid calling if that may increase risk.',
});

const DEFAULT_NOTE =
  'I need urgent help during my hike. Please call me now. If I do not answer, use the map link below and contact local emergency services.';
const DEFAULT_DURESS_NOTE =
  'I may be under pressure and cannot speak safely. Please monitor my location discreetly and contact local emergency services if I stop responding.';

class SosDispatchValidationError extends Error {}

function normalizeText(value, maxLength) {
  return String(value || '')
    .replace(
      /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f\u2028\u2029\u202a-\u202e\u2066-\u2069]/g,
      ''
    )
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, maxLength);
}

function normalizeSosTimeZone(value) {
  const storedTimeZone = String(value || '').trim();
  const timeZone = storedTimeZone === 'Asia/Kuching'
    ? 'Asia/Kuala_Lumpur' : storedTimeZone;
  if (!timeZone || timeZone.length > 80) return DEFAULT_SOS_TIME_ZONE;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone }).format(new Date(0));
    return timeZone;
  } catch (_) {
    return DEFAULT_SOS_TIME_ZONE;
  }
}

function timeZoneOffsetLabel(date, timeZone) {
  const part = new Intl.DateTimeFormat('en-US', {
    timeZone,
    timeZoneName: 'longOffset',
  }).formatToParts(date).find((item) => item.type === 'timeZoneName');
  const raw = String(part?.value || 'GMT+08:00');
  if (raw === 'GMT') return 'GMT+0';
  const match = /^GMT([+-])(\d{1,2})(?::(\d{2}))?$/.exec(raw);
  if (!match) return raw;
  const hours = String(Number(match[2]));
  return !match[3] || match[3] === '00'
    ? `GMT${match[1]}${hours}`
    : `GMT${match[1]}${hours}:${match[3]}`;
}

function formatSosDateTime(triggeredAtMillis, preferredTimeZone) {
  const date = new Date(triggeredAtMillis);
  const timeZone = normalizeSosTimeZone(preferredTimeZone);
  const values = Object.fromEntries(
    new Intl.DateTimeFormat('en-US', {
      timeZone,
      day: 'numeric',
      month: 'short',
      year: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
      second: '2-digit',
      hour12: true,
    }).formatToParts(date).map((part) => [part.type, part.value])
  );
  return `${values.day} ${values.month} ${values.year}, `
    + `${values.hour}:${values.minute}:${values.second} ${values.dayPeriod} `
    + `(${timeZoneOffsetLabel(date, timeZone)} · ${timeZone})`;
}

function reasonForSos(mode, triggerSource) {
  if (mode === 'manual') {
    return triggerSource === 'emergency_button'
      ? 'User triggered SOS through an emergency button.'
      : 'User triggered SOS through mobile phone.';
  }
  return SOS_REASONS[mode];
}

// parseSosDispatchRequest: Bound emergency contact, coordinate, device, and timing inputs before delivery.
function parseSosDispatchRequest(data, nowMillis = Date.now()) {
  const payload = data && typeof data === 'object' && !Array.isArray(data)
    ? data
    : {};
  const recipientPhone = String(payload.phoneNumber || '').trim();
  const dispatchId = String(payload.dispatchId || '').trim();
  const mode = String(payload.mode || '').trim();
  const isTest = payload.isTest === true;
  const triggerSource = String(
    payload.triggerSource
      || (mode === 'manual' || mode === 'test'
        ? 'mobile_phone'
        : 'automatic_detection')
  ).trim();
  if (!/^\+[1-9]\d{7,14}$/.test(recipientPhone)) {
    throw new SosDispatchValidationError('The emergency contact number is invalid.');
  }
  if (!/^[A-Za-z0-9_-]{8,180}$/.test(dispatchId)) {
    throw new SosDispatchValidationError('The SOS dispatch id is invalid.');
  }
  if (!SOS_MODES.has(mode) || (mode === 'test') !== isTest) {
    throw new SosDispatchValidationError('The SOS mode is invalid.');
  }
  if (!SOS_TRIGGER_SOURCES.has(triggerSource)) {
    throw new SosDispatchValidationError('The SOS trigger source is invalid.');
  }

  const triggeredAtMillis = Date.parse(String(payload.triggeredAtLocal || ''));
  const maxAgeMillis = isTest ? 10 * 60 * 1000 : 24 * 60 * 60 * 1000;
  if (
    !Number.isFinite(triggeredAtMillis)
    || triggeredAtMillis < nowMillis - maxAgeMillis
    || triggeredAtMillis > nowMillis + 2 * 60 * 1000
  ) {
    throw new SosDispatchValidationError('The SOS trigger time is invalid.');
  }

  const hasLatitude = payload.latitude !== undefined && payload.latitude !== null;
  const hasLongitude = payload.longitude !== undefined && payload.longitude !== null;
  if (hasLatitude !== hasLongitude) {
    throw new SosDispatchValidationError('The SOS location is incomplete.');
  }
  let location = null;
  if (hasLatitude) {
    const latitude = Number(payload.latitude);
    const longitude = Number(payload.longitude);
    const accuracyMeters = payload.accuracyMeters === undefined
      || payload.accuracyMeters === null
      ? null
      : Number(payload.accuracyMeters);
    if (
      !Number.isFinite(latitude)
      || latitude < -90
      || latitude > 90
      || !Number.isFinite(longitude)
      || longitude < -180
      || longitude > 180
      || (accuracyMeters !== null
        && (!Number.isFinite(accuracyMeters)
          || accuracyMeters < 0
          || accuracyMeters > 10000))
    ) {
      throw new SosDispatchValidationError('The SOS location is invalid.');
    }
    location = { latitude, longitude, accuracyMeters };
  }

  const rawCustomNote = normalizeText(payload.customNote, 1000);
  if (rawCustomNote.length > 240) {
    throw new SosDispatchValidationError('The SOS note is too long.');
  }
  return {
    recipientPhone,
    dispatchId,
    mode,
    isTest,
    triggerSource,
    triggeredAtMillis,
    customNote: rawCustomNote,
    location,
    ...(normalizeShirtColor(payload.shirtColor) && !isTest
      ? {shirtColor: normalizeShirtColor(payload.shirtColor)} : {}),
  };
}

// composeSosMessage: Compose only validated details using the selected local timezone.
function composeSosMessage({
  ownerPhone,
  mode,
  isTest,
  triggeredAtMillis,
  customNote,
  location,
  shirtColor,
  triggerSource = 'mobile_phone',
  preferredTimeZone = DEFAULT_SOS_TIME_ZONE,
}) {
  const triggeredAt = formatSosDateTime(
    triggeredAtMillis,
    preferredTimeZone
  );
  if (isTest) {
    return [
      '🧪 *HikerCircle Messaging Test*',
      '',
      `📞 *Hiker*\n${ownerPhone}`,
      '',
      `🕒 *Sent*\n${triggeredAt}`,
      '',
      'This is not an emergency. The hiker is testing cloud messaging before a hike; no action is required.',
    ].join('\n');
  }
  const locationLine = location
    ? `https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}`
    : 'Location unavailable';
  const accuracyLine = location?.accuracyMeters === null
    || location?.accuracyMeters === undefined
      ? null
      : `Estimated accuracy: within ${Math.round(location.accuracyMeters)} m`;
  const action = mode === 'duress'
    ? 'Do not call if that may increase danger. Discreetly share this alert and location with emergency responders.'
    : 'Call the hiker first. If there is no response, share this alert and map link with emergency responders.';
  return [
    '🚨 *HikerCircle SOS Alert*',
    '',
    `📞 *Hiker*\n${ownerPhone}`,
    '',
    `🕒 *Triggered*\n${triggeredAt}`,
    '',
    `⚠️ *Reason*\n${reasonForSos(mode, triggerSource)}`,
    '',
    ...(normalizeShirtColor(shirtColor) ? [`👕 *Shirt colour*\n${SHIRT_COLORS[shirtColor]}`, ''] : []),
    `📍 *Location*\n${locationLine}`,
    ...(accuracyLine ? [accuracyLine] : []),
    '',
    `💬 *Hiker's message*\n${customNote || (mode === 'duress' ? DEFAULT_DURESS_NOTE : DEFAULT_NOTE)}`,
    '',
    `✅ *What to do*\n${action}`,
  ].join('\n');
}

function sosDispatchDocumentId(uid, dispatchId, recipientPhone) {
  return crypto
    .createHash('sha256')
    .update(`${uid}:${dispatchId}:${recipientPhone}`)
    .digest('hex');
}

function sosDispatchPayloadHash(dispatch) {
  const location = dispatch.location
    ? [
        dispatch.location.latitude,
        dispatch.location.longitude,
        dispatch.location.accuracyMeters,
      ]
    : null;
  const canonicalPayload = [
    dispatch.recipientPhone,
    dispatch.dispatchId,
    dispatch.mode,
    dispatch.isTest === true,
    dispatch.triggerSource,
    dispatch.triggeredAtMillis,
    dispatch.customNote,
    location,
  ];
  // Preserve legacy hashes exactly when the optional clothing snapshot is absent.
  if (normalizeShirtColor(dispatch.shirtColor) && dispatch.isTest !== true) canonicalPayload.push({shirtColor: dispatch.shirtColor});
  return crypto
    .createHash('sha256')
    .update(JSON.stringify(canonicalPayload))
    .digest('hex');
}

// classifySosProviderHttpFailure: Separate definite rejection from provider outcomes that may already have accepted the message.
function classifySosProviderHttpFailure(statusCode) {
  const status = Number(statusCode);
  const deliveryUncertain = status === 408 || status >= 500;
  return {
    status: deliveryUncertain ? 'delivery_uncertain' : 'failed',
    retryable: !deliveryUncertain && (status === 425 || status === 429),
    deliveryUncertain,
  };
}

module.exports = {
  DEFAULT_NOTE,
  DEFAULT_DURESS_NOTE,
  DEFAULT_SOS_TIME_ZONE,
  SosDispatchValidationError,
  composeSosMessage,
  formatSosDateTime,
  classifySosProviderHttpFailure,
  parseSosDispatchRequest,
  normalizeSosTimeZone,
  sosDispatchDocumentId,
  sosDispatchPayloadHash,
};

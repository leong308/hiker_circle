'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  SosDispatchValidationError,
  classifySosProviderHttpFailure,
  composeSosMessage,
  formatSosDateTime,
  normalizeSosTimeZone,
  parseSosDispatchRequest,
  sosDispatchDocumentId,
  sosDispatchPayloadHash,
} = require('../sos_dispatch_helpers');

const now = Date.parse('2026-08-04T10:00:00.000Z');

test('parses and bounds a structured SOS request', () => {
  const request = parseSosDispatchRequest({
    phoneNumber: '+60123456789',
    dispatchId: 'manual_123456789_60123456789',
    mode: 'manual',
    triggerSource: 'emergency_button',
    triggeredAtLocal: '2026-08-04T09:59:00.000Z',
    latitude: 3.139,
    longitude: 101.6869,
    accuracyMeters: 12.4,
    customNote: 'Please contact the ranger.',
    isTest: false,
  }, now);

  assert.equal(request.mode, 'manual');
  assert.equal(request.triggerSource, 'emergency_button');
  assert.equal(request.location.latitude, 3.139);
  assert.equal(request.customNote, 'Please contact the ranger.');
});

test('rejects arbitrary text-only and stale dispatch payloads', () => {
  assert.throws(
    () => parseSosDispatchRequest({
      phoneNumber: '+60123456789',
      message: 'arbitrary provider text',
    }, now),
    SosDispatchValidationError
  );
  assert.throws(
    () => parseSosDispatchRequest({
      phoneNumber: '+60123456789',
      dispatchId: 'manual_123456789_60123456789',
      mode: 'manual',
      triggeredAtLocal: '2026-08-01T09:59:00.000Z',
      isTest: false,
    }, now),
    /trigger time/
  );
});

test('duress message does not instruct the contact to call', () => {
  const message = composeSosMessage({
    ownerPhone: '+60111111111',
    mode: 'duress',
    isTest: false,
    triggeredAtMillis: now,
    customNote: '',
    location: null,
  });

  assert.match(message, /Do not call/);
  assert.doesNotMatch(message, /call (?:me|the hiker)/i);
});

test('manual SOS message uses saved timezone and mobile trigger wording', () => {
  const message = composeSosMessage({
    ownerPhone: '+60111111111',
    mode: 'manual',
    isTest: false,
    triggeredAtMillis: Date.parse('2026-08-18T13:50:34.313Z'),
    customNote: '',
    location: { latitude: 5.3032197, longitude: 100.2704058, accuracyMeters: 100 },
    triggerSource: 'mobile_phone',
    preferredTimeZone: 'Asia/Singapore',
  });

  assert.match(message, /18 Aug 2026, 9:50:34 PM \(GMT\+8 · Asia\/Singapore\)/);
  assert.match(message, /User triggered SOS through mobile phone\./);
  assert.doesNotMatch(message, /Type:/);
  assert.doesNotMatch(message, /13:50:34\.313Z/);
  assert.match(message, /\*Triggered\*/);
  assert.match(message, /\*What to do\*/);
});

test('emergency-button SOS is clearly distinguished', () => {
  const message = composeSosMessage({
    ownerPhone: '+60111111111',
    mode: 'manual',
    isTest: false,
    triggeredAtMillis: now,
    customNote: '',
    location: null,
    triggerSource: 'emergency_button',
    preferredTimeZone: 'Asia/Singapore',
  });

  assert.match(message, /User triggered SOS through an emergency button\./);
  assert.doesNotMatch(message, /through mobile phone/);
});

test('invalid or missing timezone safely falls back to GMT+8', () => {
  assert.equal(normalizeSosTimeZone('not/a real timezone'), 'Asia/Singapore');
  assert.equal(normalizeSosTimeZone(''), 'Asia/Singapore');
  assert.match(formatSosDateTime(now, 'invalid'), /GMT\+8 · Asia\/Singapore/);
});

test('dispatch document id is deterministic and recipient-scoped', () => {
  const first = sosDispatchDocumentId('uid', 'dispatch_123', '+60111111111');
  const retry = sosDispatchDocumentId('uid', 'dispatch_123', '+60111111111');
  const other = sosDispatchDocumentId('uid', 'dispatch_123', '+60222222222');

  assert.equal(first, retry);
  assert.notEqual(first, other);
  assert.match(first, /^[a-f0-9]{64}$/);
});

test('dispatch payload hash rejects id reuse with altered emergency content', () => {
  const dispatch = parseSosDispatchRequest({
    phoneNumber: '+60123456789',
    dispatchId: 'manual_123456789_60123456789',
    mode: 'manual',
    triggerSource: 'mobile_phone',
    triggeredAtLocal: '2026-08-04T09:59:00.000Z',
    latitude: 3.139,
    longitude: 101.6869,
    accuracyMeters: 12.4,
    customNote: 'Please contact the ranger.',
    isTest: false,
  }, now);

  const first = sosDispatchPayloadHash(dispatch);
  const retry = sosDispatchPayloadHash({ ...dispatch });
  const altered = sosDispatchPayloadHash({
    ...dispatch,
    customNote: 'Send help to a different location.',
  });

  assert.equal(first, retry);
  assert.notEqual(first, altered);
  assert.match(first, /^[a-f0-9]{64}$/);
});

test('custom notes cannot inject lines or bidirectional control text', () => {
  const dispatch = parseSosDispatchRequest({
    phoneNumber: '+60123456789',
    dispatchId: 'manual_123456789_60123456789',
    mode: 'manual',
    triggeredAtLocal: '2026-08-04T09:59:00.000Z',
    customNote: 'Safe\nAction:\u202e fake instruction',
    isTest: false,
  }, now);

  assert.equal(dispatch.customNote, 'Safe Action: fake instruction');
});

test('rejects an unrecognized trigger source', () => {
  assert.throws(
    () => parseSosDispatchRequest({
      phoneNumber: '+60123456789',
      dispatchId: 'manual_123456789_60123456789',
      mode: 'manual',
      triggerSource: 'client_supplied_label',
      triggeredAtLocal: '2026-08-04T09:59:00.000Z',
      isTest: false,
    }, now),
    /trigger source/
  );
});

test('ambiguous SOS provider responses are terminal to avoid duplicates', () => {
  for (const statusCode of [408, 500, 502, 503, 504]) {
    assert.deepEqual(classifySosProviderHttpFailure(statusCode), {
      status: 'delivery_uncertain',
      retryable: false,
      deliveryUncertain: true,
    });
  }
});

test('only explicit pre-enqueue throttling responses remain retryable', () => {
  for (const statusCode of [425, 429]) {
    assert.deepEqual(classifySosProviderHttpFailure(statusCode), {
      status: 'failed',
      retryable: true,
      deliveryUncertain: false,
    });
  }
  assert.deepEqual(classifySosProviderHttpFailure(400), {
    status: 'failed',
    retryable: false,
    deliveryUncertain: false,
  });
});

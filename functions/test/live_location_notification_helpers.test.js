'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  LiveLocationNotificationValidationError,
  composeLiveLocationStartMessage,
  liveLocationDispatchDocumentId,
  parseLiveLocationNotificationRequest,
} = require('../live_location_notification_helpers');

test('parses stable hike and share identifiers', () => {
  assert.deepEqual(
    parseLiveLocationNotificationRequest({
      sessionId: 'hike_12345678',
      shareId: 'share_12345678',
    }),
    { sessionId: 'hike_12345678', shareId: 'share_12345678' }
  );
});

test('rejects paths and short identifiers', () => {
  assert.throws(
    () => parseLiveLocationNotificationRequest({
      sessionId: '../hike',
      shareId: 'short',
    }),
    LiveLocationNotificationValidationError
  );
});

test('dispatch id is deterministic per contact and hike', () => {
  const first = liveLocationDispatchDocumentId(
    '+60123456789',
    'hike_12345678',
    '+60111111111'
  );
  const retry = liveLocationDispatchDocumentId(
    '+60123456789',
    'hike_12345678',
    '+60111111111'
  );
  const other = liveLocationDispatchDocumentId(
    '+60123456789',
    'hike_12345678',
    '+60222222222'
  );
  assert.equal(first, retry);
  assert.notEqual(first, other);
  assert.match(first, /^[a-f0-9]{64}$/);
});

test('message clearly distinguishes an automatic update from SOS', () => {
  const message = composeLiveLocationStartMessage({
    hikerName: 'Aina',
    ownerPhone: '+60123456789',
    trailName: 'Bukit Gasing Loop',
    startedAt: '1 Sep 2026, 4:00 PM (Asia/Kuala_Lumpur)',
    shareUrl:
      'https://hiker-circle.web.app/live-location?share=share_12345678',
  });
  assert.match(message, /Aina has started Bukit Gasing Loop/);
  assert.match(message, /not an SOS alert/i);
  assert.match(message, /expires after 24 hours/i);
});

test('message rejects a non-HikerCircle link', () => {
  assert.throws(
    () => composeLiveLocationStartMessage({
      hikerName: 'Aina',
      ownerPhone: '+60123456789',
      trailName: 'Trail',
      startedAt: 'now',
      shareUrl: 'https://example.com/live',
    }),
    LiveLocationNotificationValidationError
  );
});

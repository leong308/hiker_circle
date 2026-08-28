'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  joinRequestDocumentId,
  joinRequestLifecycle,
  upcomingHikeUnavailableReason,
} = require('../upcoming_hike_join_request_helpers');

const futureHike = {
  departureTimeLocal: '2030-01-01T08:00:00.000Z',
};

test('join request ids are deterministic and requester scoped', () => {
  const first = joinRequestDocumentId('hike_1', '+60123456789');
  assert.equal(first, joinRequestDocumentId('hike_1', '+60123456789'));
  assert.notEqual(first, joinRequestDocumentId('hike_1', '+60987654321'));
  assert.match(first, /^join_[a-f0-9]{48}$/);
});

test('accepted and rejected requests remain terminal', () => {
  assert.deepEqual(
    joinRequestLifecycle({ status: 'accepted' }, futureHike, 0),
    { status: 'accepted', reason: 'accepted' }
  );
  assert.deepEqual(
    joinRequestLifecycle({ status: 'rejected' }, futureHike, 0),
    { status: 'rejected', reason: 'rejected' }
  );
});

test('removed, started, and ended hikes expire a pending request', () => {
  assert.equal(upcomingHikeUnavailableReason(null, 0), 'hike_removed');
  assert.equal(
    upcomingHikeUnavailableReason({ ...futureHike, teamHikeSessionId: 'team_1' }, 0),
    'hike_started'
  );
  assert.deepEqual(
    joinRequestLifecycle(
      { status: 'pending' },
      { departureTimeLocal: '2025-01-01T08:00:00.000Z' },
      Date.parse('2025-01-01T10:00:00.000Z')
    ),
    { status: 'expired', reason: 'hike_ended' }
  );
});

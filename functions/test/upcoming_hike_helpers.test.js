'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { buildUpcomingHikePreview } = require('../upcoming_hike_helpers');

const now = Date.parse('2026-08-04T10:00:00.000Z');
const privateHike = {
  trailId: 'trail_1',
  trailName: 'Safe Ridge',
  latitude: 3.1,
  longitude: 101.6,
  area: 'Gombak',
  state: 'Selangor',
  distanceKm: 7,
  durationMinutes: 180,
  difficulty: 'Moderate',
  startPointName: 'Gate',
  destinationName: 'Summit',
  departureTimeLocal: '2026-08-04T11:00:00.000Z',
  expectedReturnTimeLocal: '2026-08-04T15:00:00.000Z',
  hikeType: 'team',
  participantCount: 2,
  creatorPhone: '+60111111111',
  creatorUserId: '+60111111111',
  creatorName: 'Host',
  participantPhones: ['+60111111111', '+60222222222'],
  creationKeyHash: 'secret-hash',
  draft: {
    emergencyContactNames: ['Private contact'],
    duressEnabled: true,
    completedChecklistItems: ['Water'],
    customCheckpoints: [{ latitude: 3.2, longitude: 101.7 }],
  },
  createdAtLocal: '2026-08-04T09:00:00.000Z',
};

test('public upcoming-hike preview strips private plan and member data', () => {
  const preview = buildUpcomingHikePreview(
    'upcoming_1',
    privateHike,
    '+60333333333',
    now
  );

  assert.ok(preview);
  assert.equal(preview.creatorPhone, '');
  assert.deepEqual(preview.participantPhones, []);
  for (const forbidden of ['draft', 'creatorUserId', 'creationKeyHash']) {
    assert.equal(Object.hasOwn(preview, forbidden), false);
  }
  assert.equal(JSON.stringify(preview).includes('Private contact'), false);
  assert.equal(JSON.stringify(preview).includes('+60111111111'), false);
  assert.equal(JSON.stringify(preview).includes('+60222222222'), false);
});

test('preview reveals only the caller own membership marker', () => {
  const preview = buildUpcomingHikePreview(
    'upcoming_1',
    privateHike,
    '+60222222222',
    now
  );

  assert.ok(preview);
  assert.equal(preview.creatorPhone, '');
  assert.deepEqual(preview.participantPhones, ['+60222222222']);
});

test('deleted and expired hikes are not returned', () => {
  assert.equal(
    buildUpcomingHikePreview(
      'upcoming_1',
      { ...privateHike, isDeleted: true },
      '+60333333333',
      now
    ),
    null
  );
  assert.equal(
    buildUpcomingHikePreview(
      'upcoming_1',
      { ...privateHike, departureTimeLocal: '2026-08-04T08:00:00.000Z' },
      '+60333333333',
      now
    ),
    null
  );
});

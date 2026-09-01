'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { publicStatsPayload } = require('../public_stats_helpers');

test('public stats expose only rounded, non-negative aggregate values', () => {
  const payload = publicStatsPayload({
    registeredHikers: 3,
    totalDistanceKm: 28.437,
    completedHikes: 7,
    soloHikes: 4,
    groupHikes: 3,
    safetyCheckIns: 12,
    phoneNumber: '+60123456789',
    routePoints: [{ latitude: 5.3, longitude: 100.3 }],
  }, new Date('2026-08-31T08:00:00.000Z'));

  assert.deepEqual(payload, {
    registeredHikers: 3,
    totalDistanceKm: 28.4,
    completedHikes: 7,
    soloHikes: 4,
    groupHikes: 3,
    safetyCheckIns: 12,
    calculatedAt: '2026-08-31T08:00:00.000Z',
  });
  assert.equal(JSON.stringify(payload).includes('+60123456789'), false);
  assert.equal(JSON.stringify(payload).includes('latitude'), false);
});

test('public stats replace invalid or negative values with zero', () => {
  const payload = publicStatsPayload({
    registeredHikers: -5,
    totalDistanceKm: Number.NaN,
    completedHikes: 'invalid',
    soloHikes: -1,
    groupHikes: Number.POSITIVE_INFINITY,
    safetyCheckIns: null,
  }, new Date('invalid'));

  assert.equal(payload.registeredHikers, 0);
  assert.equal(payload.totalDistanceKm, 0);
  assert.equal(payload.completedHikes, 0);
  assert.equal(payload.soloHikes, 0);
  assert.equal(payload.groupHikes, 0);
  assert.equal(payload.safetyCheckIns, 0);
  assert.equal(payload.calculatedAt, '1970-01-01T00:00:00.000Z');
});

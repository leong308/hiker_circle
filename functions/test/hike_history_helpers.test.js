'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { detailData, summaryData } = require('../hike_history_helpers');

const session = {
  userId: 'private-user',
  userPhoneNumber: '+60111111111',
  status: 'completed',
  hikeType: 'solo',
  trailId: 'trail_1',
  trailName: 'Pine Ridge',
  startedAtLocal: '2026-08-20T01:00:00.000Z',
  endedAtLocal: '2026-08-20T03:30:00.000Z',
  summaryReport: {
    distanceKm: 8.4,
    checkIns: 3,
    manualPins: 1,
    routePointCount: 80,
    batteryStartPercent: 92,
    batteryEndPercent: 71,
    insights: ['Good tracking coverage.'],
  },
  trail: {
    trailId: 'trail_1',
    name: 'Pine Ridge',
    area: 'Gombak',
    state: 'Selangor',
    difficulty: 'Moderate',
    distanceKm: 7.8,
    estimatedDurationMinutes: 180,
    elevationGainMeters: 520,
  },
  emergencyContactNames: ['Must not be returned'],
  monitoringFcmToken: 'must-not-leak',
};

test('history summary exposes useful totals without account identifiers', () => {
  const summary = summaryData('session_1', session);
  assert.equal(summary.sessionId, 'session_1');
  assert.equal(summary.durationSeconds, 9000);
  assert.equal(summary.distanceKm, 8.4);
  const encoded = JSON.stringify(summary);
  assert.equal(encoded.includes('+60111111111'), false);
  assert.equal(encoded.includes('private-user'), false);
  assert.equal(encoded.includes('must-not-leak'), false);
});

test('history detail combines route, safety, telemetry, and rating data', () => {
  const detail = detailData({
    sessionId: 'session_1',
    session,
    capture: {
      routePoints: [
        { latitude: 3.1, longitude: 101.6, capturedAtLocal: '2026-08-20T01:00:00Z' },
        { latitude: 3.2, longitude: 101.7, capturedAtLocal: '2026-08-20T03:00:00Z' },
      ],
      manualPins: [{
        pinId: 'pin_1',
        pinnedAtLocal: '2026-08-20T02:00:00Z',
        coordinate: { latitude: 3.15, longitude: 101.65 },
      }],
    },
    checkIns: [{
      checkInId: 'check_1',
      status: 'safe',
      createdAtLocal: '2026-08-20T02:10:00Z',
      batteryLevel: 80,
      location: { latitude: 3.16, longitude: 101.66 },
    }],
    locationPoints: [{
      latitude: 3.1,
      longitude: 101.6,
      altitude: 120,
      batteryLevel: 88,
      recordedAtLocal: '2026-08-20T01:10:00Z',
    }],
    rating: {
      rating: 5,
      difficulty: 'moderate',
      comment: 'Excellent route.',
    },
    groupChatId: 'team_team_1',
    memberTracks: [{
      name: 'Aisha',
      isCurrentUser: false,
      routePoints: [
        { latitude: 3.1, longitude: 101.6, capturedAtLocal: '2026-08-20T01:00:00Z' },
        { latitude: 3.2, longitude: 101.7, capturedAtLocal: '2026-08-20T03:00:00Z' },
      ],
    }],
  });
  assert.equal(detail.routePoints.length, 2);
  assert.equal(detail.safety.manualPins.length, 1);
  assert.equal(detail.safety.checkIns.length, 1);
  assert.equal(detail.performance.minAltitudeMeters, 120);
  assert.deepEqual(detail.rating, {
    stars: 5,
    difficulty: 'moderate',
    comment: 'Excellent route.',
  });
  assert.equal(detail.source.groupChatId, 'team_team_1');
  assert.equal(detail.team.memberTracks[0].name, 'Aisha');
  assert.equal(detail.team.memberTracks[0].routePoints.length, 2);
  const encoded = JSON.stringify(detail);
  assert.equal(encoded.includes('Must not be returned'), false);
  assert.equal(encoded.includes('must-not-leak'), false);
});

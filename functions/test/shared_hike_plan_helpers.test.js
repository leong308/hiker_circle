'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  SHARED_HIKE_PLAN_PRIVACY_VERSION,
  projectSharedHikePlan,
  sharedHikePlanNeedsRedaction,
  sharedRouteAndTimingMatch,
  teamSourceMatchesRequest,
  scheduledTeamLaunchCanResume,
  legacyActiveHikeCanAdoptTeamSource,
} = require('../shared_hike_plan_helpers');

const sharedPlan = {
  hikeType: 'team',
  trail: { trailId: 'trail_1', name: 'Ridge' },
  startPointName: 'Gate',
  destinationName: 'Summit',
  departureTime: '2024-01-01T01:00:00.000Z',
  expectedArrivalTime: '2024-01-01T03:00:00.000Z',
  expectedReturnTime: '2024-01-01T04:00:00.000Z',
  teamBuddies: [{ phoneNumber: '+60111111111' }],
  customCheckpoints: [
    { name: 'Junction', latitude: 3.1, longitude: 101.6, order: 1 },
  ],
};

test('shared hike projection removes every personal safety field', () => {
  const projected = projectSharedHikePlan({
    ...sharedPlan,
    emergencyContactNames: ['Private contact'],
    safetyCheckInIntervalSeconds: 60,
    locationRecordingIntervalSeconds: 5,
    shareLiveLocation: true,
    fallDetectionEnabled: true,
    fallDetectionSettings: { sensorSensitivity: 10 },
    pathDeviationEnabled: true,
    pathDeviationDistanceMeters: 17,
    offlinePhysicalAlertEnabled: true,
    duressEnabled: true,
    completedChecklistItems: ['Medication'],
  });

  assert.deepEqual(projected, sharedPlan);
  assert.equal(SHARED_HIKE_PLAN_PRIVACY_VERSION, 1);
  assert.equal(sharedHikePlanNeedsRedaction(projected), false);
  assert.equal(
    sharedHikePlanNeedsRedaction({ ...projected, duressEnabled: true }),
    true
  );
});

test('legacy projection preserves stale timing without validating it', () => {
  const projected = projectSharedHikePlan(sharedPlan);
  assert.equal(projected.departureTime, '2024-01-01T01:00:00.000Z');
});

test('source team launch must match route and equivalent timing', () => {
  assert.equal(
    sharedRouteAndTimingMatch(
      {
        ...sharedPlan,
        departureTime: '2024-01-01T09:00:00.000+08:00',
      },
      sharedPlan
    ),
    true
  );
  assert.equal(
    sharedRouteAndTimingMatch(
      { ...sharedPlan, expectedReturnTime: '2024-01-01T05:00:00.000Z' },
      sharedPlan
    ),
    false
  );
  assert.equal(
    sharedRouteAndTimingMatch(
      {
        ...sharedPlan,
        customCheckpoints: [
          { name: 'Other', latitude: 3.1, longitude: 101.6, order: 1 },
        ],
      },
      sharedPlan
    ),
    false
  );
});

test('scheduled team identity cannot be omitted or substituted', () => {
  const team = { sourceUpcomingHikeId: 'upcoming_123' };
  assert.equal(teamSourceMatchesRequest(team, 'upcoming_123'), true);
  assert.equal(teamSourceMatchesRequest(team, ''), false);
  assert.equal(teamSourceMatchesRequest(team, 'upcoming_other'), false);
  assert.equal(teamSourceMatchesRequest({}, ''), true);
});

test('a cancelled pre-start scheduled launch can resume but a started one cannot', () => {
  const team = { phase: 'completed' };
  const upcoming = {
    teamHikeSessionId: 'team_123',
    startedParticipantPhones: [],
  };
  assert.equal(
    scheduledTeamLaunchCanResume(team, upcoming, 'team_123', 'upcoming_123'),
    true
  );
  assert.equal(
    scheduledTeamLaunchCanResume(
      team,
      { ...upcoming, startedParticipantPhones: ['+60111111111'] },
      'team_123',
      'upcoming_123'
    ),
    false
  );
  assert.equal(
    scheduledTeamLaunchCanResume(
      { phase: 'active' },
      upcoming,
      'team_123',
      'upcoming_123'
    ),
    false
  );
});

test('legacy team active hike can adopt only its linked scheduled source', () => {
  const existing = {
    sourceUpcomingHikeId: '',
    teamHikeSessionId: 'team_123',
  };
  assert.equal(
    legacyActiveHikeCanAdoptTeamSource(
      existing,
      'upcoming_123',
      'team_123'
    ),
    true
  );
  assert.equal(
    legacyActiveHikeCanAdoptTeamSource(existing, '', 'team_123'),
    false
  );
  assert.equal(
    legacyActiveHikeCanAdoptTeamSource(
      existing,
      'upcoming_123',
      'team_other'
    ),
    false
  );
});

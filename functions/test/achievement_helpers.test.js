'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  achievementProgressHash,
  achievementSlug,
  completedHikeAchievementEvents,
  malaysiaStateSlug,
} = require('../achievement_helpers');

test('achievement progress hash is stable by id and changes with progress', () => {
  const definitions = [
    {
      achievementId: 'b',
      title: 'Second',
      rewardType: 'cumulative',
      targetCount: 2,
    },
    {
      achievementId: 'a',
      title: 'First',
      rewardType: 'cumulative',
      targetCount: 1,
    },
  ];
  const awards = [
    { achievementId: 'b', progressCount: 1, updatedAtLocal: '2026-09-05' },
  ];
  const initial = achievementProgressHash({ definitions, awards });
  assert.equal(
    initial,
    achievementProgressHash({
      definitions: definitions.toReversed(),
      awards: awards.toReversed(),
    }),
  );
  assert.notEqual(
    initial,
    achievementProgressHash({
      definitions,
      awards: [{ ...awards[0], progressCount: 2 }],
    }),
  );
});

test('completed hikes emit repeatable, unique-trail, and Malaysian-state events', () => {
  assert.deepEqual(
    completedHikeAchievementEvents({
      sessionId: 'session_1',
      trailId: 'trail_broga_001',
      state: 'Negeri Sembilan',
      country: 'Malaysia',
    }),
    [
      { metricKey: 'hike_completed', eventKey: 'hike-completed:session_1' },
      {
        metricKey: 'distinct_trail_completed',
        eventKey: 'distinct-trail-completed:trail-broga-001',
      },
      {
        metricKey: 'malaysia_state_hiked',
        eventKey: 'malaysia-state-hiked:negeri-sembilan',
      },
    ],
  );
});

test('state travel progress is not emitted for trails outside Malaysia', () => {
  const events = completedHikeAchievementEvents({
    sessionId: 'session_2',
    trailId: 'trail_overseas',
    state: 'Chiang Mai',
    country: 'Thailand',
  });
  assert.equal(events.some((event) => event.metricKey === 'malaysia_state_hiked'), false);
});

test('achievement slugs are stable for spaces and punctuation', () => {
  assert.equal(achievementSlug(' Kuala Lumpur! '), 'kuala-lumpur');
});

test('country exploration counts states, not federal territories', () => {
  assert.equal(malaysiaStateSlug('Melaka'), 'malacca');
  assert.equal(malaysiaStateSlug('Pulau Pinang'), 'penang');
  assert.equal(malaysiaStateSlug('Kuala Lumpur'), '');
  assert.equal(malaysiaStateSlug('Putrajaya'), '');
});

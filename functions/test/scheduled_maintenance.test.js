'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {runMaintenanceTasks} = require('../scheduled_maintenance');

test('maintenance tasks remain sequential and continue after a failure', async () => {
  const events = [];
  const failure = new Error('first task failed');

  await assert.rejects(
    runMaintenanceTasks(
      'combined job',
      [
        {name: 'first', run: async () => {
          events.push('first');
          throw failure;
        }},
        {name: 'second', run: async () => events.push('second')},
      ],
      (name, error) => events.push(`${name}:${error.message}`)
    ),
    (error) => error instanceof AggregateError
      && error.errors.length === 1
      && error.errors[0] === failure
  );

  assert.deepEqual(events, [
    'first',
    'first:first task failed',
    'second',
  ]);
});

test('maintenance runner completes when every task succeeds', async () => {
  const events = [];
  await runMaintenanceTasks('combined job', [
    {name: 'first', run: async () => events.push('first')},
    {name: 'second', run: async () => events.push('second')},
  ]);
  assert.deepEqual(events, ['first', 'second']);
});

test('independent maintenance tasks can run concurrently', async () => {
  let releaseFirst;
  const firstCanFinish = new Promise((resolve) => { releaseFirst = resolve; });
  const events = [];
  await runMaintenanceTasks(
    'combined job',
    [
      {name: 'first', run: async () => {
        events.push('first-start');
        await firstCanFinish;
        events.push('first-end');
      }},
      {name: 'second', run: async () => {
        events.push('second');
        releaseFirst();
      }},
    ],
    () => undefined,
    {concurrent: true}
  );
  assert.deepEqual(events, ['first-start', 'second', 'first-end']);
});

test('scheduler exports stay consolidated and removed jobs do not return', () => {
  const source = fs.readFileSync(
    path.join(__dirname, '..', 'index.js'),
    'utf8'
  );
  for (const name of [
    'processUpcomingHikeOperations',
    'monitorActiveHikes',
    'cleanExpiredTeamAndGroupChats',
  ]) {
    assert.match(source, new RegExp(`exports\\.${name}\\s*=`));
  }
  for (const name of [
    'sendScheduledActiveHikeCheckIns',
    'redactLegacySharedHikeDrafts',
    'processUpcomingHikeLifecycle',
    'sendUpcomingHikePrecautions',
    'cleanExpiredUpcomingHikes',
    'checkActiveHikeMonitoringHeartbeats',
    'cleanStaleHikeSessions',
    'cleanExpiredTeamHikeInvitations',
    'cleanExpiredGroupChats',
  ]) {
    assert.doesNotMatch(source, new RegExp(`exports\\.${name}\\s*=`));
  }
});

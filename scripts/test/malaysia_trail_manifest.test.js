'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { trails } = require('../malaysia_trail_manifest');
const { validateManifest, validateTrail } = require('../seed_malaysia_trails');

function validImportedTrail() {
  return {
    name: 'Test hiking trail',
    area: 'Test area',
    state: 'Johor',
    distanceKm: 2,
    estimatedDurationMinutes: 60,
    difficultyVoteCounts: { easy: 0, moderate: 0, hard: 0 },
    difficultyRatingCount: 0,
    checkpoints: [
      { latitude: 2, longitude: 103 },
      { latitude: 2.01, longitude: 103.01 },
      { latitude: 2, longitude: 103 },
    ],
    routeEncodedPolyline: 'valid-polyline',
  };
}

test('manifest has unique AllTrails-referenced Malaysian hikes', () => {
  assert.doesNotThrow(validateManifest);
  assert.equal(new Set(trails.map((trail) => trail.name)).size, trails.length);
  assert.ok(trails.every((trail) => !Object.hasOwn(trail, 'difficulty')));
  assert.ok(
    trails.every((trail) =>
      trail.allTrailsUrl.startsWith('https://www.alltrails.com/')),
  );
});

test('import schema starts without an admin-set difficulty', () => {
  const trail = validImportedTrail();
  assert.doesNotThrow(() => validateTrail(trail));
  assert.throws(
    () => validateTrail({ ...trail, difficulty: 'hard' }),
    /without an admin-set difficulty/,
  );
});

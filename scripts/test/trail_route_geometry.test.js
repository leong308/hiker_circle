'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  assemblePrimaryRelation,
  mirrorOutAndBack,
  shortestPathInRelation,
  validateGeometry,
} = require('../lib/trail_route_geometry');

function fixture({ members, ways, nodes }) {
  return {
    elements: [
      {
        type: 'relation',
        id: 1,
        tags: { route: 'hiking' },
        members,
      },
      ...ways.map(([id, nodeIds]) => ({ type: 'way', id, nodes: nodeIds })),
      ...nodes.map(([id, lat, lon]) => ({ type: 'node', id, lat, lon })),
    ],
  };
}

test('excludes alternative members and never jumps to disconnected geometry', () => {
  const data = fixture({
    members: [
      { type: 'way', ref: 11, role: '' },
      { type: 'way', ref: 99, role: 'alternative' },
      { type: 'way', ref: 12, role: '' },
    ],
    ways: [[11, [1, 2]], [12, [2, 3]], [99, [8, 9]]],
    nodes: [
      [1, 3.0, 101.0], [2, 3.001, 101.0], [3, 3.002, 101.0],
      [8, 5.0, 103.0], [9, 5.001, 103.0],
    ],
  });

  const result = assemblePrimaryRelation(data, 1);

  assert.deepEqual(result.points.map((point) => point.lat), [3, 3.001, 3.002]);
  assert.deepEqual(result.excludedRoles, ['alternative']);
  assert.ok(validateGeometry(result.points, 'point-to-point').maxSegmentMeters < 200);
});

test('assembles a loop by shared OSM endpoints even when members are unordered', () => {
  const data = fixture({
    members: [
      { type: 'way', ref: 21, role: '' },
      { type: 'way', ref: 23, role: '' },
      { type: 'way', ref: 22, role: '' },
    ],
    ways: [[21, [1, 2]], [22, [2, 3]], [23, [3, 1]]],
    nodes: [[1, 3, 101], [2, 3, 101.001], [3, 3.001, 101.001]],
  });

  const result = assemblePrimaryRelation(data, 1);
  const audit = validateGeometry(result.points, 'loop');

  assert.equal(audit.endpointGapMeters, 0);
  assert.equal(result.includedMemberCount, 3);
});

test('finds the connected shortest hiking path within a branched relation', () => {
  const data = fixture({
    members: [
      { type: 'way', ref: 31, role: '' },
      { type: 'way', ref: 32, role: '' },
      { type: 'way', ref: 33, role: '' },
    ],
    ways: [[31, [1, 2, 3]], [32, [2, 4, 3]], [33, [3, 5]]],
    nodes: [
      [1, 3, 101], [2, 3, 101.001], [3, 3, 101.002],
      [4, 3.01, 101.001], [5, 3, 101.003],
    ],
  });

  const result = shortestPathInRelation(
    data,
    1,
    { lat: 3, lon: 101 },
    { lat: 3, lon: 101.003 },
    { maxSnapMeters: 50 },
  );

  assert.deepEqual(result.points.map((point) => point.lon), [101, 101.001, 101.002, 101.003]);
});

test('mirrors an outbound hiking path into a closed out-and-back route', () => {
  const route = mirrorOutAndBack([
    { lat: 3, lon: 101 },
    { lat: 3.001, lon: 101 },
    { lat: 3.002, lon: 101 },
  ]);

  assert.equal(route.length, 5);
  assert.deepEqual(route[0], route[route.length - 1]);
  assert.equal(validateGeometry(route, 'out-and-back').endpointGapMeters, 0);
});

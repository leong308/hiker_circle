const test = require('node:test');
const assert = require('node:assert/strict');
const { normalizeNearbySosReport } = require('../nearby_sos_helpers');

test('same device and counter deduplicate to the same incident', () => {
  const now = 1_800_000_000_000;
  const first = normalizeNearbySosReport({
    deviceId: 'AABBCCDDEEFF',
    counter: 42,
    receivedAtMillis: now,
    rssi: -60,
  }, now);
  const second = normalizeNearbySosReport({
    deviceId: 'aabbccddeeff',
    counter: 42,
    receivedAtMillis: now + 2000,
    rssi: -75,
  }, now + 2000);
  assert.equal(first.incidentId, second.incidentId);
  assert.equal(first.deviceIdHash, second.deviceIdHash);
});

test('different counters create different incidents', () => {
  const now = 1_800_000_000_000;
  const first = normalizeNearbySosReport({
    deviceId: 'AABBCCDDEEFF', counter: 1, receivedAtMillis: now,
  }, now);
  const second = normalizeNearbySosReport({
    deviceId: 'AABBCCDDEEFF', counter: 2, receivedAtMillis: now,
  }, now);
  assert.notEqual(first.incidentId, second.incidentId);
});

test('rejects stale or invalid reports', () => {
  const now = 1_800_000_000_000;
  assert.throws(() => normalizeNearbySosReport({
    deviceId: 'AABBCCDDEEFF', counter: 1, receivedAtMillis: now - 700_000,
  }, now), /invalid-received-at/);
  assert.throws(() => normalizeNearbySosReport({
    deviceId: 'bad id', counter: 1, receivedAtMillis: now,
  }, now), /invalid-device-id/);
});

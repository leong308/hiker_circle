const test = require('node:test');
const assert = require('node:assert/strict');
const { cancelUpcomingHike } = require('../cancel_upcoming_hike');
class ErrorWithCode extends Error { constructor(code, message) { super(message); this.code = code; } }
const owner = { hikeId: 'hike', uid: 'host-id', phoneNumber: '+60111111111' };
function fixture(extra = {}) {
  const data = { creatorUserId: owner.uid, creatorPhone: owner.phoneNumber, ...extra };
  const updates = [];
  const db = {
    collection: () => ({ doc: id => ({ id }) }),
    runTransaction: async callback => callback({
      get: async () => ({ exists: true, data: () => data }),
      update: (_, change) => { updates.push(change); Object.assign(data, change); },
    }),
  };
  return { data, updates, cancel: (user = owner) => cancelUpcomingHike(db, user, ErrorWithCode, () => 'timestamp') };
}
test('host cancellation marks the schedule deleted and repeated retries are harmless', async () => {
  const f = fixture();
  assert.deepEqual(await f.cancel(), { cancelled: true });
  assert.equal(f.data.isDeleted, true);
  assert.equal(f.data.cancelledByUserId, owner.uid);
  await f.cancel();
  assert.equal(f.updates.length, 1);
});
test('a participant or mismatched authenticated identity cannot cancel', async () => {
  for (const user of [{ ...owner, uid: 'guest' }, { ...owner, phoneNumber: '+60222222222' }]) {
    const f = fixture();
    await assert.rejects(f.cancel(user), { code: 'permission-denied' });
    assert.equal(f.updates.length, 0);
  }
});
test('launch state read by the transaction prevents cancelling a started hike', async () => {
  for (const state of [{ startedParticipantPhones: [owner.phoneNumber] },
    { teamHikeSessionId: 'team' }, { teamLaunchLinkedAt: 'timestamp' }, { teamLaunchLinkedAtLocal: 'date' }]) {
    const f = fixture(state);
    await assert.rejects(f.cancel(), { code: 'failed-precondition' });
    assert.equal(f.updates.length, 0);
  }
});

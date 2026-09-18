const test = require('node:test');
const assert = require('node:assert/strict');
const { validateSoloHikeDistance: validate } = require('../solo_hike_policy');
class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
test('10 km needs no acknowledgement; over 10 through 20 needs matching acknowledgement', () => {
  validate(10, false, null, HttpsError);
  assert.throws(() => validate(10.001, false, null, HttpsError));
  validate(20, false, 20, HttpsError);
  assert.throws(() => validate(20, false, 15, HttpsError));
  assert.throws(() => validate(15, false, '15', HttpsError));
});
test('over 20 rejects solo even with acknowledgement but accepts group setup', () => {
  assert.throws(() => validate(20.001, false, 20.001, HttpsError), /group/);
  validate(35, true, null, HttpsError);
});

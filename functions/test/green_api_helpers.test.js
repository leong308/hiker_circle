'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  greenApiMessageId,
  greenApiStateReadiness,
} = require('../green_api_helpers');

test('only authorized GreenAPI instances are ready to send', () => {
  assert.deepEqual(greenApiStateReadiness('authorized'), {
    ready: true,
    retryable: false,
    state: 'authorized',
  });
  assert.equal(greenApiStateReadiness('notAuthorized').ready, false);
  assert.equal(greenApiStateReadiness('notAuthorized').retryable, false);
  assert.match(
    greenApiStateReadiness('notAuthorized').message,
    /Re-authorize/,
  );
});

test('starting and unavailable status checks remain retryable', () => {
  assert.equal(greenApiStateReadiness('starting').retryable, true);
  assert.equal(greenApiStateReadiness('').retryable, true);
  assert.equal(greenApiStateReadiness('blocked').retryable, false);
  assert.equal(greenApiStateReadiness('yellowCard').retryable, false);
});

test('a successful send requires a non-empty provider message id', () => {
  assert.equal(greenApiMessageId({ idMessage: '  abc-123  ' }), 'abc-123');
  assert.equal(greenApiMessageId({}), '');
  assert.equal(greenApiMessageId(null), '');
});

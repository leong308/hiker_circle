'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const { sendGreenApiOtp } = require('../green_api_helpers');
const args = { endpointFor: (method) => method, chatId: '60123456789@c.us',
  code: '012345', message: 'Your verification code is 012345. It expires in 5 minutes.' };
test('OTP copy button preserves leading zero and visible code', async () => {
  const calls = [];
  const response = new Response(JSON.stringify({idMessage: 'accepted'}));
  assert.equal(await sendGreenApiOtp({...args, fetchImpl: async (url, request) => {
    calls.push({url, ...JSON.parse(request.body)}); return response;
  }}), response);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'sendInteractiveButtons');
  assert.equal(calls[0].body, args.message);
  assert.deepEqual(calls[0].buttons, [{type: 'copy', buttonId: 'copy_otp',
    buttonText: 'Copy OTP', copyCode: '012345'}]);
});
test('explicit button rejection falls back with the same OTP and request deadline', async () => {
  for (const status of [400, 403, 404, 405, 422]) {
    const calls = [];
    await sendGreenApiOtp({...args, fetchImpl: async (url, request) => {
      calls.push({url, request});
      return new Response('{}', {status: calls.length === 1 ? status : 200});
    }});
    assert.deepEqual(calls.map((call) => call.url), ['sendInteractiveButtons', 'sendMessage']);
    assert.deepEqual(JSON.parse(calls[1].request.body), {chatId: args.chatId, message: args.message});
    assert.equal(calls[0].request.signal, calls[1].request.signal);
  }
});
test('uncertain delivery and rate limiting never cause duplicate sends', async () => {
  for (const status of [200, 429, 500, 502, 503, 504]) {
    let calls = 0;
    const response = new Response('{}', {status});
    assert.equal(await sendGreenApiOtp({...args, fetchImpl: async () => {
      calls++; return response;
    }}), response);
    assert.equal(calls, 1);
  }
  let calls = 0;
  await assert.rejects(sendGreenApiOtp({...args, fetchImpl: async () => {
    calls++; throw new DOMException('Timed out', 'TimeoutError');
  }}), {name: 'TimeoutError'});
  assert.equal(calls, 1);
});
test('malformed OTP cannot be dispatched', async () => {
  await assert.rejects(sendGreenApiOtp({...args, code:'12345', fetchImpl: async () => {
    assert.fail('Must not dispatch');
  }}), TypeError);
});

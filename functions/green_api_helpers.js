'use strict';

const stateDescriptions = Object.freeze({
  notAuthorized:
    'GreenAPI is not connected to WhatsApp. Re-authorize the instance in the GreenAPI console.',
  blocked:
    'The GreenAPI WhatsApp instance is blocked and cannot send messages.',
  starting:
    'The GreenAPI WhatsApp instance is still starting. Try again shortly.',
  yellowCard:
    'GreenAPI has temporarily suspended message sending for this WhatsApp account.',
});

function greenApiStateReadiness(rawState) {
  const state = String(rawState || '').trim();
  if (state === 'authorized') {
    return { ready: true, retryable: false, state };
  }
  return {
    ready: false,
    retryable: state === 'starting' || state === '',
    state,
    message:
      stateDescriptions[state]
      || 'GreenAPI returned an unknown instance state.',
  };
}

function greenApiMessageId(responseData) {
  if (!responseData || typeof responseData !== 'object') return '';
  return String(responseData.idMessage || '').trim().slice(0, 240);
}

// Keep OTPs visible in the body even if a WhatsApp client hides buttons.
async function sendGreenApiOtp({ endpointFor, chatId, code, message,
  fetchImpl = fetch }) {
  if (!/^[0-9]{6}$/.test(code)) throw new TypeError('Expected six OTP digits');
  const signal = AbortSignal.timeout(12 * 1000);
  const send = (method, payload) => fetchImpl(endpointFor(method), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
    signal,
  });
  const response = await send('sendInteractiveButtons', {
    chatId,
    header: 'HikerCircle verification',
    body: message,
    footer: 'Never share this code with anyone.',
    buttons: [{ type: 'copy', buttonId: 'copy_otp',
      buttonText: 'Copy OTP', copyCode: code }],
  });
  // These statuses explicitly reject the request before queueing. Never retry
  // on a timeout, rate limit, 5xx or a success without idMessage: delivery may
  // already have happened and the caller must retain its uncertain state.
  if ([400, 403, 404, 405, 422].includes(response.status)) {
    await response.body?.cancel();
    return send('sendMessage', { chatId, message });
  }
  return response;
}

module.exports = {
  sendGreenApiOtp,
  greenApiMessageId,
  greenApiStateReadiness,
};

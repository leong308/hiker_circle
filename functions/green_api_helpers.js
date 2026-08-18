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

module.exports = {
  greenApiMessageId,
  greenApiStateReadiness,
};

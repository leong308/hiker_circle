// Canonical content hashes validate unchanged mobile payloads; chat reminder cooldowns depend on departure time.
'use strict';
const {createHash} = require('node:crypto');

// canonical: Sort map keys and normalize Firestore timestamps before content hashing.
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') {
    if (typeof value.toDate === 'function') return value.toDate().toISOString();
    return Object.fromEntries(Object.keys(value).sort().filter(key => value[key] !== undefined)
      .map(key => [key, canonical(value[key])]));
  }
  return value;
}
function contentHash(value) { return createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex'); }
// conditionalPayload: Return cache metadata alone when the validated payload hash matches the client copy.
function conditionalPayload(payload, request, revisionHash) {
  const hash = contentHash(payload);
  return request.knownContentHash === hash
    ? {notModified: true, contentHash: hash, revisionHash, payloadChecked: true}
    : {...payload, contentHash: hash, revisionHash, payloadChecked: true};
}
// reminderCooldown: Tighten reminder spacing as departure approaches and stop once departure has passed.
function reminderCooldown(departureMillis, now = Date.now()) {
  const before = departureMillis - now;
  if (Number.isFinite(before) && before <= 0) return null;
  if (!Number.isFinite(before) || before > 12 * 60 * 60 * 1000) return 12 * 60 * 60 * 1000;
  if (before > 60 * 60 * 1000) return 60 * 60 * 1000;
  return 5 * 60 * 1000;
}
module.exports = {canonical, contentHash, conditionalPayload, reminderCooldown};

'use strict';
const crypto = require('crypto');
const WINDOW_MS = 15000;
const MAX_ATTEMPTS = 3;
const MAX_AGE_MS = 24 * 60 * 60 * 1000;

// Bind provider evidence to this SOS recipient and outbound attempt without exposing account identifiers.
function referenceFor(id, attempt) {
  return `HC-SOS-${crypto.createHash('sha256').update(id).digest('hex').slice(0, 18)}-${attempt}`;
}

// A missing acknowledgement is distinct from a known rejection and can still be corrected later.
function stateFor(record, now = Date.now()) {
  if (record.status === 'sent') return 'confirmed';
  if (record.status === 'failed') return 'failed';
  if (record.status === 'delivery_uncertain'
    || record.status === 'sending' && Number(record.confirmationDeadlineMillis) <= now) return 'unconfirmed';
  return 'sending';
}

// Publish only owner-visible contact outcomes, never payloads, credentials or attempt leases.
function receipt(record, now = Date.now()) {
  const state = stateFor(record, now);
  return {alertId: String(record.alertId || ''), dispatchId: String(record.dispatchId || ''),
    phoneNumber: String(record.recipientPhoneNumber || ''), contactName: String(record.contactName || 'Contact'),
    contactIndex: Number(record.contactIndex || 0), triggeredAtMillis: Number(record.triggeredAtMillis || 0),
    confirmationDeadlineMillis: Number(record.confirmationDeadlineMillis || 0), status: state,
    wasSent: state === 'confirmed', retryable: state === 'failed' && record.retryable === true && Number(record.attemptCount) < MAX_ATTEMPTS,
    providerMessageId: String(record.providerMessageId || ''), providerStatus: String(record.providerStatus || ''),
    attemptCount: Number(record.attemptCount || 0), nextRetryAtMillis: Number(record.nextRetryAtMillis || 0),
    errorMessage: state === 'unconfirmed' ? 'No confirmation within 15 seconds. Still checking; this contact will not be resent blindly.' : String(record.clientMessage || ''),
    updatedAtMillis: now};
}

// Receipt writes share the canonical transaction, so a stale client log cannot erase late confirmations.
function project(tx, db, id, record, now = Date.now()) {
  if (record.isTest === true || !record.confirmationTracking || !record.ownerUid) return;
  // Update cloud: publish SOS delivery receipt
  tx.set(db.collection('sosDeliveryReceipts').doc(record.ownerUid).collection('dispatches').doc(id), receipt(record, now));
}

// Search actual provider queue/history evidence using both the recipient and the unique attempt reference.
function evidenceFor(record, queue, journal) {
  const chat = `${String(record.recipientPhoneNumber || '').replace(/\D/g, '')}@c.us`;
  const token = `SOS reference: ${record.confirmationReference}`;
  const candidates = [...(Array.isArray(queue) ? queue.map(item => ({...item, queued: true})) : []),
    ...(Array.isArray(journal) ? journal : [])];
  const matches = candidates.filter(item => {
    if (item.sendByApi === false) return false;
    const body = item.body || {}, data = item.messageData || {};
    const text = String(body.message || item.textMessage || item.extendedTextMessage?.text || data.textMessageData?.textMessage || data.extendedTextMessageData?.text || '');
    const id = String(item.idMessage || item.messageID || '');
    return String(item.chatId || body.chatId || '') === chat && id
      && (record.providerMessageId && id === record.providerMessageId || record.confirmationReference && text.split(/\r?\n/).some(line => line.trim() === token));
  });
  // A journal delivery wins over an older queue entry for the same message.
  const rank = item => ({read: 6, delivered: 5, sent: 3, pending: 2, failed: 4, noAccount: 4, notInGroup: 4}[item.statusMessage] || (item.queued ? 1 : 3));
  matches.sort((a,b) => rank(b) - rank(a));
  if (!matches.length) return null;
  const match = matches[0];
  return {messageId: String(match.idMessage || match.messageID), status: String(match.statusMessage || 'queued')};
}

// Reconcile one current attempt transactionally before deciding whether this exact contact needs a retry.
async function reconcile({db, ref, previous, evidence, now = Date.now(), deleteField}) {
  return db.runTransaction(async tx => {
    // Query SOS dispatch status
    const snapshot = await tx.get(ref), current = snapshot.data() || {};
    if (!snapshot.exists || !current.confirmationTracking || current.isTest
      || current.attemptNonce !== previous.attemptNonce) return null;
    const patch = {updatedAtMillis: now};
    if (evidence) {
      patch.providerMessageId = evidence.messageId;
      patch.providerStatus = evidence.status;
      if (['failed', 'noAccount', 'notInGroup'].includes(evidence.status)) {
        patch.status = 'failed'; patch.wasSent = false; patch.deliveryUncertain = false;
        patch.retryable = evidence.status === 'failed' && Number(current.attemptCount) < MAX_ATTEMPTS;
        patch.clientMessage = evidence.status === 'noAccount' ? 'This contact has no WhatsApp account.' : 'The provider confirmed this contact could not be reached.';
      } else {
        patch.status = 'sent'; patch.wasSent = true; patch.retryable = false; patch.deliveryUncertain = false;
        patch.clientMessage = ''; patch.confirmedAtMillis = now;
      }
    } else if (current.status === 'sending' && Number(current.confirmationDeadlineMillis) <= now) {
      patch.status = 'delivery_uncertain'; patch.retryable = false; patch.deliveryUncertain = true;
    }
    const next = {...current, ...patch};
    const expired = now - Number(current.triggeredAtMillis) >= MAX_AGE_MS;
    if (expired) { patch.retryable = false; patch.nextRetryAtMillis = 0; }
    const terminal = expired || ['delivered', 'read'].includes(next.providerStatus)
      || next.status === 'failed' && (!next.retryable || Number(next.attemptCount) >= MAX_ATTEMPTS);
    patch.nextCheckAtMillis = terminal ? deleteField() : now + 60000;
    if (next.status === 'failed' && next.retryable && !next.nextRetryAtMillis) patch.nextRetryAtMillis = now + 60000;
    // Update cloud: save confirmed dispatch status
    tx.set(ref, patch, {merge: true});
    project(tx, db, ref.id, {...next, ...patch}, now);
    return {...next, ...patch, expired};
  });
}

module.exports = {WINDOW_MS, MAX_ATTEMPTS, MAX_AGE_MS, referenceFor, stateFor, receipt, project, evidenceFor, reconcile};

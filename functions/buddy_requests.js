// Reciprocal buddy requests and delayed, cancellable FCM delivery share one transaction boundary.
'use strict';
const {randomUUID} = require('node:crypto');
const userModules = require('./user_modules');
const lifecycle = require('./fcm_outbox_delivery');
const NOTIFICATION_DELAY_MILLIS = 8000;
const phoneKey = phone => String(phone || '').replace(/\D/g, '');
const validPhone = phone => /^\+[1-9]\d{7,14}$/.test(phone);
const disabled = user => user?.accountDisabled === true || user?.status === 'disabled';

function createBuddyRequestService({db, FieldValue, HttpsError, userIdFor,
  tokensFor, messaging, displayNameFor, now = Date.now,
  delay = millis => new Promise(resolve => setTimeout(resolve, millis)),
  readUser = userModules.readUser, setUser = userModules.setUser,
  updateUser = userModules.updateUser}) {
  const timestamp = () => FieldValue.serverTimestamp();
  const userRef = phone => db.collection('users').doc(userIdFor(phone));
  const noticeRef = id => db.collection('fcmOutbox').doc(`buddy_request_${id}`);

  async function manage({ownerPhone, uid, action, otherPhone}) {
    ownerPhone = String(ownerPhone || '').trim();
    otherPhone = String(otherPhone || '').trim();
    if (!uid || uid !== userIdFor(ownerPhone) || !validPhone(ownerPhone)) {
      throw new HttpsError('unauthenticated', 'Sign in to manage buddies.');
    }
    if (!['send', 'cancel', 'accept', 'decline'].includes(action)
        || !validPhone(otherPhone) || phoneKey(ownerPhone) === phoneKey(otherPhone)) {
      throw new HttpsError('invalid-argument', 'The buddy request is invalid.');
    }
    const ownerRef = userRef(ownerPhone), otherRef = userRef(otherPhone);
    const ownerKey = phoneKey(ownerPhone), otherKey = phoneKey(otherPhone);
    const newRequestId = randomUUID();
    return db.runTransaction(async transaction => {
      const [ownerSnapshot, otherSnapshot] = await Promise.all([
        readUser(ownerRef, ['profile', 'social'], transaction),
        readUser(otherRef, ['profile', 'social'], transaction),
      ]);
      if (!ownerSnapshot.exists) {
        throw new HttpsError('not-found', 'Your hiker account is unavailable.');
      }
      const owner = ownerSnapshot.data() || {}, other = otherSnapshot.data() || {};
      const isBuddy = (owner.buddyPhoneNumbers || []).some(phone => phoneKey(phone) === otherKey);
      if (action === 'send') {
        if (!otherSnapshot.exists || disabled(other)) {
          throw new HttpsError('failed-precondition', 'This hiker is unavailable.');
        }
        if (isBuddy) {
          throw new HttpsError('failed-precondition', 'This hiker is already your buddy.');
        }
        if (owner.buddyRequestsOutgoing?.[otherKey]) return {status: 'sent'};
        if (owner.buddyRequestsIncoming?.[otherKey]) {
          throw new HttpsError('failed-precondition',
            'This hiker has already sent you a request. Open Friend requests to respond.');
        }
        const rateRef = db.collection('buddyRequestRateLimits').doc(uid);
        const rateSnapshot = await transaction.get(rateRef);
        const rate = rateSnapshot.data() || {}, createdAtMillis = now();
        const windowStartedAtMillis = Number(rate.windowStartedAtMillis || 0);
        const inWindow = createdAtMillis - windowStartedAtMillis < 60 * 60 * 1000;
        const count = inWindow ? Number(rate.requestCount || 0) : 0;
        if (count >= 20) {
          throw new HttpsError('resource-exhausted', 'Too many buddy requests were sent. Try again later.');
        }
        const displayName = String(displayNameFor(owner, `Hiker ${ownerKey.slice(-4)}`)).slice(0, 80);
        const photoURL = String(owner.profile?.photoURL || '').slice(0, 2000);
        const createdAtLocal = new Date(createdAtMillis).toISOString();
        setUser(transaction, otherRef, {
          buddyRequestsIncoming: {[ownerKey]: {
            requestId: newRequestId, phoneNumber: ownerPhone, displayName,
            handle: `@hiker${ownerKey.slice(-4)}`, ...(photoURL ? {photoURL} : {}), createdAtLocal,
          }}, buddyRequestsUpdatedAt: timestamp(),
        }, {merge: true});
        setUser(transaction, ownerRef, {
          buddyRequestsOutgoing: {[otherKey]: {
            requestId: newRequestId, phoneNumber: otherPhone, createdAtLocal,
          }}, buddyRequestsUpdatedAt: timestamp(),
        }, {merge: true});
        transaction.set(rateRef, {
          windowStartedAtMillis: inWindow ? windowStartedAtMillis : createdAtMillis,
          requestCount: count + 1, updatedAt: timestamp(),
        }, {merge: true});
        transaction.create(noticeRef(newRequestId), {
          type: 'buddy_request', requestId: newRequestId, status: 'pending',
          senderPhoneNumber: ownerPhone, recipientPhoneNumber: otherPhone, senderName: displayName,
          createdAtMillis, createdAt: timestamp(), createdAtLocal,
          notBeforeMillis: createdAtMillis + NOTIFICATION_DELAY_MILLIS,
        });
        return {status: 'sent'};
      }

      const cancelling = action === 'cancel';
      const pending = cancelling
        ? owner.buddyRequestsOutgoing?.[otherKey]
        : owner.buddyRequestsIncoming?.[otherKey];
      if (!pending) {
        if (cancelling && !isBuddy) return {status: 'cancelled'};
        throw new HttpsError('failed-precondition', isBuddy
          ? 'This request was already accepted. You are now buddies.'
          : 'This buddy request has already been handled.');
      }
      const reciprocal = cancelling
        ? other.buddyRequestsIncoming?.[ownerKey]
        : other.buddyRequestsOutgoing?.[ownerKey];
      const sameRequest = reciprocal && (pending.requestId
        ? reciprocal.requestId === pending.requestId
        : !reciprocal.requestId && reciprocal.createdAtLocal === pending.createdAtLocal);
      if (!cancelling && (!otherSnapshot.exists || !sameRequest || disabled(other))) {
        throw new HttpsError('failed-precondition', 'This buddy request is no longer available.');
      }
      const outboxRef = pending.requestId ? noticeRef(pending.requestId) : null;
      const outbox = outboxRef ? await transaction.get(outboxRef) : null;
      const ownerUpdate = {
        [`${cancelling ? 'buddyRequestsOutgoing' : 'buddyRequestsIncoming'}.${otherKey}`]: FieldValue.delete(),
        buddyRequestsUpdatedAt: timestamp(),
      };
      const otherUpdate = {
        [`${cancelling ? 'buddyRequestsIncoming' : 'buddyRequestsOutgoing'}.${ownerKey}`]: FieldValue.delete(),
        buddyRequestsUpdatedAt: timestamp(),
      };
      if (action === 'accept') {
        ownerUpdate.buddyPhoneNumbers = FieldValue.arrayUnion(otherPhone);
        ownerUpdate.buddiesUpdatedAt = timestamp();
        otherUpdate.buddyPhoneNumbers = FieldValue.arrayUnion(ownerPhone);
        otherUpdate.buddiesUpdatedAt = timestamp();
      }
      updateUser(transaction, ownerRef, ownerUpdate);
      if (otherSnapshot.exists && sameRequest) updateUser(transaction, otherRef, otherUpdate);
      const notice = outbox?.data() || {};
      if (outbox?.exists && (notice.status === 'pending'
          || (notice.status === 'sending' && notice.deliveryPhase === 'preflight'))) {
        transaction.update(outboxRef, {status: 'cancelled', cancellationReason: action,
          processedAt: timestamp(), processedAtLocal: new Date(now()).toISOString()});
      }
      return {status: cancelling ? 'cancelled' : action === 'accept' ? 'accepted' : 'declined'};
    });
  }

  async function deliver(reference) {
    const initial = await reference.get();
    const notice = initial.data() || {};
    if (!initial.exists || notice.type !== 'buddy_request'
        || !['pending', 'sending'].includes(notice.status)) return;
    const due = Number(notice.notBeforeMillis);
    const created = Number(notice.createdAtMillis);
    if (!Number.isFinite(due) || !Number.isFinite(created)
        || due < created + NOTIFICATION_DELAY_MILLIS) {
      throw new Error('invalid_buddy_notification_deadline');
    }
    // A durable outbox owns this wait; closing the sender's app cannot skip or shorten it.
    if (now() < due) await delay(due - now());
    if (now() < due) throw new Error('buddy_notification_not_due');
    const claim = await lifecycle.claimOutbox(db, reference, timestamp, now());
    if (!claim) return;
    const payload = claim.payload;
    const finish = update => lifecycle.updateClaim(db, reference, claim.attemptId, update);
    try {
      const senderPhone = String(payload.senderPhoneNumber || '');
      const recipientPhone = String(payload.recipientPhoneNumber || '');
      if (!validPhone(senderPhone) || !validPhone(recipientPhone) || senderPhone === recipientPhone) {
        await finish({status: 'failed', error: 'invalid_buddy_notification'});
        return;
      }
      const recipientDevices = await readUser(userRef(recipientPhone), ['devices']);
      const tokens = tokensFor(recipientDevices.data() || {});
      // Re-read both request copies and claim outbound in the same transaction that cancel conflicts with.
      const outbound = await db.runTransaction(async transaction => {
        const [currentSnapshot, senderSnapshot, recipientSnapshot] = await Promise.all([
          transaction.get(reference),
          readUser(userRef(senderPhone), ['social'], transaction),
          readUser(userRef(recipientPhone), ['social'], transaction),
        ]);
        const current = currentSnapshot.data() || {};
        if (current.status !== 'sending' || current.deliveryPhase !== 'preflight'
            || current.deliveryAttemptId !== claim.attemptId) return false;
        const sender = senderSnapshot.data() || {}, recipient = recipientSnapshot.data() || {};
        const outgoing = sender.buddyRequestsOutgoing?.[phoneKey(recipientPhone)];
        const incoming = recipient.buddyRequestsIncoming?.[phoneKey(senderPhone)];
        const stillPending = senderSnapshot.exists && recipientSnapshot.exists
          && !disabled(sender) && !disabled(recipient)
          && outgoing?.requestId === payload.requestId && incoming?.requestId === payload.requestId
          && !(sender.buddyPhoneNumbers || []).some(phone => phoneKey(phone) === phoneKey(recipientPhone))
          && !(recipient.buddyPhoneNumbers || []).some(phone => phoneKey(phone) === phoneKey(senderPhone));
        if (!stillPending) {
          transaction.update(reference, {status: 'cancelled', cancellationReason: 'request_no_longer_pending',
            processedAt: timestamp(), processedAtLocal: new Date(now()).toISOString()});
          return false;
        }
        if (!tokens.length) {
          transaction.update(reference, {status: 'no_token', processedAt: timestamp()});
          return false;
        }
        transaction.update(reference, {deliveryPhase: 'outbound',
          deliveryLeaseExpiresAtMillis: now() + lifecycle.LEASE_MILLIS});
        return true;
      });
      if (!outbound) return;
      let successCount = 0, failureCount = 0;
      try {
        for (let index = 0; index < tokens.length; index += 500) {
          const response = await messaging().sendEachForMulticast({
            tokens: tokens.slice(index, index + 500),
            notification: {title: 'New friend request',
              body: `${String(payload.senderName || 'A hiker').slice(0, 80)} wants to be your hiking buddy.`},
            data: {type: 'buddy_request', requestId: payload.requestId, messageId: reference.id,
              deepLink: `hikercircle://buddy/requests?ownerPhoneNumber=${encodeURIComponent(recipientPhone)}`},
            android: {priority: 'high'},
            apns: {headers: {'apns-priority': '10'}, payload: {aps: {sound: 'default'}}},
          });
          successCount += response.successCount;
          failureCount += response.failureCount;
        }
      } catch (_) {
        await finish({status: 'delivery_uncertain', error: 'fcm_transport_error',
          successCount, failureCount, processedAt: timestamp()});
        return;
      }
      await finish({status: failureCount === 0 ? 'sent' : 'partial', successCount, failureCount,
        processedAt: timestamp(), processedAtLocal: new Date(now()).toISOString()});
    } catch (error) {
      if (await lifecycle.retryPreflight(db, reference, claim.attemptId, error, now())) throw error;
      await finish({status: 'delivery_uncertain', error: 'delivery_or_bookkeeping_failed', processedAt: timestamp()});
    }
  }
  return {manage, deliver};
}
module.exports = {createBuddyRequestService, NOTIFICATION_DELAY_MILLIS};

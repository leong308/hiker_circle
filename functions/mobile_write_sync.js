'use strict';
const {contentHash} = require('./mobile_cache_helpers');
const {Timestamp} = require('firebase-admin/firestore');
const ID = /^[^/\x00-\x1f]{1,240}$/;
const PHONE = /^\+[1-9]\d{7,14}$/;

// Compare Firestore timestamps without discarding their submillisecond ordering.
function atOrBefore(left, right) {
  if (!left || !right) return false;
  if (Number.isFinite(left.seconds) && Number.isFinite(right.seconds)) {
    return left.seconds < right.seconds || (left.seconds === right.seconds && left.nanoseconds <= right.nanoseconds);
  }
  return new Date(left).getTime() <= new Date(right).getTime();
}

// Fixed owner writes compare content inside the same transaction that acknowledges it.
function createMobileWriteSync({database, authorize, HttpsError, timestamp, preview, clock = Date.now}) {
  const fail = (message) => { throw new HttpsError('invalid-argument', message); };
  const id = value => { if (typeof value !== 'string' || !ID.test(value)) fail('Invalid record identity.'); return value; };
  const text = (value, max) => { if (typeof value !== 'string' || value.length > max) fail('Invalid message content.'); return value; };
  // Participants append immutable message identities; retrying never resets receipts or metadata.
  async function appendChatMessage(request) {
    const {uid, phoneNumber} = authorize(request);
    const chatId = id(request.data?.chatId), messageId = id(request.data?.messageId);
    const raw = request.data?.message || {}, now = clock();
    const sent = Date.parse(raw.sentAtLocal);
    if (!Number.isFinite(sent) || sent > now + 300000) fail('Invalid original message time.');
    const message = {chatId, senderPhone: phoneNumber, senderName: text(raw.senderName, 100),
      text: text(raw.text, 5000), sentAtLocal: raw.sentAtLocal, isSystemMessage: false, seenBy: [phoneNumber]};
    if (!message.senderName.length) fail('A sender name is required.');
    if (raw.attachment) {
      const a = raw.attachment;
      const prefix = `https://firebasestorage.googleapis.com/v0/b/hiker-circle.firebasestorage.app/o/group_chats%2F${encodeURIComponent(chatId)}%2Fattachments%2F`;
      if (!['image', 'video', 'document'].includes(a.type) || typeof a.url !== 'string' || !a.url.startsWith(prefix)
        || a.url.length > 2048 || !Number.isSafeInteger(a.sizeBytes) || a.sizeBytes < 1 || a.sizeBytes > 25 * 1024 * 1024) fail('Invalid attachment.');
      message.attachment = {type: a.type, url: a.url, fileName: text(a.fileName, 255), contentType: text(a.contentType, 150), sizeBytes: a.sizeBytes};
    }
    if (!message.text && !message.attachment) fail('An empty message cannot be sent.');
    if (raw.sharedPost) {
      const p = raw.sharedPost;
      message.sharedPost = {postId: id(p.postId), authorName: text(p.authorName, 100), caption: text(p.caption, 600), trailName: text(p.trailName, 160)};
    }
    const hash = contentHash(message);
    const db = database(), chat = db.collection('groupChats').doc(chatId), ref = chat.collection('messages').doc(messageId);
    return db.runTransaction(async tx => {
      const [c, existing] = await Promise.all([tx.get(chat), tx.get(ref)]);
      const data = c.data() || {};
      if (!c.exists || !data.participantPhones?.includes(phoneNumber) || data.isDeleted === true
        || (data.chatRemovesAtLocal && Date.parse(data.chatRemovesAtLocal) <= now)) throw new HttpsError('permission-denied', 'This conversation is unavailable.');
      if (existing.exists) {
        const saved = existing.data();
        // Ignore viewer receipts and server processing fields when comparing immutable content.
        const original = Object.fromEntries(Object.keys(message).filter(k => k !== 'seenBy').map(k => [k, saved[k]]));
        const incoming = {...message}; delete incoming.seenBy;
        if (!saved.payloadHash) { delete original.sentAtLocal; delete incoming.sentAtLocal; }
        if (saved.senderPhone !== phoneNumber || contentHash(original) !== contentHash(incoming)) throw new HttpsError('already-exists', 'This message identity has different content.');
      } else {
        tx.create(ref, {...message, createdAt: timestamp(), cloudCreatedAtMillis: now, payloadHash: hash, senderUserId: uid});
      }
      if (!Number.isFinite(Date.parse(data.lastMessageAtLocal)) || sent > Date.parse(data.lastMessageAtLocal)) {
        tx.set(chat, {lastMessage: preview(message), lastMessageAtLocal: message.sentAtLocal, lastMessageSenderPhone: phoneNumber}, {merge: true});
      }
      return {messageId, contentHash: hash, confirmed: true, sentAtLocal: existing.exists ? existing.data().sentAtLocal : message.sentAtLocal};
    });
  }

  // Old offline receipts advance monotonically and preserve messages newer than the read cutoff.
  async function acknowledgeChatRead(request) {
    const {phoneNumber} = authorize(request), chatId = id(request.data?.chatId);
    const requested = Date.parse(request.data?.readAtLocal);
    if (!Number.isFinite(requested)) fail('Invalid read time.');
    const db = database(), chat = db.collection('groupChats').doc(chatId), key = phoneNumber.replace(/\D/g, '');
    return db.runTransaction(async tx => {
      const snapshot = await tx.get(chat), data = snapshot.data() || {};
      if (!snapshot.exists || !data.participantPhones?.includes(phoneNumber)) throw new HttpsError('permission-denied', 'This conversation is unavailable.');
      const cutoff = Math.max(Date.parse(data.lastReadAt?.[key]) || 0, Math.min(clock(), requested));
      const [recent, legacy] = await Promise.all([
        tx.get(chat.collection('messages').where('createdAt', '>', Timestamp.fromMillis(cutoff)).limit(1001)),
        tx.get(chat.collection('messages').where('sentAtLocal', '>', new Date(cutoff).toISOString()).limit(1001)),
      ]);
      const messages = {docs: [...new Map([...recent.docs, ...legacy.docs].map(doc => [doc.id, doc])).values()], readTime: recent.readTime};
      if (messages.docs.length > 1000) throw new HttpsError('resource-exhausted', 'Open the conversation to refresh its unread state.');
      const unread = messages.docs.filter(doc => { const m = doc.data(); return m.senderPhone !== phoneNumber
        && m.isSystemMessage !== true && !atOrBefore(doc.createTime, Timestamp.fromMillis(cutoff)) && !m.seenBy?.includes(phoneNumber); }).length;
      tx.set(chat, {lastReadAt: {[key]: new Date(cutoff).toISOString()}, unreadCount: {[key]: unread},
        unreadReconciledThrough: {[key]: messages.readTime || snapshot.readTime}}, {merge: true});
      return {confirmed: true, readAtLocal: new Date(cutoff).toISOString(), unreadCount: unread};
    });
  }

  // Only the dirty safety field is eligible to overwrite cloud data; roles and other fields are absent.
  async function syncSafetyPreferences(request) {
    const {uid, phoneNumber} = authorize(request), field = request.data?.field;
    let value = request.data?.value;
    if (field === 'sos_contacts') {
      if (!Array.isArray(value) || value.length > 3) fail('Save up to three contacts.');
      const seen = new Set();
      value = value.map(c => {
        if (!PHONE.test(c?.phoneNumber) || c.phoneNumber === phoneNumber || seen.has(c.phoneNumber)) fail('Invalid emergency contact.');
        seen.add(c.phoneNumber);
        const name = text(c.name, 80), relationship = text(c.relationship, 80);
        if (!name.trim()) fail('A contact name is required.');
        return {name, relationship, phoneNumber: c.phoneNumber};
      });
    } else if (/^sosWhatsappNotes\.(manual|duress|medical)$/.test(field || '')) value = text(value, 240);
    else fail('Unsupported safety field.');
    const mode = field.split('.')[1], sequence = request.data?.operationSeq;
    if (mode && (!Number.isSafeInteger(sequence) || sequence < 1)) fail('A durable note revision is required.');
    const sessionId = request.auth?.token?.mobileSessionId || 'owner';
    const ref = database().collection('users').doc(uid).collection('modules').doc('sos');
    return database().runTransaction(async tx => {
      const snapshot = await tx.get(ref), data = snapshot.data() || {};
      if (request.auth?.token?.mobileSessionId) {
        const active = await tx.get(database().collection('mobileSessions').doc(uid));
        if (active.data()?.activeSessionId !== sessionId) throw new HttpsError('unauthenticated', 'Your active session changed.');
      }
      const previous = mode ? data.sosWhatsappNotes?.[mode] ?? '' : data.sos_contacts ?? [];
      const hash = contentHash(value), changed = contentHash(previous) !== hash;
      const operation = data.sosNoteOperations?.[mode];
      if (mode && operation?.sessionId === sessionId) {
        if (operation.sequence > sequence) return {confirmed: true, superseded: true, contentHash: contentHash(previous)};
        if (operation.sequence === sequence && operation.contentHash !== hash) throw new HttpsError('already-exists', 'This note revision has different content.');
      }
      if (changed) tx.set(ref, mode ? {sosWhatsappNotes: {[mode]: value}, sosWhatsappNotesUpdatedAt: timestamp()}
        : {sos_contacts: value, sosContactsCount: value.length, sosContactsUpdatedAt: timestamp()}, {merge: true});
      if (mode) tx.set(ref, {sosNoteOperations: {[mode]: {sessionId, sequence, contentHash: hash}}}, {merge: true});
      else tx.set(ref, {sosContactsCloudOnly: true}, {merge: true});
      return {confirmed: true, contentHash: hash, changed};
    });
  }
  return {appendChatMessage, acknowledgeChatRead, syncSafetyPreferences};
}
module.exports = {createMobileWriteSync, atOrBefore};

const { before, after, test } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, updateDoc, getDocs, collection, query, where, orderBy, serverTimestamp } = require('firebase/firestore');
const { ref, uploadBytes, getBytes } = require('firebase/storage');

let env;
let owner;
let other;
let admin;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-hiker-circle',
    firestore: { host: '127.0.0.1', port: 8181,
      rules: fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8') },
    storage: { host: '127.0.0.1', port: 9199,
      rules: fs.readFileSync(path.resolve(__dirname, '../storage.rules'), 'utf8') },
  });
  owner = env.authenticatedContext('owner', { phoneNumber: '+600000001' }).firestore();
  other = env.authenticatedContext('other', { phoneNumber: '+600000002' }).firestore();
  admin = env.authenticatedContext('admin', { phoneNumber: '+600000003', isAdmin: true }).firestore();
});
after(async () => { await env?.cleanup(); });

const payload = (extra = {}) => ({ uid: 'owner', category: 'Problem', message: 'The trail screen did not load.',
  screenshotPath: '', platform: 'android', status: 'New', createdAt: serverTimestamp(), ...extra });

test('owner can create and read, other users and anonymous cannot read', async () => {
  await assertSucceeds(getDoc(doc(owner, 'appFeedback/private')));
  await assertSucceeds(setDoc(doc(owner, 'appFeedback/private'), payload()));
  await assertSucceeds(getDoc(doc(owner, 'appFeedback/private')));
  await assertFails(getDoc(doc(other, 'appFeedback/private')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'appFeedback/private')));
  await assertSucceeds(getDoc(doc(admin, 'appFeedback/private')));
});

test('rejects forged owners, status, metadata, timestamps, oversized content and foreign screenshot paths', async () => {
  for (const [name, extra] of Object.entries({
    owner: {uid: 'other'}, status: {status: 'Resolved'}, metadata: {phoneNumber: 'secret'},
    date: {createdAt: new Date(0)}, message: {message: 'x'.repeat(4001)},
    screenshot: {screenshotPath: 'app_feedback/other/forged/screenshot.png'},
  })) {
    await assertFails(setDoc(doc(owner, `appFeedback/invalid-${name}`), payload(extra)));
  }
  await assertSucceeds(setDoc(doc(owner, 'appFeedback/with-image'), payload({screenshotPath: 'app_feedback/owner/with-image/screenshot.png'})));
});

test('only admins can change review status, not report content', async () => {
  await assertSucceeds(setDoc(doc(owner, 'appFeedback/status'), payload()));
  await assertFails(updateDoc(doc(owner, 'appFeedback/status'), {status: 'Resolved'}));
  await assertSucceeds(updateDoc(doc(admin, 'appFeedback/status'), {status: 'In review'}));
  await assertFails(updateDoc(doc(admin, 'appFeedback/status'), {message: 'Changed original report'}));
  await assertFails(updateDoc(doc(admin, 'appFeedback/status'), {status: 'Invalid'}));
});

test('personal history must filter by authenticated owner; admins can list inbox', async () => {
  await assertSucceeds(getDocs(query(collection(owner, 'appFeedback'), where('uid', '==', 'owner'), orderBy('createdAt', 'desc'))));
  await assertFails(getDocs(collection(owner, 'appFeedback')));
  await assertFails(getDocs(query(collection(other, 'appFeedback'), where('uid', '==', 'owner'))));
  await assertSucceeds(getDocs(collection(admin, 'appFeedback')));
});

test('screenshots are private and submitted attachments cannot be replaced', async () => {
  const storage = env.authenticatedContext('owner', {phoneNumber: '+600000001'}).storage();
  const otherStorage = env.authenticatedContext('other', {phoneNumber: '+600000002'}).storage();
  const adminStorage = env.authenticatedContext('admin', {phoneNumber: '+600000003', isAdmin: true}).storage();
  const file = 'app_feedback/owner/image-test/screenshot.png';
  const bytes = Uint8Array.from([137, 80, 78, 71]);
  await assertSucceeds(uploadBytes(ref(storage, file), bytes, {contentType: 'image/png'}));
  await assertSucceeds(getBytes(ref(storage, file)));
  await assertFails(getBytes(ref(otherStorage, file)));
  await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), file)));
  await assertSucceeds(getBytes(ref(adminStorage, file)));
  await assertFails(uploadBytes(ref(otherStorage, file), bytes, {contentType: 'image/png'}));
  await assertFails(uploadBytes(ref(storage, 'app_feedback/owner/bad-type/screenshot.png'), bytes, {contentType: 'text/plain'}));
  await assertFails(uploadBytes(ref(storage, 'app_feedback/owner/too-large/screenshot.png'), new Uint8Array(5 * 1024 * 1024 + 1), {contentType: 'image/png'}));
  await assertSucceeds(setDoc(doc(owner, 'appFeedback/image-test'), payload({screenshotPath: file})));
  await assertFails(uploadBytes(ref(storage, file), bytes, {contentType: 'image/png'}));
});

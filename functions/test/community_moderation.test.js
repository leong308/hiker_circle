'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {prepareContent, contentHash, sourceInfo, runIntegrityCheck,
  reviewContent, saveVerdict} = require('../community_moderation');
const {createHash} = require('node:crypto');
const idFor = path => createHash('sha256').update(path).digest('hex');
const post = caption => ({postId: 'p1', authorId: 'u1', visibility: 'public', caption});
const comment = body => ({postId: 'p1', commentId: 'c1', authorId: 'u2', body});
const NOW = Date.parse('2026-10-05T04:00:00Z');
function fixture(initial = {}) {
  const rows = new Map(Object.entries(initial));
  let queue = Promise.resolve();
  const snapshot = path => ({exists: rows.has(path), id: path.split('/').at(-1), ref: ref(path),
    data: () => structuredClone(rows.get(path))});
  function ref(path) {
    return {path, id: path.split('/').at(-1), get: async () => snapshot(path),
      set: async (patch, options) => rows.set(path, options?.merge ? {...rows.get(path), ...structuredClone(patch)} : structuredClone(patch)),
      update: async patch => rows.set(path, {...rows.get(path), ...patch}), delete: async () => rows.delete(path)};
  }
  function query(name, group = false) {
    let predicate = () => true, take = Infinity, cursor;
    const q = {doc: id => ref(`${name}/${id}`), where: (field, _op, value) => {predicate = row => row[field] === value; return q;},
      orderBy: () => q, limit: n => {take = n; return q;}, startAfter: value => {cursor = group ? value : `${name}/${value}`; return q;},
      get: async () => {
        const paths = [...rows.keys()].filter(path => (group ? path.split('/').at(-2) === name
          : path.startsWith(`${name}/`) && path.split('/').length === 2) && predicate(rows.get(path)) && (!cursor || path > cursor)).sort().slice(0, take);
        return {docs: paths.map(snapshot), size: paths.length, empty: paths.length === 0};
      }};
    return q;
  }
  const db = {doc: ref, collection: name => query(name), collectionGroup: name => query(name, true),
    runTransaction(fn) {
      const next = queue.then(async () => {
        const writes = [];
        const result = await fn({get: async reference => snapshot(reference.path),
          set: (reference, patch, options) => writes.push(() => reference.set(patch, options)),
          update: (reference, patch) => writes.push(() => reference.update(patch)),
          delete: reference => writes.push(() => reference.delete())});
        for (const write of writes) await write(); return result;
      });
      queue = next.catch(() => {}); return next;
    }};
  return {db, rows};
}

async function flaggedFixture(type = 'post') {
  const path = type === 'post' ? 'communityPosts/p1' : 'communityPosts/p1/comments/c1';
  const f = fixture({'communityPosts/p1': post('Review text'), ...(type === 'comment' ? {[path]: comment('Remove text')} : {})});
  const id = idFor(path), fingerprint = contentHash(path, f.rows.get(path));
  f.rows.set(`communityModerationChecks/${id}`, {sourcePath: path, fingerprint, stage: 'pending'});
  await saveVerdict(f.db, {path, id, fingerprint}, {flag: true, severity: 'medium', categories: ['spam_scam']}, NOW);
  return {...f, path, id};
}

test('only exact public-community source paths are eligible', () => {
  assert.equal(sourceInfo('communityPosts/p1/comments/c1').type, 'comment');
  for (const path of ['users/u1', 'groupChats/g1/messages/m1', 'other/p1/comments/c1', 'communityPosts/p1/comments/c1/private/x']) assert.equal(sourceInfo(path), null);
});

test('sensitive disclosures and malformed records go to manual review without external services', () => {
  for (const caption of ['call +60123456789', 'email a@b.com', 'OTP 123456', 'my injury details', 'my name is Alice', '3.12345, 101.12345']) {
    assert.equal(prepareContent('communityPosts/p1', post(caption)).manual, 'sensitive_content');
  }
  assert.equal(prepareContent('communityPosts/p1', {...post('hello'), postId: 'wrong'}).manual, 'integrity');
  assert.equal(prepareContent('communityPosts/p1/comments/c1', {...comment('hello'), postId: 'wrong'}).manual, 'integrity');
  const prepared = prepareContent('communityPosts/p1', {...post('Leong visit https://example.com/private?key=secret'), authorName: 'Leong'});
  assert.equal(prepared.text, '[hiker] visit [external link]');
  assert.equal(prepared.hasExternalLink, true);
});

test('caption-free photo posts are valid and do not upload images or produce an integrity flag', async () => {
  const f = fixture({'communityPosts/p1': {...post(''), imageUrls: ['https://example.com/photo.jpg']}});
  const result = await runIntegrityCheck({db: f.db, apiKey: 'private', fieldPath: '__name__', now: () => NOW,
    fetchImpl: async () => assert.fail('Unexpected external request')});
  assert.equal(result.checked, 1); assert.equal(result.flagged, 0);
});

test('dismissal preserves content and repeated decisions are idempotent', async () => {
  const f = await flaggedFixture();
  assert.equal((await reviewContent({db: f.db, reviewId: f.id, action: 'dismiss', adminId: 'admin', now: NOW})).status, 'dismissed');
  assert.equal(f.rows.get(f.path).visibility, 'public');
  assert.equal((await reviewContent({db: f.db, reviewId: f.id, action: 'hide', adminId: 'admin', now: NOW})).status, 'already-reviewed');
});

test('explicit administrator hide preserves the post; comment removal preserves a private audit copy', async () => {
  const f = await flaggedFixture();
  await reviewContent({db: f.db, reviewId: f.id, action: 'hide', adminId: 'admin', now: NOW});
  assert.equal(f.rows.get(f.path).visibility, 'hidden'); assert.equal(f.rows.get(f.path).caption, 'Review text');
  const g = await flaggedFixture('comment');
  await reviewContent({db: g.db, reviewId: g.id, action: 'hide', adminId: 'admin', now: NOW});
  assert.equal(g.rows.has(g.path), false);
  assert.equal(g.rows.get(`communityModerationReviews/${g.id}`).removedBody, 'Remove text');
});

test('a human decision cannot hide edited or already-private content', async () => {
  const f = await flaggedFixture(); f.rows.set(f.path, post('Edited text'));
  const result = await reviewContent({db: f.db, reviewId: f.id, action: 'hide', adminId: 'admin', now: NOW});
  assert.equal(result.status, 'superseded'); assert.equal(f.rows.get(f.path).visibility, 'public');
  await assert.rejects(reviewContent({db: f.db, reviewId: '../users', action: 'hide'}), /invalid-review/);
});

test('callable requires trusted admin claims; scheduler is bounded and runs every 30 minutes', async () => {
  const source = fs.readFileSync(require.resolve('../index'), 'utf8');
  const start = source.indexOf('exports.checkCommunityContentIntegrity =');
  const block = source.slice(start, source.indexOf('exports.askHikerCircleAssistant', start));
  let config, called = 0;
  const exports = {};
  vm.runInNewContext(block, {exports, onSchedule: (options, fn) => {config = options; return fn;}, onCall: (_options, fn) => fn,
    HttpsError: class extends Error {constructor(code, message) {super(message); this.code = code;}},
    admin: {firestore: () => ({})}, logger: {error() {}}, require: () => ({reviewContent: async () => {called++; return {};}})});
  assert.equal(config.schedule, 'every 30 minutes'); assert.equal(config.maxInstances, 1); assert.equal(config.timeoutSeconds, 240);
  for (const auth of [undefined, {uid: 'u', token: {}}, {uid: 'u', token: {isAdmin: false}}]) {
    await assert.rejects(exports.reviewCommunityContentFlag({auth, data: {}}), error => error.code === 'permission-denied');
  }
  await exports.reviewCommunityContentFlag({auth: {uid: 'admin', token: {isAdmin: true}}, data: {}});
  assert.equal(called, 1);
});

test('local moderation flags sensitive data while ordinary and private content remain untouched', async () => {
  const f = fixture({'communityPosts/p1': post('call +60123456789'),
    'communityPosts/p2': {...post('A beautiful hiking day'), postId:'p2'},
    'communityPosts/private': {...post('OTP 123456'), postId:'private', visibility:'private'}});
  const previousFetch = global.fetch;
  global.fetch = async () => assert.fail('Local moderation must never call a provider');
  try {
    const result = await runIntegrityCheck({db:f.db, fieldPath:'__name__', now:()=>NOW});
    assert.equal(result.flagged,1); assert.equal(result.checked,2);
    assert.equal(f.rows.get('communityPosts/p1').visibility,'public');
    assert.equal(f.rows.has(`communityModerationChecks/${idFor('communityPosts/private')}`),false);
    const next = await runIntegrityCheck({db:f.db, fieldPath:'__name__', now:()=>NOW+1000});
    assert.equal(next.checked,0);
  } finally {global.fetch = previousFetch;}
});
test('existing pending flags survive provider removal until an administrator reviews them', async () => {
  const f = await flaggedFixture();
  f.rows.get(`communityModerationChecks/${f.id}`).stage='pending';
  await runIntegrityCheck({db:f.db, fieldPath:'__name__', now:()=>NOW});
  assert.equal(f.rows.get(`communityModerationReviews/${f.id}`).status,'pending');
  await reviewContent({db:f.db, reviewId:f.id, action:'dismiss', adminId:'admin', now:NOW});
  await runIntegrityCheck({db:f.db, fieldPath:'__name__', now:()=>NOW+1000});
  assert.equal(f.rows.get(`communityModerationReviews/${f.id}`).status,'dismissed');
});
test('changed captions are checked again and hidden sources supersede pending flags', async () => {
  const f = fixture({'communityPosts/p1':post('Normal walk')});
  await runIntegrityCheck({db:f.db,fieldPath:'__name__',now:()=>NOW});
  f.rows.set('communityPosts/p1',post('OTP 123456'));
  assert.equal((await runIntegrityCheck({db:f.db,fieldPath:'__name__',now:()=>NOW+1000})).flagged,1);
  f.rows.set('communityPosts/p1',{...post('OTP 123456'),visibility:'hidden'});
  await runIntegrityCheck({db:f.db,fieldPath:'__name__',now:()=>NOW+2000});
  assert.equal(f.rows.get(`communityModerationReviews/${idFor('communityPosts/p1')}`).status,'superseded');
});

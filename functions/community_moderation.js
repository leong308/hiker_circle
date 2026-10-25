// Community text integrity scans and human moderation preserve source fingerprints and audit decisions.
'use strict';
const {createHash, randomUUID} = require('node:crypto');
const VERSION = 2;
const CATEGORIES = ['spam_scam', 'harassment', 'hate', 'sexual', 'violence', 'privacy', 'unsafe_advice'];
const LABELS = {spam_scam: 'Possible spam or scam', harassment: 'Possible harassment', hate: 'Possible hate speech',
  sexual: 'Possible sexual content', violence: 'Possible threats or graphic violence', privacy: 'Personal information',
  unsafe_advice: 'Potentially dangerous advice', integrity: 'Content record needs review',
  sensitive_content: 'Sensitive information: manual review required',
  provider_safety: 'Content requires manual review',
  check_unavailable: 'Content requires manual review'};
// Evidence records rule identities, never the personal information that matched a rule.
const SENSITIVE_KEYWORDS = ['my name is', 'nama saya', 'password', 'kata laluan', 'otp',
  'verification code', 'authenticator', 'diagnosed', 'diagnosis', 'medical record', 'my injury',
  'my illness', 'alamat rumah', 'home address', 'ic number', 'passport'];
const KEYWORD_RULES = SENSITIVE_KEYWORDS.map(phrase => ({phrase,
  id: `keyword:${phrase.replaceAll(' ', '_')}`, expression: new RegExp(`\\b${phrase}\\b`, 'i')}));
const PATTERN_RULES = [
  {id: 'pattern:email_address', expression: /[\w.+-]+@[\w.-]+\.[a-z]{2,}/i},
  {id: 'pattern:phone_number', expression: /(?:\+?\d[\d ().-]{6,}\d)/},
  {id: 'pattern:coordinates', expression: /-?\d{1,3}\.\d{3,}\s*[,/]\s*-?\d{1,3}\.\d{3,}/},
];
const INTEGRITY_RULES = ['record:invalid_path', 'record:invalid_text', 'record:empty_comment',
  'record:text_too_long', 'record:invalid_author'];
const EVIDENCE_IDS = new Set([...KEYWORD_RULES, ...PATTERN_RULES].map(rule => rule.id).concat(INTEGRITY_RULES));
function integrityResult(evidence) {
  return {manual: 'integrity', detectionSource: 'integrity', detectionEvidence: evidence, matchedKeywords: []};
}
function verdictProvenance(verdict) {
  if (!['keywords', 'pattern', 'integrity'].includes(verdict.detectionSource)) return {};
  return {detectionSource: verdict.detectionSource,
    detectionEvidence: [...new Set((Array.isArray(verdict.detectionEvidence) ? verdict.detectionEvidence : [])
      .filter(id => EVIDENCE_IDS.has(id)))],
    matchedKeywords: [...new Set((Array.isArray(verdict.matchedKeywords) ? verdict.matchedKeywords : [])
      .filter(phrase => SENSITIVE_KEYWORDS.includes(phrase)))]};
}
const sha = text => createHash('sha256').update(text).digest('hex');
function sourceInfo(path) {
  const match = /^communityPosts\/([^/]+)(?:\/comments\/([^/]+))?$/.exec(path || '');
  return match ? {postId: match[1], commentId: match[2] || null, type: match[2] ? 'comment' : 'post'} : null;
}
function contentHash(path, data) {
  const info = sourceInfo(path);
  return sha(JSON.stringify([VERSION, path, info?.type === 'post' ? data.caption : data.body, data.authorId]));
}
// prepareContent: Keep sensitive disclosures on the local review path and redact author/link context.
function prepareContent(path, data) {
  const info = sourceInfo(path);
  if (!info) return integrityResult(['record:invalid_path']);
  const text = info.type === 'post' ? data?.caption : data?.body;
  const integrityEvidence = [];
  if (typeof text !== 'string') integrityEvidence.push('record:invalid_text');
  else {
    if (info.type === 'comment' && !text.trim()) integrityEvidence.push('record:empty_comment');
    if (text.length > (info.type === 'post' ? 5000 : 2000)) integrityEvidence.push('record:text_too_long');
  }
  if (typeof data?.authorId !== 'string' || !data.authorId || data.authorId.length > 200) {
    integrityEvidence.push('record:invalid_author');
  }
  if (integrityEvidence.length) return integrityResult(integrityEvidence);
  // Caption-free hike/photo posts are valid. Images are outside this text-only checker.
  if (!text.trim()) return {skip: true};
  // Fail closed on identifiable/sensitive disclosures rather than send them outside the app backend.
  const keywords = KEYWORD_RULES.filter(rule => rule.expression.test(text));
  const patterns = PATTERN_RULES.filter(rule => rule.expression.test(text));
  if (keywords.length || patterns.length) return {manual: 'sensitive_content',
    detectionSource: keywords.length ? 'keywords' : 'pattern',
    detectionEvidence: [...keywords, ...patterns].map(rule => rule.id),
    matchedKeywords: keywords.map(rule => rule.phrase)};
  let redacted = text.replace(/https?:\/\/\S+|www\.\S+/gi, '[external link]');
  for (const value of [data.author?.name]) {
    if (typeof value === 'string' && value.length >= 2) redacted = redacted.split(value).join('[hiker]');
  }
  return {text: redacted, hasExternalLink: /https?:\/\/|www\./i.test(text)};
}
async function eligibleSource(db, path) {
  const info = sourceInfo(path);
  if (!info) return null;
  const source = await db.doc(path).get();
  if (!source.exists) return null;
  const parent = info.type === 'post' ? source : await db.doc(`communityPosts/${info.postId}`).get();
  if (!parent.exists || parent.data()?.visibility !== 'public') return null;
  return source;
}
async function saveVerdict(db, candidate, verdict, now) {
  const checkRef = db.collection('communityModerationChecks').doc(candidate.id);
  const reviewRef = db.collection('communityModerationReviews').doc(candidate.id);
  return db.runTransaction(async tx => {
    const check = await tx.get(checkRef);
    const existingReview = await tx.get(reviewRef);
    const source = await tx.get(db.doc(candidate.path));
    const info = sourceInfo(candidate.path);
    const parent = info.type === 'post' ? source : await tx.get(db.doc(`communityPosts/${info.postId}`));
    if (!source.exists || parent.data()?.visibility !== 'public'
      || check.data()?.fingerprint !== candidate.fingerprint || check.data()?.stage !== 'pending'
      || contentHash(candidate.path, source.data()) !== candidate.fingerprint) return false;
    if (existingReview.data()?.fingerprint === candidate.fingerprint
      && ['dismissed', 'actioned'].includes(existingReview.data()?.status)) {
      tx.set(checkRef, {stage: 'checked', checkedAtMillis: now}, {merge: true});
      return false;
    }
    tx.set(checkRef, {stage: verdict.retry ? 'pending' : 'checked',
      checkedAtMillis: now}, {merge: true});
    // An in-flight retry must not rewrite a review or fabricate provenance for a legacy row.
    if (existingReview.data()?.fingerprint === candidate.fingerprint
      && existingReview.data()?.status === 'pending') return true;
    if (verdict.flag) tx.set(reviewRef, {
      sourcePath: candidate.path, postId: info.postId, contentType: info.type,
      fingerprint: candidate.fingerprint, status: 'pending', severity: verdict.severity,
      categories: verdict.categories, reasons: verdict.categories.map(c => LABELS[c]),
      policyVersion: VERSION, flaggedAtMillis: now,
      ...verdictProvenance(verdict),
    });
    else if (existingReview.data()?.status !== 'pending') {
      tx.set(reviewRef, {status: 'clear', fingerprint: candidate.fingerprint, checkedAtMillis: now}, {merge: true});
    }
    return true;
  });
}
async function scanPage(db, collection, cursor, limit, fieldPath) {
  let query = collection.orderBy(fieldPath).limit(limit);
  if (cursor) query = query.startAfter(cursor);
  const page = await query.get();
  return {docs: page.docs, cursor: page.size === limit ? page.docs.at(-1).ref.path : null};
}
// scanContent: Fingerprint only eligible public post/comment paths; changed text supersedes old verdicts.
async function scanContent(db, state, now, fieldPath) {
  const posts = await scanPage(db, db.collection('communityPosts'), state.postCursor, 100, fieldPath);
  const comments = await scanPage(db, db.collectionGroup('comments'), state.commentCursor, 150, fieldPath);
  for (const document of [...posts.docs, ...comments.docs]) {
    const path = document.ref.path;
    const info = sourceInfo(path);
    if (!info) continue; // Other collections' comments and private chats are never submitted.
    const data = document.data();
    if (info.type === 'post' && data.visibility !== 'public') continue;
    if (info.type === 'comment' && !(await eligibleSource(db, path))) continue;
    const fingerprint = contentHash(path, data);
    const id = sha(path);
    const ref = db.collection('communityModerationChecks').doc(id);
    await db.runTransaction(async tx => {
      const current = await tx.get(ref);
      if (current.data()?.fingerprint === fingerprint && current.data()?.stage !== 'stale') return;
      tx.set(ref, {sourcePath: path, fingerprint, stage: 'pending', discoveredAtMillis: now, policyVersion: VERSION});
      // Previously flagged text changed: do not present a verdict for the old version.
      tx.set(db.collection('communityModerationReviews').doc(id), {status: 'superseded', fingerprint}, {merge: true});
    });
  }
  return {postCursor: posts.cursor ? posts.cursor.split('/').at(-1) : null, commentCursor: comments.cursor,
    scannedPosts: posts.docs.length, scannedComments: comments.docs.length};
}
async function reconcilePendingReviews(db, now) {
  const pending = await db.collection('communityModerationReviews').where('status', '==', 'pending').limit(100).get();
  let superseded = 0;
  for (const review of pending.docs) {
    const data = review.data(); const info = sourceInfo(data.sourcePath);
    if (!info) continue;
    const changed = await db.runTransaction(async tx => {
      const fresh = await tx.get(review.ref);
      if (fresh.data()?.status !== 'pending' || fresh.data()?.fingerprint !== data.fingerprint) return false;
      const source = await tx.get(db.doc(data.sourcePath));
      const parent = info.type === 'post' ? source : await tx.get(db.doc(`communityPosts/${info.postId}`));
      if (source.exists && parent.data()?.visibility === 'public'
        && contentHash(data.sourcePath, source.data()) === data.fingerprint) return false;
      tx.set(review.ref, {status: 'superseded', supersededAtMillis: now}, {merge: true}); return true;
    });
    if (changed) superseded++;
  }
  return superseded;
}
async function runIntegrityCheck({db, fieldPath, now = Date.now}) {
  const runRef = db.doc('maintenanceState/communityModerationRun');
  const healthRef = db.doc('communityModerationStatus/current');
  const owner = randomUUID();
  const acquired = await db.runTransaction(async tx => {
    const record = await tx.get(runRef); const data = record.data() || {};
    if (data.leaseExpiresAtMillis > now()) return null;
    tx.set(runRef, {leaseOwner: owner, leaseExpiresAtMillis: now() + 300000}, {merge: true}); return data;
  });
  if (!acquired) return {skipped: true};
  let result = {status: 'completed', checked: 0, flagged: 0, deferred: 0};
  try {
    const scan = await scanContent(db, acquired, now(), fieldPath);
    result = {...result, ...scan, superseded: await reconcilePendingReviews(db, now())};
    const pending = await db.collection('communityModerationChecks').where('stage', '==', 'pending').limit(24).get();
    const candidates = [];
    for (const check of pending.docs) {
      const data = check.data(); const source = await eligibleSource(db, data.sourcePath);
      if (!source || contentHash(data.sourcePath, source.data()) !== data.fingerprint) {
        await check.ref.set({stage: 'stale'}, {merge: true});
        await db.collection('communityModerationReviews').doc(check.id).set({status: 'superseded'}, {merge: true});
        continue;
      }
      const prepared = prepareContent(data.sourcePath, source.data());
      const candidate = {id: check.id, path: data.sourcePath, fingerprint: data.fingerprint};
      if (prepared.skip) {
        if (await saveVerdict(db, candidate, {flag: false, severity: 'low', categories: []}, now())) result.checked++;
      } else if (prepared.manual) {
        if (await saveVerdict(db, candidate, {flag: true, severity: 'medium', categories: [prepared.manual],
          detectionSource: prepared.detectionSource, detectionEvidence: prepared.detectionEvidence,
          matchedKeywords: prepared.matchedKeywords}, now())) {
          result.checked++; result.flagged++;
        }
      } else candidates.push({...candidate, ...prepared});
    }
    for (const candidate of candidates) {
      if (await saveVerdict(db, candidate, {flag: false, severity: 'low', categories: []}, now())) result.checked++;
    }
    await runRef.set({postCursor: scan.postCursor, commentCursor: scan.commentCursor}, {merge: true});
    await healthRef.set({...result, lastRunAtMillis: now(), intervalMinutes: 30, mode: 'local_rules'});
    return result;
  } catch (error) {
    await healthRef.set({status: 'failed', lastRunAtMillis: now(), intervalMinutes: 30,
      errorCode: 'scan-failed', checked: result.checked, flagged: result.flagged});
    throw error;
  } finally {
    await db.runTransaction(async tx => {
      const record = await tx.get(runRef);
      if (record.data()?.leaseOwner === owner) tx.set(runRef, {leaseOwner: null, leaseExpiresAtMillis: 0}, {merge: true});
    });
  }
}
// reviewContent: Apply a human decision only while its source fingerprint still matches.
async function reviewContent({db, reviewId, action, adminId, now = Date.now()}) {
  if (!/^[a-f0-9]{64}$/.test(reviewId || '') || !['dismiss', 'hide'].includes(action)) throw new Error('invalid-review');
  return db.runTransaction(async tx => {
    const ref = db.collection('communityModerationReviews').doc(reviewId);
    const review = await tx.get(ref); const data = review.data() || {};
    if (!review.exists || data.status !== 'pending') return {status: 'already-reviewed'};
    const info = sourceInfo(data.sourcePath);
    if (!info) throw new Error('invalid-review');
    const sourceRef = db.doc(data.sourcePath); const source = await tx.get(sourceRef);
    const postRef = db.doc(`communityPosts/${info.postId}`);
    const parent = info.type === 'post' ? source : await tx.get(postRef);
    if (!source.exists || parent.data()?.visibility !== 'public' || contentHash(data.sourcePath, source.data()) !== data.fingerprint) {
      tx.set(ref, {status: 'superseded', reviewedAtMillis: now, reviewedBy: adminId}, {merge: true});
      return {status: 'superseded'};
    }
    if (action === 'hide') {
      if (info.type === 'comment') {
        // Explicit human removal only; preserve the text in the admin-only audit record.
        tx.set(ref, {removedBody: source.data().body}, {merge: true}); tx.delete(sourceRef);
        tx.update(postRef, {commentCount: Math.max(0, Math.round(Number(parent.data()?.commentCount) || 0) - 1)});
      } else tx.update(sourceRef, {visibility: 'hidden',
        moderation: {status: 'hidden', reason: 'Reviewed by an administrator', adminId, at: new Date(now)},
        updatedAt: new Date(now)});
    }
    tx.set(db.collection('communityModerationChecks').doc(reviewId),
      {stage: 'checked', checkedAtMillis: now}, {merge: true});
    tx.set(ref, {status: action === 'dismiss' ? 'dismissed' : 'actioned', action,
      reviewedAtMillis: now, reviewedBy: adminId}, {merge: true});
    return {status: action === 'dismiss' ? 'dismissed' : 'actioned'};
  });
}
module.exports = {VERSION, CATEGORIES, sourceInfo, contentHash, prepareContent,
  saveVerdict, runIntegrityCheck, reviewContent};

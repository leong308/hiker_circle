// Community text integrity scans and human moderation preserve source fingerprints and audit decisions.
'use strict';
const {createHash, randomUUID} = require('node:crypto');
const {MAX_POST_CAPTION_LENGTH} = require('./community_content_limits');
const {beginIntegrityRun, finishIntegrityRun, releaseIntegrityRun} = require('./community_integrity_schedule');
const {VERSION, POLICY_HASH, categories: CATEGORIES, labels: LABELS,
  keywords: POLICY_KEYWORDS, evidenceLabels: EVIDENCE_LABELS, detect} = require('./community_moderation_policy');
// Keep invalid records separate from language-policy concerns.
function integrityResult(evidence) {
  return {manual: 'integrity', detectionSource: 'integrity', detectionEvidence: evidence, matchedKeywords: []};
}
// Save only evidence identities explicitly authored in the shared policy.
function verdictProvenance(verdict) {
  if (!['keywords', 'pattern', 'integrity'].includes(verdict.detectionSource)) return {};
  return {detectionSource: verdict.detectionSource,
    detectionEvidence: [...new Set((Array.isArray(verdict.detectionEvidence) ? verdict.detectionEvidence : [])
      .filter(id => EVIDENCE_LABELS.has(id)))],
    matchedKeywords: [...new Set((Array.isArray(verdict.matchedKeywords) ? verdict.matchedKeywords : [])
      .filter(phrase => POLICY_KEYWORDS.has(phrase)))]};
}
const sha = text => createHash('sha256').update(text).digest('hex');
// Accept only public-feed post/comment paths, never chat or unrelated comment collections.
function sourceInfo(path) {
  const match = /^communityPosts\/([^/]+)(?:\/comments\/([^/]+))?$/.exec(path || '');
  return match ? {postId: match[1], commentId: match[2] || null, type: match[2] ? 'comment' : 'post'} : null;
}
// A catalog edit invalidates clear checks even if its version was not manually increased.
function contentHash(path, data) {
  const info = sourceInfo(path);
  return sha(JSON.stringify([VERSION, POLICY_HASH, path, info?.type === 'post' ? data.caption : data.body, data.authorId]));
}
// Identify unchanged text independently of the policy, so human decisions survive catalog updates.
function sourceFingerprint(path, data) {
  const info = sourceInfo(path);
  return sha(JSON.stringify([path, info?.type === 'post' ? data.caption : data.body, data.authorId]));
}
// Recognize human decisions created by the former version-two checker.
function legacyFingerprint(path, data) {
  const info = sourceInfo(path);
  return sha(JSON.stringify([2, path, info?.type === 'post' ? data.caption : data.body, data.authorId]));
}
// Validate records before applying the shared language rules to their text.
function prepareContent(path, data) {
  const info = sourceInfo(path);
  if (!info) return integrityResult(['record:invalid_path']);
  const text = info.type === 'post' ? data?.caption : data?.body;
  const integrityEvidence = [];
  if (typeof text !== 'string') integrityEvidence.push('record:invalid_text');
  else {
    if (info.type === 'comment' && !text.trim()) integrityEvidence.push('record:empty_comment');
    if (text.length > (info.type === 'post' ? MAX_POST_CAPTION_LENGTH : 2000)) integrityEvidence.push('record:text_too_long');
  }
  if (typeof data?.authorId !== 'string' || !data.authorId || data.authorId.length > 200) {
    integrityEvidence.push('record:invalid_author');
  }
  if (integrityEvidence.length) return integrityResult(integrityEvidence);
  // Caption-free hike/photo posts are valid. Images are outside this text-only checker.
  if (!text.trim()) return {skip: true};
  return detect(text) || {};
}
// Re-read visibility before a saved check can inspect a source.
async function eligibleSource(db, path) {
  const info = sourceInfo(path);
  if (!info) return null;
  const source = await db.doc(path).get();
  if (!source.exists) return null;
  const parent = info.type === 'post' ? source : await db.doc(`communityPosts/${info.postId}`).get();
  if (!parent.exists || parent.data()?.visibility !== 'public') return null;
  return source;
}
// Fence source changes and concurrent human decisions before saving a rule verdict.
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
      sourceFingerprint: sourceFingerprint(candidate.path, source.data()), policyHash: POLICY_HASH,
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
// Bound discovery work while continuing through the whole collection over successive passes.
async function scanPage(db, collection, cursor, limit, fieldPath) {
  let query = collection.orderBy(fieldPath).limit(limit);
  if (cursor) query = query.startAfter(cursor);
  const page = await query.get();
  return {docs: page.docs, cursor: page.size === limit ? page.docs.at(-1).ref.path : null};
}
// scanContent: Fingerprint only eligible public post/comment paths; changed text supersedes old verdicts.
async function scanContent(db, state, now, fieldPath) {
  const currentPolicy = state.policyHash === POLICY_HASH;
  const posts = await scanPage(db, db.collection('communityPosts'), currentPolicy ? state.postCursor : null, 100, fieldPath);
  const comments = await scanPage(db, db.collectionGroup('comments'), currentPolicy ? state.commentCursor : null, 150, fieldPath);
  let queued = 0, decisionsPreserved = 0;
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
      const reviewRef = db.collection('communityModerationReviews').doc(id);
      const reviewRecord = await tx.get(reviewRef);
      const review = reviewRecord.data() || {};
      const identity = sourceFingerprint(path, data);
      const preserved = ['dismissed', 'actioned'].includes(review.status)
        && (review.sourceFingerprint === identity || review.fingerprint === legacyFingerprint(path, data)
          || review.fingerprint === fingerprint);
      if (!preserved && reviewRecord.exists && review.fingerprint && review.fingerprint !== fingerprint) {
        // Keep the prior audit, including removals and decisions, before the live queue row is replaced.
        tx.set(reviewRef.collection('history').doc(sha(review.fingerprint)), {...review, archivedAtMillis: now});
      }
      tx.set(ref, {sourcePath: path, fingerprint, sourceFingerprint: identity,
        stage: preserved ? 'checked' : 'pending', discoveredAtMillis: now, policyVersion: VERSION, policyHash: POLICY_HASH});
      if (preserved) {
        tx.set(reviewRef, {sourceFingerprint: identity, recheckedAtMillis: now,
          recheckedPolicyHash: POLICY_HASH, recheckResult: 'human_decision_preserved'}, {merge: true});
      } else {
        tx.set(reviewRef, {status: 'superseded', fingerprint}, {merge: true});
      }
      return preserved ? 'preserved' : 'queued';
    }).then(outcome => { if (outcome === 'preserved') decisionsPreserved++; else if (outcome === 'queued') queued++; });
  }
  return {postCursor: posts.cursor ? posts.cursor.split('/').at(-1) : null, commentCursor: comments.cursor,
    scannedPosts: posts.docs.length, scannedComments: comments.docs.length, queued, decisionsPreserved};
}
// Supersede pending flags when their content disappears, becomes private or changes.
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
// Share the same lease, matching and thirty-minute deadline for scheduled and manual checks.
async function runIntegrityCheck({db, fieldPath, now = Date.now, force = false}) {
  const owner = randomUUID();
  const acquired = await beginIntegrityRun({db, owner, force, now});
  if (!acquired.acquired) return acquired.result;
  let published = false;
  let result = {status: 'completed', checked: 0, flagged: 0, deferred: 0,
    policyVersion: VERSION, policyHash: POLICY_HASH};
  try {
    const scan = await scanContent(db, acquired.state, now(), fieldPath);
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
        if (await saveVerdict(db, candidate, {flag: true, severity: prepared.severity || 'medium',
          categories: prepared.categories || [prepared.manual],
          detectionSource: prepared.detectionSource, detectionEvidence: prepared.detectionEvidence,
          matchedKeywords: prepared.matchedKeywords}, now())) {
          result.checked++; result.flagged++;
        }
      } else candidates.push({...candidate, ...prepared});
    }
    for (const candidate of candidates) {
      if (await saveVerdict(db, candidate, {flag: false, severity: 'low', categories: []}, now())) result.checked++;
    }
    result.remainingPending = (await db.collection('communityModerationChecks').where('stage', '==', 'pending').limit(1).get()).size > 0;
    const completed = await finishIntegrityRun({db, owner, result, force, now});
    published = completed != null;
    return completed ?? {skipped: true, reason: 'lease-lost',
      ...(await db.doc('communityModerationStatus/current').get()).data(), serverNowMillis: now()};
  } catch (error) {
    const failed = await finishIntegrityRun({db, owner, force, now,
      result: {status: 'failed', errorCode: 'scan-failed', checked: result.checked, flagged: result.flagged}});
    published = failed != null;
    throw error;
  } finally {
    if (!published) await releaseIntegrityRun({db, owner});
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
module.exports = {VERSION, POLICY_HASH, CATEGORIES, sourceInfo, sourceFingerprint, contentHash, prepareContent,
  saveVerdict, runIntegrityCheck, reviewContent};

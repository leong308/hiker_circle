// Community text integrity scans and human moderation preserve source fingerprints and audit decisions.
'use strict';
const {createHash, randomUUID} = require('node:crypto');
const {MAX_POST_CAPTION_LENGTH} = require('./community_content_limits');
const {beginIntegrityRun, finishIntegrityRun} = require('./community_integrity_schedule');
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
// Query public content and its current review together.
async function checkContent(db, ref, now) {
  const path = ref.path;
  const info = sourceInfo(path);
  if (!info) return null;
  const id = sha(path);
  const checkRef = db.collection('communityModerationChecks').doc(id);
  const reviewRef = db.collection('communityModerationReviews').doc(id);
  return db.runTransaction(async tx => {
    const parent = await tx.get(info.type === 'post' ? ref : ref.parent.parent);
    if (parent.get('visibility') !== 'public') return null;
    const source = info.type === 'post' ? parent : await tx.get(ref);
    if (!source.exists) return null;
    const data = source.data();
    const fingerprint = contentHash(path, data);
    const identity = sourceFingerprint(path, data);
    const verdict = prepareContent(path, data);
    const [check, reviewDoc] = await tx.getAll(checkRef, reviewRef);
    const review = reviewDoc.data() || {};
    const preserved = ['dismissed', 'actioned'].includes(review.status)
      && (review.sourceFingerprint === identity || review.fingerprint === legacyFingerprint(path, data)
        || review.fingerprint === fingerprint);
    const status = preserved ? review.status : verdict.manual ? 'pending' : 'clear';
    if (check.get('fingerprint') === fingerprint && check.get('stage') === 'checked'
      && review.status === status && (preserved || review.fingerprint === fingerprint)) return status;
    // Update cloud: archive the previous verdict
    if (!preserved && review.fingerprint && review.fingerprint !== fingerprint) {
      tx.set(reviewRef.collection('history').doc(sha(review.fingerprint)), {...review, archivedAtMillis: now});
    }
    // Update cloud: save moderation check
    tx.set(checkRef, {sourcePath: path, fingerprint, sourceFingerprint: identity, stage: 'checked',
      checkedAtMillis: now, policyVersion: VERSION, policyHash: POLICY_HASH});
    if (preserved) {
      tx.set(reviewRef, {sourceFingerprint: identity, recheckedAtMillis: now, recheckedPolicyHash: POLICY_HASH,
        recheckResult: 'human_decision_preserved'}, {merge: true});
    } else if (review.fingerprint !== fingerprint || review.status !== status) {
      const record = {status, fingerprint, sourceFingerprint: identity, sourcePath: path};
      if (verdict.manual) {
        const categories = verdict.categories || [verdict.manual];
        Object.assign(record, {postId: info.postId, contentType: info.type, severity: verdict.severity || 'medium',
          categories, reasons: categories.map(c => LABELS[c]), policyVersion: VERSION, policyHash: POLICY_HASH,
          flaggedAtMillis: now, ...verdictProvenance(verdict)});
      } else record.checkedAtMillis = now;
      tx.set(reviewRef, record);
    }
    return status;
  });
}

// Close flags whose source disappeared or became private.
async function reconcileReview(db, ref, now) {
  return db.runTransaction(async tx => {
    const review = (await tx.get(ref)).data();
    if (review?.status !== 'pending' || !sourceInfo(review.sourcePath)) return false;
    const source = await tx.get(db.doc(review.sourcePath));
    const parent = sourceInfo(review.sourcePath).type === 'post' ? source : await tx.get(source.ref.parent.parent);
    if (source.exists && parent.get('visibility') === 'public'
      && contentHash(review.sourcePath, source.data()) === review.fingerprint) return false;
    // Update cloud: close outdated review
    tx.set(ref, {status: 'superseded', supersededAtMillis: now}, {merge: true});
    return true;
  });
}

async function runIntegrityCheck({db, fieldPath, eventId, now = Date.now}) {
  const eventRef = eventId ? db.doc('maintenanceState/communityModerationRun').collection('events').doc(sha(eventId)) : null;
  const run = {db, owner: randomUUID(), eventRef, now};
  const claim = await beginIntegrityRun(run);
  if (claim.skipped) return claim;
  const result = claim.progress?.result || {checked: 0, flagged: 0, scannedPosts: 0, scannedComments: 0,
    decisionsPreserved: 0, superseded: 0, policyVersion: VERSION, policyHash: POLICY_HASH};
  const queries = [db.collection('communityPosts').where('visibility', '==', 'public'),
    db.collectionGroup('comments'), db.collection('communityModerationReviews').where('status', '==', 'pending')];
  let cursor = claim.progress?.cursor;
  try {
    for (let phase = claim.progress?.phase ?? 0; phase < queries.length; phase++) {
      do {
        // Query the next page of posts, comments or flags
        let query = queries[phase].orderBy(fieldPath).select().limit(100);
        if (cursor) query = query.startAfter(db.doc(cursor));
        const page = await query.get();
        for (let i = 0; i < page.size; i += 8) {
          const docs = page.docs.slice(i, i + 8);
          if (phase === 2) {
            const changed = await Promise.all(docs.map(doc => reconcileReview(db, doc.ref, now())));
            result.superseded += changed.filter(Boolean).length;
          } else {
            const outcomes = await Promise.all(docs.map(doc => checkContent(db, doc.ref, now())));
            for (const status of outcomes.filter(Boolean)) {
              result[phase === 0 ? 'scannedPosts' : 'scannedComments']++;
              result.checked++;
              if (status === 'pending') result.flagged++;
              if (['dismissed', 'actioned'].includes(status)) result.decisionsPreserved++;
            }
          }
        }
        cursor = page.size === 100 ? page.docs.at(-1).ref.path : null;
        // Update cloud: resume this event after a retry
        if (eventRef) await eventRef.set({phase: cursor ? phase : phase + 1, cursor, result});
      } while (cursor);
    }
    return await finishIntegrityRun({...run, result: {...result, status: 'completed'}});
  } catch (error) {
    await finishIntegrityRun({...run, result: {...result, status: 'failed', errorCode: 'scan-failed'}});
    throw error;
  }
}
// reviewContent: Apply a human decision only while its source fingerprint still matches.
async function reviewContent({db, reviewId, action, adminId, now = Date.now()}) {
  if (!/^[a-f0-9]{64}$/.test(reviewId || '') || !['dismiss', 'hide'].includes(action)) throw new Error('invalid-review');
  return db.runTransaction(async tx => {
    const ref = db.collection('communityModerationReviews').doc(reviewId);
    // Query flagged review and source post
    const review = await tx.get(ref); const data = review.data() || {};
    if (!review.exists || data.status !== 'pending') return {status: 'already-reviewed'};
    const info = sourceInfo(data.sourcePath);
    if (!info) throw new Error('invalid-review');
    const sourceRef = db.doc(data.sourcePath); const source = await tx.get(sourceRef);
    const postRef = db.doc(`communityPosts/${info.postId}`);
    const parent = info.type === 'post' ? source : await tx.get(postRef);
    if (!source.exists || parent.data()?.visibility !== 'public' || contentHash(data.sourcePath, source.data()) !== data.fingerprint) {
      // Update cloud: apply moderation decision
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
  runIntegrityCheck, reviewContent};

// Comment-count reconciliation derives totals from canonical children for maintenance and regression checks.
'use strict';

// Recompute from the current canonical children in the same transaction. This
// handles reordered create/delete events, retries, and legacy comments that
// predate per-event receipts without applying a stale +/-1 delta.
// reconcileCommentCount: Count present comments rather than replaying create/delete deltas out of order.
async function reconcileCommentCount(db, postId, timestamp) {
  const postRef = db.collection('communityPosts').doc(postId);
  return db.runTransaction(async tx => {
    // Query post and stored comments
    const [post, comments] = await Promise.all([
      tx.get(postRef), tx.get(postRef.collection('comments').select()),
    ]);
    if (!post.exists || Number(post.data()?.commentCount) === comments.size) return;
    // Update cloud: repair post comment count
    tx.update(postRef, { commentCount: comments.size });
  });
}
module.exports = { reconcileCommentCount };

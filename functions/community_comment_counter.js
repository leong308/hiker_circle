'use strict';

// Recompute from the current canonical children in the same transaction. This
// handles reordered create/delete events, retries, and legacy comments that
// predate per-event receipts without applying a stale +/-1 delta.
async function reconcileCommentCount(db, postId, timestamp) {
  const postRef = db.collection('communityPosts').doc(postId);
  return db.runTransaction(async tx => {
    const [post, comments] = await Promise.all([
      tx.get(postRef), tx.get(postRef.collection('comments').select()),
    ]);
    if (!post.exists || Number(post.data()?.commentCount) === comments.size) return;
    tx.update(postRef, { commentCount: comments.size, updatedAt: timestamp(),
      updatedAtLocal: new Date().toISOString() });
  });
}
module.exports = { reconcileCommentCount };

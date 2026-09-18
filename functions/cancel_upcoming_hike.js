// Atomic soft cancellation. Reads the same schedule document as launch/join,
// so a racing launch cannot be silently cancelled after tracking has started.
async function cancelUpcomingHike(db, { hikeId, uid, phoneNumber }, HttpsError, timestamp) {
  const reference = db.collection('upcomingHikes').doc(hikeId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) throw new HttpsError('not-found', 'This hike is no longer available.');
    const hike = snapshot.data();
    if (hike.creatorUserId !== uid || hike.creatorPhone !== phoneNumber) {
      throw new HttpsError('permission-denied', 'Only the host can cancel this hike.');
    }
    if (hike.isDeleted === true) return { cancelled: true };
    if (hike.teamHikeSessionId || hike.teamLaunchLinkedAt || hike.teamLaunchLinkedAtLocal
        || (hike.startedParticipantPhones || []).length > 0) {
      throw new HttpsError('failed-precondition', 'This hike has already started its launch. Return to the active hike controls.');
    }
    transaction.update(reference, {
      isDeleted: true,
      cancelledByUserId: uid,
      cancelledAt: timestamp(),
    });
    return { cancelled: true };
  });
}
module.exports = { cancelUpcomingHike };

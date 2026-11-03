'use strict';

// Cancellation is the operational status; Expired is the history category.
function cancelledHikeHistoryFields({uid, timestamp, now = Date.now(), cancelledAtLocal}) {
  const proposed = Date.parse(cancelledAtLocal);
  const time = Number.isFinite(proposed) && proposed <= now + 300000 ? Math.min(proposed, now) : now;
  const local = new Date(time).toISOString();
  return {isDeleted:true, status:'cancelled', expired:true, historyCategory:'expired',
    deletedReason:'user_cancelled', cancelledByUserId:uid, cancelledAt:timestamp,
    cancelledAtLocal:local, deletedAtLocal:local, expiredAt:timestamp, expiredAtLocal:local};
}
module.exports = {cancelledHikeHistoryFields};

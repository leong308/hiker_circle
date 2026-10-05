'use strict';
const {reconcileHikeSchedule, withMaintenanceRunLease} = require('./active_hike_monitor_schedule');

// Match the existing listings/maintenance query, including the departure grace period.
function isUpcomingListing(hike) {return hike?.isDeleted === false;}
function upcomingMembershipChanged(before, after) {
  return isUpcomingListing(before) !== isUpcomingListing(after);
}
async function hasUpcomingListing(db) {
  return !(await db.collection('upcomingHikes').where('isDeleted', '==', false)
    .limit(1).select().get()).empty;
}
function reconcileUpcomingHikeOperations(options) {
  return reconcileHikeSchedule({...options, controlDocument: 'upcomingHikeOperationsSchedule',
    hasWork: hasUpcomingListing, membershipField: 'hasUpcomingListing'});
}
function withUpcomingRunLease(db, work, now = Date.now, scheduleTime) {
  // Longer than the 540-second function deadline; a crashed worker cannot overlap its replacement.
  return withMaintenanceRunLease({db, work, now, scheduleTime,
    documentId: 'upcomingHikeOperationsRun', leaseMillis: 600000});
}
module.exports = {isUpcomingListing, upcomingMembershipChanged, hasUpcomingListing,
  reconcileUpcomingHikeOperations, withUpcomingRunLease};

'use strict';

// A previously saved plan remains launchable during its start window; older plans become private history.
function offlinePlanRecovery(recovery, draft, now = Date.now()) {
  const created = Date.parse(recovery?.createdAtLocal), departure = Date.parse(draft?.departureTime);
  const valid = Number.isFinite(created) && Number.isFinite(departure) && created <= departure + 120000
    && created <= now + 300000 && departure >= now - 365 * 86400000;
  return {offlineRecovery: valid, expiredRecovery: valid && departure + 15 * 60000 <= now};
}
module.exports = {offlinePlanRecovery};

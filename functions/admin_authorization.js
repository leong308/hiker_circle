// Privileged business actions use the protected account read by the current-session guard.
'use strict';

function isAdminUser(account) {
  if (!account || account.accountDisabled === true || account.status === 'disabled') return false;
  const role = typeof account.role === 'string' ? account.role.toLowerCase() : '';
  return account.isAdmin === true || role === 'admin' || role === 'super_admin'
    || (Array.isArray(account.roles)
      && account.roles.some(value => typeof value === 'string' && value.toLowerCase() === 'admin'));
}

function createAdminAuthorization({HttpsError}) {
  // Request data and login-time claims cannot populate this private map. The
  // caller binds it only after requireActive verifies MFA/session/account state.
  const accounts = new WeakMap();
  const hasAdminAccess = request => isAdminUser(accounts.get(request));
  return {
    bindActiveAccount(request, account) { accounts.set(request, account); },
    hasAdminAccess,
    requireAdminAccess(request) {
      if (!hasAdminAccess(request)) {
        throw new HttpsError('permission-denied', 'Administrator access is required.');
      }
    },
  };
}

module.exports = {isAdminUser, createAdminAuthorization};

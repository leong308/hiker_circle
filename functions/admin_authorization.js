// Privileged business actions use the protected account read by the current-session guard.
'use strict';

// Normalize the supported legacy role flags before applying current account restrictions.
function accountRole(account = {}) {
  const roles = [account.role, ...(Array.isArray(account.roles) ? account.roles : [])]
    .filter(value => typeof value === 'string').map(value => value.toLowerCase().replace(/[\s_-]/g, ''));
  if (account.isSuperAdmin === true || roles.includes('superadmin')) return 'superadmin';
  return account.isAdmin === true || roles.includes('admin') ? 'admin' : 'hiker';
}
function isAdminUser(account) {
  return !!account && account.accountDisabled !== true && account.status !== 'disabled' && accountRole(account) !== 'hiker';
}
function isSuperAdminUser(account) { return isAdminUser(account) && accountRole(account) === 'superadmin'; }

function createAdminAuthorization({HttpsError}) {
  // Request data and login-time claims cannot populate this private map. The
  // caller binds it only after requireActive verifies MFA/session/account state.
  const accounts = new WeakMap();
  const hasAdminAccess = request => isAdminUser(accounts.get(request));
  return {
    bindActiveAccount(request, account) { accounts.set(request, account); },
    hasAdminAccess,
    requireSuperAdminAccess(request) {
      if (!isSuperAdminUser(accounts.get(request))) throw new HttpsError('permission-denied', 'Superadmin access is required.');
    },
    requireAdminAccess(request) {
      if (!hasAdminAccess(request)) {
        throw new HttpsError('permission-denied', 'Administrator access is required.');
      }
    },
  };
}

module.exports = {accountRole, isAdminUser, isSuperAdminUser, createAdminAuthorization};

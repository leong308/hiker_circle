// MFA removal retains a supported security method while updating canonical factor metadata atomically.
const {readUser, readUsers, readUserQuery, setUser, updateUser} = require('./user_modules');
'use strict';
// removeMfaFactor: Read all bound factors before removal so concurrent changes cannot leave no supported method.
async function removeMfaFactor(db, userId, factorId, ErrorType, timestamp) {
  const userRef = db.collection('users').doc(userId);
  return db.runTransaction(async tx => {
    // Query read and parent write serialize both removal and enrollment.
    const [snapshot] = await Promise.all([
      tx.get(userRef.collection('authFactors')), readUser(userRef, ["security"], tx),
    ]);
    const factors = snapshot.docs.filter(d => d.data()?.enabled !== false);
    const target = factors.find(d => d.id === factorId);
    if (!target) throw new ErrorType('not-found', 'This security method no longer exists.');
    if (factors.length <= 1) throw new ErrorType('failed-precondition', 'At least one Authenticator or passkey method must remain bound.');
    const remaining = factors.filter(d => d.id !== factorId);
    const methods = [...new Set(remaining.map(d => d.data().type))]
      .filter(type => ['totp', 'passkey'].includes(type)).sort();
    tx.delete(target.ref);
    setUser(tx, userRef, { mfaRequired: true, mfaFactorCount: remaining.length, mfaMethods: methods,
      mfaUpdatedAt: timestamp(), mfaUpdatedAtLocal: new Date().toISOString() }, { merge: true });
    return { removed: true, factorCount: remaining.length, methods };
  });
}
module.exports = { removeMfaFactor };

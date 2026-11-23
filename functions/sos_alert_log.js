'use strict';

// This operation saves history only. It never contacts the messaging provider.
async function saveSosAlertLog(db, {uid, phoneNumber, alert}, ErrorType, timestamp) {
  const data = alert && typeof alert === 'object' && !Array.isArray(alert) ? alert : {};
  const id = String(data.id || '');
  if (!/^(manual|medical|fall_stillness|prolonged_stillness|duress)_\d{10,22}$/.test(id)
    || data.triggeredByPhoneNumber !== phoneNumber
    || !Number.isFinite(Date.parse(data.triggeredAtLocal))
    || !Array.isArray(data.dispatches) || data.dispatches.length > 3
    || !Number.isInteger(data.contactCount) || data.contactCount < 0 || data.contactCount > 3
    || JSON.stringify(data).length > 40000) {
    throw new ErrorType('invalid-argument', 'The SOS history entry is invalid.');
  }
  const userRef = db.collection('users').doc(uid);
  const moduleRef = userRef.collection('modules').doc('sos');
  const alertRef = db.collection('sosAlerts').doc(id);
  await db.runTransaction(async tx => {
    // Query account, SOS module and alert
    const [userDoc, moduleDoc, existingDoc] = await Promise.all([tx.get(userRef), tx.get(moduleRef), tx.get(alertRef)]);
    const user = userDoc.data() || {};
    if (!userDoc.exists || user.accountDisabled === true || user.status === 'disabled') {
      throw new ErrorType('permission-denied', 'Your account is unavailable.');
    }
    if (existingDoc.exists && (existingDoc.data().userId !== uid || existingDoc.data().phoneNumber !== phoneNumber)) {
      throw new ErrorType('permission-denied', 'This SOS entry belongs to another account.');
    }
    const saved = moduleDoc.data() || {};
    const alertPath = `sosAlerts/${id}`;
    const isLatest = !Number.isFinite(Date.parse(saved.sosAlertsUpdatedAtLocal))
      || Date.parse(data.triggeredAtLocal) >= Date.parse(saved.sosAlertsUpdatedAtLocal);
    const previous = Array.isArray(saved.recentSosAlertPaths) ? saved.recentSosAlertPaths.filter(p => typeof p === 'string' && p.startsWith('sosAlerts/')) : [];
    const paths = [...new Set(isLatest ? [alertPath, ...previous] : [...previous, alertPath])].slice(0,30);
    const allowed = ['id','mode','status','triggeredAtLocal','triggeredByPhoneNumber','contactCount','sentCount',
      'failedCount','dispatches','message','triggerSource','shirtColor','triggerLocation'];
    const payload = Object.fromEntries(allowed.filter(k => data[k] !== undefined).map(k => [k,data[k]]));
    // Update cloud: save SOS alert and owner reference
    tx.set(alertRef, {...payload,userId:uid,phoneNumber,cloudLogPath:alertPath,updatedAt:timestamp()}, {merge:true});
    tx.set(moduleRef, {recentSosAlertPaths:paths,
      sosAlertsCount: Math.max(0, Number(saved.sosAlertsCount) || 0) + (existingDoc.exists ? 0 : 1),
      sosAlertsUpdatedAt:timestamp(),
      ...(isLatest ? {latestSosAlertPath:alertPath,sosAlertsUpdatedAtLocal:data.triggeredAtLocal} : {}),
    }, {merge:true});
  });
  return {saved:true,alertId:id};
}
module.exports = {saveSosAlertLog};

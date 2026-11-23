'use strict';
const crypto = require('crypto');
const {metricFor} = require('./achievement_catalog');

// Accumulate each trusted event once per user/metric, independent of how many badges use it.
async function recordEvents({db, userId, metricKey, events, now = new Date().toISOString()}) {
  const metric = metricFor(metricKey);
  if (!metric) return 0;
  const unique = [...new Map(events.filter(event => event.eventKey && Number.isInteger(event.increment)
    && event.increment > 0 && event.increment <= metric.maxIncrement)
    .map(event => [event.eventKey, event])).values()];
  const totalRef = db.collection('achievementMetricTotals').doc(`${userId}_${metricKey}`);
  let total = 0;
  for (let offset = 0; offset < Math.max(1, unique.length); offset += 100) {
    const chunk = unique.slice(offset, offset + 100);
    total = await db.runTransaction(async tx => {
      const refs = chunk.map(event => db.collection('achievementEventReceipts')
        .doc(crypto.createHash('sha256').update(`metric:${userId}:${metricKey}:${event.eventKey}`).digest('hex')));
      // Query achievement total and prior events
      const [current, receipts] = await Promise.all([tx.get(totalRef), Promise.all(refs.map(ref => tx.get(ref)))]);
      const previous = Math.max(0, Number(current.data()?.progressCount || 0));
      let delta = 0;
      receipts.forEach((receipt, index) => {
        if (receipt.exists) return;
        const event = chunk[index];
        delta += event.increment;
        // Update cloud: save achievement events and total
        tx.create(refs[index], {userId, metricKey, eventKey: event.eventKey, increment: event.increment,
          applied: true, createdAtLocal: now});
      });
      const progressCount = Math.min(1000000000, previous + delta);
      tx.set(totalRef, {userId, metricKey, progressCount, updatedAtLocal: now}, {merge: true});
      return progressCount;
    });
  }
  return total;
}

module.exports = {recordEvents};

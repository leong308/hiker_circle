// Host join reviews expose application activity totals, never private profile or route records.
'use strict';
const {readUser} = require('./user_modules');

// Keep a public alias while excluding contact-like names and legacy phone-suffix placeholders.
function safeJoinAlias(value) {
  const alias = typeof value === 'string'
    ? value.replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029\u202a-\u202e\u2066-\u2069]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 80) : '';
  return !alias || /\S+@\S+|\+?\d[\d\s().-]{6,}\d|^Hiker\s+\d{4}$/i.test(alias) ? 'A hiker' : alias;
}

// Accept bounded stored numbers without allowing arbitrary fields into the response.
function safeNumber(value, maximum = 1000000000) {
  return typeof value === 'number' && Number.isFinite(value) ? Math.max(0, Math.min(maximum, value)) : 0;
}

// Round only after summing recorded distances; planned trail lengths do not count.
function hikingStats(hikes, user, unlockedAchievements = 0) {
  let completedHikes = 0, totalDistanceKm = 0, longestHikeKm = 0, soloHikes = 0, groupHikes = 0;
  for (const hike of hikes) {
    if (hike?.status !== 'completed') continue;
    const reportDistance = hike.summaryReport?.distanceKm;
    const distance = safeNumber(typeof reportDistance === 'number' && Number.isFinite(reportDistance)
      ? reportDistance : hike.distanceKm, 5000);
    completedHikes++;
    totalDistanceKm += distance;
    longestHikeKm = Math.max(longestHikeKm, distance);
    if (hike.hikeType === 'team') groupHikes++; else soloHikes++;
  }
  return {available: true, completedHikes, totalDistanceKm: Math.round(totalDistanceKm * 10) / 10,
    longestHikeKm: Math.round(longestHikeKm * 10) / 10, soloHikes, groupHikes,
    hikerLevel: Math.max(1, Math.floor(safeNumber(user?.hikerLevel, 1000))),
    achievementPoints: Math.floor(safeNumber(user?.achievementPoints)),
    unlockedAchievements: Math.floor(safeNumber(unlockedAchievements))};
}

// Query only the requester's completed metrics; raw profile, timestamps and coordinates never leave this module.
async function loadJoinRequesterDetails(db, userId) {
  if (typeof userId !== 'string' || !userId || userId.length > 200 || /[\/\u0000-\u001f]/.test(userId)) return unavailableDetails();
  const account = await readUser(db.collection('users').doc(userId), ['profile', 'achievements']);
  const user = account.data();
  if (!account.exists || user?.accountDisabled === true || user?.status === 'disabled') return unavailableDetails();
  const [history, awards] = await Promise.all([
    db.collection('hikeSessions').where('userId', '==', userId).where('status', '==', 'completed')
      .select('status', 'distanceKm', 'summaryReport.distanceKm', 'hikeType').get(),
    db.collection('userAchievements').where('userId', '==', userId).where('isUnlocked', '==', true).count().get(),
  ]);
  return {profile: {displayName: safeJoinAlias(user?.profile?.username)},
    stats: hikingStats(history.docs.map(doc => doc.data()), user, awards.data().count),
    achievements: [], hikeHistory: []};
}

// Represent unavailable history distinctly from an actual new hiker with zero completed hikes.
function unavailableDetails(alias) {
  return {profile: {displayName: safeJoinAlias(alias)}, stats: {available: false}, achievements: [], hikeHistory: []};
}

// Keep the push concise; the authenticated review contains the complete aggregate summary.
function joinNotificationBody({requesterName, trailName, stats, compact = false}) {
  const name = safeJoinAlias(requesterName);
  const trail = String(trailName || 'your hike').replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, 100);
  const introduction = `${name} wants to join ${trail}.`;
  if (stats?.available !== true) return `${introduction}\nHiking stats are temporarily unavailable. Review in HikerCircle.`;
  const safe = Object.fromEntries(['completedHikes', 'totalDistanceKm', 'longestHikeKm', 'soloHikes', 'groupHikes',
    'hikerLevel', 'unlockedAchievements'].map(key => [key, safeNumber(stats[key])]));
  const totals = `${Math.floor(safe.completedHikes)} completed hikes · ${safe.totalDistanceKm.toFixed(1)} km recorded`;
  return compact ? `${introduction}\n${totals}` : [introduction, '', 'HikerCircle hiking record', totals,
    `Longest hike: ${safe.longestHikeKm.toFixed(1)} km`,
    `Solo: ${Math.floor(safe.soloHikes)} · Group: ${Math.floor(safe.groupHikes)}`,
    `Level ${Math.max(1, Math.floor(safe.hikerLevel))} · ${Math.floor(safe.unlockedAchievements)} achievements unlocked`,
    '', 'Open HikerCircle to review this request.'].join('\n');
}

module.exports = {safeJoinAlias, hikingStats, loadJoinRequesterDetails, unavailableDetails, joinNotificationBody};

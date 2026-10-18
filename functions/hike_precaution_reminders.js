// Forecast-based precaution notifications send only new or worsening environmental risks for upcoming hikes.
const {readUser, readUsers, readUserQuery, setUser, updateUser} = require('./user_modules');
'use strict';
const {createHash} = require('node:crypto');

// Same advisory thresholds as trail_precautions.dart. Notifications deliberately
// exclude routine equipment/ascent tips; only changing environmental risks push.
// upcomingPrecautions: Compare the actual hike window with fresh hourly risks and daylight boundaries.
function upcomingPrecautions(weather, departure, duration, now = Date.now()) {
  const f = weather?.forecastData;
  const h = f?.hourly;
  if (!h || !Number.isFinite(Date.parse(weather.cachedAtLocal)) || now - Date.parse(weather.cachedAtLocal) >= 4 * 3600000) return [];
  const rows = (h.time || []).map((t, i) => ({t, i})).filter(({t}) => Number.isFinite(t) && t * 1000 + 3600000 > departure && t * 1000 < departure + (duration + 60) * 60000);
  const number = (key, i) => Number.isFinite(h[key]?.[i]) ? h[key][i] : null;
  const some = (p) => rows.some(({i}) => p(i));
  const atLeast = (key, i, limit) => number(key, i) !== null && number(key, i) >= limit;
  const result = [];
  const add = (id, severity, message) => result.push({id, severity, message});
  if (some(i => [95,96,99].includes(number('weather_code',i)))) add('storm',3,'Thunderstorms forecast. Consider postponing; avoid exposed ridges and water.');
  const heavy = some(i => atLeast('precipitation',i,10) || [65,67,82].includes(number('weather_code',i)));
  if (heavy) add('rain',3,'Heavy rain forecast. Consider postponing and check trail closures. Avoid streams and gullies.');
  else if (some(i => atLeast('precipitation_probability',i,60) || atLeast('precipitation',i,0.01))) add('rain',1,'Wet trail expected. Take care on slippery roots and rocks.');
  if (some(i => atLeast('temperature_2m',i,32) || atLeast('apparent_temperature',i,35) || (atLeast('temperature_2m',i,30) && atLeast('relative_humidity_2m',i,80)))) add('heat',2,'Heat stress risk. Start earlier, slow down and plan shaded breaks and drinking water.');
  if (some(i => atLeast('wind_speed_10m',i,25) || atLeast('wind_gusts_10m',i,40))) add('wind',some(i => atLeast('wind_gusts_10m',i,60)) ? 3 : 2,'Strong winds forecast. Avoid exposed sections and damaged trees.');
  if (some(i => number('temperature_2m',i) !== null && number('temperature_2m',i) <= 15 && (atLeast('precipitation',i,0.01) || atLeast('wind_speed_10m',i,20)))) add('cold',2,'Cool wet or windy conditions. Pack waterproof and dry layers.');
  if (some(i => [45,48].includes(number('weather_code',i)) || (number('visibility',i) !== null && number('visibility',i) < 1000))) add('visibility',2,'Poor visibility forecast. Download your route and keep the group together.');
  if (some(i => atLeast('uv_index',i,3))) add('uv',some(i => atLeast('uv_index',i,8)) ? 2 : 1,'Sun protection needed. Plan shade and minimise prolonged exposure.');
  const day = (f.daily?.time || []).findIndex(t => departure >= t * 1000 && departure < (t + 86400) * 1000);
  const rise = f.daily?.sunrise?.[day]; const set = f.daily?.sunset?.[day];
  if (Number.isFinite(rise) && Number.isFinite(set)) {
    const end = departure + duration * 60000;
    if (departure < rise * 1000 || end >= set * 1000) add('dark',3,'Your hike overlaps darkness. Consider changing the start time; carry a headlamp and spare power.');
    else if (end >= set * 1000 - 3600000) add('sunset',2,'Limited daylight buffer. Start earlier or shorten the route; carry a headlamp.');
  }
  return result.sort((a,b) => b.severity-a.severity || a.id.localeCompare(b.id));
}

// sendPrecautionReminders: Claim each hiker/departure delivery and notify only risks above the previously sent severity.
async function sendPrecautionReminders({db, messaging, getWeather, userId, tokensFor, now = Date.now(), hikes}) {
  const hikeSnapshot = hikes || await db.collection('upcomingHikes').get();
  for (const doc of hikeSnapshot.docs) {
    const hike = doc.data();
    const departure = Date.parse(hike.departureTimeLocal || hike.departureTime);
    if (hike.isDeleted || hike.startedAtLocal || ['active','ended','completed','cancelled'].includes(hike.status) || !Number.isFinite(departure) || departure <= now || departure > now + 24 * 3600000) continue;
    try {
      if (hike.teamHikeSessionId) {
        const team = (await db.collection('teamHikeSessions').doc(hike.teamHikeSessionId).get()).data();
        if (team && ['active','ended','completed','cancelled'].includes(team.phase)) continue;
      }
      if (!hike.trailId) continue;
      const trail = (await db.collection('trails').doc(hike.trailId).get()).data();
      if (!trail || !Number.isFinite(trail.latitude) || !Number.isFinite(trail.longitude)) continue;
      const weather = await getWeather(db, trail.latitude, trail.longitude, {maxAgeMs: 15 * 60000});
      const cautions = upcomingPrecautions(weather, departure, Number(trail.estimatedDurationMinutes) || 120, now);
      if (!cautions.length) continue;
      const phones = [...new Set([hike.creatorPhone, ...(hike.participantPhones || [])].filter(p => typeof p === 'string' && p.trim()))];
      for (const phone of phones) {
        const id = createHash('sha256').update(`${doc.id}:${departure}:${phone}`).digest('hex');
        const ref = db.collection('hikePrecautionDeliveries').doc(id);
        const claim = await db.runTransaction(async tx => {
          const current = (await tx.get(doc.ref)).data();
          const previous = (await tx.get(ref)).data() || {};
          if (!current || current.isDeleted || current.startedAtLocal || Date.parse(current.departureTimeLocal || current.departureTime) !== departure || ![current.creatorPhone, ...(current.participantPhones || [])].includes(phone) || previous.leaseUntil > now) return null;
          const fresh = cautions.filter(c => (previous.sent?.[c.id] || 0) < c.severity);
          if (!fresh.length) return null;
          tx.set(ref, {leaseUntil: now + 10 * 60000}, {merge:true});
          return {fresh, sent: previous.sent || {}};
        });
        if (!claim) continue;
        const user = (await readUser(db.collection('users').doc(userId(phone)), ["devices"])).data();
        const tokens = tokensFor(user || {});
        if (!tokens.length) { await ref.set({leaseUntil:0}, {merge:true}); continue; }
        let success = 0;
        for (let i=0;i<tokens.length;i+=500) {
          const response = await messaging.sendEachForMulticast({tokens:tokens.slice(i,i+500),
            notification:{title:`Precautions for ${String(hike.trailName || 'your upcoming hike').slice(0,80)}`, body:claim.fresh.map(c=>c.message).join(' ').slice(0,900)},
            data:{type:'upcoming_hike_precaution',upcomingHikeId:doc.id,deepLink:`hikercircle://upcoming-hike/view?upcomingHikeId=${encodeURIComponent(doc.id)}`},
            android:{priority:'high',ttl:Math.max(0, departure-now)},
            apns:{headers:{'apns-expiration':String(Math.floor(departure/1000))},payload:{aps:{sound:'default'}}},
          });
          success += response.successCount;
        }
        await ref.set({leaseUntil:0, ...(success ? {sent:{...claim.sent,...Object.fromEntries(claim.fresh.map(c=>[c.id,c.severity]))},sentAt:new Date(now).toISOString()} : {})},{merge:true});
      }
    } catch (error) { console.warn('Upcoming precaution check failed', doc.id, error.message); }
  }
}
module.exports = {upcomingPrecautions, sendPrecautionReminders};

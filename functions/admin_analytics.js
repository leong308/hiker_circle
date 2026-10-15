'use strict';
const {hydrateUsers} = require('./user_modules');
// Aggregate-only response. Never return account identifiers, captions, GPS tracks or contact details.
const SOURCES = {
  users: ['createdAt','createdAtLocal','isAdmin','role','roles','accountDisabled','status'],
  trailRequests: ['status'],
  trails: ['name','state','distanceKm','estimatedDurationMinutes','elevationGainMeters','difficulty','isVerifiedTrail','offlineMapAvailable','routeProvider','routeGeometryMetadata.pointCount'],
  hikeSessions: ['status','userId','trailId','trailName','hikeType','startedAt','startedAtLocal','endedAt','endedAtLocal','distanceKm','durationMinutes'],
  upcomingHikes: ['isDeleted','status','departureTime','departureTimeLocal','hikeType'],
  communityPosts: ['createdAt','createdAtLocal','visibility','likeCount','commentCount'],
  hazardReports: ['status','severity','hazardType','reportedAt','reportedAtLocal'],
  appFeedback: ['status','createdAt','createdAtLocal','category'],
  communityModerationReviews: ['status','contentType'],
  achievements: ['isActive'],
  userAchievements: ['achievementId','isUnlocked'],
  sosAlerts: ['status','createdAt','createdAtLocal'],
};
function millis(value) {
  if (value?.toMillis) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number') return Number.isFinite(value) && value > 0 ? value : null;
  if (typeof value === 'string') {const date=Date.parse(value); return Number.isFinite(date) ? date : null;}
  return null;
}
function dateOf(row, ...keys) {for(const key of keys){const value=millis(row[key]);if(value!==null)return value;}return null;}
const dayKey = time => new Date(time+8*3600000).toISOString().slice(0,10);
const num = value => Number.isFinite(Number(value)) && Number(value)>=0 ? Number(value) : 0;
const label = value => typeof value==='string' && value.trim() ? value.trim() : 'Not recorded';
function distribution(rows, key) {
  const counts=new Map();for(const row of rows){const name=key(row);counts.set(name,(counts.get(name)||0)+1);}
  return [...counts].map(([label,value])=>({label,value})).sort((a,b)=>b.value-a.value||a.label.localeCompare(b.label));
}
async function readSource(db, name, fields, documentId, limit=10000) {
  const collection=db.collection(name);
  const total=(await collection.count().get()).data().count;
  const rows=[];let last;
  while(rows.length<limit){let query=collection.select(...fields).orderBy(documentId).limit(Math.min(500,limit-rows.length));if(last)query=query.startAfter(last);
    const page=await query.get();
    const documents = name === 'users' ? await hydrateUsers(page.docs, ['devices'], db) : page.docs;
    rows.push(...documents.map(doc=>({id:doc.id,...doc.data()})));if(page.size<500)break;last=page.docs.at(-1);}
  return {rows,total,complete:rows.length===total};
}
function aggregateAnalytics(sources, now=Date.now()) {
  const today=dayKey(now);
  const dayStart=Date.parse(today+'T00:00:00Z');
  const daily=Array.from({length:90},(_,i)=>({date:new Date(dayStart-(89-i)*86400000).toISOString().slice(0,10),users:0,hikes:0,posts:0,distanceKm:0}));
  const monthStart=new Date(dayStart);monthStart.setUTCDate(1);
  const monthly=Array.from({length:12},(_,i)=>{const date=new Date(monthStart);date.setUTCMonth(date.getUTCMonth()-(11-i));return {date:date.toISOString().slice(0,7),users:0,hikes:0,posts:0,distanceKm:0};});
  const days=new Map(daily.map(row=>[row.date,row]));const months=new Map(monthly.map(row=>[row.date,row]));
  const unknownDates={users:0,hikes:0,posts:0};
  function record(time,key,distance=0){if(time===null||time>now){unknownDates[key]++;return;}const day=dayKey(time);const d=days.get(day);const m=months.get(day.slice(0,7));for(const row of [d,m])if(row){row[key]++;if(key==='hikes')row.distanceKm+=distance;}}
  const users=sources.users.rows, trails=sources.trails.rows, hikes=sources.hikeSessions.rows, posts=sources.communityPosts.rows;
  const activeUsers=new Set();const popular=new Map();let recentSignIns=0;
  for(const user of users){record(dateOf(user,'createdAt','createdAtLocal'),'users');const signIn=dateOf(user,'lastSignedInAt','lastSignedInAtLocal');if(signIn!==null&&signIn<=now&&signIn>=now-30*86400000)recentSignIns++;}
  let distance=0,duration=0,completed=0,active=0,abandoned=0;
  for(const hike of hikes){const start=dateOf(hike,'startedAt','startedAtLocal');if(start!==null&&start<=now&&start>=now-30*86400000&&hike.userId)activeUsers.add(hike.userId);
    if(hike.status==='active')active++;if(hike.status==='abandoned')abandoned++;
    if(hike.status!=='completed')continue;completed++;const km=num(hike.distanceKm);distance+=km;duration+=num(hike.durationMinutes);
    record(dateOf(hike,'endedAtLocal','endedAt'),'hikes',km);if(hike.trailId)popular.set(hike.trailId,(popular.get(hike.trailId)||0)+1);}
  for(const post of posts)record(dateOf(post,'createdAt','createdAtLocal'),'posts');
  const pendingHazards=sources.hazardReports.rows.filter(r=>!r.status||['pending','unverified'].includes(r.status)).length;
  const pendingReviews=sources.communityModerationReviews.rows.filter(r=>r.status==='pending').length;
  const openFeedback=sources.appFeedback.rows.filter(r=>!['resolved','closed'].includes(String(r.status||'').toLowerCase())).length;
  const trailNames=new Map(trails.map(t=>[t.id,t.name]));
  const stateName=value=>{const s=label(value);return /^(penang|pulau pinang)$/i.test(s)?'Penang':/^(melaka|malacca)$/i.test(s)?'Melaka':s;};
  return {schemaVersion:1,generatedAtMillis:now,timeZone:'Asia/Kuala_Lumpur',
    coverage:Object.fromEntries(Object.entries(sources).map(([k,v])=>[k,{total:v.total,analysed:v.rows.length,complete:v.complete}])),unknownDates,
    totals:{users:sources.users.total,trails:sources.trails.total,hikeSessions:sources.hikeSessions.total,posts:sources.communityPosts.total,
      achievements:sources.achievements.total,achievementAwards:sources.userAchievements.rows.filter(a=>a.isUnlocked===true).length,sosAlerts:sources.sosAlerts.total},
    users:{recentSignIns,activeHikers30Days:activeUsers.size,administrators:users.filter(u=>u.isAdmin===true||['admin','super_admin'].includes(u.role)||Array.isArray(u.roles)&&u.roles.includes('admin')).length,disabled:users.filter(u=>u.accountDisabled===true||u.status==='disabled').length},
    trails:{verified:trails.filter(t=>t.isVerifiedTrail===true).length,routeStored:trails.filter(t=>num(t.routeGeometryMetadata?.pointCount)>0||/^stored-/.test(t.routeProvider||'')).length,
      offlineAvailable:trails.filter(t=>t.offlineMapAvailable===true).length,totalDistanceKm:trails.reduce((n,t)=>n+num(t.distanceKm),0),
      byState:distribution(trails,t=>stateName(t.state)),byDifficulty:distribution(trails,t=>label(t.difficulty).toLowerCase()),
      byLength:distribution(trails,t=>{const km=num(t.distanceKm);return !km?'Not recorded':km<5?'Under 5 km':km<=10?'5–10 km':km<=20?'10–20 km':'Over 20 km';})},
    rewards:{active:sources.achievements.rows.filter(a=>a.isActive!==false).length,inactive:sources.achievements.rows.filter(a=>a.isActive===false).length},
    hikes:{completed,active,abandoned,distanceKm:distance,hours:duration/60,averageDistanceKm:completed?distance/completed:0,
      byStatus:distribution(hikes,h=>label(h.status)),byType:distribution(hikes,h=>label(h.hikeType)),
      upcoming:sources.upcomingHikes.rows.filter(h=>!h.isDeleted&&!['cancelled','completed'].includes(h.status)&&dateOf(h,'departureTimeLocal','departureTime')>now).length,
      popularTrails:[...popular].sort((a,b)=>b[1]-a[1]).slice(0,6).map(([id,value])=>({label:trailNames.get(id)||(id.startsWith('unlisted_')?'Unlisted location hike':'Archived trail'),value}))},
    community:{byVisibility:distribution(posts,p=>label(p.visibility)),likes:posts.reduce((n,p)=>n+num(p.likeCount),0),comments:posts.reduce((n,p)=>n+num(p.commentCount),0)},
    safety:{pendingTrailRequests:sources.trailRequests.rows.filter(r=>r.status==='pending').length,pendingHazards,pendingReviews,openFeedback,bySeverity:distribution(sources.hazardReports.rows,r=>label(r.severity)),byHazardStatus:distribution(sources.hazardReports.rows,r=>label(r.status)),
      byFeedbackStatus:distribution(sources.appFeedback.rows,r=>label(r.status).toLowerCase()),byFeedbackCategory:distribution(sources.appFeedback.rows,r=>label(r.category)),byHazardType:distribution(sources.hazardReports.rows,r=>label(r.hazardType)),bySosStatus:distribution(sources.sosAlerts.rows,r=>label(r.status))},
    daily,monthly};
}
let cached, inFlight;
async function loadAdminAnalytics({db,documentId,now=Date.now,forceRefresh=false}) {
  if(!forceRefresh&&cached&&now()-cached.generatedAtMillis<60000)return cached;
  if(inFlight)return inFlight;
  inFlight=(async()=>{const entries=await Promise.all(Object.entries(SOURCES).map(async([name,fields])=>[name,await readSource(db,name,fields,documentId)]));
    const result=aggregateAnalytics(Object.fromEntries(entries),now());cached=result;return result;})();
  try{return await inFlight;}finally{inFlight=null;}
}
module.exports={SOURCES,millis,dateOf,aggregateAnalytics,readSource,loadAdminAnalytics};

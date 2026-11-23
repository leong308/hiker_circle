// Read-only system analytics. Only aggregate figures and public catalogue labels leave this module.
'use strict';
const {hazardLifecycleStage, classifyHazard} = require('./trail_hazard_policy');
const {visible: visibleAchievement} = require('./achievement_catalog');
const {stateFor: sosContactState} = require('./sos_confirmation');
const DAY = 86400000, MYT = 8 * 3600000, WEATHER_TTL = 3 * 3600000;
const PERIODS = [7, 30, 90, 365];
const SOURCES = Object.freeze({
  users: ['createdAt','createdAtLocal','isAdmin','role','roles','accountDisabled','status'],
  trails: ['name','state','distanceKm','difficulty','isVerifiedTrail','offlineMapAvailable','routeProvider','routeGeometryMetadata.pointCount','ratingAverage','ratingCount','coverImageUrl','latitude','longitude','weather.cachedAtLocal','weather.schemaVersion'],
  trailRequests: ['status','createdAtMillis','submittedAtMillis'],
  hikeSessions: ['status','userId','trailId','hikeType','startedAt','startedAtLocal','endedAt','endedAtLocal','distanceKm','durationMinutes','summaryReport.distanceKm','summaryReport.durationMinutes'],
  upcomingHikes: ['isDeleted','expired','deletedReason','status','departureTime','departureTimeLocal','startedAt','startedAtLocal','endedAt','endedAtLocal','teamLaunchConsumed','teamHikeSessionId'],
  teamHikeSessions: ['phase','createdAt','createdAtLocal'],
  upcomingHikeJoinRequests: ['status','createdAt','createdAtLocal'],
  hazardReports: ['status','severity','hazardType','reportedAt','reportedAtLocal','expiresAt','expiresAtLocal','resolvedAt','resolutionCount','resolutionId','riskLevel','hazardPolicyVersion'],
  sosAlerts: ['status','isTest','triggeredAt','triggeredAtLocal','createdAt','createdAtLocal'],
  sosWhatsAppDispatches: ['status','isTest','confirmationTracking','triggeredAtMillis','confirmationDeadlineMillis','confirmedAtMillis','retryable','nextRetryAtMillis','attemptCount','createdAt','createdAtLocal'],
  fcmOutbox: ['status','type','createdAt','createdAtLocal','createdAtMillis','processedAt','processedAtLocal','retryAfterMillis','notBeforeMillis','successCount','failureCount'],
  trailWeatherCache: ['updatedAtMs','retryAfterMs','leaseUntilMs','weather.schemaVersion'],
  checkpointWeather: ['weather.cachedAtLocal','weather.schemaVersion'],
  live_location_shares: ['isActive','expiresAt','expiresAtLocal'],
  appFeedback: ['status','createdAt','createdAtLocal','category'],
  communityPosts: ['createdAt','visibility','likeCount','commentCount'],
  communityModerationReviews: ['status'],
  achievements: ['name','title','isActive','metricKey'],
  userAchievements: ['achievementId','userId','isUnlocked','awardedAt','awardedAtLocal'],
});
const SOURCE_LABELS = Object.freeze({users:'Accounts',trails:'Trail catalogue',trailRequests:'Trail submissions',hikeSessions:'Hiker sessions',upcomingHikes:'Scheduled plans',teamHikeSessions:'Team sessions',upcomingHikeJoinRequests:'Join requests',hazardReports:'Hazard reports',sosAlerts:'SOS alerts',sosWhatsAppDispatches:'SOS contact dispatches',fcmOutbox:'Push notification jobs',trailWeatherCache:'Shared forecasts',checkpointWeather:'Checkpoint forecasts',live_location_shares:'Live location shares',appFeedback:'Hiker feedback',communityPosts:'Community posts',communityModerationReviews:'Content reviews',achievements:'Achievement definitions',userAchievements:'Achievement awards'});

// Read Firestore, ISO and millisecond timestamps without substituting today's date.
function millis(value) {
  let result;
  if (typeof value?.toMillis === 'function') result = value.toMillis();
  else if (value instanceof Date) result = value.getTime();
  else if (typeof value === 'number') result = value;
  else if (typeof value === 'string' && value.trim()) result = Date.parse(value);
  return Number.isFinite(result) && result > 0 ? result : null;
}
// Prefer the first valid recorded date in schema order.
function dateOf(row, ...keys) { for (const key of keys) { const time = millis(row[key]); if (time !== null) return time; } return null; }
// Keep missing or malformed amounts out of nonnegative counters.
function num(value) { return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : 0; }
// Preserve readable public labels without returning arbitrary objects.
function label(value, fallback = 'Not recorded') { return typeof value === 'string' && value.trim() ? value.trim() : fallback; }
// Normalize persisted state names before comparing them.
function state(value) { return label(value, '').toLowerCase(); }
// Use Malaysia's calendar consistently across charts and comparison windows.
function dayKey(time) { return new Date(time + MYT).toISOString().slice(0, 10); }
// Group already-aggregated counters into sorted chart rows.
function entries(counts) { return [...counts].map(([label,value]) => ({label,value})).sort((a,b) => b.value-a.value || a.label.localeCompare(b.label)); }
// Increment a named aggregate rather than retaining its source document.
function increment(counts, name, value = 1) { counts.set(name, (counts.get(name) || 0) + value); }
// Report a percentage only when a meaningful denominator exists.
function percent(numerator, denominator) { return denominator > 0 ? numerator / denominator * 100 : null; }
// Summarize recorded timings; missing timestamps never become zero-second deliveries.
function median(values) { if (!values.length) return null; const sorted = [...values].sort((a,b) => a-b); const i = Math.floor(sorted.length/2); return sorted.length%2 ? sorted[i] : (sorted[i-1]+sorted[i])/2; }
// Classify a scheduled plan using canonical team consumption before applying the 15-minute start window.
function classifyScheduledPlan(row, now, phase = '') {
  const status=state(row.status),departure=dateOf(row,'departureTimeLocal','departureTime');
  if(['active','completed','ended','abandoned'].includes(phase)||row.teamLaunchConsumed===true||row.startedAt||row.startedAtLocal||row.endedAt||row.endedAtLocal||['started','active','completed','ended','abandoned'].includes(status))return {label:'Started / ended',key:'started'};
  if(['cancelled','canceled'].includes(phase))return {label:'Cancelled / removed',key:'cancelled'};
  if(row.expired===true||status==='expired'||row.deletedReason==='departure_time_expired'||(!row.isDeleted&&!['cancelled','canceled','deleted','rejected'].includes(status)&&departure!==null&&departure+15*60000<=now))return {label:'Expired',key:'expired'};
  if(row.isDeleted||['cancelled','canceled','deleted','rejected'].includes(status))return {label:'Cancelled / removed',key:'cancelled'};
  if(departure!==null&&departure>now)return {label:'Upcoming',key:'upcoming'};
  if(departure!==null&&departure+15*60000>now)return {label:'Start window open',key:'readyToStart'};
  return {label:'Date unavailable'};
}
// Create a compact period accumulator with private deduplication sets.
function periodBucket() { return {newUsers:0,startedHikes:0,completedHikes:0,abandonedHikes:0,distanceKm:0,hours:0,distanceSamples:0,durationSamples:0,hazards:0,sosAlerts:0,awards:0,posts:0,teamSessions:0,joinRequests:0,acceptedJoinRequests:0,contactConfirmed:0,contactFailed:0,contactUnconfirmed:0,contactSending:0,hikers:new Map(),outcomes:new Map(),hikeTypes:new Map()}; }
// Remove private identities and add rates for one calendar comparison bucket.
function finishBucket(bucket) {
  const {hikers,outcomes,hikeTypes,...counts} = bucket;
  return {...counts,distanceKm:bucket.completedHikes>0&&!bucket.distanceSamples?null:bucket.distanceKm,hours:bucket.completedHikes>0&&!bucket.durationSamples?null:bucket.hours,activeHikers:hikers.size,repeatHikers:[...hikers.values()].filter(n => n >= 2).length,
    completionRate:percent(bucket.completedHikes,bucket.completedHikes+bucket.abandonedHikes),
    averageDistanceKm:bucket.distanceSamples ? bucket.distanceKm/bucket.distanceSamples : null,
    averageHours:bucket.durationSamples ? bucket.hours/bucket.durationSamples : null,
    contactConfirmationRate:percent(bucket.contactConfirmed,bucket.contactConfirmed+bucket.contactFailed+bucket.contactUnconfirmed+bucket.contactSending),
    outcomes:entries(outcomes),hikeTypes:entries(hikeTypes)};
}

// Consume projected pages into bounded aggregate state instead of keeping thousands of full documents.
function createAccumulator(now = Date.now()) {
  const todayStart = Date.parse(dayKey(now)+'T00:00:00Z')-MYT;
  const periods = Object.fromEntries(PERIODS.map(days => [days,{start:todayStart-(days-1)*DAY,previousStart:todayStart-(2*days-1)*DAY,current:periodBucket(),previous:periodBucket()}]));
  const daily = Array.from({length:365},(_,i) => ({date:dayKey(todayStart-(364-i)*DAY),users:0,hikes:0,distanceKm:0,hazards:0,sosAlerts:0,awards:0,posts:0}));
  const dailyMap = new Map(daily.map(row => [row.date,row]));
  const dateIssues = {}, coverage = {};
  const teamPhases=new Map(),deferredPlans=[];
  const userIds = new Set(), hikerIds = new Set(), completedHikerIds = new Set(), awardUsers = new Set(), trailNames = new Map(), achievementNames = new Map(), trailPopularity = new Map(), awardPopularity = new Map();
  const distributions = Object.fromEntries(['accountStatus','hikeStatus','hikeType','teamPhase','plans','joinStatus','hazardLifecycle','hazardTypes','openHazardTypes','hazardSeverity','trailStates','trailDifficulty','trailLength','feedbackStatus','feedbackCategory','postVisibility','sosStatus','contactStatus','notificationStatus','notificationTypes','weather','checkpointWeather','ruleCategories'].map(key => [key,new Map()]));
  const totals = {users:0,trails:0,hikeSessions:0,posts:0,achievements:0,achievementAwards:0,sosAlerts:0};
  const users = {administrators:0,disabled:0,recentSignIns:0};
  const hikes = {active:0,completed:0,abandoned:0,distanceKm:0,hours:0,distanceSamples:0,durationSamples:0};
  const plans = {upcoming:0,readyToStart:0,expired:0,cancelled:0,started:0};
  const teams = {active:0,preparing:0,completed:0};
  const trails = {analysedCount:0,verified:0,routeStored:0,offlineAvailable:0,totalDistanceKm:0,missingCover:0,missingLocation:0,missingDistance:0,freshForecasts:0,staleForecasts:0,missingForecasts:0,ratingCount:0,ratedVotes:0,ratingWeightedTotal:0};
  const safety = {reportedHazards:0,resolvingHazards:0,resolvedHazards:0,expiredHazards:0,confirmedResolutions:0,legacyResolutions:0,resolvedReports:0,criticalOpen:0,oldestOpenAtMillis:null};
  const contacts = {confirmed:0,failed:0,unconfirmed:0,sending:0,retryScheduled:0,recentUnconfirmed:0,recentFailed:0};
  const notifications = {pending:0,sending:0,failed:0,unconfirmed:0,noDevice:0,partial:0,accepted:0,overdue:0,acceptedDevices:0,rejectedDevices:0,oldestPendingAtMillis:null};
  const feedback = {open:0,oldestOpenAtMillis:null,pendingTrailRequests:0,oldestTrailRequestAtMillis:null,pendingContentReviews:0};
  const rewards = {active:0,inactive:0,retired:0};
  const weather = {fresh:0,stale:0,unavailable:0,retryCooldown:0,refreshing:0};
  const checkpointForecasts = {fresh:0,stale:0,unavailable:0};
  const location = {activeShares:0};
  const content = {posts:0,likes:0,comments:0};
  const notificationTimings = [], confirmationTimings = [], resolutionTimings = [];

  // Track unusable dates separately from legitimate empty activity windows.
  function validDate(source, time) {
    const issue = dateIssues[source] ||= {missing:0,future:0};
    if (time === null) { issue.missing++; return false; }
    if (time > now) { issue.future++; return false; }
    return true;
  }
  // Add one dated event to all matching current/previous windows and the daily series.
  function event(source, time, metric, value = 1, extra) {
    if (!validDate(source,time)) return;
    for (const period of Object.values(periods)) {
      const bucket = time >= period.start ? period.current : time >= period.previousStart ? period.previous : null;
      if (bucket) { bucket[metric] += value; extra?.(bucket); }
    }
    const day = dailyMap.get(dayKey(time));
    const chartKey = {newUsers:'users',completedHikes:'hikes'}[metric] || metric;
    if (day && Object.hasOwn(day,chartKey)) day[chartKey] += value;
  }
  // Retain the oldest known queue timestamp without inventing ages for legacy records.
  function oldest(target, key, time) { if (time !== null && time <= now) target[key] = Math.min(target[key] ?? time,time); }
  // Apply the shared three-hour forecast freshness rule.
  function forecastState(time, schema) { return schema !== 2 || time === null || time > now+60000 ? 'unavailable' : now-time < WEATHER_TTL ? 'fresh' : 'stale'; }

  // Reduce a single projected source row; never copy account IDs into public chart labels.
  function consume(source, row) {
    const d = distributions;
    switch (source) {
      case 'users': {
        userIds.add(row.id); const disabled = row.accountDisabled === true || state(row.status) === 'disabled';
        users.disabled += Number(disabled); increment(d.accountStatus,disabled ? 'Disabled' : 'Enabled');
        users.administrators += Number(row.isAdmin === true || ['admin','super_admin'].includes(row.role) || Array.isArray(row.roles) && row.roles.includes('admin'));
        const signIn = dateOf(row,'lastSignedInAt','lastSignedInAtLocal');
        if (signIn !== null && signIn <= now && signIn >= now-30*DAY) users.recentSignIns++;
        event(source,dateOf(row,'createdAt','createdAtLocal'),'newUsers'); break;
      }
      case 'hikeSessions': {
        const status = state(row.status); increment(d.hikeStatus,status || 'Not recorded'); increment(d.hikeType,label(row.hikeType));
        if (status === 'active') hikes.active++;
        const start=dateOf(row,'startedAt','startedAtLocal');
        if (row.userId && start!==null && start<=now) hikerIds.add(row.userId);
        event('hikeStarts',start,'startedHikes',1,bucket => { if (row.userId) bucket.hikers.set(row.userId,(bucket.hikers.get(row.userId)||0)+1); });
        if (!['completed','abandoned'].includes(status)) break;
        const ended = dateOf(row,'endedAt','endedAtLocal');
        if (status === 'abandoned') { hikes.abandoned++; event('hikeEnds',ended,'abandonedHikes',1,bucket => increment(bucket.outcomes,'Abandoned')); break; }
        const distance=row.summaryReport?.distanceKm ?? row.distanceKm,duration=row.summaryReport?.durationMinutes ?? row.durationMinutes;
        const hasDistance=typeof distance==='number'&&Number.isFinite(distance)&&distance>=0;
        const hasDuration=typeof duration==='number'&&Number.isFinite(duration)&&duration>=0;
        const elapsed=start!==null&&ended!==null&&ended>=start&&ended<=now?(ended-start)/3600000:null;
        const km=hasDistance?distance:0,hours=hasDuration?duration/60:elapsed??0;
        const durationKnown=hasDuration||elapsed!==null;
        hikes.completed++; if(row.userId&&start!==null&&start<=now&&ended!==null&&ended<=now)completedHikerIds.add(row.userId); hikes.distanceKm+=km; hikes.hours+=hours;hikes.distanceSamples+=Number(hasDistance);hikes.durationSamples+=Number(durationKnown);
        if (row.trailId) increment(trailPopularity,row.trailId);
        event('hikeEnds',ended,'completedHikes',1,bucket => { bucket.distanceKm+=km; bucket.hours+=hours;bucket.distanceSamples+=Number(hasDistance);bucket.durationSamples+=Number(durationKnown); increment(bucket.outcomes,'Completed'); increment(bucket.hikeTypes,label(row.hikeType)); });
        if (ended !== null && ended <= now) { const day=dailyMap.get(dayKey(ended)); if (day) day.distanceKm+=km; }
        break;
      }
      case 'upcomingHikes': {
        if(row.teamHikeSessionId){deferredPlans.push(row);break;}
        const plan=classifyScheduledPlan(row,now);if(plan.key)plans[plan.key]++;increment(d.plans,plan.label);break;
      }
      case 'teamHikeSessions': {
        const phase=state(row.phase);teamPhases.set(row.id,phase); increment(d.teamPhase,phase || 'Not recorded');
        if (phase==='active') teams.active++;
        if (['inviting','ready','countdown','preparing'].includes(phase)) teams.preparing++;
        if (['completed','ended'].includes(phase)) teams.completed++;
        event(source,dateOf(row,'createdAt','createdAtLocal'),'teamSessions'); break;
      }
      case 'upcomingHikeJoinRequests': {
        increment(d.joinStatus,label(row.status));
        event(source,dateOf(row,'createdAt','createdAtLocal'),'joinRequests',1,bucket => { if (state(row.status)==='accepted') bucket.acceptedJoinRequests++; }); break;
      }
      case 'trails': {
        trails.analysedCount++;trailNames.set(row.id,label(row.name,'Unnamed trail'));
        trails.verified+=Number(row.isVerifiedTrail===true); trails.offlineAvailable+=Number(row.offlineMapAvailable===true);
        trails.routeStored+=Number(num(row.routeGeometryMetadata?.pointCount)>0 || /^stored-/.test(row.routeProvider||''));
        trails.totalDistanceKm+=num(row.distanceKm); trails.missingDistance+=Number(!num(row.distanceKm));
        trails.missingLocation+=Number(!Number.isFinite(row.latitude) || Math.abs(row.latitude)>90 || !Number.isFinite(row.longitude) || Math.abs(row.longitude)>180);
        trails.missingCover+=Number(!(typeof row.coverImageUrl==='string' && row.coverImageUrl.trim() || Array.isArray(row.coverImageUrl) && row.coverImageUrl.some(v=>typeof v==='string'&&v.trim())));
        const ratingCount=num(row.ratingCount); trails.ratingCount+=ratingCount; if(typeof row.ratingAverage==='number'&&Number.isFinite(row.ratingAverage)&&row.ratingAverage>=1&&row.ratingAverage<=5){trails.ratedVotes+=ratingCount;trails.ratingWeightedTotal+=row.ratingAverage*ratingCount;}
        const region=label(row.state); increment(d.trailStates,/^(penang|pulau pinang)$/i.test(region)?'Penang':/^(melaka|malacca)$/i.test(region)?'Melaka':region);
        increment(d.trailDifficulty,label(row.difficulty)); const km=num(row.distanceKm); increment(d.trailLength,!km?'Not recorded':km<5?'Under 5 km':km<=10?'5–10 km':km<=20?'10–20 km':'Over 20 km');
        const freshness=forecastState(millis(row.weather?.cachedAtLocal),row.weather?.schemaVersion);
        trails[freshness==='fresh'?'freshForecasts':freshness==='stale'?'staleForecasts':'missingForecasts']++; break;
      }
      case 'hazardReports': {
        const stage=hazardLifecycleStage(row,now); if (stage===null) break;
        increment(d.hazardLifecycle,stage); increment(d.hazardTypes,label(row.hazardType)); increment(d.hazardSeverity,label(row.severity));
        safety[{Reported:'reportedHazards',Resolving:'resolvingHazards',Resolved:'resolvedHazards'}[stage]]++;
        if (stage!=='Resolved') { safety.criticalOpen+=Number(row.hazardPolicyVersion>=1&&['fatal','normal'].includes(row.riskLevel)?row.riskLevel==='fatal':classifyHazard(row.hazardType).riskLevel==='fatal'); increment(d.openHazardTypes,label(row.hazardType)); oldest(safety,'oldestOpenAtMillis',dateOf(row,'reportedAt','reportedAtLocal')); }
        else if (state(row.status)==='resolved' || num(row.resolutionCount)>=3) { safety.resolvedReports++;if(num(row.resolutionCount)>=3)safety.confirmedResolutions++;else safety.legacyResolutions++; const start=dateOf(row,'reportedAt','reportedAtLocal'), end=dateOf(row,'resolvedAt'); if (start!==null&&end!==null&&end>=start&&end<=now) resolutionTimings.push((end-start)/3600000); }
        else safety.expiredHazards++;
        event(source,dateOf(row,'reportedAt','reportedAtLocal'),'hazards'); break;
      }
      case 'sosAlerts': {
        if (row.isTest===true) break; totals.sosAlerts++; increment(d.sosStatus,label(row.status)); event(source,dateOf(row,'triggeredAt','triggeredAtLocal','createdAt','createdAtLocal'),'sosAlerts'); break;
      }
      case 'sosWhatsAppDispatches': {
        if (row.isTest===true) break;
        const result=sosContactState(row,now); contacts[result]++; increment(d.contactStatus,result);
        const triggered=dateOf(row,'triggeredAtMillis','createdAt','createdAtLocal');
        if(triggered!==null&&triggered<=now&&triggered>=now-DAY){if(result==='unconfirmed')contacts.recentUnconfirmed++;if(result==='failed')contacts.recentFailed++;}
        if (result==='failed' && row.retryable===true && num(row.nextRetryAtMillis)>0) contacts.retryScheduled++;
        event(source,dateOf(row,'triggeredAtMillis','createdAt','createdAtLocal'),{confirmed:'contactConfirmed',failed:'contactFailed',unconfirmed:'contactUnconfirmed',sending:'contactSending'}[result]);
        const start=millis(row.triggeredAtMillis), end=millis(row.confirmedAtMillis); if (result==='confirmed'&&start!==null&&end!==null&&end>=start&&end<=now) confirmationTimings.push((end-start)/1000); break;
      }
      case 'fcmOutbox': {
        const status=state(row.status), start=dateOf(row,'createdAt','createdAtLocal','createdAtMillis'), end=dateOf(row,'processedAt','processedAtLocal');
        increment(d.notificationStatus,status||'Not recorded'); increment(d.notificationTypes,label(row.type));
        const key={pending:'pending',sending:'sending',failed:'failed',delivery_uncertain:'unconfirmed',no_token:'noDevice',partial:'partial',sent:'accepted'}[status]; if (key) notifications[key]++;
        if (status==='pending') { oldest(notifications,'oldestPendingAtMillis',start); if(start!==null && start<now-5*60000 && num(row.retryAfterMillis)<=now && num(row.notBeforeMillis)<=now) notifications.overdue++; }
        notifications.acceptedDevices+=num(row.successCount); notifications.rejectedDevices+=num(row.failureCount);
        if(end!==null&&start!==null&&end>=start&&end<=now) notificationTimings.push((end-start)/1000); break;
      }
      case 'trailWeatherCache': {
        const freshness=forecastState(millis(row.updatedAtMs),row.weather?.schemaVersion); weather[freshness]++; increment(d.weather,freshness);
        weather.retryCooldown+=Number(num(row.retryAfterMs)>now); weather.refreshing+=Number(num(row.leaseUntilMs)>now); break;
      }
      case 'checkpointWeather': { const freshness=forecastState(millis(row.weather?.cachedAtLocal),row.weather?.schemaVersion); checkpointForecasts[freshness]++; increment(d.checkpointWeather,freshness); break; }
      case 'live_location_shares': { const expiry=dateOf(row,'expiresAt','expiresAtLocal'); if(row.isActive===true&&expiry!==null&&expiry>now) location.activeShares++; break; }
      case 'appFeedback': {
        const status=state(row.status); increment(d.feedbackStatus,status||'Not recorded'); increment(d.feedbackCategory,label(row.category));
        if(!['resolved','closed'].includes(status)) { feedback.open++; oldest(feedback,'oldestOpenAtMillis',dateOf(row,'createdAt','createdAtLocal')); } break;
      }
      case 'trailRequests': { if(state(row.status)==='pending') {feedback.pendingTrailRequests++;oldest(feedback,'oldestTrailRequestAtMillis',dateOf(row,'submittedAtMillis','createdAtMillis'));} break; }
      case 'communityModerationReviews': { if(state(row.status)==='pending') feedback.pendingContentReviews++; break; }
      case 'communityPosts': { content.posts++;content.likes+=num(row.likeCount);content.comments+=num(row.commentCount);increment(d.postVisibility,label(row.visibility));event(source,dateOf(row,'createdAt'),'posts');break; }
      case 'achievements': { achievementNames.set(row.id,label(row.name||row.title,'Achievement')); rewards[visibleAchievement({...row,achievementId:row.id})?row.isActive===false?'inactive':'active':'retired']++;increment(d.ruleCategories,label(row.metricKey));break; }
      case 'userAchievements': { if(row.isUnlocked!==true) break;totals.achievementAwards++;if(row.userId)awardUsers.add(row.userId);if(row.achievementId)increment(awardPopularity,row.achievementId);event(source,dateOf(row,'awardedAt','awardedAtLocal'),'awards');break; }
    }
  }
  // Attach read coverage independently of sampled/derived figures.
  function setCoverage(source, info) { coverage[source]={label:SOURCE_LABELS[source],...info}; }
  // Publish aggregate results and public names after all independent sources finish.
  function finish() {
    for(const [source,key] of Object.entries({users:'users',trails:'trails',hikeSessions:'hikeSessions',communityPosts:'posts',achievements:'achievements'})) totals[key]=coverage[source]?.total ?? null;
    const finalPlans={...plans},planStates=new Map(distributions.plans);
    for(const row of deferredPlans){
      const phase=teamPhases.get(row.teamHikeSessionId),base=classifyScheduledPlan(row,now);
      // A missing canonical team cannot prove a linked plan is still upcoming or expired.
      if(!phase&&base.key!=='started'){increment(planStates,'Team state unavailable');continue;}
      const plan=classifyScheduledPlan(row,now,phase);if(plan.key)finalPlans[plan.key]++;increment(planStates,plan.label);
    }
    const activated=[...userIds].filter(id=>hikerIds.has(id)).length,completedHikers=[...userIds].filter(id=>completedHikerIds.has(id)).length;
    const months=new Map();for(const row of daily){const key=row.date.slice(0,7);const month=months.get(key)||{date:key,users:0,hikes:0,distanceKm:0,hazards:0,sosAlerts:0,awards:0,posts:0};for(const metric of Object.keys(month))if(metric!=='date')month[metric]+=row[metric];months.set(key,month);}
    const windows=Object.fromEntries(Object.entries(periods).map(([days,period])=>[days,{startMillis:period.start,endMillis:now,previousStartMillis:period.previousStart,previousEndMillis:period.start,current:finishBucket(period.current),previous:finishBucket(period.previous)}]));
    const allContacts=contacts.confirmed+contacts.failed+contacts.unconfirmed+contacts.sending;
    const completeSources=Object.values(coverage).filter(row=>row.complete).length;
    const attention=[];
    // Only recorded nonzero findings create attention cards; missing sources are separately disclosed.
    function issue(key,title,detail,count,severity,route) {if(count>0)attention.push({key,title,detail,count,severity,route});}
    issue('sos-unconfirmed','SOS contacts unconfirmed','Last 24 hours. Late provider confirmations can still arrive.',contacts.recentUnconfirmed,'urgent','safety');
    issue('sos-failed','SOS contacts failed','Known contact dispatch failures from the last 24 hours.',contacts.recentFailed,'urgent','safety');
    issue('critical-hazards','Serious trail cautions','Current reported or resolving hazards classified as serious risk.',safety.criticalOpen,'urgent','safety');
    issue('push-overdue','Notification backlog','Due notification jobs have waited more than five minutes.',notifications.overdue,'warning','tools');
    issue('trail-requests','Trail submissions pending','Recorded trail submissions are waiting for review.',feedback.pendingTrailRequests,'normal','trails');
    issue('feedback','Open hiker feedback','Follow up on feedback that has not been closed.',feedback.open,'normal','tools');
    return {schemaVersion:3,generatedAtMillis:now,timeZone:'Asia/Kuala_Lumpur',coverage,
      quality:{sourceCount:Object.keys(SOURCES).length,completeSources,unavailableSources:Object.entries(coverage).filter(([,v])=>!v.available).map(([key])=>key),partialSources:Object.entries(coverage).filter(([,v])=>v.available&&!v.complete).map(([key])=>key),dateIssues},
      totals,users:{...users,activated,completedHikers,hikingFunnel:[{label:'Registered accounts',value:userIds.size},{label:'Started a hike',value:activated},{label:'Completed a hike',value:completedHikers}],activationRate:percent(activated,userIds.size),awardRecipients:awardUsers.size,byStatus:entries(distributions.accountStatus)},
      hikes:{...hikes,distanceKm:hikes.completed>0&&!hikes.distanceSamples?null:hikes.distanceKm,hours:hikes.completed>0&&!hikes.durationSamples?null:hikes.hours,averageDistanceKm:hikes.distanceSamples?hikes.distanceKm/hikes.distanceSamples:null,completionRate:percent(hikes.completed,hikes.completed+hikes.abandoned),byStatus:entries(distributions.hikeStatus),byType:entries(distributions.hikeType),upcoming:finalPlans.upcoming,popularTrails:entries(trailPopularity).slice(0,8).map(row=>({label:trailNames.get(row.label)||(row.label.startsWith('unlisted_')?'Unlisted location hike':'Trail unavailable'),value:row.value}))},
      plans:{...finalPlans,byStatus:entries(planStates)},teams:{...teams,byPhase:entries(distributions.teamPhase)},joining:{byStatus:entries(distributions.joinStatus)},
      trails:{...trails,averageRating:trails.ratedVotes?trails.ratingWeightedTotal/trails.ratedVotes:null,byState:entries(distributions.trailStates),byDifficulty:entries(distributions.trailDifficulty),byLength:entries(distributions.trailLength)},
      safety:{...safety,pendingTrailRequests:feedback.pendingTrailRequests,pendingReviews:feedback.pendingContentReviews,openFeedback:feedback.open,byFeedbackStatus:entries(distributions.feedbackStatus),byFeedbackCategory:entries(distributions.feedbackCategory),pendingHazards:safety.reportedHazards+safety.resolvingHazards,medianResolutionHours:median(resolutionTimings),byHazardLifecycle:entries(distributions.hazardLifecycle),byHazardType:entries(distributions.hazardTypes),byOpenHazardType:entries(distributions.openHazardTypes),bySeverity:entries(distributions.hazardSeverity),bySosStatus:entries(distributions.sosStatus)},
      contacts:{...contacts,total:allContacts,confirmationRate:percent(contacts.confirmed,allContacts),medianConfirmationSeconds:median(confirmationTimings),byStatus:entries(distributions.contactStatus)},
      operations:{notifications:{...notifications,medianProcessingSeconds:median(notificationTimings),deviceAcceptanceRate:percent(notifications.acceptedDevices,notifications.acceptedDevices+notifications.rejectedDevices),byStatus:entries(distributions.notificationStatus),byType:entries(distributions.notificationTypes)},weather:{...weather,byFreshness:entries(distributions.weather)},checkpointForecasts:{...checkpointForecasts,byFreshness:entries(distributions.checkpointWeather)},...location},
      feedback:{...feedback,byStatus:entries(distributions.feedbackStatus),byCategory:entries(distributions.feedbackCategory)},
      rewards:{...rewards,recipients:awardUsers.size,topAwards:entries(awardPopularity).slice(0,8).map(row=>({label:achievementNames.get(row.label)||'Achievement unavailable',value:row.value})),byRule:entries(distributions.ruleCategories)},
      content:{...content,byVisibility:entries(distributions.postVisibility)},community:{likes:content.likes,comments:content.comments,byVisibility:entries(distributions.postVisibility)},attention,windows,daily,monthly:[...months.values()].slice(-12)};
  }
  return {consume,setCoverage,finish};
}

// Bound each read by the shared snapshot deadline so one unavailable source cannot block all analysis.
async function withinBudget(operation, deadline) {
  const remaining = Math.min(15000, deadline-Date.now());
  if (remaining <= 0) throw Error('Snapshot read budget exhausted');
  let timer;
  try { return await Promise.race([operation(),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Analytics source read timed out')),remaining);})]); }
  finally { clearTimeout(timer); }
}

// Scan every projected page until exhaustion or the callable's shared read budget, disclosing partial results.
async function readSource(db, name, fields, documentId, {consume,deadline=Date.now()+90000} = {}) {
  const collection=name==='checkpointWeather'?db.collectionGroup(name):db.collection(name);
  let total=null,analysed=0,last,exhausted=false;
  try {
    // Query paginated analytics records and count
    total=(await withinBudget(()=>collection.count().get(),deadline)).data().count;
    while(Date.now()<deadline) {
      let query=collection.select(...fields).orderBy(documentId).limit(500);if(last)query=query.startAfter(last);
      const page=await withinBudget(()=>query.get(),deadline);
      let deviceDates=new Map();
      if(name==='users'&&page.docs.length) {
        // Select only sign-in timestamps from device modules, never notification tokens or credentials.
        // Query device last sign-in times
        const modules=await withinBudget(()=>db.getAll(...page.docs.map(doc=>doc.ref.collection('modules').doc('devices')),{fieldMask:['lastSignedInAt','lastSignedInAtLocal']}),deadline);
        deviceDates=new Map(modules.map(doc=>[doc.ref.parent.parent.id,doc.data()||{}]));
      }
      for(const doc of page.docs) {consume?.(name,{...doc.data(),...(deviceDates.get(doc.id)||{}),id:doc.id});analysed++;}
      if(page.docs.length<500){exhausted=true;break;}last=page.docs.at(-1);
    }
    return {total,analysed,complete:exhausted,available:true};
  } catch (_) { return {total,analysed,complete:false,available:total!==null||analysed>0}; }
}
// Adapt isolated row fixtures to the same production accumulator for deterministic validation.
function aggregateAnalytics(sources, now=Date.now()) {
  const accumulator=createAccumulator(now);
  for(const source of Object.keys(SOURCES)) {const input=sources[source];if(input){for(const row of input.rows||[])accumulator.consume(source,row);accumulator.setCoverage(source,{total:input.total??input.rows?.length??0,analysed:input.rows?.length??0,complete:input.complete!==false,available:input.available!==false});}else accumulator.setCoverage(source,{total:null,analysed:0,complete:false,available:false});}
  return accumulator.finish();
}
let cached,inFlight,cachedDb,inFlightDb;
// Share short-lived read-only snapshots while keeping projects and in-flight refreshes isolated.
async function loadAdminAnalytics({db,documentId,now=Date.now,forceRefresh=false}) {
  if(!forceRefresh&&cachedDb===db&&cached&&now()-cached.generatedAtMillis<(cached.quality.completeSources===cached.quality.sourceCount?60000:15000))return cached;
  if(inFlight&&inFlightDb===db)return inFlight;
  const accumulator=createAccumulator(now()),deadline=Date.now()+90000,started=Date.now();
  inFlightDb=db;
  const task=(async()=>{
    const queue=Object.entries(SOURCES);
    // Three independent scans bound Firestore load and keep each source's pagination sequential.
    await Promise.all(Array.from({length:3},async()=>{while(queue.length){const [source,fields]=queue.shift();const info=await readSource(db,source,fields,documentId,{consume:accumulator.consume,deadline});accumulator.setCoverage(source,info);}}));
    const result=accumulator.finish();if(Object.values(result.coverage).every(row=>!row.available))throw Error('Analytics sources unavailable');
    result.buildDurationMillis=Date.now()-started;cached=result;cachedDb=db;return result;
  })();
  inFlight=task;
  try{return await task;}finally{if(inFlight===task){inFlight=null;inFlightDb=null;}}
}
module.exports={SOURCES,SOURCE_LABELS,PERIODS,millis,dateOf,createAccumulator,aggregateAnalytics,readSource,loadAdminAnalytics};

'use strict';
const test=require('node:test');const assert=require('node:assert/strict');
const fs=require('node:fs');const vm=require('node:vm');
const {SOURCES,aggregateAnalytics,millis,readSource}=require('../admin_analytics');
const NOW=Date.parse('2026-10-12T02:00:00Z');
function fixture(patch={}){return Object.fromEntries(Object.keys(SOURCES).map(k=>{const rows=patch[k]||[];return[k,{rows,total:rows.length,complete:true}];}));}
test('Malaysia date bins accept timestamps and legacy ISO dates without inventing missing dates',()=>{
 assert.equal(millis({toMillis:()=>NOW}),NOW);assert.equal(millis('invalid'),null);
 const result=aggregateAnalytics(fixture({users:[{id:'u',createdAt:'2026-10-11T18:00:00Z'},{id:'unknown'},{id:'future',createdAt:NOW+86400000}]}),NOW);
 assert.equal(result.daily.at(-1).date,'2026-10-12');assert.equal(result.daily.at(-1).users,1);
 assert.equal(result.monthly.at(-1).users,1);assert.equal(result.unknownDates.users,2);assert.equal(result.totals.users,3);
});
test('hike outcomes, completed distance, distinct hikers and future listings use canonical statuses',()=>{
 const result=aggregateAnalytics(fixture({hikeSessions:[
  {id:'one',status:'completed',userId:'private',startedAtLocal:new Date(NOW-1000).toISOString(),endedAtLocal:new Date(NOW).toISOString(),distanceKm:5,durationMinutes:120,trailId:'hill'},
  {id:'two',status:'active',userId:'private',startedAtLocal:new Date(NOW-1000).toISOString(),distanceKm:100},
  {id:'three',status:'abandoned',userId:'other',startedAtLocal:new Date(NOW-1000).toISOString()},
 ],trails:[{id:'hill',name:'Hill'}],upcomingHikes:[{departureTimeLocal:new Date(NOW+1000).toISOString()},{isDeleted:true,departureTime:NOW+1000},{status:'cancelled',departureTime:NOW+1000},{departureTime:NOW-1000}]}),NOW);
 assert.equal(result.hikes.completed,1);assert.equal(result.hikes.active,1);assert.equal(result.hikes.abandoned,1);
 assert.equal(result.hikes.distanceKm,5);assert.equal(result.hikes.hours,2);assert.equal(result.users.activeHikers30Days,2);assert.equal(result.hikes.upcoming,1);
 assert.deepEqual(result.hikes.popularTrails,[{label:'Hill',value:1}]);
 assert.ok(!JSON.stringify(result).includes('private'));
});
test('trail quality and state aliases are counted without treating unrated routes as easy',()=>{
 const result=aggregateAnalytics(fixture({trails:[{id:'a',state:'Pulau Pinang',isVerifiedTrail:true,distanceKm:4,routeGeometryMetadata:{pointCount:100}},
 {id:'b',state:'Penang',distanceKm:12,difficulty:'hard',offlineMapAvailable:true}]}),NOW);
 assert.equal(result.trails.verified,1);assert.equal(result.trails.routeStored,1);assert.equal(result.trails.offlineAvailable,1);assert.equal(result.trails.totalDistanceKm,16);
 assert.deepEqual(result.trails.byState,[{label:'Penang',value:2}]);assert.ok(result.trails.byDifficulty.some(r=>r.label==='not recorded'));
});
test('review queues include legacy unverified hazards and exclude resolved feedback',()=>{
 const result=aggregateAnalytics(fixture({hazardReports:[{status:'pending'},{status:'unverified'},{},{status:'approved'}],
 communityModerationReviews:[{status:'pending'},{status:'dismissed'}],appFeedback:[{status:'new'},{status:'resolved'},{status:'closed'}],communityPosts:[{visibility:'public',likeCount:3,commentCount:2}]}),NOW);
 assert.equal(result.safety.pendingHazards,3);assert.equal(result.safety.pendingReviews,1);assert.equal(result.safety.openFeedback,1);assert.equal(result.community.likes,3);assert.equal(result.community.comments,2);
});
test('projections exclude profiles, content, passwords, tracks and phone details',()=>{
 const text=JSON.stringify(SOURCES);
 for(const key of ['passwordHash','phoneNumber','caption','imageUrls','routePoints','emergencyContacts'])assert.ok(!text.includes(key));
});
test('Firestore scan paginates projected fields; total counts remain independent of the scan cap',async()=>{
 const rows=Array.from({length:520},(_,i)=>({id:String(i),data:()=>({name:'Trail'})}));let cursor=-1;const projections=[];
 const collection={count:()=>({get:async()=>({data:()=>({count:520})})}),select:(...fields)=>{projections.push(fields);return{orderBy(){return this;},limit(n){this.n=n;return this;},startAfter(last){cursor=Number(last.id);return this;},get:async function(){const docs=rows.slice(cursor+1,cursor+1+this.n);return{docs,size:docs.length};}};}};
 const result=await readSource({collection:()=>collection},'trails',['name'],'__name__');
 assert.equal(result.rows.length,520);assert.equal(result.complete,true);assert.equal(projections.length,2);
 cursor=-1;const capped=await readSource({collection:()=>collection},'trails',['name'],'__name__',100);assert.equal(capped.total,520);assert.equal(capped.rows.length,100);assert.equal(capped.complete,false);
});
test('analytics endpoint rejects callers without a trusted admin claim',async()=>{
 const source=fs.readFileSync(require.resolve('../index'),'utf8');const start=source.indexOf('exports.getAdminDashboardAnalytics');const block=source.slice(start,source.indexOf('exports.reviewCommunityContentFlag',start));const exports={};let called=0;
 vm.runInNewContext(block,{exports,onCall:(_options,fn)=>fn,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}},admin:{firestore:()=>({})},FieldPath:{documentId:()=> '__name__'},logger:{error(){}},require:()=>({loadAdminAnalytics:async()=>{called++;return{};}})});
 for(const auth of [undefined,{uid:'u',token:{}},{uid:'u',token:{isAdmin:false}}])await assert.rejects(exports.getAdminDashboardAnalytics({auth}),e=>e.code==='permission-denied');
 await exports.getAdminDashboardAnalytics({auth:{uid:'admin',token:{isAdmin:true}},data:{}});assert.equal(called,1);
});
test('failed data reads propagate instead of creating a zero-filled healthy dashboard',async()=>{
 await assert.rejects(readSource({collection:()=>({count:()=>({get:async()=>{throw Error('unavailable');}})})},'users',[], '__name__'),/unavailable/);
});

test('reward awards exclude progress-only records and feedback status is case-insensitive',()=>{
 const result=aggregateAnalytics(fixture({userAchievements:[{isUnlocked:true},{isUnlocked:false},{}],appFeedback:[{status:'Resolved'},{status:'Closed'},{status:'New'}]}),NOW);
 assert.equal(result.totals.achievementAwards,1);assert.equal(result.safety.openFeedback,1);
});

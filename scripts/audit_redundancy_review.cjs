'use strict';

// Review-only audit. Firebase requests are reads/list/query operations; output
// contains schema, counts and code references, never document contents/secrets.
const fs = require('fs');
const path = require('path');
const {execFileSync} = require('child_process');
const {firebaseAccessToken, firestoreRequest, projectId} = require('./seed_malaysia_trails');
const root = path.resolve(__dirname, '..');
// Optional source trees can be absent in a checkout; inspect only existing paths.
const sourceTrees = ['lib', 'functions', 'scripts', 'tool', 'test', 'android', 'ios', 'web', 'windows', 'macos', 'linux']
  .filter(directory => fs.existsSync(path.join(root, directory)));
const files = execFileSync('rg', ['--files', ...sourceTrees, '-g', '!**/node_modules/**', '-g', '!**/build/**', '-g', '!**/Pods/**', '-g', '!**/package-lock.json'], {cwd: root, encoding: 'utf8'}).trim().split(/\r?\n/).map(f => f.replaceAll('\\', '/'));
const source = new Map(files.filter(f => /\.(dart|js|cjs|kt|java|swift|html|json|xml|yaml|py|ps1)$/.test(f)).map(f => [f, fs.readFileSync(path.join(root, f), 'utf8')]));
const production = [...source].filter(([f]) => !/\/test\/|^test\/|^scripts\/|^tool\//.test(f));
const appText = production.map(([,t]) => t).join('\n');
const sourceWords = new Set(appText.match(/[A-Za-z_][A-Za-z0-9_]*/g) || []);
// Dynamic dictionary keys can be phone numbers, IDs or tokens. Report schema
// placeholders, never those keys. Unknown nested keys are also anonymized.
const dictionaryFields = new Set(['fcmTokenByAppId','buddyRequestsIncoming','buddyRequestsOutgoing',
  'groupChatMutedUntil','pinnedChats','activeHikeSessionIdsByPhone','unreadCount','lastReadAt',
  'memberNames','memberPhotoUrls','participantsByPhone','memberAliases','participantLocations']);
function nestedSchema(docs) {
 const stats = new Map();
 function walk(fields, prefix = '', dynamic = false) {
  for (const [key,value] of Object.entries(fields || {})) {
   const safe = dynamic || !sourceWords.has(key) || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(key) ? '{key}' : key;
   const field = prefix ? prefix + '.' + safe : safe;
   const type = Object.keys(value)[0]; const entry = stats.get(field) || {occurrences:0,types:[]};
   entry.occurrences++; if(!entry.types.includes(type))entry.types.push(type); stats.set(field,entry);
   if(value.mapValue)walk(value.mapValue.fields,field,dictionaryFields.has(key));
   if(value.arrayValue)for(const item of value.arrayValue.values||[]) {
    if(item.mapValue)walk(item.mapValue.fields,field+'[]',dictionaryFields.has(key));
   }
  }
 }
 docs.forEach(d=>walk(d.fields));
 return Object.fromEntries([...stats].sort(([a],[b])=>a.localeCompare(b)));
}
const report = {generatedAt: new Date().toISOString(), projectId, static: {}, live: {}};
function matches(text, regex) {return [...text.matchAll(regex)];}
function reach(graph, roots) {const visited = new Set(); const visit = f => {if (visited.has(f)) return; visited.add(f); for (const dep of graph.get(f) || []) visit(dep);}; roots.forEach(visit); return visited;}
const dartFiles = [...source.keys()].filter(f => f.startsWith('lib/') && f.endsWith('.dart'));
const dartGraph = new Map(dartFiles.map(f => [f, matches(source.get(f), /\b(?:import|export|part)\s+['"]([^'"]+)['"]/g).map(m => m[1]).filter(v => !v.startsWith('dart:') && (!v.startsWith('package:') || v.startsWith('package:hiker_circle/'))).map(v => v.startsWith('package:') ? 'lib/' + v.slice('package:hiker_circle/'.length) : path.posix.normalize(path.posix.join(path.posix.dirname(f), v)))]));
const mainReach = reach(dartGraph, ['lib/main.dart']);
const allReach = reach(dartGraph, dartFiles.filter(f => /(?:^|\/)\w*main\.dart$/.test(f)));
report.static.dart = {fileCount: dartFiles.length, unreachableFromMain: dartFiles.filter(f => !mainReach.has(f)), unreachableFromAnyEntryPoint: dartFiles.filter(f => !allReach.has(f))};
const jsFiles = [...source.keys()].filter(f => f.startsWith('functions/') && !f.includes('/test/') && /\.(js|cjs)$/.test(f));
const jsGraph = new Map(jsFiles.map(f => [f, matches(source.get(f), /require\(['"](\.[^'"]+)['"]\)/g).map(m => path.posix.normalize(path.posix.join(path.posix.dirname(f), m[1] + (/\.[a-z]+$/.test(m[1]) ? '' : '.js'))))]));
const jsReach = reach(jsGraph, ['functions/index.js']);
report.static.backendModules = {fileCount: jsFiles.length, unreachable: jsFiles.filter(f => !jsReach.has(f))};
report.static.singleOccurrencePublicSymbols = dartFiles.flatMap(f => matches(source.get(f), /^(?:abstract |sealed |final |base |interface )?(?:class|enum|mixin)\s+([A-Z]\w+)/gm).filter(m => matches(appText, new RegExp('\\b' + m[1] + '\\b', 'g')).length === 1).map(m => ({file:f,symbol:m[1]})));
const pub = fs.readFileSync(path.join(root,'pubspec.yaml'),'utf8');
report.static.unimportedDependencies = matches(pub.split('dependencies:')[1].split('dev_dependencies:')[0], /^  ([a-z][a-z_0-9]+):/gm).map(m => m[1]).filter(d => d !== 'flutter' && !(d === 'cupertino_icons' && appText.includes('CupertinoIcons.')) && !appText.includes(`package:${d}/`));
report.static.publicMethodsWithoutCallers = dartFiles.flatMap(f => matches(source.get(f), /^  (?:static )?(?:Future<[^\n]+?>|Stream<[^\n]+?>|void|bool|int|String|List<[^\n]+?>|Map<[^\n]+?>)\s+([a-z]\w+)\s*\(/gm).filter(m => matches(appText, new RegExp('\\b' + m[1] + '\\b', 'g')).length === 1).map(m => ({file:f,symbol:m[1],line:source.get(f).slice(0,m.index).split('\n').length})));
report.static.backendFunctionsWithoutCallers = jsFiles.flatMap(f => matches(source.get(f), /^(?:async )?function\s+(\w+)\(/gm).filter(m => matches(appText,new RegExp('\\b'+m[1]+'\\b','g')).length === 1).map(m=>({file:f,symbol:m[1],line:source.get(f).slice(0,m.index).split('\n').length})));
report.static.assets = matches(pub, /^    - (assets\/[^\r\n]+)/gm).map(m => ({path:m[1],bytes:fs.statSync(path.join(root,m[1])).size,sourceReferences:production.filter(([,t]) => t.includes(m[1])).map(([f]) => f)}));
report.static.functionExports = matches(source.get('functions/index.js'), /exports\.(\w+)\s*=/g).map(m => m[1]);
for (const m of matches(source.get('functions/index.js'), /Object\.entries\(\{([^}]+)\}\)\)\s*\{\s*exports\[name\]/g)) {
 report.static.functionExports.push(...matches(m[1], /(\w+)\s*:/g).map(v=>v[1]));
}
report.static.functionExports=[...new Set(report.static.functionExports)];
report.static.unreferencedSqlTables = matches(source.get('lib/app/Data/local_session_database.dart'), /CREATE TABLE(?: IF NOT EXISTS)?\s+(\w+)/g).map(m => m[1]).filter((t,i,a) => a.indexOf(t)===i).map(t => ({table:t,files:production.filter(([,text])=>text.includes(t)).map(([f])=>f)}));
function decode(v) {if(v.mapValue) return Object.fromEntries(Object.entries(v.mapValue.fields||{}).map(([k,n])=>[k,decode(n)])); if(v.arrayValue) return (v.arrayValue.values||[]).map(decode); return Object.values(v)[0];}
function fields(d) {return Object.fromEntries(Object.entries(d.fields||{}).map(([k,v])=>[k,decode(v)]));}
function milliseconds(v) {if(typeof v==='number')return v; if(typeof v==='string')return /^\d{12,}$/.test(v)?Number(v):Date.parse(v); return NaN;}
async function mapLimit(values, action, concurrency=6) {let next=0;const result=[];await Promise.all(Array.from({length:Math.min(concurrency,values.length)},async()=>{while(next<values.length){const i=next++; result[i]=await action(values[i]);}}));return result;}
function summary(docs) {const statuses={}, fieldStats={};let expired=0,consumed=0,oldest=null,newest=null;for(const doc of docs){const data=fields(doc);for(const[k,v]of Object.entries(doc.fields||{})){const s=fieldStats[k]||{present:0,wireBytes:0,types:[]};s.present++;s.wireBytes+=Buffer.byteLength(JSON.stringify(v));const type=Object.keys(v)[0];if(!s.types.includes(type))s.types.push(type);fieldStats[k]=s;}if(data.status)statuses[data.status]=(statuses[data.status]||0)+1;if(milliseconds(data.expiresAtMillis ?? data.expiresAt ?? data.expiresAtLocal)<Date.now())expired++;if(data.consumed===true||data.used===true)consumed++;if(doc.createTime&&(!oldest||doc.createTime<oldest))oldest=doc.createTime;if(doc.updateTime&&(!newest||doc.updateTime>newest))newest=doc.updateTime;}return{count:docs.length,expired,consumed,statuses,oldestCreated:oldest,newestUpdated:newest,topFieldsByWireSize:Object.entries(fieldStats).sort((a,b)=>b[1].wireBytes-a[1].wireBytes).slice(0,12).map(([name,s])=>({name,...s})),fieldsAbsentFromProductionSource:Object.keys(fieldStats).filter(k=>!appText.includes(k)),fieldPresence:Object.fromEntries(Object.entries(fieldStats).map(([k,s])=>[k,s.present]))};}
async function main(){
 const token=await firebaseAccessToken();
 const db=`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)`;
 const docRoot=`${db}/documents`;
 const get=(url,options)=>firestoreRequest(token,url,options);
 const collectionIds=[];let pageToken='';do{const r=await get(`${docRoot}:listCollectionIds`,{method:'POST',body:JSON.stringify({pageSize:1000,...(pageToken?{pageToken}: {})})});collectionIds.push(...r.collectionIds||[]);pageToken=r.nextPageToken||'';}while(pageToken);
 const documents=new Map();
 await mapLimit(collectionIds.sort(),async id=>{const docs=[];let next='';do{const u=new URL(`${docRoot}/${id}`);u.searchParams.set('pageSize','300');if(next)u.searchParams.set('pageToken',next);const r=await get(u);docs.push(...r.documents||[]);next=r.nextPageToken||'';}while(next);documents.set(id,docs);console.log(`Read ${id}: ${docs.length}`);});
 report.live.collections=Object.fromEntries([...documents].sort().map(([id,docs])=>[id,{...summary(docs),productionReferences:production.filter(([,text])=>text.includes(id)).map(([f])=>f)}]));
 const groups=['authFactors','comments','messages','ratings','reminderPreferences','reports','routeGeometry','snapshotArchives','modules'];
 const groupDocs=new Map();
 await mapLimit(groups,async id=>{const r=await get(`${docRoot}:runQuery`,{method:'POST',body:JSON.stringify({structuredQuery:{from:[{collectionId:id,allDescendants:true}]}})});const docs=(r||[]).filter(x=>x.document).map(x=>x.document);groupDocs.set(id,docs);report.live.subcollections=report.live.subcollections||{};const parents={};for(const doc of docs){const p=doc.name.split('/documents/')[1].split('/')[0];parents[p]=(parents[p]||0)+1;}report.live.subcollections[id]={...summary(docs),rootParents:parents};});
 let allDocs=[...[...documents.values()].flat(),...[...groupDocs.values()].flat()];
 if(process.argv.includes('--discover')){
   const inspected=new Set();const discovered=new Set(groups);const extra=[];
   while(true){const pending=allDocs.filter(d=>!inspected.has(d.name));if(!pending.length)break;
     console.log(`Discovering subcollections under ${pending.length} documents...`);
     await mapLimit(pending,async d=>{inspected.add(d.name);let next='';do{const r=await get(`https://firestore.googleapis.com/v1/${d.name}:listCollectionIds`,{method:'POST',body:JSON.stringify({pageSize:1000,...(next?{pageToken:next}:{})})});for(const id of r.collectionIds||[])discovered.add(id);next=r.nextPageToken||'';}while(next);},12);
     const unknown=[...discovered].filter(id=>!groupDocs.has(id));if(!unknown.length)break;
     await mapLimit(unknown,async id=>{const r=await get(`${docRoot}:runQuery`,{method:'POST',body:JSON.stringify({structuredQuery:{from:[{collectionId:id,allDescendants:true}]}})});const docs=(r||[]).filter(x=>x.document).map(x=>x.document);groupDocs.set(id,docs);extra.push(id);const parents={};for(const d of docs){const p=d.name.split('/documents/')[1].split('/')[0];parents[p]=(parents[p]||0)+1;}report.live.subcollections[id]={...summary(docs),rootParents:parents};});
     allDocs=[...[...documents.values()].flat(),...[...groupDocs.values()].flat()];
   }
   report.live.subcollectionDiscovery={documentsInspected:inspected.size,additionalCollectionGroups:extra};
 }
 const knownPaths=new Set(allDocs.map(d=>d.name));
 report.live.nestedSchemas=Object.fromEntries([...documents,...groupDocs].map(([id,docs])=>[id,nestedSchema(docs)]));
 report.live.orphanSubcollections={};for(const[id,docs]of groupDocs){const n=docs.filter(d=>!knownPaths.has(d.name.slice(0,d.name.lastIndexOf('/'+id+'/')))).length;if(n)report.live.orphanSubcollections[id]=n;}
 const ids=collection=>new Set((documents.get(collection)||[]).map(d=>d.name.split('/').at(-1)));
 const sessions=ids('hikeSessions'),trails=ids('trails'),teamSessions=ids('teamHikeSessions');
 report.live.relationships={};
 for(const collection of ['hikeRouteCaptures','footprints','networkObservations','checkIns']) {const docs=documents.get(collection)||[];report.live.relationships[collection]={count:docs.length,missingHikeSession:docs.filter(d=>{const v=fields(d);return v.sessionId&&!sessions.has(v.sessionId);}).length};}
 const weatherKeys=new Set((documents.get('trails')||[]).map(d=>{const v=fields(d);return Number(v.latitude).toFixed(4)+'_'+Number(v.longitude).toFixed(4);}));
 report.live.relationships.trailWeatherCache={withoutCurrentTrailCoordinates:(documents.get('trailWeatherCache')||[]).filter(d=>!weatherKeys.has(d.name.split('/').at(-1))).length};
 report.live.relationships.groupChats={...Object.fromEntries(['direct','group'].map(type=>[type,(documents.get('groupChats')||[]).filter(d=>fields(d).chatType===type).length])),softDeleted:(documents.get('groupChats')||[]).filter(d=>fields(d).isDeleted===true).length,pastRemovalTime:(documents.get('groupChats')||[]).filter(d=>milliseconds(fields(d).chatRemovesAtLocal)<Date.now()).length,missingReferencedTeamSession:(documents.get('groupChats')||[]).filter(d=>{const v=fields(d);return v.teamHikeSessionId&&!teamSessions.has(v.teamHikeSessionId);}).length};
 const phaseCounts={};for(const d of documents.get('teamHikeSessions')||[]){const v=fields(d);phaseCounts[v.phase]=(phaseCounts[v.phase]||0)+1;}report.live.relationships.teamPhases=phaseCounts;
 report.live.relationships.upcomingSoftDeleted=(documents.get('upcomingHikes')||[]).filter(d=>fields(d).isDeleted===true).length;
 const sessionData=new Map((documents.get('hikeSessions')||[]).map(d=>[d.name.split('/').at(-1),fields(d)]));
 report.live.relationships.activeTeamLinks=(documents.get('teamHikeSessions')||[]).filter(d=>fields(d).phase==='active').map(d=>{const v=fields(d);const linked=[...new Set([v.activeHikeSessionId,...Object.values(v.activeHikeSessionIdsByPhone||{})].filter(Boolean))];return{linkedCount:linked.length,linkedStatuses:linked.map(id=>sessionData.get(id)?.status||'missing'),draftPresent:!!v.draft};});
 report.live.relationships.flatChatReadReceiptFields={documentsWithLiteralDottedFields:(documents.get('groupChats')||[]).filter(d=>Object.keys(d.fields||{}).some(k=>/^(lastReadAt|unreadCount)\./.test(k))).length,literalFieldCount:(documents.get('groupChats')||[]).reduce((sum,d)=>sum+Object.keys(d.fields||{}).filter(k=>/^(lastReadAt|unreadCount)\./.test(k)).length,0)};
 report.live.userDuplication=(documents.get('users')||[]).map(d=>{const v=fields(d);return{tokenArrayCount:(v.fcmTokens||[]).length,tokenMapCount:Object.keys(v.fcmTokenByAppId||{}).length,tokenCopiesEqual:v.activeFcmToken===v.lastFcmToken&&v.activeFcmToken===(v.fcmTokens||[])[0],usernameCopiesEqual:v.username===v.profile?.username,oldEmbeddedSosMapsPresent:'latest_sos_alert'in v||'sos_alerts'in v};});
 const references=new Set();const visit=v=>{if(typeof v==='string'){const m=v.match(/\/o\/([^?]+)/);if(m&&v.includes('firebasestorage.googleapis.com'))references.add(decodeURIComponent(m[1]));else if(v.startsWith('gs://hiker-circle.firebasestorage.app/'))references.add(v.slice('gs://hiker-circle.firebasestorage.app/'.length));else if(/^(trail_covers|community_hikes|group_chats|profile_photos|app_feedback|releases|first_aid)\//.test(v))references.add(v);}else if(v&&typeof v==='object')Object.values(v).forEach(visit);};
 allDocs.forEach(d=>visit(fields(d)));for(const f of ['assets/guides/first_aid_guide.json','web/site/beta-release.json'])if(fs.existsSync(path.join(root,f)))visit(JSON.parse(fs.readFileSync(path.join(root,f),'utf8')));
 let authCount=0,authNext='';do{const r=await get(`https://identitytoolkit.googleapis.com/v1/projects/${projectId}/accounts:batchGet?maxResults=1000${authNext?'&nextPageToken='+encodeURIComponent(authNext):''}`);authCount+=(r.users||[]).length;for(const u of r.users||[])visit(u.photoUrl);authNext=r.nextPageToken||'';}while(authNext);report.live.authAccountCount=authCount;
 const objects=[];let storageNext='';do{const u=new URL('https://storage.googleapis.com/storage/v1/b/hiker-circle.firebasestorage.app/o');u.searchParams.set('maxResults','1000');u.searchParams.set('fields','items(name,size,contentType,timeCreated),nextPageToken');if(storageNext)u.searchParams.set('pageToken',storageNext);const r=await get(u);objects.push(...r.items||[]);storageNext=r.nextPageToken||'';}while(storageNext);
 const prefixes={};for(const o of objects){const p=o.name.split('/')[0];const s=prefixes[p]||{count:0,bytes:0,unreferencedCount:0,unreferencedBytes:0};s.count++;s.bytes+=Number(o.size);if(!references.has(o.name)){s.unreferencedCount++;s.unreferencedBytes+=Number(o.size);}prefixes[p]=s;}report.live.storage={count:objects.length,bytes:objects.reduce((s,o)=>s+Number(o.size),0),prefixes,unreferencedObjects:objects.filter(o=>!references.has(o.name)).map(o=>({name:o.name,bytes:Number(o.size),contentType:o.contentType}))};
 const functions=[];for(const region of ['us-central1','asia-southeast1']){const r=await get(`https://cloudfunctions.googleapis.com/v2/projects/${projectId}/locations/${region}/functions?pageSize=1000`);functions.push(...r.functions||[]);}report.live.functions=functions.map(f=>({name:f.name.split('/').at(-1),region:f.name.split('/')[3],state:f.state,updated:f.updateTime,trigger:f.eventTrigger?.eventType||'http',entryPoint:f.buildConfig?.entryPoint}));report.live.deployedWithoutExport=report.live.functions.filter(f=>!report.static.functionExports.includes(f.name));report.live.exportsWithoutDeployment=report.static.functionExports.filter(id=>!report.live.functions.some(f=>f.name===id));
 report.live.scheduler=[];for(const region of ['us-central1','asia-southeast1']){const r=await get(`https://cloudscheduler.googleapis.com/v1/projects/${projectId}/locations/${region}/jobs?pageSize=500`);report.live.scheduler.push(...(r.jobs||[]).map(j=>({name:j.name.split('/').at(-1),region,schedule:j.schedule,state:j.state,target:j.httpTarget?.uri||j.pubsubTarget?.topicName,lastAttemptTime:j.lastAttemptTime})));}
 report.live.indexes=(await get(`${db}/collectionGroups/-/indexes`)).indexes?.map(i=>({name:i.name.split('/').at(-1),collection:i.name.split('/collectionGroups/')[1].split('/')[0],fields:i.fields,queryScope:i.queryScope,state:i.state}));
 try{const r=await get(`${db}/collectionGroups/-/fields?filter=ttl_config:*`);report.live.ttlPolicies=(r.fields||[]).filter(f=>f.ttlConfig).map(f=>({name:f.name,ttlConfig:f.ttlConfig}));}catch(e){report.live.ttlInspectionError=e.message;}
 const output=path.join(root,'tmp','redundancy-review-audit.json');fs.mkdirSync(path.dirname(output),{recursive:true});const safeJson=JSON.stringify(report,null,2).replace(/((?:unreadCount|lastReadAt)\.)\+?\d{7,15}/g,'$1{memberKey}');fs.writeFileSync(output,safeJson);console.log(`Review metadata: ${output}`);console.log(JSON.stringify({dart:report.static.dart,backend:report.static.backendModules,dependencies:report.static.unimportedDependencies,symbols:report.static.singleOccurrencePublicSymbols,storage:report.live.storage,deployedWithoutExport:report.live.deployedWithoutExport,exportsWithoutDeployment:report.live.exportsWithoutDeployment,ttlPolicies:report.live.ttlPolicies,discovery:report.live.subcollectionDiscovery},null,2));
}
main().catch(e=>{console.error(e);process.exitCode=1;});

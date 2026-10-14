'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const {submit, update, mediaFor, active, MAX_MEDIA_BYTES, LIFETIME_MS} = require('../trail_cautions');
const NOW = Date.parse('2026-10-12T08:00:00Z');
function fixture() {
  const rows = new Map(), files = new Map();
  const ref = path => ({path, collection:name => ({doc:id => ref(`${path}/${name}/${id}`)})});
  let queue = Promise.resolve();
  const db = {collection:name => ({doc:id => ref(`${name}/${id}`)}),
    runTransaction: fn => {
      const task = queue.then(async () => {
        const writes=[]; let writing=false;
        const result=await fn({
          get:async r => { assert.equal(writing,false,'Firestore reads must precede writes'); return {exists:rows.has(r.path), data:() => structuredClone(rows.get(r.path))}; },
          create:(r,data) => {writing=true;writes.push(() => {assert.equal(rows.has(r.path),false); rows.set(r.path,structuredClone(data));});},
          update:(r,data) => {writing=true;writes.push(() => rows.set(r.path,{...rows.get(r.path),...structuredClone(data)}));},
        });
        for (const write of writes) write(); return result;
      }); queue=task.catch(() => {}); return task;
    }};
  const bucket = {name:'test-bucket',file:path => ({getMetadata:async () => {
    if (!files.has(path)) throw Error('not found'); return [files.get(path)];
  },setMetadata:async value => {files.get(path).metadata=value.metadata;}})};
  const options={db,bucket,uid:'owner',phone:'+60111111111',now:NOW,timestamp:n => new Date(n).toISOString()};
  const data={hazardId:'caution-1',trailId:'trail-1',trailName:'Ridge',hazardType:'Fallen tree',description:'Across the path',latitude:5.1,longitude:100.2};
  const action=(uid,kind,extra={}) => { const {requestId='one',...payload}=extra; return update({...options,uid,data:{hazardId:'caution-1',requestId:`${uid}_${kind}_${requestId}`,action:kind,...payload}}); };
  return {rows,files,options,data,action,bucket};
}

test('report creation is idempotent, begins with one confirmation, and expires after seven days',async () => {
  const f=fixture(); await submit({...f.options,data:f.data}); await submit({...f.options,data:f.data});
  const report=f.rows.get('hazardReports/caution-1');
  assert.equal(report.reportCount,1); assert.equal(report.reportedBy,'owner');
  assert.equal(report.expiresAt,new Date(NOW+LIFETIME_MS).toISOString());
  assert.equal(active(report,NOW+LIFETIME_MS-1),true); assert.equal(active(report,NOW+LIFETIME_MS),false);
  assert.equal((await f.action('owner','confirm')).duplicate,true);
  assert.equal(f.rows.get('hazardReports/caution-1').reportCount,1);
});
test('concurrent retries and one-account multiple requests never inflate confirmation counts',async () => {
  const f=fixture(); await submit({...f.options,data:f.data});
  await Promise.all([f.action('a','confirm'),f.action('a','confirm'),f.action('a','confirm',{requestId:'two'}),f.action('b','confirm')]);
  assert.equal(f.rows.get('hazardReports/caution-1').reportCount,3);
});
test('three distinct resolution votes resolve the caution and later hikers may also confirm resolution',async () => {
  const f=fixture(); await submit({...f.options,data:f.data});
  await f.action('a','resolve',{description:'Tree cleared'});
  await f.action('a','confirmResolution');
  await f.action('b','confirmResolution');
  assert.equal(f.rows.get('hazardReports/caution-1').status,'unverified');
  await f.action('c','confirmResolution');
  assert.equal(f.rows.get('hazardReports/caution-1').status,'resolved');
  await f.action('d','confirmResolution');
  assert.equal(f.rows.get('hazardReports/caution-1').resolutionCount,4);
});
test('resolved cautions cannot be raised by a bare upvote; confirmed evidence reopens once',async () => {
  const f=fixture(); await submit({...f.options,data:f.data});
  await f.action('a','resolve'); await f.action('b','confirmResolution'); await f.action('c','confirmResolution');
  for (const action of ['confirm','reopen']) await assert.rejects(f.action('a',action),{code:'failed-precondition'});
  await assert.rejects(f.action('a','reopen',{description:'Still present'}),{code:'failed-precondition'});
  await f.action('a','reopen',{description:'New fallen tree here',confirmed:true});
  await f.action('a','reopen',{description:'New fallen tree here',confirmed:true});
  const report=f.rows.get('hazardReports/caution-1');
  assert.equal(report.status,'unverified'); assert.equal(report.reportCount,2); assert.equal(report.resolutionCount,0);
  assert.equal(report.cycle,1); assert.equal(report.resolutionId,null); assert.equal(report.latestEvidence.description,'New fallen tree here');
  assert.equal(report.expiresAt,new Date(NOW+LIFETIME_MS).toISOString());
  await f.action('b','confirm'); assert.equal(f.rows.get('hazardReports/caution-1').reportCount,3);
});
test('existing resolution voters may add evidence without adding another vote',async () => {
  const f=fixture(); await submit({...f.options,data:f.data}); await f.action('a','resolve');
  await f.action('a','resolve',{requestId:'evidence',description:'Bridge repaired today'});
  assert.equal(f.rows.get('hazardReports/caution-1').resolutionCount,1);
  assert.equal(f.rows.get('hazardReports/caution-1/updates/a_resolve_evidence').description,'Bridge repaired today');
});
test('expired and rejected reports stay in history but do not accept votes',async () => {
  const f=fixture(); await submit({...f.options,data:f.data});
  await assert.rejects(update({...f.options,now:NOW+LIFETIME_MS,data:{hazardId:'caution-1',requestId:'new',action:'confirm'}}),{code:'failed-precondition'});
  f.rows.get('hazardReports/caution-1').status='rejected'; await assert.rejects(f.action('b','confirm'),{code:'failed-precondition'});
  assert.equal(f.rows.has('hazardReports/caution-1'),true);
});
test('actual uploaded object metadata enforces ownership, MIME, duplicate paths and total 50 MB',async () => {
  const f=fixture(); const path='trail_cautions/owner/caution-1/image.jpg';
  f.files.set(path,{size:'100',contentType:'image/jpeg',metadata:{ownerUid:'owner',hazardId:'caution-1'}});
  const media=[{storagePath:path,name:'proof.jpg',url:'https://attacker.invalid/untrusted'}];
  const result=await mediaFor({...f.options,hazardId:'caution-1',media});
  assert.match(result[0].url,/firebasestorage.googleapis.com/); assert.equal(result[0].sizeBytes,100);
  await assert.rejects(mediaFor({...f.options,uid:'other',hazardId:'caution-1',media}),{code:'invalid-argument'});
  await assert.rejects(mediaFor({...f.options,hazardId:'caution-1',media:[...media,...media]}),{code:'invalid-argument'});
  f.files.get(path).contentType='video/mp4'; await assert.rejects(mediaFor({...f.options,hazardId:'caution-1',media}),{code:'invalid-argument'});
  f.files.get(path).contentType='image/jpeg'; f.files.get(path).size=String(MAX_MEDIA_BYTES+1);
  await assert.rejects(mediaFor({...f.options,hazardId:'caution-1',media}),{code:'invalid-argument'});
  f.files.get(path).size=String(MAX_MEDIA_BYTES);
  assert.equal((await mediaFor({...f.options,hazardId:'caution-1',media}))[0].sizeBytes,MAX_MEDIA_BYTES);
});
test('media-only evidence can reopen a resolved report, with its uploaded media retained',async () => {
  const f=fixture(); await submit({...f.options,data:f.data});
  await f.action('a','resolve'); await f.action('b','confirmResolution'); await f.action('c','confirmResolution');
  const path='trail_cautions/owner/caution-1/video.mp4';
  f.files.set(path,{size:'300',contentType:'video/mp4',metadata:{ownerUid:'owner',hazardId:'caution-1'}});
  await f.action('owner','reopen',{confirmed:true,media:[{storagePath:path}]});
  assert.equal(f.rows.get('hazardReports/caution-1').latestEvidence.media[0].contentType,'video/mp4');
});

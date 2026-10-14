'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');
const {createRequire} = require('node:module');
const runtime = createRequire(path.join(__dirname,'../functions/package.json'));
const {submit,update} = require('../functions/trail_cautions');
exports.run = async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) throw Error('Emulators are required.');
  const {initializeApp,deleteApp}=runtime('firebase-admin/app');
  const {getFirestore,Timestamp}=runtime('firebase-admin/firestore');
  const {getStorage}=runtime('firebase-admin/storage');
  const app=initializeApp({projectId:'demo-hiker-circle',storageBucket:'demo-hiker-circle.appspot.com'},'caution-emulator');
  try {
    const db=getFirestore(app),bucket=getStorage(app).bucket(),uid='user_owner',hazardId='emulator-caution';
    const now=Date.now(),options={db,bucket,uid,phone:'+60111111111',now,timestamp:n => Timestamp.fromMillis(n)};
    const storagePath=`trail_cautions/${uid}/${hazardId}/proof.jpg`;
    await bucket.file(storagePath).save(Buffer.from([0xff,0xd8,0xff,0xd9]),{resumable:false,metadata:{contentType:'image/jpeg',metadata:{ownerUid:uid,hazardId}}});
    const data={hazardId,trailId:'trail-1',trailName:'Ridge',hazardType:'Fallen tree',description:'Across the path',latitude:5.1,longitude:100.2,media:[{storagePath,name:'proof.jpg'}]};
    await submit({...options,data});await submit({...options,data});
    const act=(actor,action,requestId,extra={}) => update({...options,uid:actor,data:{hazardId,action,requestId,...extra}});
    await Promise.all([act('a','confirm','a-1'),act('a','confirm','a-2'),act('b','confirm','b-1')]);
    const ref=db.collection('hazardReports').doc(hazardId);
    let report=(await ref.get()).data();assert.equal(report.reportCount,3);assert.equal(report.media.length,1);
    assert.equal((await bucket.file(storagePath).getMetadata())[0].metadata.firebaseStorageDownloadTokens.length>0,true);
    await act('a','resolve','a-resolution',{description:'Path is clear'});
    await Promise.all([act('b','confirmResolution','b-resolution'),act('c','confirmResolution','c-resolution'),act('b','confirmResolution','b-duplicate')]);
    report=(await ref.get()).data();assert.equal(report.status,'resolved');assert.equal(report.resolutionCount,3);
    await assert.rejects(act('d','reopen','no-evidence',{confirmed:true}),{code:'failed-precondition'});
    await act('d','reopen','with-evidence',{confirmed:true,description:'New tree blocking this location'});
    await act('d','reopen','with-evidence',{confirmed:true,description:'New tree blocking this location'});
    report=(await ref.get()).data();assert.equal(report.status,'unverified');assert.equal(report.reportCount,4);assert.equal(report.resolutionCount,0);
    assert.equal(report.expiresAt.toMillis(),now+7*86400000);
    await assert.rejects(update({...options,now:now+7*86400000,data:{hazardId,action:'confirm',requestId:'expired'}}),{code:'failed-precondition'});
    assert.equal((await ref.get()).exists,true);
    console.log('PASS Real Firestore caution transactions, concurrent votes, Storage media, resolution, reopening and expiry');
  } finally {await deleteApp(app);}
};

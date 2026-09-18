'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {transformFields,planRename,documentUrl} = require('../rename_trail_ids');
const {firestoreDocumentRoot:root} = require('../seed_malaysia_trails');
const s = stringValue => ({stringValue});
const doc = (name,fields) => ({name:`${root}/${name}`,fields,updateTime:'2026-09-14T00:00:00Z'});
test('encodes special characters in document IDs for read-back',()=>{
  assert.ok(documentUrl(`${root}/downloadedMaps/+123_new`).endsWith('/downloadedMaps/%2B123_new'));
});
test('repairs nested snapshots, lists and pointers without changing coordinates, timestamps or media paths',()=>{
  const fields = {trailId:s('old'),trail:{mapValue:{fields:{trailId:s('old')}}},
    favorites:{arrayValue:{values:[s('old'),s('other')]}},
    geometryDocument:s(`${root}/trails/old/routeGeometry/xyz`),
    ref:{referenceValue:`${root}/trails/old`},
    photo:s('https://storage.example/trail_covers/old/photo.jpg'),
    localFilePath:s('mapbox-tile-region://trail-old'),
    point:{geoPointValue:{latitude:5.4,longitude:100.2}},
    empty:{mapValue:{}},emptyArray:{arrayValue:{}},
    createdAt:{timestampValue:'2026-09-14T00:00:00Z'}};
  const result = transformFields(fields,'old','new');
  assert.equal(result.trail.mapValue.fields.trailId.stringValue,'new');
  assert.deepEqual(result.favorites.arrayValue.values,[s('new'),s('other')]);
  assert.equal(result.geometryDocument.stringValue,`${root}/trails/new/routeGeometry/xyz`);
  assert.equal(result.ref.referenceValue,`${root}/trails/new`);
  for(const k of ['photo','localFilePath','point','createdAt','empty','emptyArray'])assert.deepEqual(result[k],fields[k]);
});
test('moves root, geometry, rating and download record atomically with optimistic preconditions',()=>{
  const docs = [doc('trails/old',{trailId:s('old')}),doc('trails/old/routeGeometry/g',{pointCount:{integerValue:'1081'}}),
    doc('trails/old/ratings/r',{trailId:s('old')}),doc('hikeSessions/h',{trailId:s('old')}),
    doc('downloadedMaps/user_old',{trailId:s('old'),downloadedMapId:s('user_old')})];
  const p=planRename(docs,'old','new');
  assert.equal(p.changes.length,5);assert.equal(p.writes.length,9);
  assert.equal(p.writes.filter(w=>w.delete).length,4);
  assert.ok(p.writes.every(w=>w.currentDocument));
  assert.equal(p.changes[4].after.fields.downloadedMapId.stringValue,'user_new');
  const after=p.changes.map(c=>({...c.after,updateTime:'new'}));
  assert.equal(planRename(after,'old','new').writes.length,0);
});
test('rejects destination collisions and a missing source',()=>{
  assert.throws(()=>planRename([doc('trails/old',{}),doc('trails/new',{})],'old','new'),/already exists/);
  assert.throws(()=>planRename([],'old','new'),/missing/);
});

'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {prepare}=require('../migrate_native_trail_routes');
const {firestoreFields}=require('../seed_malaysia_trails');
const {encodePolyline}=require('../lib/imported_route_geometry');
const points=[{lat:5.41,lon:100.27},{lat:5.411,lon:100.271},{lat:5.41,lon:100.27}];
const name='projects/hiker-circle/databases/(default)/documents/trails/test';
function document(extra={}) {return {name,fields:firestoreFields({
  name:'Test trail',routeEncodedPolyline:encodePolyline(points),
  checkpoints:[{latitude:5.41,longitude:100.27,name:'Trailhead',order:1}],
  ratingAverage:4.7,...extra})};}
test('conversion preserves traversal and only updates metadata/reference fields',()=>{
  const d=document({routeReferenceUrl:'https://example.com/reference'});
  const before=JSON.stringify(d);
  const p=prepare(d);
  assert.deepEqual(p.geometry.points,points);
  assert.equal(JSON.stringify(d),before);
  for(const key of ['checkpoints','routeEncodedPolyline','ratingAverage','name'])
    assert.equal(Object.hasOwn(p.updates,key),false);
  assert.equal(p.changed,true);
});
test('existing native precision and per-vertex elevations survive',()=>{
  const precise=points.map(p=>({...p,lat:p.lat+0.000001,ele:123}));
  const existing={name:`${name}/routeGeometry/native`,fields:firestoreFields({
    coordinateSystem:'WGS84',points:precise,pointCount:3,updatedAt:'2026-09-14'})};
  const p=prepare(document(),existing);
  assert.deepEqual(p.geometry.points,precise);
});
test('reruns are idempotent for the native representation',()=>{
  const first=prepare(document());
  const d=document(first.updates);
  const g={name:first.geometryName,fields:firestoreFields(first.geometry)};
  assert.equal(prepare(d,g).changed,false);
});
test('invalid paths fail before any writes',()=>{
  assert.throws(()=>prepare(document({routeEncodedPolyline:'x'})),/Malformed/);
  assert.throws(()=>prepare(document({routeEncodedPolyline:''})),/Invalid/);
});

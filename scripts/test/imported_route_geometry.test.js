'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {prepareTrack, checkpointsHash, decodePolyline} = require('../lib/imported_route_geometry');
const track = {points: [
  {lat:5.41,lon:100.27,ele:80}, {lat:5.4101,lon:100.2701,ele:90},
  {lat:5.4102,lon:100.2702,ele:100}, {lat:5.4101,lon:100.2701,ele:90},
  {lat:5.41,lon:100.27,ele:80},
], waypoints: []};
test('retains every outbound and return vertex, including duplicates', () => {
  const p=prepareTrack(track);
  assert.deepEqual(decodePolyline(p.polyline),track.points.map(({lat,lon})=>({lat,lon})));
  assert.equal(p.maxErrorMeters,0);
  assert.equal(p.closed,true);
  assert.equal(p.elevationGainMeters,20);
});
test('reports bounded quantization error rather than claiming exact fidelity', () => {
  const p=prepareTrack({...track,points:track.points.map(p=>({...p,lat:p.lat+0.000004}))});
  assert.ok(p.maxErrorMeters>0 && p.maxErrorMeters<1);
});
test('rejects disconnected geometry and non-finite coordinates', () => {
  assert.throws(()=>prepareTrack({...track,points:[...track.points,{lat:6,lon:102}]}),/gap/);
  assert.throws(()=>prepareTrack({...track,points:[...track.points,{lat:NaN,lon:102}]}),/Invalid/);
});
test('fingerprint ignores labels but changes when checkpoint geometry changes', () => {
  const c=prepareTrack(track).checkpoints;
  assert.equal(checkpointsHash(c),checkpointsHash(c.map(p=>({...p,name:'Renamed'}))));
  assert.notEqual(checkpointsHash(c),checkpointsHash(c.map((p,i)=>i? p:{...p,latitude:5.5})));
});

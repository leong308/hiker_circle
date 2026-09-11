'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {upcomingPrecautions} = require('../hike_precaution_reminders');
const now = Date.UTC(2026,8,10);
function weather(overrides={}) { return {cachedAtLocal:new Date(now).toISOString(),forecastData:{hourly:{time:[now/1000,now/1000+3600,now/1000+7200],weather_code:[0,0,95],...overrides}}}; }
test('excludes storm outside hiking window including buffer',()=>{
  assert.equal(upcomingPrecautions(weather(),now,30,now).length,0);
  assert.equal(upcomingPrecautions(weather(),now,120,now)[0].id,'storm');
});
test('humidity and heat must coincide',()=>{
  const w=weather({temperature_2m:[30,25],relative_humidity_2m:[50,90]});
  assert.equal(upcomingPrecautions(w,now,30,now).length,0);
  w.forecastData.hourly.relative_humidity_2m[0]=80;
  assert.equal(upcomingPrecautions(w,now,30,now)[0].id,'heat');
});
test('stale or unknown freshness does not send weather claims',()=>{
  const w=weather(); w.cachedAtLocal='invalid';
  assert.deepEqual(upcomingPrecautions(w,now,120,now),[]);
  w.cachedAtLocal=new Date(now-4*3600000).toISOString();
  assert.deepEqual(upcomingPrecautions(w,now,120,now),[]);
});
test('heavy rain and strong gusts outrank ordinary precautions',()=>{
  const result=upcomingPrecautions(weather({precipitation:[10,0],wind_gusts_10m:[60,0],uv_index:[8,0]}),now,30,now);
  assert.deepEqual(result.map(c=>[c.id,c.severity]),[['rain',3],['wind',3],['uv',2]]);
});

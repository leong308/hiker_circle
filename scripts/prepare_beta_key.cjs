// Creates an app/API-restricted beta key; private configuration stays ignored.
const fs=require('node:fs'); const path=require('node:path');
async function main(){
 const root=path.join(process.env.APPDATA,'npm/node_modules/firebase-tools/lib');
 const auth=require(path.join(root,'auth.js')); const scopes=require(path.join(root,'scopes.js'));
 const a=auth.getGlobalDefaultAccount(); if(!a) throw Error('Login required');
 const t=await auth.getAccessToken(a.tokens.refresh_token,[scopes.CLOUD_PLATFORM,scopes.FIREBASE_PLATFORM]);
 const headers={Authorization:`Bearer ${t.access_token}`,'Content-Type':'application/json'};
 const parent='projects/hiker-circle/locations/global'; const name=parent+'/keys/hikercircle-android-beta';
 let r=await fetch('https://apikeys.googleapis.com/v2/'+name,{headers});
 if(r.status===404){
  r=await fetch('https://apikeys.googleapis.com/v2/'+parent+'/keys?keyId=hikercircle-android-beta',{method:'POST',headers,body:JSON.stringify({displayName:'HikerCircle Android direct beta',restrictions:{androidKeyRestrictions:{allowedApplications:[{packageName:'com.leongziqi.hikercircle',sha1Fingerprint:'4E84B7B37406768A071559598FFE800C61987B3A'}]},apiTargets:[{service:'geocoding-backend.googleapis.com'},{service:'routes.googleapis.com'},{service:'maps-android-backend.googleapis.com'}]}})});
  if(!r.ok) throw Error('Key creation HTTP '+r.status);
  let op=await r.json();
  while(!op.done){await new Promise(r=>setTimeout(r,1500));const p=await fetch('https://apikeys.googleapis.com/v2/'+op.name,{headers});op=await p.json();}
  if(op.error) throw Error('Key creation operation failed');
 }else if(!r.ok) throw Error('Key inspection HTTP '+r.status);
 const k=await fetch('https://apikeys.googleapis.com/v2/'+name+'/keyString',{headers});if(!k.ok) throw Error('Key retrieval HTTP '+k.status);
 const {keyString}=await k.json();
 const good={'X-Android-Package':'com.leongziqi.hikercircle','X-Android-Cert':'4E84B7B37406768A071559598FFE800C61987B3A'};
 const url='https://maps.googleapis.com/maps/api/geocode/json?latlng=5.34277,100.28203&key='+encodeURIComponent(keyString);
 const valid=await (await fetch(url,{headers:good})).json();
 const invalid=await (await fetch(url,{headers:{...good,'X-Android-Package':'invalid.beta.client'}})).json();
 console.log('Geocoding valid client: '+valid.status+'; invalid client: '+invalid.status);
 const routeBody=JSON.stringify({origin:{location:{latLng:{latitude:5.34277,longitude:100.28203}}},destination:{location:{latLng:{latitude:5.34293,longitude:100.28635}}},travelMode:'WALK'});
 const routeHeaders={...good,'Content-Type':'application/json','X-Goog-Api-Key':keyString,'X-Goog-FieldMask':'routes.distanceMeters'};
 const route=await fetch('https://routes.googleapis.com/directions/v2:computeRoutes',{method:'POST',headers:routeHeaders,body:routeBody});
 const wrongRoute=await fetch('https://routes.googleapis.com/directions/v2:computeRoutes',{method:'POST',headers:{...routeHeaders,'X-Android-Package':'invalid.beta.client'},body:routeBody});
 console.log('Routes valid client HTTP '+route.status+'; invalid client HTTP '+wrongRoute.status);
 if(!route.ok||wrongRoute.status!==403) throw Error('Routes restriction verification failed');
 fs.mkdirSync('output/beta',{recursive:true});
 fs.writeFileSync('output/beta/restricted-key.json',JSON.stringify({keyString,name,verified:valid.status==='OK'&&invalid.status==='REQUEST_DENIED'}));
 if(valid.status!=='OK'||invalid.status!=='REQUEST_DENIED') throw Error('Restriction verification has not passed; do not publish');
 console.log('Restricted beta key verified. No key values printed.');
}
main().catch(e=>{console.error(e.message);process.exitCode=1});

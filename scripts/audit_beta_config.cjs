// Read-only audit. Never prints API-key values or access tokens.
const fs = require('node:fs');
const path = require('node:path');
async function main() {
  const root = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
  const auth = require(path.join(root, 'auth.js'));
  const scopes = require(path.join(root, 'scopes.js'));
  const account = auth.getGlobalDefaultAccount();
  if (!account) throw new Error('Firebase login required');
  const token = await auth.getAccessToken(account.tokens.refresh_token, [scopes.CLOUD_PLATFORM, scopes.FIREBASE_PLATFORM]);
  const headers = {Authorization: `Bearer ${token.access_token}`};
  const env = Object.fromEntries(fs.readFileSync('.env','utf8').split(/\r?\n/).filter(x=>/^[A-Z_]+=/.test(x)).map(x=>{const i=x.indexOf('=');return [x.slice(0,i),x.slice(i+1).trim().replace(/^['"]|['"]$/g,'')]}));
  for (const name of ['GOOGLE_ROUTES_API_KEY','GOOGLE_GEOCODING_API_KEY']) {
    const lookup = await fetch('https://apikeys.googleapis.com/v2/keys:lookupKey?keyString='+encodeURIComponent(env[name]),{headers});
    if (!lookup.ok) {console.log(name+': restriction audit unavailable ('+lookup.status+')');continue;}
    const info = await lookup.json();
    const response=await fetch('https://apikeys.googleapis.com/v2/'+info.name,{headers});
    if(!response.ok) {console.log(name+': restriction audit unavailable ('+response.status+')');continue;}
    const key=await response.json();
    console.log(name+': '+JSON.stringify(key.restrictions || {}));
  }
  console.log('Mapbox public token format: '+Boolean(env.MAPBOX_ACCESS_TOKEN?.startsWith('pk.')));
}
main().catch(()=>{console.error('Configuration audit failed; no credentials printed.');process.exitCode=1});

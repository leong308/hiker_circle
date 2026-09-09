'use strict';

// Original KKM bytes only: no cutting, re-encoding, dubbing or added branding.
// Reuse policy: https://infosihat.moh.gov.my/faq.html (question 2).
const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const root = path.resolve(__dirname, '..');
const bucket = 'hiker-circle.firebasestorage.app';
const apply = process.argv.includes('--apply');
const verify = process.argv.includes('--verify');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'assets/guides/first_aid_guide.json'), 'utf8'));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

async function main() {
  const videos = manifest.topics.map(t => t.video).filter(Boolean);
  const authRoot = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
  let token;
  if (apply || verify) {
    const auth = require(path.join(authRoot, 'auth.js'));
    const account = auth.getGlobalDefaultAccount();
    if (!account) throw Error('Sign in to Firebase CLI first.');
    const scopes = require(path.join(authRoot, 'scopes.js'));
    token = (await auth.getAccessToken(account.tokens.refresh_token, [scopes.CLOUD_PLATFORM, scopes.FIREBASE_PLATFORM])).access_token;
  }
  for (const video of videos) {
    if (video.region !== 'MY' || video.version < 2 ||
        new URL(video.downloadUrl).hostname !== 'infosihat.moh.gov.my' ||
        video.licenseUrl !== 'https://infosihat.moh.gov.my/faq.html' ||
        !/^[a-f0-9]{64}$/.test(video.sha256)) throw Error('Unapproved source metadata');
    const file = path.join(root, 'tmp/kkm_first_aid', path.basename(video.storagePath));
    fs.mkdirSync(path.dirname(file), {recursive:true});
    let bytes;
    if (!verify) {
      if (fs.existsSync(file)) bytes = fs.readFileSync(file);
      else {
        const response = await fetch(video.downloadUrl, {signal:AbortSignal.timeout(180000)});
        if (!response.ok) throw Error(`KKM download failed: ${response.status}`);
        bytes = Buffer.from(await response.arrayBuffer());
        if (bytes.length !== video.expectedBytes || hash(bytes) !== video.sha256) throw Error('Source has changed. Review it before updating the manifest.');
        fs.writeFileSync(file, bytes);
      }
      if (bytes.length !== video.expectedBytes || hash(bytes) !== video.sha256) throw Error('Local file integrity mismatch');
    }
    const endpoint = `https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(video.storagePath)}`;
    if (apply) {
      const url = new URL(`https://storage.googleapis.com/upload/storage/v1/b/${bucket}/o`);
      url.searchParams.set('uploadType', 'media');
      url.searchParams.set('name', video.storagePath);
      url.searchParams.set('ifGenerationMatch', '0');
      const response = await fetch(url, {method:'POST', headers:{Authorization:`Bearer ${token}`, 'Content-Type':'video/mp4'}, body:bytes, signal:AbortSignal.timeout(180000)});
      if (!response.ok && response.status !== 412) throw Error(`Upload failed: ${response.status}`);
      if (response.ok) {
        const metadata = await fetch(endpoint, {method:'PATCH', headers:{Authorization:`Bearer ${token}`, 'Content-Type':'application/json'}, body:JSON.stringify({cacheControl:'private,max-age=31536000,immutable', metadata:{sourcePage:video.sourceUrl, license:video.license, licenseUrl:video.licenseUrl, attribution:video.attribution, sha256:video.sha256, appMediaVersion:String(video.version)}})});
        if (!metadata.ok) throw Error(`Metadata update failed: ${metadata.status}`);
      }
    }
    if (apply || verify) {
      const response = await fetch(`${endpoint}?alt=media`, {headers:{Authorization:`Bearer ${token}`}, signal:AbortSignal.timeout(180000)});
      if (!response.ok) throw Error(`Readback failed: ${response.status}`);
      const remote = Buffer.from(await response.arrayBuffer());
      if (remote.length !== video.expectedBytes || hash(remote) !== video.sha256) throw Error('Published object differs from approved KKM original');
    }
    console.log(`${video.storagePath}: ${video.expectedBytes} bytes; SHA-256 verified${apply || verify ? ' against Firebase readback' : ''}`);
  }
  console.log(`${videos.length} KKM originals checked. ${manifest.topics.length - videos.length} topics have no verified video; no substitute footage uploaded.`);
}
main().catch(error => {console.error(error.message); process.exitCode = 1;});

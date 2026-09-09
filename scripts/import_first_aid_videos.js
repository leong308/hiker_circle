/* eslint-disable no-console */
'use strict';

throw new Error('Retired US media importer. Use import_kkm_first_aid_videos.cjs; do not republish withdrawn tutorials.');

// Downloads the explicitly public-domain source videos, converts them to a
// mobile-friendly MP4, and uploads versioned immutable objects to Firebase
// Storage. Attribution remains visible in the app's guide JSON.

const { createHash } = require('crypto');
const { createWriteStream, existsSync, mkdirSync, readFileSync, renameSync, statSync, unlinkSync } = require('fs');
const { pipeline } = require('stream/promises');
const { Readable } = require('stream');
const { spawn } = require('child_process');
const path = require('path');

const projectId = 'hiker-circle';
const bucket = 'hiker-circle.firebasestorage.app';
const version = 1;
const applyChanges = process.argv.includes('--apply');
const outputRoot = path.resolve(__dirname, '..', 'tmp', 'first_aid_videos');

const media = [
  {
    id: 'falls_injury',
    title: 'Basic first-aid response in the field',
    sourcePage: 'https://www.dvidshub.net/video/431657/first-aid-and-zero-range',
    sourceUrl: 'https://d34w7g4gy10iej.cloudfront.net/video/1511/DOD_102846599/DOD_102846599-1024x576-1769k.mp4',
    attribution: 'U.S. Army video by Spc. William Marlow / DVIDS',
  },
  {
    id: 'bleeding',
    title: 'Hemorrhage control and tourniquet training',
    sourcePage: 'https://www.dvidshub.net/video/341221/bridging-gap-between-navy-medicine-and-marine-corps-tactics',
    sourceUrl: 'https://d34w7g4gy10iej.cloudfront.net/video/1406/DOD_101716576/DOD_101716576-720x406-800k.mp4',
    attribution: 'U.S. Marine Corps video by Cpl. Joshua Murray / DVIDS',
  },
  {
    id: 'sprain',
    title: 'Getting an ankle injury professionally assessed',
    sourcePage: 'https://www.dvidshub.net/video/915217/wilford-halls-new-physical-and-occupational-therapy-direct-access-clinic',
    sourceUrl: 'https://d34w7g4gy10iej.cloudfront.net/video/2403/DOD_110168678/DOD_110168678.mp4',
    attribution: 'U.S. Air Force video by Senior Airman Joshua Rosario / DVIDS',
  },
  {
    id: 'heat_exhaustion',
    title: 'Recognising and preventing heat injury',
    sourcePage: 'https://www.dvidshub.net/video/335780/heat-injury',
    sourceUrl: 'https://d34w7g4gy10iej.cloudfront.net/video/1405/DOD_101566685/DOD_101566685-720x406-800k.mp4',
    attribution: 'U.S. Army Combat Readiness Center / DVIDS',
  },
  {
    id: 'snake_bite',
    title: 'Venomous snake encounter safety',
    sourcePage: 'https://www.dvidshub.net/video/681179/habu-safety-101',
    sourceUrl: 'https://d34w7g4gy10iej.cloudfront.net/video/1905/DOD_106764386/DOD_106764386-1024x576-1769k.mp4',
    attribution: 'U.S. Air Force video by Senior Airman Kristan Campbell / DVIDS',
  },
  {
    id: 'lost_stranded',
    title: 'Hiking safety and emergency preparation',
    sourcePage: 'https://www.dvidshub.net/video/966114/hiking-safety',
    sourceUrl: 'https://d34w7g4gy10iej.cloudfront.net/video/2506/DOD_111061655/DOD_111061655.mp4',
    attribution: 'U.S. Air Force video by Airman First Class Maria Washler / DVIDS',
  },
  {
    id: 'severe_weather',
    title: 'Lightning safety on the trail',
    sourcePage: 'https://www.dvidshub.net/video/926312/lightning-safety',
    sourceUrl: 'https://d34w7g4gy10iej.cloudfront.net/video/2406/DOD_110359411/DOD_110359411.mp4',
    attribution: 'U.S. Navy video by Charity Robinson / DVIDS',
  },
];

async function firebaseAccessToken() {
  const firebaseToolsRoot = path.join(
    process.env.APPDATA || '', 'npm', 'node_modules', 'firebase-tools', 'lib',
  );
  const auth = require(path.join(firebaseToolsRoot, 'auth.js'));
  const scopes = require(path.join(firebaseToolsRoot, 'scopes.js'));
  const account = auth.getGlobalDefaultAccount();
  if (!account) throw new Error('Firebase CLI is not signed in.');
  if (account.tokens.access_token && Date.now() < account.tokens.expires_at - 30000) {
    return account.tokens.access_token;
  }
  const refreshed = await auth.getAccessToken(account.tokens.refresh_token, [
    scopes.CLOUD_PLATFORM,
    scopes.FIREBASE_PLATFORM,
  ]);
  return refreshed.access_token;
}

async function download(url, target) {
  const head = await fetch(url, { method: 'HEAD', signal: AbortSignal.timeout(30000) });
  if (!head.ok) throw new Error(`Source check failed (${head.status}) for ${url}`);
  const expectedBytes = Number(head.headers.get('content-length'));
  if (existsSync(target) && statSync(target).size === expectedBytes) return;
  const partial = `${target}.part`;
  if (existsSync(partial)) unlinkSync(partial);
  const response = await fetch(url, { signal: AbortSignal.timeout(600000) });
  if (!response.ok || !response.body) {
    throw new Error(`Download failed (${response.status}) for ${url}`);
  }
  await pipeline(Readable.fromWeb(response.body), createWriteStream(partial));
  if (Number.isFinite(expectedBytes) && statSync(partial).size !== expectedBytes) {
    unlinkSync(partial);
    throw new Error(`Incomplete source download for ${url}`);
  }
  if (existsSync(target)) unlinkSync(target);
  renameSync(partial, target);
}

function runFfmpeg(input, output) {
  const executable = process.env.FIRST_AID_FFMPEG || 'ffmpeg';
  const args = [
    '-hide_banner', '-loglevel', 'error', '-y', '-i', input,
    '-map', '0:v:0', '-map', '0:a?',
    '-vf', 'scale=min(854\\,iw):-2',
    '-c:v', 'libx264', '-preset', 'medium', '-crf', '25',
    '-maxrate', '1200k', '-bufsize', '2400k', '-pix_fmt', 'yuv420p',
    '-c:a', 'aac', '-b:a', '96k', '-movflags', '+faststart', output,
  ];
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, { stdio: 'inherit' });
    child.on('error', reject);
    child.on('exit', (code) => code === 0 ? resolve() : reject(new Error(`ffmpeg exited with ${code}`)));
  });
}

async function upload(token, item, file) {
  const objectName = `first_aid/videos/${item.id}_v${version}.mp4`;
  const uploadUrl = new URL(`https://storage.googleapis.com/upload/storage/v1/b/${bucket}/o`);
  uploadUrl.searchParams.set('uploadType', 'media');
  uploadUrl.searchParams.set('name', objectName);
  const uploadResponse = await fetch(uploadUrl, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'video/mp4',
      'Content-Length': String(statSync(file).size),
    },
    body: readFileSync(file),
    signal: AbortSignal.timeout(300000),
  });
  if (!uploadResponse.ok) {
    throw new Error(`Storage upload failed (${uploadResponse.status}): ${await uploadResponse.text()}`);
  }

  const metadataUrl = `https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(objectName)}`;
  const metadataResponse = await fetch(metadataUrl, {
    method: 'PATCH',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      cacheControl: 'public,max-age=31536000,immutable',
      metadata: {
        sourcePage: item.sourcePage,
        attribution: item.attribution,
        license: 'Public domain (U.S. government work)',
        appMediaVersion: String(version),
      },
    }),
  });
  if (!metadataResponse.ok) {
    throw new Error(`Metadata update failed (${metadataResponse.status}): ${await metadataResponse.text()}`);
  }
  return objectName;
}

async function main() {
  mkdirSync(outputRoot, { recursive: true });
  const token = applyChanges ? await firebaseAccessToken() : null;
  const report = [];

  for (const [index, item] of media.entries()) {
    console.log(`[${index + 1}/${media.length}] ${item.title}`);
    const source = path.join(outputRoot, `${item.id}.source.mp4`);
    const output = path.join(outputRoot, `${item.id}_v${version}.mp4`);
    await download(item.sourceUrl, source);
    if (!existsSync(output) || statSync(output).size === 0) await runFfmpeg(source, output);
    const bytes = statSync(output).size;
    const sha256 = createHash('sha256').update(readFileSync(output)).digest('hex');
    const storagePath = applyChanges
      ? await upload(token, item, output)
      : `first_aid/videos/${item.id}_v${version}.mp4`;
    report.push({ id: item.id, storagePath, expectedBytes: bytes, sha256 });
  }

  console.log(JSON.stringify(report, null, 2));
  console.log(applyChanges ? `Uploaded ${report.length} tutorials to ${bucket}.` : 'Dry run complete. Add --apply to upload.');
}

main().catch((error) => {
  console.error(error && error.stack || error);
  process.exitCode = 1;
});

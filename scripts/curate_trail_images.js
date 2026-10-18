#!/usr/bin/env node
// curate_trail_images selects attributable trail photos and updates image credits.

'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { execFileSync } = require('child_process');

const projectId = 'hiker-circle';
const storageBucket = 'hiker-circle.firebasestorage.app';
const firestoreRoot =
  `https://firestore.googleapis.com/v1/projects/${projectId}` +
  '/databases/(default)/documents';
const manifestPath = path.join(__dirname, 'trail_image_manifest.json');
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const applyChanges = process.argv.includes('--apply');
const verifyLive = process.argv.includes('--verify-live');
const selectedTrailId = process.argv
  .find((argument) => argument.startsWith('--trail='))
  ?.slice('--trail='.length);
const userAgent =
  'HikerCircleTrailImageCurator/1.0 (https://github.com/; contact: app administrator)';

function firestoreValue(value) {
  if (value === null) return { nullValue: null };
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(firestoreValue) } };
  }
  switch (typeof value) {
    case 'boolean':
      return { booleanValue: value };
    case 'number':
      return Number.isInteger(value)
        ? { integerValue: String(value) }
        : { doubleValue: value };
    case 'string':
      return { stringValue: value };
    case 'object': {
      const fields = {};
      for (const [key, item] of Object.entries(value)) {
        fields[key] = firestoreValue(item);
      }
      return { mapValue: { fields } };
    }
    default:
      throw new Error(`Unsupported Firestore value: ${typeof value}`);
  }
}

function firestoreFields(data) {
  return Object.fromEntries(
    Object.entries(data).map(([key, value]) => [key, firestoreValue(value)]),
  );
}

function fromFirestoreValue(value) {
  if (!value) return null;
  if ('nullValue' in value) return null;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('timestampValue' in value) return value.timestampValue;
  if ('arrayValue' in value) {
    return (value.arrayValue.values || []).map(fromFirestoreValue);
  }
  if ('mapValue' in value) {
    return Object.fromEntries(
      Object.entries(value.mapValue.fields || {}).map(([key, item]) => [
        key,
        fromFirestoreValue(item),
      ]),
    );
  }
  if ('geoPointValue' in value) return value.geoPointValue;
  return null;
}

function firestoreDocument(document) {
  const fields = Object.fromEntries(
    Object.entries(document.fields || {}).map(([key, value]) => [
      key,
      fromFirestoreValue(value),
    ]),
  );
  return {
    ...fields,
    trailId: fields.trailId || document.name.split('/').pop(),
    documentName: document.name,
  };
}

async function firebaseAccessToken() {
  const npmExecutable = process.platform === 'win32' ? 'npm.cmd' : 'npm';
  const globalNodeModules = execFileSync(npmExecutable, ['root', '-g'], {
    encoding: 'utf8',
  }).trim();
  const firebaseToolsRoot = path.join(globalNodeModules, 'firebase-tools', 'lib');
  const auth = require(path.join(firebaseToolsRoot, 'auth.js'));
  const scopes = require(path.join(firebaseToolsRoot, 'scopes.js'));
  const account = auth.getGlobalDefaultAccount();
  if (!account) {
    throw new Error('Firebase CLI is not signed in. Run firebase login --reauth.');
  }
  if (
    account.tokens.access_token &&
    Date.now() < account.tokens.expires_at - 30000
  ) {
    return account.tokens.access_token;
  }
  const refreshed = await auth.getAccessToken(account.tokens.refresh_token, [
    scopes.CLOUD_PLATFORM,
    scopes.FIREBASE_PLATFORM,
  ]);
  return refreshed.access_token;
}

async function requestJson(url, options = {}) {
  const response = await fetch(url, options);
  if (!response.ok) {
    throw new Error(`${response.status} ${response.statusText}: ${await response.text()}`);
  }
  return response.status === 204 ? {} : response.json();
}

async function firebaseRequest(token, url, options = {}) {
  return requestJson(url, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });
}

async function loadTrails(token) {
  const documents = [];
  let pageToken = '';
  do {
    const url = new URL(`${firestoreRoot}/trails`);
    url.searchParams.set('pageSize', '300');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const data = await firebaseRequest(token, url);
    documents.push(...(data.documents || []));
    pageToken = data.nextPageToken || '';
  } while (pageToken);
  return documents.map(firestoreDocument);
}

function stripHtml(value) {
  return String(value || '')
    .replace(/<br\s*\/?>/gi, ' ')
    .replace(/<[^>]*>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&quot;/gi, '"')
    .replace(/&#0*39;/gi, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

function metadataValue(metadata, key) {
  return stripHtml(metadata?.[key]?.value);
}

function trustedCommonsLicense(shortName, licenseUrl) {
  const normalized = `${shortName} ${licenseUrl}`.toLowerCase();
  if (normalized.includes('noncommercial') || normalized.includes('no derivatives')) {
    return false;
  }
  return (
    normalized.includes('cc0') ||
    normalized.includes('public domain') ||
    /cc by(?:-sa)?(?: |$)/i.test(shortName) ||
    /creativecommons\.org\/(?:licenses\/(?:by|by-sa)\/|publicdomain\/)/i.test(
      licenseUrl,
    )
  );
}

async function commonsImage(fileTitle) {
  const url = new URL('https://commons.wikimedia.org/w/api.php');
  url.searchParams.set('action', 'query');
  url.searchParams.set('format', 'json');
  url.searchParams.set('formatversion', '2');
  url.searchParams.set('redirects', '1');
  url.searchParams.set('prop', 'imageinfo');
  url.searchParams.set('iiprop', 'url|mime|size|extmetadata');
  url.searchParams.set('iiurlwidth', '1600');
  url.searchParams.set('titles', fileTitle);
  const data = await requestJson(url, {
    headers: { 'User-Agent': userAgent, Accept: 'application/json' },
  });
  const page = data.query?.pages?.[0];
  const info = page?.imageinfo?.[0];
  if (!page || page.missing || !info) {
    throw new Error(`Wikimedia Commons file not found: ${fileTitle}`);
  }
  const metadata = info.extmetadata || {};
  const licenseName = metadataValue(metadata, 'LicenseShortName');
  const licenseUrl = metadataValue(metadata, 'LicenseUrl');
  if (!trustedCommonsLicense(licenseName, licenseUrl)) {
    throw new Error(
      `Unsupported or unclear license for ${page.title}: ${licenseName || 'unknown'}`,
    );
  }
  const canonicalTitle = page.title;
  const sourcePageUrl =
    'https://commons.wikimedia.org/wiki/' +
    encodeURIComponent(canonicalTitle.replaceAll(' ', '_'));
  return {
    fileTitle: canonicalTitle,
    downloadUrl: info.thumburl || info.url,
    mimeType: info.thumbmime || info.mime,
    sourcePageUrl,
    credit: {
      sourceName: 'Wikimedia Commons',
      sourcePageUrl,
      author:
        metadataValue(metadata, 'Artist') ||
        metadataValue(metadata, 'Credit') ||
        'Wikimedia Commons contributor',
      licenseName,
      licenseUrl,
      description:
        metadataValue(metadata, 'ImageDescription') ||
        canonicalTitle.replace(/^File:/, ''),
    },
  };
}

function decodePolyline(encoded, precision) {
  if (typeof encoded !== 'string' || encoded.length === 0) return [];
  const coordinates = [];
  let index = 0;
  let latitude = 0;
  let longitude = 0;
  const factor = 10 ** precision;
  while (index < encoded.length) {
    let shift = 0;
    let result = 0;
    let byte;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    latitude += result & 1 ? ~(result >> 1) : result >> 1;
    shift = 0;
    result = 0;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    longitude += result & 1 ? ~(result >> 1) : result >> 1;
    coordinates.push([latitude / factor, longitude / factor]);
  }
  return coordinates;
}

function routePoints(trail) {
  const checkpointPoints = (trail.checkpoints || [])
    .map((checkpoint) => [checkpoint.latitude, checkpoint.longitude])
    .filter(([latitude, longitude]) =>
      Number.isFinite(latitude) && Number.isFinite(longitude),
    );
  const candidates = [5, 6]
    .map((precision) => decodePolyline(trail.routeEncodedPolyline, precision))
    .filter((points) => points.length >= 2)
    .filter((points) =>
      points.every(
        ([latitude, longitude]) =>
          Number.isFinite(latitude) &&
          Number.isFinite(longitude) &&
          Math.abs(latitude) <= 90 &&
          Math.abs(longitude) <= 180,
      ),
    );
  if (candidates.length === 0) return checkpointPoints;
  const reference = checkpointPoints[0] || [trail.latitude, trail.longitude];
  candidates.sort((first, second) => {
    const distance = (points) =>
      Math.abs(points[0][0] - reference[0]) +
      Math.abs(points[0][1] - reference[1]);
    return distance(first) - distance(second);
  });
  return candidates[0];
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const value of buffer) {
    crc ^= value;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const typeBuffer = Buffer.from(type, 'ascii');
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])));
  return Buffer.concat([length, typeBuffer, data, checksum]);
}

function encodePng(width, height, pixels) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  const rows = Buffer.alloc(height * (width * 4 + 1));
  for (let y = 0; y < height; y += 1) {
    const rowOffset = y * (width * 4 + 1);
    rows[rowOffset] = 0;
    pixels.copy(rows, rowOffset + 1, y * width * 4, (y + 1) * width * 4);
  }
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk('IHDR', header),
    pngChunk('IDAT', zlib.deflateSync(rows, { level: 9 })),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

function routeCover(trail) {
  const width = 1200;
  const height = 675;
  const pixels = Buffer.alloc(width * height * 4);
  const seed = crypto
    .createHash('sha256')
    .update(trail.trailId)
    .digest()
    .readUInt32BE(0);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const index = (y * width + x) * 4;
      const wave =
        Math.sin((x + (seed & 63)) / 67) * 4 +
        Math.cos((y + ((seed >>> 6) & 63)) / 43) * 3;
      const vertical = y / height;
      pixels[index] = Math.max(16, Math.min(42, 28 + wave - vertical * 7));
      pixels[index + 1] = Math.max(58, Math.min(116, 92 + wave * 2 - vertical * 18));
      pixels[index + 2] = Math.max(42, Math.min(84, 67 + wave - vertical * 12));
      pixels[index + 3] = 255;
    }
  }

  const blendPixel = (x, y, red, green, blue, alpha = 255) => {
    const px = Math.round(x);
    const py = Math.round(y);
    if (px < 0 || py < 0 || px >= width || py >= height) return;
    const offset = (py * width + px) * 4;
    const amount = alpha / 255;
    pixels[offset] = Math.round(pixels[offset] * (1 - amount) + red * amount);
    pixels[offset + 1] = Math.round(
      pixels[offset + 1] * (1 - amount) + green * amount,
    );
    pixels[offset + 2] = Math.round(
      pixels[offset + 2] * (1 - amount) + blue * amount,
    );
  };
  const circle = (centerX, centerY, radius, color, alpha = 255) => {
    for (let y = -radius; y <= radius; y += 1) {
      const span = Math.floor(Math.sqrt(radius * radius - y * y));
      for (let x = -span; x <= span; x += 1) {
        blendPixel(centerX + x, centerY + y, ...color, alpha);
      }
    }
  };
  const thickLine = (x0, y0, x1, y1, radius, color, alpha = 255) => {
    const steps = Math.max(1, Math.ceil(Math.hypot(x1 - x0, y1 - y0)));
    for (let step = 0; step <= steps; step += 1) {
      const ratio = step / steps;
      circle(
        x0 + (x1 - x0) * ratio,
        y0 + (y1 - y0) * ratio,
        radius,
        color,
        alpha,
      );
    }
  };

  for (let contour = 0; contour < 12; contour += 1) {
    const phase = ((seed >>> (contour % 16)) & 31) / 5;
    let previousY = null;
    for (let x = -5; x <= width + 5; x += 5) {
      const y =
        30 +
        contour * 58 +
        Math.sin(x / 95 + phase) * 24 +
        Math.cos(x / 41 + phase * 0.7) * 8;
      if (previousY !== null) {
        thickLine(x - 5, previousY, x, y, 1, [190, 225, 178], 42);
      }
      previousY = y;
    }
  }

  const points = routePoints(trail);
  if (points.length < 2) {
    throw new Error(`No usable route geometry for ${trail.trailId}`);
  }
  const latitudes = points.map((point) => point[0]);
  const longitudes = points.map((point) => point[1]);
  const minLatitude = Math.min(...latitudes);
  const maxLatitude = Math.max(...latitudes);
  const minLongitude = Math.min(...longitudes);
  const maxLongitude = Math.max(...longitudes);
  const padding = 88;
  const longitudeSpan = Math.max(maxLongitude - minLongitude, 0.00001);
  const latitudeSpan = Math.max(maxLatitude - minLatitude, 0.00001);
  const scale = Math.min(
    (width - padding * 2) / longitudeSpan,
    (height - padding * 2) / latitudeSpan,
  );
  const drawnWidth = longitudeSpan * scale;
  const drawnHeight = latitudeSpan * scale;
  const offsetX = (width - drawnWidth) / 2;
  const offsetY = (height - drawnHeight) / 2;
  const canvasPoints = points.map(([latitude, longitude]) => [
    offsetX + (longitude - minLongitude) * scale,
    offsetY + (maxLatitude - latitude) * scale,
  ]);
  const stride = Math.max(1, Math.floor(canvasPoints.length / 2500));
  const simplified = canvasPoints.filter(
    (_, index) => index % stride === 0 || index === canvasPoints.length - 1,
  );
  for (let index = 1; index < simplified.length; index += 1) {
    const previous = simplified[index - 1];
    const current = simplified[index];
    thickLine(...previous, ...current, 10, [8, 35, 25], 150);
  }
  for (let index = 1; index < simplified.length; index += 1) {
    const previous = simplified[index - 1];
    const current = simplified[index];
    thickLine(...previous, ...current, 6, [119, 225, 160], 255);
  }
  const drawPin = ([x, y], color) => {
    circle(x, y, 20, [255, 255, 255], 255);
    circle(x, y, 14, color, 255);
    circle(x, y, 5, [255, 255, 255], 255);
  };
  drawPin(simplified[0], [39, 174, 96]);
  drawPin(simplified[simplified.length - 1], [222, 72, 72]);
  return encodePng(width, height, pixels);
}

function extensionForMime(mimeType) {
  return switchMime(mimeType);
}

function switchMime(mimeType) {
  if (mimeType === 'image/png') return 'png';
  if (mimeType === 'image/webp') return 'webp';
  if (mimeType === 'image/jpeg') return 'jpg';
  throw new Error(`Unsupported image type: ${mimeType}`);
}

async function downloadImage(image) {
  const response = await fetch(image.downloadUrl, {
    headers: { 'User-Agent': userAgent, Accept: 'image/*' },
  });
  if (!response.ok) {
    throw new Error(`Image download failed (${response.status}): ${image.fileTitle}`);
  }
  const mimeType = (response.headers.get('content-type') || image.mimeType)
    .split(';')[0]
    .trim();
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(mimeType)) {
    throw new Error(`Unexpected download type ${mimeType}: ${image.fileTitle}`);
  }
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length === 0 || bytes.length > 25 * 1024 * 1024) {
    throw new Error(`Invalid image size for ${image.fileTitle}: ${bytes.length}`);
  }
  return { bytes, mimeType };
}

async function objectMetadata(token, objectPath) {
  const url =
    `https://storage.googleapis.com/storage/v1/b/${storageBucket}/o/` +
    encodeURIComponent(objectPath);
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (response.status === 404) return null;
  if (!response.ok) {
    throw new Error(`Storage metadata ${response.status}: ${await response.text()}`);
  }
  return response.json();
}

async function uploadCuratedImage(token, objectPath, bytes, mimeType, source) {
  let metadata = await objectMetadata(token, objectPath);
  let downloadToken = metadata?.metadata?.firebaseStorageDownloadTokens
    ?.split(',')[0]
    ?.trim();
  if (!metadata) {
    const uploadUrl = new URL(
      `https://storage.googleapis.com/upload/storage/v1/b/${storageBucket}/o`,
    );
    uploadUrl.searchParams.set('uploadType', 'media');
    uploadUrl.searchParams.set('name', objectPath);
    const response = await fetch(uploadUrl, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': mimeType,
      },
      body: bytes,
    });
    if (!response.ok) {
      throw new Error(`Storage upload ${response.status}: ${await response.text()}`);
    }
    metadata = await response.json();
  }
  if (!downloadToken) downloadToken = crypto.randomUUID();
  const metadataUrl =
    `https://storage.googleapis.com/storage/v1/b/${storageBucket}/o/` +
    encodeURIComponent(objectPath);
  await firebaseRequest(token, metadataUrl, {
    method: 'PATCH',
    body: JSON.stringify({
      cacheControl: 'public,max-age=31536000,immutable',
      contentDisposition: 'inline',
      metadata: {
        ...(metadata.metadata || {}),
        firebaseStorageDownloadTokens: downloadToken,
        curatedBy: 'scripts/curate_trail_images.js',
        sourceName: source.sourceName,
        sourcePageUrl: source.sourcePageUrl || '',
        licenseName: source.licenseName || '',
        licenseUrl: source.licenseUrl || '',
      },
    }),
  });
  return (
    `https://firebasestorage.googleapis.com/v0/b/${storageBucket}/o/` +
    `${encodeURIComponent(objectPath)}?alt=media&token=${downloadToken}`
  );
}

function storageObjectPath(trailId, index, bytes, mimeType) {
  const digest = crypto.createHash('sha256').update(bytes).digest('hex').slice(0, 16);
  return `trail_covers/curated/${trailId}/${index + 1}-${digest}.${extensionForMime(mimeType)}`;
}

function routeCredit(trail) {
  const sourcePageUrl = String(trail.dataSourceUrl || '');
  const isOpenStreetMap = sourcePageUrl.includes('openstreetmap.org');
  return {
    sourceName: isOpenStreetMap
      ? 'OpenStreetMap contributors'
      : 'Hiker Circle route data',
    sourcePageUrl,
    author: isOpenStreetMap
      ? 'OpenStreetMap contributors'
      : 'Generated from the trail route stored by Hiker Circle',
    licenseName: isOpenStreetMap
      ? 'Open Database License (ODbL)'
      : 'Generated route cover',
    licenseUrl: isOpenStreetMap
      ? 'https://www.openstreetmap.org/copyright'
      : '',
    description:
      `Generated route cover for ${trail.name}; no substitute location photo was used.`,
  };
}

async function curatedAssetsForTrail(token, trail, entry, commonsAssets) {
  const urls = [];
  const credits = [];
  for (let index = 0; index < commonsAssets.length; index += 1) {
    const image = commonsAssets[index];
    const { bytes, mimeType } = await downloadImage(image);
    const objectPath = storageObjectPath(trail.trailId, index, bytes, mimeType);
    console.log(`  Upload ${objectPath}`);
    urls.push(
      await uploadCuratedImage(token, objectPath, bytes, mimeType, image.credit),
    );
    credits.push(image.credit);
  }
  if (entry.routeCover) {
    const bytes = routeCover(trail);
    const mimeType = 'image/png';
    const objectPath = storageObjectPath(trail.trailId, 0, bytes, mimeType);
    const credit = routeCredit(trail);
    console.log(`  Upload ${objectPath}`);
    urls.push(
      await uploadCuratedImage(token, objectPath, bytes, mimeType, credit),
    );
    credits.push(credit);
  }
  return { urls, credits };
}

async function main() {
  const token = await firebaseAccessToken();
  const allTrails = await loadTrails(token);
  const selectedTrails = selectedTrailId
    ? allTrails.filter((trail) => trail.trailId === selectedTrailId)
    : allTrails;
  if (selectedTrailId && selectedTrails.length !== 1) {
    throw new Error(`Live trail not found: ${selectedTrailId}`);
  }
  const manifestIds = new Set(Object.keys(manifest));
  const liveIds = new Set(allTrails.map((trail) => trail.trailId));
  const missingManifest = [...liveIds].filter((trailId) => !manifestIds.has(trailId));
  const staleManifest = [...manifestIds].filter((trailId) => !liveIds.has(trailId));
  if (missingManifest.length > 0 || staleManifest.length > 0) {
    throw new Error(
      `Manifest/live mismatch. Missing: ${missingManifest.join(', ') || 'none'}; ` +
      `stale: ${staleManifest.join(', ') || 'none'}`,
    );
  }

  if (verifyLive) {
    let imageCount = 0;
    for (const trail of selectedTrails) {
      const entry = manifest[trail.trailId];
      const urls = Array.isArray(trail.coverImageUrl)
        ? trail.coverImageUrl.filter(Boolean)
        : trail.coverImageUrl
          ? [trail.coverImageUrl]
          : [];
      if (urls.length === 0) {
        throw new Error(`${trail.trailId} has no live cover image.`);
      }
      if (urls.some((url) => !url.includes('firebasestorage.googleapis.com'))) {
        throw new Error(`${trail.trailId} still has a non-Firebase cover image.`);
      }
      if (!entry.keepExisting) {
        const credits = Array.isArray(trail.coverImageCredits)
          ? trail.coverImageCredits
          : [];
        if (credits.length !== urls.length) {
          throw new Error(
            `${trail.trailId} has ${urls.length} images but ${credits.length} credits.`,
          );
        }
        if (trail.coverImageCurationVersion !== 1) {
          throw new Error(`${trail.trailId} has the wrong curation version.`);
        }
      }
      for (const imageUrl of urls) {
        const response = await fetch(imageUrl, { method: 'HEAD' });
        if (!response.ok || !response.headers.get('content-type')?.startsWith('image/')) {
          throw new Error(
            `${trail.trailId} has an unreadable Firebase image (${response.status}).`,
          );
        }
        imageCount += 1;
      }
    }
    console.log(
      `Verified ${imageCount} downloadable Firebase images across ` +
        `${selectedTrails.length} live trails.`,
    );
    return;
  }

  console.log(
    `${applyChanges ? 'Apply' : 'Dry run'}: validating ${selectedTrails.length} ` +
      `of ${allTrails.length} live trails.`,
  );
  const prepared = [];
  for (const [trailIndex, trail] of selectedTrails.entries()) {
    const entry = manifest[trail.trailId];
    const prefix = `[${trailIndex + 1}/${selectedTrails.length}] ${trail.name}`;
    if (entry.keepExisting) {
      const existing = Array.isArray(trail.coverImageUrl)
        ? trail.coverImageUrl.filter(Boolean)
        : trail.coverImageUrl
          ? [trail.coverImageUrl]
          : [];
      if (
        existing.length === 0 ||
        existing.some((url) => !url.includes('firebasestorage.googleapis.com'))
      ) {
        throw new Error(`${trail.trailId} is marked keepExisting without Firebase images.`);
      }
      console.log(`${prefix}: keep ${existing.length} existing Firebase image(s).`);
      continue;
    }
    const commonsAssets = [];
    for (const title of entry.commonsFiles || []) {
      const image = await commonsImage(title);
      commonsAssets.push(image);
      console.log(
        `${prefix}: verified ${image.fileTitle} (${image.credit.licenseName}).`,
      );
    }
    if (entry.routeCover) {
      const points = routePoints(trail);
      if (points.length < 2) throw new Error(`${trail.trailId} has no route geometry.`);
      console.log(`${prefix}: verified route cover geometry (${points.length} points).`);
    }
    if (commonsAssets.length === 0 && !entry.routeCover) {
      throw new Error(`${trail.trailId} has no curated image source.`);
    }
    prepared.push({ trail, entry, commonsAssets });
  }
  if (!applyChanges) {
    console.log('Dry run complete. Re-run with --apply to upload and update Firestore.');
    return;
  }

  const writes = [];
  for (const [index, item] of prepared.entries()) {
    console.log(`[upload ${index + 1}/${prepared.length}] ${item.trail.name}`);
    const assets = await curatedAssetsForTrail(
      token,
      item.trail,
      item.entry,
      item.commonsAssets,
    );
    const updatedAtLocal = new Date().toISOString();
    writes.push({
      update: {
        name: item.trail.documentName,
        fields: firestoreFields({
          coverImageUrl: assets.urls,
          coverImageCredits: assets.credits,
          coverImageCurationVersion: 1,
          coverImageUpdatedAtLocal: updatedAtLocal,
        }),
      },
      updateMask: {
        fieldPaths: [
          'coverImageUrl',
          'coverImageCredits',
          'coverImageCurationVersion',
          'coverImageUpdatedAtLocal',
        ],
      },
      currentDocument: { exists: true },
    });
  }
  if (writes.length > 0) {
    await firebaseRequest(
      token,
      `https://firestore.googleapis.com/v1/projects/${projectId}` +
        '/databases/(default)/documents:commit',
      { method: 'POST', body: JSON.stringify({ writes }) },
    );
  }
  console.log(
    `Updated ${writes.length} trails; retained ` +
      `${selectedTrails.length - writes.length} existing Firebase image sets.`,
  );
}

main().catch((error) => {
  console.error(error?.stack || error);
  process.exitCode = 1;
});

// Generate missing covers after either native trail-creation flow commits its stored route.
'use strict';

const {createHash, randomUUID} = require('node:crypto');
const {FieldValue} = require('firebase-admin/firestore');
const {routeCover, routeCredit, routePoints} = require('./trail_route_cover');

const COVER_VERSION = 1;
const digest = value => createHash('sha256').update(value).digest('hex');
const urls = value => (Array.isArray(value) ? value : [value])
  .filter(url => typeof url === 'string' && url.trim()).map(url => url.trim());

function coverPlan(trailId, data) {
  if (!data || !/^[A-Za-z0-9_-]{1,240}$/.test(trailId)) return null;
  const existing = [...new Set([...urls(data.coverImageUrl), ...urls(data.coverImageUrls)])];
  const generated = data.generatedRouteCover;
  // Preserve photos and legacy curated images. Only our own sole generated cover can be refreshed.
  if (existing.length && (existing.length !== 1 || existing[0] !== generated?.imageUrl)) return null;
  const encoded = data.routeEncodedPolyline;
  if (typeof encoded !== 'string' || !encoded.trim() || encoded.length > 650000) return null;
  const trail = {...data, trailId, name: typeof data.name === 'string' ? data.name : trailId};
  const points = routePoints(trail);
  if (points.length < 2 || !points.some(point => point[0] !== points[0][0] || point[1] !== points[0][1])) return null;
  const signature = digest(JSON.stringify([COVER_VERSION, trailId, trail.name, encoded,
    points[0], trail.dataSourceUrl || '']));
  if (existing.length && generated?.version === COVER_VERSION && generated.signature === signature) return null;
  return {trail, signature, geometrySha256: digest(encoded)};
}

async function ensureTrailCover({db, bucket, trailId, render = routeCover, now = () => new Date().toISOString()}) {
  const reference = db.collection('trails').doc(trailId);
  const snapshot = await reference.get();
  const plan = coverPlan(trailId, snapshot.data());
  if (!plan) return {written: false, reason: 'not-needed'};

  const png = render(plan.trail);
  const imageHash = digest(png);
  const storagePath = `trail_covers/${trailId}/route-v${COVER_VERSION}-${imageHash.slice(0, 24)}.png`;
  const file = bucket.file(storagePath);
  const credit = routeCredit(plan.trail);
  try {
    await file.save(png, {
      resumable: false,
      preconditionOpts: {ifGenerationMatch: 0},
      metadata: {
        contentType: 'image/png',
        cacheControl: 'public,max-age=31536000,immutable',
        metadata: {
          firebaseStorageDownloadTokens: randomUUID(),
          sourceName: credit.sourceName,
          licenseName: credit.licenseName,
          generatedBy: 'generateMissingTrailCover',
          coverVersion: String(COVER_VERSION),
          geometrySha256: plan.geometrySha256,
        },
      },
    });
  } catch (error) {
    // Concurrent/retried events share the same immutable object and download token.
    if (Number(error.code) !== 412) throw error;
  }
  const [metadata] = await file.getMetadata();
  const token = String(metadata.metadata?.firebaseStorageDownloadTokens || '').split(',')[0];
  if (!token) throw new Error('The generated trail cover has no download token.');
  const imageUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(storagePath)}`
    + `?alt=media&token=${encodeURIComponent(token)}`;
  const generatedAt = now();

  return db.runTransaction(async transaction => {
    // An upload, rename, route edit or deletion may have raced the PNG render/upload.
    const current = await transaction.get(reference);
    const currentPlan = coverPlan(trailId, current.data());
    if (!currentPlan || currentPlan.signature !== plan.signature) return {written: false, reason: 'changed'};
    transaction.update(reference, {
      coverImageUrl: [imageUrl],
      coverImageCredits: [credit],
      coverImageCurationVersion: COVER_VERSION,
      coverImageUpdatedAtLocal: generatedAt,
      generatedRouteCover: {
        version: COVER_VERSION,
        signature: plan.signature,
        geometrySha256: plan.geometrySha256,
        storagePath,
        imageUrl,
        generatedAtLocal: generatedAt,
      },
      routeCoverRequestedAt: FieldValue.delete(),
    });
    return {written: true, storagePath};
  });
}

module.exports = {COVER_VERSION, coverPlan, ensureTrailCover};

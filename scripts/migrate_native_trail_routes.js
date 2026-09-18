/* eslint-disable no-console */
'use strict';
// Convert existing saved routes without fetching, simplifying, or rerouting.
// Run without --apply to validate the entire catalogue before any mutation.
const fs = require('fs');
const { isDeepStrictEqual } = require('util');
const { decodePolyline, encodePolyline, sha256 } = require('./lib/imported_route_geometry');
const { existingTrails, firebaseAccessToken, firestoreFields, firestoreRequest,
  projectId } = require('./seed_malaysia_trails');

const removedFields = ['dataSourceUrl', 'routeReferenceName', 'routeReferenceUrl',
  'routeReferenceNote', 'routeVerifiedAtLocal', 'osmRelationId'];
function decode(v) {
  if (!v) return null;
  if (v.mapValue) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k,x]) => [k,decode(x)]));
  if (v.arrayValue) return (v.arrayValue.values || []).map(decode);
  if (v.integerValue !== undefined) return Number(v.integerValue);
  if (v.doubleValue !== undefined) return Number(v.doubleValue);
  if (v.booleanValue !== undefined) return v.booleanValue;
  return v.stringValue ?? null;
}
function prepare(document, existingGeometry, sources = []) {
  const fields = document.fields;
  const polyline = decode(fields.routeEncodedPolyline);
  if (typeof polyline !== 'string') throw new Error('Missing stored path.');
  let points = decodePolyline(polyline);
  if (points.length < 2 || points.some(p => !Number.isFinite(p.lat) ||
      !Number.isFinite(p.lon) || Math.abs(p.lat) > 90 || Math.abs(p.lon) > 180)) {
    throw new Error('Invalid stored route coordinates.');
  }
  if (encodePolyline(points) !== polyline) throw new Error('Polyline round-trip failed.');
  const checksum = sha256(polyline);
  const previousMeta = decode(fields.routeGeometryMetadata) || {};
  // Preserve higher coordinate precision and vertex elevations from existing
  // native imports when they encode to exactly the current display path.
  const nativePoints = existingGeometry && decode(existingGeometry.fields.points);
  if (Array.isArray(nativePoints) && nativePoints.length === points.length &&
      nativePoints.every(p => Number.isFinite(p.lat) && Number.isFinite(p.lon) &&
        Math.abs(p.lat) <= 90 && Math.abs(p.lon) <= 180 &&
        (p.ele === undefined || Number.isFinite(p.ele))) &&
      encodePolyline(nativePoints) === polyline) {
    points = nativePoints.map(p => ({lat:p.lat, lon:p.lon,
      ...(p.ele !== undefined ? {ele:p.ele} : {})}));
  }
  if (Buffer.byteLength(JSON.stringify(points)) > 700000) throw new Error('Geometry exceeds document budget.');
  const name = existingGeometry?.name || `${document.name}/routeGeometry/${checksum}`;
  const now = new Date().toISOString();
  const geometry = {coordinateSystem:'WGS84', points, pointCount:points.length,
    updatedAt:decode(existingGeometry?.fields.updatedAt) || now};
  const metadata = {schemaVersion:1, geometrySha256:checksum, geometryDocument:name,
    pointCount:points.length, polylinePrecision:5,
    updatedAt:previousMeta.updatedAt || now};
  const updates = {dataSource:'Stored route coordinates', routeProvider:'stored-polyline',
    routeGeometryMetadata:metadata};
  const changed = sources.length > 0 || removedFields.some(k => fields[k] !== undefined) ||
    Object.entries(updates).some(([k,v]) => !isDeepStrictEqual(decode(fields[k]),v)) ||
    !existingGeometry || !isDeepStrictEqual(decode({mapValue:{fields:existingGeometry.fields}}),geometry);
  if (changed) updates.updatedAtLocal = now;
  return {document, geometryName:name, geometry, updates, sources, changed,
    checkpointCount:decode(fields.checkpoints)?.length || 0};
}
async function main() {
  const token = await firebaseAccessToken();
  const documents = await existingTrails(token);
  const plans = [];
  // Validate every trail before writing any route. A failed precondition never
  // overwrites a concurrently edited trail.
  for (const document of documents) {
    try {
      const metadata = decode(document.fields.routeGeometryMetadata);
      let existingGeometry;
      if (metadata?.geometryDocument) {
        const candidate = metadata.geometryDocument.startsWith('projects/')
          ? metadata.geometryDocument
          : `projects/${projectId}/databases/(default)/documents/${metadata.geometryDocument}`;
        if (!candidate.startsWith(`${document.name}/routeGeometry/`)) {
          throw new Error('Geometry pointer is outside this trail.');
        }
        existingGeometry = await firestoreRequest(token, `https://firestore.googleapis.com/v1/${candidate}`);
      }
      const listing = await firestoreRequest(token,
        `https://firestore.googleapis.com/v1/${document.name}/routeSources?pageSize=100`);
      if (listing.nextPageToken) throw new Error('Unexpected source archive pagination.');
      plans.push(prepare(document, existingGeometry, listing.documents || []));
    } catch (error) {throw new Error(`${decode(document.fields.name)}: ${error.message}`);}
  }
  const changed = plans.filter(p => p.changed);
  console.log(`Validated ${plans.length} trails; ${changed.length} need conversion; ${plans.length - changed.length} already native.`);
  const report = plans.map(p => ({trailId:p.document.name.split('/').pop(),
    name:decode(p.document.fields.name), pointCount:p.geometry.pointCount,
    checkpointCount:p.checkpointCount, status:p.changed?'validated':'already-native'}));
  if (process.argv.includes('--apply')) {
    for (const plan of changed) {
      const {document, geometryName, geometry, updates, sources} = plan;
      await firestoreRequest(token,
        `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`, {
          method:'POST', body:JSON.stringify({writes:[
            {update:{name:geometryName,fields:firestoreFields(geometry)}},
            {update:{name:document.name,fields:firestoreFields(updates)},
              updateMask:{fieldPaths:[...Object.keys(updates),...removedFields]},
              currentDocument:{updateTime:document.updateTime}},
            ...sources.map(d=>({delete:d.name,currentDocument:{updateTime:d.updateTime}})),
          ]}),
        });
      console.log(`Converted ${decode(document.fields.name)} (${geometry.pointCount} points).`);
    }
    for (const plan of plans) {
      const live = await firestoreRequest(token,`https://firestore.googleapis.com/v1/${plan.document.name}`);
      const native = await firestoreRequest(token,`https://firestore.googleapis.com/v1/${plan.geometryName}`);
      for (const [k,v] of Object.entries(plan.document.fields)) {
        if (removedFields.includes(k) || Object.hasOwn(plan.updates,k)) continue;
        if (!isDeepStrictEqual(decode(live.fields[k]),decode(v))) throw new Error(`Unrelated field changed: ${k}`);
      }
      for (const [k,v] of Object.entries(plan.updates)) {
        if (!isDeepStrictEqual(decode(live.fields[k]),v)) throw new Error(`Update verification failed: ${k}`);
      }
      if (removedFields.some(k=>live.fields[k] !== undefined) ||
          !isDeepStrictEqual(decode(native.fields.points),plan.geometry.points)) {
        throw new Error('Native route verification failed.');
      }
      report.find(r=>r.trailId===plan.document.name.split('/').pop()).status='verified-native';
    }
    console.log(`Verified all ${plans.length} native routes; saved paths, checkpoints, IDs and unrelated fields preserved.`);
  }
  fs.mkdirSync('output/route-audit',{recursive:true});
  fs.writeFileSync('output/route-audit/native-route-migration.json',JSON.stringify(report,null,2));
}
if(require.main===module)main().catch(e=>{console.error(e.message);process.exitCode=1;});
module.exports={prepare,decode,removedFields};

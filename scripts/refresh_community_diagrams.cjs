'use strict';

// Metadata refresh only: this script never writes Firebase or user values.
// Default execution prints counts. Use --apply after the guarded cloud cutover
// to replace only community schema metadata and persist stable relation IDs.
const fs = require('node:fs');
const path = require('node:path');
const {createHash, randomUUID} = require('node:crypto');
const {firebaseAccessToken, projectId} = require('./seed_malaysia_trails');
const root = path.resolve(__dirname, '..');
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
const POST = 'communityPosts/{postId}', COMMENT = `${POST}/comments/{commentId}`,
  REACTION = `${POST}/reactions/{userId}`, RETIRED = 'communityCounterEventReceipts/{documentId}';
const evidence = ['functions/community_posts.js', 'firestore.rules', 'Live community migration verification'];
const field = (type, note) => ({types: [type], evidence: [...evidence], ...(note ? {note} : {})});
const map = (fields, note) => ({...field('map', note), fields});
const array = (items, note) => ({...field('array', note), items});
const author = () => map({name: field('string'), photoURL: field('string')}, 'Small display snapshot. Current profile and level data are hydrated separately; no phone, handle, or level aliases are stored in this document.');
function canonicalSchemas() {
  const description = 'Server-owned community records. IDs and parent ownership come from document paths; embedded objects remain single JSON rows in main-layer diagrams.';
  return {
    [POST]: {path: POST, documentsObserved: 0, family: 'Community & chat', scope: 'root collection', description,
      evidence: [...evidence], fields: {
        authorId: field('string', 'Canonical user identity. The author display snapshot contains no repeated account identifier.'), author: author(),
        kind: field('string', 'note or hike.'), caption: field('string', 'Up to 5,000 characters; photo/hike posts may have an empty caption.'),
        images: array(map({path: field('string'), url: field('string')}), 'Up to six photos. Storage paths support ownership/cleanup; URLs support immediate feed display.'),
        trail: map({id: field('string'), name: field('string')}, 'Optional trail display snapshot. An unlisted hike may use a synthetic ID with no catalogue document.'),
        hike: map({sessionId: field('string'), state: field('string'), distanceKm: field('double'), durationMinutes: field('integer'),
          checkIns: field('integer'), manualPins: field('integer'), highestAltitudeMeters: field('double'), routePointCount: field('integer'),
          routePreview: array(map({latitude: field('double'), longitude: field('double')}))},
        'Optional active/completed hike snapshot; at most 80 preview coordinates. Full private routes and detailed summaries stay in hikeRouteCaptures/hikeSessions. Nested references are notes only.'),
        visibility: field('string', 'public, hidden, or removed. Moderation uses the same canonical visibility.'),
        likeCount: field('integer', 'Atomically maintained with reactions by validated callables.'),
        commentCount: field('integer', 'Atomically maintained with comments, including administrator removals.'),
        createdAt: field('timestamp'), updatedAt: field('timestamp', 'Content revision time. Counter-only changes do not invalidate edits.'),
        moderation: map({status: field('string'), reason: field('string'), adminId: field('string'), at: field('timestamp')},
          'Optional administrator decision/audit information. This map stays one main-layer JSON row.'),
      }},
    [COMMENT]: {path: COMMENT, documentsObserved: 0, family: 'Community & chat', scope: 'subcollection',
      description: 'Post comments. Parent post and comment identity derive from the path; author identity is stored once. Counter updates and comment writes commit atomically.',
      evidence: [...evidence], fields: {authorId: field('string'), author: author(), body: field('string', 'Between 1 and 2,000 characters.'),
        createdAt: field('timestamp'), updatedAt: field('timestamp')}},
    [REACTION]: {path: REACTION, documentsObserved: 0, family: 'Community & chat', scope: 'subcollection',
      description: 'A like is represented by one document at communityPosts/{postId}/reactions/{userId}. Its path provides both the post and user identities; absence means not liked. Each post/user pair has at most one reaction.',
      evidence: [...evidence], fields: {createdAt: field('timestamp', 'The only stored reaction field. User/post references in the diagram are derived metadata, not repeated cloud fields.')}},
  };
}
async function api(token, url) {
  const response = await fetch(url, {headers: {Authorization: `Bearer ${token}`}, signal: AbortSignal.timeout(60000)});
  if (!response.ok) throw new Error(`Read-only diagram verification failed (HTTP ${response.status}).`);
  return response.json();
}
async function list(token, collection) {
  const docs = []; let next = '';
  do {
    const url = new URL(`${base}/${collection}`); url.searchParams.set('pageSize', '300');
    if (next) url.searchParams.set('pageToken', next);
    const page = await api(token, url); docs.push(...page.documents || []); next = page.nextPageToken || '';
  } while (next);
  return docs;
}
function collect(node, value) {
  const type = Object.keys(value)[0].replace(/Value$/, '');
  node.types ||= []; if (!node.types.includes(type)) node.types.push(type);
  if (type === 'map') {
    node.fields ||= {};
    for (const [key, child] of Object.entries(value.mapValue.fields || {})) collect(node.fields[key] ||= {evidence: [...evidence]}, child);
  } else if (type === 'array') {
    node.items ||= {evidence: [...evidence]};
    for (const child of value.arrayValue.values || []) collect(node.items, child);
  }
}
function observe(schema, documents) {
  schema.documentsObserved = documents.length;
  for (const definition of Object.values(schema.fields)) definition.present = 0;
  for (const document of documents) for (const [key, value] of Object.entries(document.fields || {})) {
    if (!schema.fields[key]) throw new Error('A noncanonical community field remains; diagram metadata was not refreshed.');
    collect(schema.fields[key], value); schema.fields[key].present++;
  }
  return schema;
}
function endpointExists(schemas, context, name) {
  const [schemaPath, ...segments] = context.split('::');
  let node = schemas[schemaPath];
  if (!node) return false;
  if (!segments.length && ['__documentPath','__documentId','__ownerId'].includes(name)) return true;
  for (const segment of segments) {
    node = node.fields?.[segment]; if (!node) return false;
    if (node.items) node = node.items;
  }
  return !!node.fields?.[name];
}
function communityRelationships() {
  const logical = 'Application-managed logical reference; Firestore does not enforce referential integrity.';
  return [
    {parent: 'users/{userId}', child: POST, parentField: '__documentId', childField: 'authorId', cardinality: '1:M', kind: 'reference', note: logical},
    {parent: 'users/{userId}', child: COMMENT, parentField: '__documentId', childField: 'authorId', cardinality: '1:M', kind: 'reference', note: logical},
    {parent: POST, child: COMMENT, parentField: '__documentId', childField: '__ownerId', cardinality: '1:M', kind: 'path ownership', note: logical},
    {parent: POST, child: REACTION, parentField: '__documentId', childField: '__ownerId', cardinality: '1:M', kind: 'path ownership',
      note: 'The parent post ID is derived from the reaction document path. No postId field is stored in each reaction.'},
    {parent: 'users/{userId}', child: REACTION, parentField: '__documentId', childField: '__documentId', cardinality: '1:M', kind: 'path identity',
      note: 'A reaction document ID is the reacting user ID. A user can react to many posts; each post/user path identifies at most one like. No userId field is stored.'},
    {parent: 'hikeSessions/{sessionId}', child: `${POST}::hike`, parentField: '__documentId', childField: 'sessionId', cardinality: '1:M', kind: 'reference',
      note: 'Optional shared hike association inside the single hike JSON map. The server verifies the session belongs to the author; one active/completed session can be shared in multiple posts. Notes only in the main-layer diagram.'},
    {parent: 'hikeRouteCaptures/{documentId}', child: `${POST}::hike`, parentField: '__documentId', childField: 'sessionId', cardinality: '1:M', kind: 'reference',
      note: 'The full private capture, when available, uses the same session ID. Public posts contain only a compact route preview; there is no repeated routeCaptureId or reverse communityPostId alias. Notes only in the main-layer diagram.'},
    {parent: 'trails/{trailId}', child: `${POST}::trail`, parentField: '__documentId', childField: 'id', cardinality: '1:M', kind: 'reference',
      note: 'Optional catalogue association inside the trail JSON map. Unlisted hikes can use a synthetic trail ID with no trails document. Notes only in the main-layer diagram.'},
    {parent: 'users/{userId}', child: `${POST}::moderation`, parentField: '__documentId', childField: 'adminId', cardinality: '1:M', kind: 'reference',
      note: 'Optional administrator identity inside the moderation JSON map. Notes only in the main-layer diagram.'},
  ];
}
// Match Python json.dumps(sort_keys=True) exactly, including its default
// separators and ASCII escaping, because existing UUID5 relation IDs use it.
function pythonJson(value) {
  if (Array.isArray(value)) return '[' + value.map(pythonJson).join(', ') + ']';
  if (value && typeof value === 'object') return '{' + Object.keys(value).sort().map(key => pythonJson(key) + ': ' + pythonJson(value[key])).join(', ') + '}';
  return JSON.stringify(value).replace(/[^\x00-\x7f]/g, char => '\\u' + char.charCodeAt(0).toString(16).padStart(4, '0'));
}
function relationshipId(edge) {
  const namespace = Buffer.from('6ba7b8119dad11d180b400c04fd430c8', 'hex');
  const bytes = createHash('sha1').update(namespace).update('hikercircle-firestore/relation:' + pythonJson(edge)).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 15) | 80; bytes[8] = (bytes[8] & 63) | 128;
  const text = bytes.toString('hex'); return [text.slice(0,8),text.slice(8,12),text.slice(12,16),text.slice(16,20),text.slice(20)].join('-');
}
function relationIndex(existing, catalogue, relationships) {
  const result = [...existing], byId = new Map(existing.map(row => [row.relationshipId, row.number]));
  const used = new Map(existing.map(row => [row.number, row.relationshipId]));
  const tableName = value => value.split('::')[0].split('/').filter(segment => !segment.startsWith('{')).join('/');
  function add(edge, number) {
    const id = relationshipId(edge);
    if (byId.has(id)) { if (number && byId.get(id) !== number) throw new Error('Existing relation numbering conflicts.'); return; }
    if (number && used.has(number) && used.get(number) !== id) throw new Error('A relationship number would be reused.');
    if (!number) number = 'R' + String(Math.max(180, ...[...used.keys()].map(value => Number(value.slice(1)))) + 1).padStart(3, '0');
    result.push({number, diagram: `${number} | ${tableName(edge.child)} / ${edge.childField}`, relationshipId: id,
      parent: tableName(edge.parent), parentField: edge.parentField, child: tableName(edge.child), childField: edge.childField,
      cardinality: edge.cardinality, description: edge.note});
    byId.set(id, number); used.set(number, id);
  }
  for (const row of catalogue) if (row.source) add(row.source, row.id);
  for (const edge of relationships) add(edge);
  if (used.size !== result.length || byId.size !== result.length) throw new Error('Relation IDs or numbers are not unique.');
  return result.sort((a,b) => Number(a.number.slice(1)) - Number(b.number.slice(1)));
}
function updatedInventory(source, observed) {
  const next = structuredClone(source), replacements = canonicalSchemas();
  for (const [schemaPath, schema] of Object.entries(replacements)) next.schemas[schemaPath] = observe(schema, observed[schemaPath] || []);
  delete next.schemas[RETIRED];
  delete next.schemas['hikeRouteCaptures/{documentId}'].fields.communityPostId;
  next.relationships = next.relationships.filter(edge => endpointExists(next.schemas, edge.parent, edge.parentField)
    && endpointExists(next.schemas, edge.child, edge.childField));
  const known = new Set(next.relationships.map(relationshipId));
  for (const edge of communityRelationships()) if (!known.has(relationshipId(edge))) {next.relationships.push(edge); known.add(relationshipId(edge));}
  next.communityMigrationVerifiedAt = new Date().toISOString();
  return next;
}
function atomicJson(target, value) {
  const temporary = `${target}.community-${randomUUID()}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2), {flag: 'wx'});
  fs.renameSync(temporary, target);
}
async function main() {
  const apply = process.argv.includes('--apply'), token = await firebaseAccessToken();
  const [posts, captures, retired] = await Promise.all(['communityPosts','hikeRouteCaptures','communityCounterEventReceipts'].map(name => list(token, name)));
  const comments = [], reactions = [];
  for (const post of posts) {
    const postId = post.name.split('/').at(-1);
    const [postComments, postReactions] = await Promise.all(['comments','reactions'].map(name => list(token, `communityPosts/${encodeURIComponent(postId)}/${name}`)));
    comments.push(...postComments); reactions.push(...postReactions);
  }
  const legacyPosts = posts.filter(post => !post.fields?.kind || post.fields?.postId || post.fields?.authorPhoneNumber).length;
  const legacyComments = comments.filter(comment => comment.fields?.postId || comment.fields?.commentId || comment.fields?.authorPhoneNumber).length;
  const captureAliases = captures.filter(capture => capture.fields?.communityPostId).length;
  const summary = {projectId, apply, posts: posts.length, comments: comments.length, reactions: reactions.length,
    legacyPosts, legacyComments, captureAliases, retiredCounterReceipts: retired.length};
  if (legacyPosts || legacyComments || captureAliases || retired.length) {
    console.log(JSON.stringify({...summary, ready: false}));
    if (apply) throw new Error('Cloud migration is incomplete; diagram metadata was not changed.');
    return;
  }
  const sourcePath = path.join(root, 'output/firestore/hikercircle-firestore-schema.json');
  const source = JSON.parse(fs.readFileSync(sourcePath, 'utf8'));
  const next = updatedInventory(source, {[POST]: posts, [COMMENT]: comments, [REACTION]: reactions});
  next.firestoreIndexConfiguration = JSON.parse(fs.readFileSync(path.join(root, 'firestore.indexes.json'), 'utf8'));
  const indexPath = path.join(root, 'output/firestore/relationship-index.json');
  const catalogue = JSON.parse(fs.readFileSync(path.join(root, 'output/dbdiagram/firestore/relationship-catalogue.json'), 'utf8'));
  const oldIndex = JSON.parse(fs.readFileSync(indexPath, 'utf8'));
  const index = relationIndex(oldIndex, catalogue, next.relationships);
  const report = {...summary, ready: true, documentShapes: Object.keys(next.schemas).length,
    relationships: next.relationships.length, storedTopLevelFields: Object.values(next.schemas).reduce((count, schema) => count + Object.keys(schema.fields).length, 0),
    indexedRelationshipNumbers: index.length, verifiedAt: next.communityMigrationVerifiedAt};
  if (apply) {
    atomicJson(sourcePath + '.before-community.json', source);
    atomicJson(indexPath + '.before-community.json', oldIndex);
    atomicJson(indexPath, index); atomicJson(sourcePath, next);
    atomicJson(path.join(root, 'output/firestore/community-migration-verification.json'), report);
  }
  console.log(JSON.stringify(report));
}
if (require.main === module) main().catch(error => {console.error(error.message); process.exitCode = 1;});
module.exports = {POST, COMMENT, REACTION, canonicalSchemas, updatedInventory, relationshipId, relationIndex, pythonJson};

#!/usr/bin/env node
'use strict';

// Prepare the Firebase Hosting website without deleting Flutter build artifacts.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const source = path.join(root, 'web');
const destination = path.join(root, 'build', 'web');
const args = new Set(process.argv.slice(2));
const acceptedArgs = new Set(['--check', '--strict', '--strict-captures', '--help']);
for (const arg of args) {
  if (!acceptedArgs.has(arg)) throw new Error(`Unknown argument: ${arg}`);
}
if (args.has('--help')) {
  console.log('node tool/prepare_website.cjs [--check] [--strict] [--strict-captures]');
  console.log('Validates displayed local assets, then overlays web/ onto build/web/.');
  console.log('--check: validate only; --strict: explicit default asset validation.');
  console.log('--strict-captures: also fail while any showcase capture is pending.');
  process.exit(0);
}

function walk(directory) {
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) throw new Error(`Symbolic links are not supported: ${file}`);
    return entry.isDirectory() ? walk(file) : [file];
  });
}

function localAsset(url) {
  if (typeof url !== 'string' || !url.startsWith('/')) return null;
  const pathname = decodeURIComponent(url.split(/[?#]/, 1)[0]);
  if (!/\.(?:png|jpe?g|webp|gif|svg|ico|mp4|webm|ttf|woff2?|css|js|json)$/i.test(pathname)) return null;
  if (pathname.startsWith('/internal/app-showcase/')) {
    return path.join(source, 'internal-showcase', pathname.slice('/internal/app-showcase/'.length));
  }
  return path.join(source, pathname.slice(1));
}

const errors = [];
const references = new Map();
const mediaExtensions = /\.(?:png|jpe?g|webp|gif|svg|ico|mp4|webm|ttf|woff2?)$/i;
const sourceFiles = walk(source);
function outputName(file) {
  const name = path.relative(source, file).replaceAll(path.sep, '/');
  if (['index.html', 'get-app.html', 'privacy-policy.html', 'live-location.html', 'manifest.json', 'favicon.png'].includes(name)) return name;
  if (['.well-known/apple-app-site-association', '.well-known/assetlinks.json'].includes(name)) return name;
  if (/^(?:site-assets|privacy-assets|icons)\//.test(name) && mediaExtensions.test(name)) return name;
  if (name.startsWith('site/') && (/\.(?:css|js)$/i.test(name) || mediaExtensions.test(name) || name === 'site/beta-release.json')) return name;
  if (/^internal-showcase\/(?:index\.html|showcase\.(?:css|js)|catalog\.json)$/.test(name)) {
    return name.replace('internal-showcase/', 'internal/app-showcase/');
  }
  if (name.startsWith('internal-showcase/media/') && /\.(?:png|jpe?g|webp|mp4|webm)$/i.test(name)
      && [...references.values()].includes(file)) {
    return name.replace('internal-showcase/', 'internal/app-showcase/');
  }
  return null;
}
// Match the mobile allowlist: only the public Mapbox token enters this JSON.
let mapboxToken = process.env.MAPBOX_ACCESS_TOKEN;
if (mapboxToken === undefined) {
  const publicConfig = path.join(root, '.env.public');
  const match = fs.existsSync(publicConfig)
    ? fs.readFileSync(publicConfig, 'utf8').match(/^MAPBOX_ACCESS_TOKEN=(.*)$/m) : null;
  mapboxToken = match ? match[1].trim().replace(/^(["'])(.*)\1$/, '$2') : '';
}
mapboxToken = mapboxToken.trim();
if (mapboxToken && (!mapboxToken.startsWith('pk.') || /\s/.test(mapboxToken))) {
  throw new Error('MAPBOX_ACCESS_TOKEN must be a public pk token.');
}
const generated = new Map([['/map-config.json', JSON.stringify({ mapboxAccessToken: mapboxToken }) + '\n']]);
function inspectReference(url, owner) {
  const file = localAsset(url);
  if (!file) return;
  const relative = path.relative(source, file);
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    errors.push(`${owner}: asset escapes web/: ${url}`);
    return;
  }
  references.set(url.split(/[?#]/, 1)[0], file);
  if (generated.has(url.split(/[?#]/, 1)[0])) return;
  if (!fs.existsSync(file) || !fs.statSync(file).isFile() || fs.statSync(file).size === 0) {
    errors.push(`${owner}: missing or empty ${url}`);
  }
}

// Inspect actual root-relative resource literals, including Evolution media in JS.
for (const file of sourceFiles) {
  if (!/\.(?:html|css|js)$/i.test(file)) continue;
  const owner = path.relative(root, file).replaceAll(path.sep, '/');
  const text = fs.readFileSync(file, 'utf8');
  if (file.endsWith('.js')) {
    try { new vm.Script(text, { filename: owner }); }
    catch (error) { errors.push(`${owner}: ${error.message}`); }
  }
  for (const match of text.matchAll(/["'`](\/[^"'`\s<>]+)["'`]/g)) inspectReference(match[1], owner);
  // CSS also permits relative, unquoted URLs.
  for (const match of text.matchAll(/url\(\s*["']?(\.\.?\/[^\s"')]+)["']?\s*\)/g)) {
    const relativeUrl = '/' + path.relative(source, path.resolve(path.dirname(file), match[1])).replaceAll(path.sep, '/');
    inspectReference(relativeUrl, owner);
  }
}

const catalogFile = path.join(source, 'internal-showcase', 'catalog.json');
const catalog = JSON.parse(fs.readFileSync(catalogFile, 'utf8'));
if (!Array.isArray(catalog.items) || !Array.isArray(catalog.chapters)) {
  throw new Error('Showcase catalog must contain items and chapters arrays.');
}
const ids = new Set();
const chapterIds = new Set(catalog.chapters.map((chapter) => chapter.id));
const pending = [];
const incompletePlans = [];
let deviceItems = 0;
let archivedReferences = 0;
function linkedMedia(item) {
  return [item.image, item.video, item.poster,
    ...(item.images || []).map((entry) => entry.src),
    ...(item.videos || []).flatMap((entry) => [entry.src, entry.poster])].filter(Boolean);
}
for (const item of catalog.items) {
  if (!item.id || ids.has(item.id)) errors.push(`catalog: missing or duplicate feature ID ${item.id}`);
  ids.add(item.id);
  if (!chapterIds.has(item.chapter)) errors.push(`catalog: unknown chapter for ${item.id}`);
  if (!Array.isArray(item.points) || !item.capturePlan) errors.push(`catalog: incomplete feature ${item.id}`);
  if (item.source === 'archive') {
    archivedReferences += 1;
    const media = linkedMedia(item);
    if (!item.captureMeta?.archive || !media.length) errors.push(`catalog: incomplete archive provenance for ${item.id}`);
    for (const url of media) {
      if (url !== '/site-assets/evolution/01-foundation-first-sos-iphone.png') {
        errors.push(`catalog: archive reference is not the approved Foundation original: ${url}`);
      }
      inspectReference(url, `catalog:${item.id}`);
    }
    const planned = [
      ...(item.capturePlan?.screenshots || []).map((shot) => shot.file),
      ...(item.capturePlan?.recording ? [item.capturePlan.recording.file] : []),
    ];
    if (planned.length) incompletePlans.push({ id: item.id, files: planned });
    continue;
  }
  if (item.source !== 'device') {
    pending.push(item.id);
    incompletePlans.push({ id: item.id, files: [
      ...(item.capturePlan?.screenshots || []).map((shot) => shot.file),
      ...(item.capturePlan?.recording ? [item.capturePlan.recording.file] : []),
    ] });
    continue;
  }
  deviceItems += 1;
  const media = linkedMedia(item);
  if (!media.length) errors.push(`catalog: device feature ${item.id} has no media`);
  for (const url of media) {
    if (!url.startsWith('/internal/app-showcase/media/')) {
      errors.push(`catalog: ${item.id} media must be a dedicated showcase capture: ${url}`);
    }
    inspectReference(url, `catalog:${item.id}`);
  }
  const wiredNames = new Set(media.filter((url) => {
    const file = localAsset(url);
    return file && fs.existsSync(file) && fs.statSync(file).isFile() && fs.statSync(file).size > 0;
  }).map((url) => path.posix.basename(url.split(/[?#]/, 1)[0])));
  const remaining = [
    ...(item.capturePlan?.screenshots || []).map((shot) => shot.file),
    ...(item.capturePlan?.recording ? [item.capturePlan.recording.file] : []),
  ].filter((name) => {
    const actualName = item.captureCoverage?.aliases?.[name] || name;
    const explicit = item.captureCoverage?.fulfilledFiles;
    return typeof actualName !== 'string' || /[\\/]/.test(actualName)
      || !wiredNames.has(actualName) || (Array.isArray(explicit) && !explicit.includes(name));
  });
  if (remaining.length) incompletePlans.push({ id: item.id, files: remaining });
}
if (args.has('--strict-captures') && incompletePlans.length) {
  errors.push(`Showcase has ${incompletePlans.length} incomplete capture plans:\n` + incompletePlans
    .map((item) => `${item.id}: ${item.files.join(', ') || 'review capture plan'}`).join('\n'));
}
const publishFiles = new Map(sourceFiles.map((file) => [outputName(file), file]).filter(([name]) => name));
for (const [url, file] of references) {
  if (!generated.has(url) && !outputName(file)) errors.push(`Asset is not approved for website publication: ${url}`);
}
if (errors.length) {
  console.error([...new Set(errors)].join('\n'));
  console.error('Website preparation stopped. No output files were changed.');
  process.exit(1);
}

if (!args.has('--check')) {
  for (const directory of [path.join(root, 'build'), destination]) {
    if (fs.existsSync(directory) && fs.lstatSync(directory).isSymbolicLink()) {
      throw new Error('Website output must not be a symbolic link.');
    }
  }
  // Remove stale files only from these website-owned directories. This also
  // removes source-only capture logs left by an earlier broad directory copy.
  const managed = ['site', 'site-assets', 'privacy-assets', 'icons', 'internal/app-showcase', 'internal-showcase'];
  function safeTarget(name) {
    const target = path.resolve(destination, name);
    if (!target.startsWith(destination + path.sep)) throw new Error('Unsafe website output target.');
    let current = destination;
    for (const part of path.relative(destination, target).split(path.sep)) {
      current = path.join(current, part);
      if (fs.existsSync(current) && fs.lstatSync(current).isSymbolicLink()) {
        throw new Error('Website output contains a symbolic link.');
      }
    }
    return target;
  }
  // Check output paths before either cleanup or copying, including junctions.
  for (const name of [...managed, ...publishFiles.keys(), ...[...generated.keys()].map((url) => url.slice(1))]) safeTarget(name);
  fs.mkdirSync(destination, { recursive: true });
  for (const directory of managed) {
    const target = safeTarget(directory);
    for (const file of walk(target)) {
      const name = path.relative(destination, file).replaceAll(path.sep, '/');
      if (!publishFiles.has(name)) fs.rmSync(file);
    }
  }
  for (const [name, file] of publishFiles) {
    const target = safeTarget(name);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.copyFileSync(file, target);
  }
  for (const [url, content] of generated) fs.writeFileSync(path.join(destination, url.slice(1)), content);
}
console.log(JSON.stringify({
  mode: args.has('--check') ? 'checked' : 'prepared',
  output: path.relative(root, destination).replaceAll(path.sep, '/'),
  displayedAssets: references.size,
  sourceFilesPublished: publishFiles.size,
  mapboxConfigured: Boolean(mapboxToken),
  showcaseFeatures: catalog.items.length,
  featuresWithDeviceMedia: deviceItems,
  archivedReferences,
  featuresAwaitingCapture: pending.length,
  incompleteCapturePlans: incompletePlans.length,
  captureFilesRemaining: incompletePlans.reduce((total, item) => total + item.files.length, 0),
}, null, 2));

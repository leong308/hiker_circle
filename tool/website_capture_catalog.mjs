#!/usr/bin/env node
// Inventory real capture files without treating requested or legacy media as new captures.
import { existsSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { basename, dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const writeIndex = args.indexOf('--write');
if (writeIndex >= 0 && (!args[writeIndex + 1] || args[writeIndex + 1].startsWith('--'))) {
  throw new Error('--write requires an output JSON path.');
}
const catalog = JSON.parse(readFileSync(join(root, 'web/internal-showcase/catalog.json'), 'utf8'));
const portable = (path) => relative(root, path).replaceAll('\\', '/');
const unique = (values) => [...new Set(values)];

function inspectFile(path) {
  return existsSync(path) && statSync(path).isFile()
    ? { path: portable(path), bytes: statSync(path).size }
    : null;
}

function inspectUrl(url) {
  const pathname = url.split(/[?#]/, 1)[0];
  if (!pathname.startsWith('/') || pathname.includes('..')) {
    return { url, status: 'invalid', reason: 'Expected an absolute website asset path.' };
  }
  const local = pathname.startsWith('/internal/app-showcase/')
    ? join(root, 'web/internal-showcase', pathname.slice('/internal/app-showcase/'.length))
    : join(root, 'web', pathname.slice(1));
  const durable = inspectFile(local);
  const built = inspectFile(join(root, 'build/web', pathname.slice(1)));
  return {
    url,
    status: durable ? 'available-in-source' : built ? 'build-only' : 'missing',
    expectedSourcePath: portable(local),
    ...(durable ? { source: durable } : {}),
    ...(built ? { build: built } : {}),
    ...(!durable ? { reason: built
      ? 'Only the build output contains this file; no durable source capture is present.'
      : 'The referenced media file is absent from source and build output.' } : {}),
  };
}

function linkedMedia(item) {
  return unique([
    item.image,
    item.video,
    item.poster,
    ...(item.images || []).map((entry) => entry.src),
    ...(item.videos || []).flatMap((entry) => [entry.src, entry.poster]),
  ].filter((url) => typeof url === 'string')).map(inspectUrl);
}

function requestedCapture(file, kind, details) {
  // A basename from the plan is resolved only in the dedicated source media folder.
  if (!file || file.includes('/') || file.includes('\\') || file.includes('..')) {
    throw new Error(`Invalid capture filename in catalog: ${file}`);
  }
  const path = join(root, 'web/internal-showcase/media', file);
  const source = inspectFile(path);
  return {
    file,
    kind,
    status: source ? 'file-present' : 'pending',
    path: portable(path),
    ...(source ? { bytes: source.bytes } : { reason: 'The requested capture file has not been added to website source.' }),
    ...details,
  };
}

const items = catalog.items.map((item) => {
  const plan = item.capturePlan || { screenshots: [] };
  const requests = [
    ...(plan.screenshots || []).map((shot) => requestedCapture(shot.file, 'image', { show: shot.show })),
    ...(plan.recording ? [requestedCapture(plan.recording.file, 'video', {
      duration: plan.recording.duration,
      steps: plan.recording.steps,
    })] : []),
  ];
  const media = linkedMedia(item);
  for (const capture of requests) {
    const availability = item.captureAvailability?.files?.[capture.file];
    if (availability && capture.status === 'pending') Object.assign(capture, availability);
  }
  const wiredFiles = new Set(media.filter((asset) => asset.status === 'available-in-source')
    .map((asset) => basename(asset.url.split(/[?#]/, 1)[0])));
  const explicitlyFulfilled = item.captureCoverage?.fulfilledFiles;
  const aliases = item.captureCoverage?.aliases || {};
  const fulfilledFiles = new Set(requests.filter((capture) => {
    const actualFile = aliases[capture.file] || capture.file;
    if (typeof actualFile !== 'string' || actualFile.includes('/') || actualFile.includes('\\')) return false;
    const fulfilled = wiredFiles.has(actualFile)
      && (!Array.isArray(explicitlyFulfilled) || explicitlyFulfilled.includes(capture.file));
    if (fulfilled && actualFile !== capture.file) {
      capture.status = 'accepted-alias';
      capture.satisfiedBy = actualFile;
      capture.sourcePath = `web/internal-showcase/media/${actualFile}`;
      delete capture.reason;
    }
    return fulfilled;
  }).map((capture) => capture.file));
  const remainingRequests = requests.filter((capture) => !fulfilledFiles.has(capture.file));
  return {
    id: item.id,
    chapter: item.chapter,
    title: item.title,
    catalogSource: item.source,
    status: media.length && media.every((asset) => asset.status === 'available-in-source')
      ? item.source === 'archive' ? 'archived-reference' : 'wired-to-source'
      : media.some((asset) => asset.status === 'missing' || asset.status === 'invalid')
        ? 'missing-linked-media'
        : 'capture-pending',
    ...(plan.setup ? { setup: plan.setup } : {}),
    ...(item.notes ? { notes: item.notes } : {}),
    ...(item.capturedAt ? { capturedAt: item.capturedAt } : {}),
    ...(item.captureBuild ? { captureBuild: item.captureBuild } : {}),
    ...(item.captureMeta ? { captureMeta: item.captureMeta } : {}),
    ...(item.captureAvailability ? { captureAvailability: item.captureAvailability } : {}),
    ...(item.archiveAttribution ? { archiveAttribution: item.archiveAttribution } : {}),
    coverage: {
      status: item.source === 'archive' && media.length ? 'historical-reference'
        : remainingRequests.length === 0 && requests.length > 0 ? 'complete'
        : remainingRequests.length < requests.length ? 'partial'
          : media.some((asset) => asset.status === 'available-in-source') ? 'supplementary-only' : 'pending',
      plannedCaptures: requests.length,
      wiredCaptures: requests.length - remainingRequests.length,
      remainingFiles: remainingRequests.map((capture) => capture.file),
      ...(item.captureCoverage?.note ? { note: item.captureCoverage.note } : {}),
    },
    requests,
    linkedMedia: media,
  };
});

const publicSources = ['web/index.html', 'web/get-app.html', 'web/site/app.js'];
const publicUrls = unique(publicSources.flatMap((path) =>
  [...readFileSync(join(root, path), 'utf8').matchAll(/\/site-assets\/[^\s"'<>`)]+/g)].map((match) => match[0])));
const publicMedia = publicUrls.map(inspectUrl);
const requests = items.flatMap((item) => item.requests);
const linked = [...items.flatMap((item) => item.linkedMedia), ...publicMedia];
const manifest = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  catalogUpdated: catalog.updated,
  sourceRoot: '.',
  mediaSourceDirectory: 'web/internal-showcase/media',
  deploymentMediaDirectory: 'build/web/internal/app-showcase/media',
  statusMeaning: {
    'wired-to-source': 'All currently linked media exists in durable website source. Review capture date and build separately.',
    'archived-reference': 'An explicitly labelled historical source image is preserved; it is not a new/current capture.',
    'capture-pending': 'The catalog has not been wired to complete durable capture media.',
    'missing-linked-media': 'At least one currently linked media file is absent or invalid.',
    'file-present': 'The requested basename exists; this alone does not verify its content or freshness.',
    'accepted-alias': 'The reviewed capture is wired under an explicitly accepted alternative filename.',
    unavailable: 'Capture is intentionally blocked; the protection remains in place.',
    'not-attempted': 'A dependent screen was not attempted after the protected entry screen blocked capture.',
    pending: 'The requested basename does not exist in durable source.',
    'build-only': 'A legacy or uncatalogued asset exists only in generated build output.',
  },
  summary: {
    features: items.length,
    wiredFeatures: items.filter((item) => item.status === 'wired-to-source').length,
    archivedReferences: items.filter((item) => item.status === 'archived-reference').length,
    completedCapturePlans: items.filter((item) => item.coverage.status === 'complete').length,
    partiallyWiredPlans: items.filter((item) => item.coverage.status === 'partial').length,
    featuresWithSupplementaryMedia: items.filter((item) => item.coverage.status === 'supplementary-only').length,
    missingLinkedFeatures: items.filter((item) => item.status === 'missing-linked-media').length,
    requestedScreenshots: requests.filter((capture) => capture.kind === 'image').length,
    requestedRecordings: requests.filter((capture) => capture.kind === 'video').length,
    pendingCaptures: items.reduce((total, item) => total + item.coverage.remainingFiles.length, 0),
    missingCaptureFiles: requests.filter((capture) => ['pending', 'unavailable', 'not-attempted'].includes(capture.status)).length,
    unavailableCaptures: requests.filter((capture) => capture.status === 'unavailable').length,
    notAttemptedCaptures: requests.filter((capture) => capture.status === 'not-attempted').length,
    missingLinkedAssets: unique(linked.filter((asset) => asset.status === 'missing' || asset.status === 'invalid').map((asset) => asset.url)).length,
    buildOnlyAssets: unique(linked.filter((asset) => asset.status === 'build-only').map((asset) => asset.url)).length,
  },
  items,
  publicMedia,
};

if (writeIndex >= 0) {
  const output = isAbsolute(args[writeIndex + 1]) ? args[writeIndex + 1] : join(root, args[writeIndex + 1]);
  writeFileSync(output, JSON.stringify(manifest, null, 2) + '\n');
  console.log(JSON.stringify({ output: portable(output), ...manifest.summary }));
} else {
  console.log(JSON.stringify(manifest, null, 2));
}
if (args.includes('--check') && manifest.summary.missingLinkedAssets > 0) process.exitCode = 1;
if (args.includes('--check-complete') && (manifest.summary.pendingCaptures > 0 || items.some((item) => !['wired-to-source', 'archived-reference'].includes(item.status)))) {
  process.exitCode = 1;
}

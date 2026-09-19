const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const pageRoot = path.join(root, 'web/internal-showcase');
const catalog = JSON.parse(fs.readFileSync(path.join(pageRoot, 'catalog.json'), 'utf8'));
const chapters = new Set(catalog.chapters.map((chapter) => chapter.id));
const ids = new Set();
let assets = 0;
for (const item of catalog.items) {
  assert(!ids.has(item.id), `Duplicate feature: ${item.id}`);
  ids.add(item.id);
  assert(chapters.has(item.chapter), `Unknown chapter: ${item.id}`);
  assert(item.title && item.description && item.capture && item.captureFile, `Incomplete feature: ${item.id}`);
  assert(item.description.split(/\s+/).length <= 20, `Description too long: ${item.id}`);
  assert(item.flow.length >= 3 && item.flow.length <= 6, `Invalid flow: ${item.id}`);
  assert(['device', 'preview', 'needed'].includes(item.source), `Invalid source: ${item.id}`);
  assert(item.source !== 'needed' || (!item.image && !item.video), `Capture-needed feature already has media: ${item.id}`);
  for (const asset of [item.image, item.video, ...(item.images || []).map((image) => image.src)].filter(Boolean)) {
    assert(asset.startsWith('/site-assets/') || asset.startsWith('/internal/app-showcase/media/'), `Unexpected asset URL: ${asset}`);
    const local = asset.startsWith('/internal/app-showcase/')
      ? path.join(pageRoot, asset.slice('/internal/app-showcase/'.length))
      : path.join(root, 'web', asset);
    assert(fs.existsSync(local), `Missing asset: ${asset}`);
    assets++;
  }
}
const html = fs.readFileSync(path.join(pageRoot, 'index.html'), 'utf8');
assert(html.includes('noindex, nofollow, noarchive, nosnippet'), 'Missing noindex meta');
assert(!fs.readFileSync(path.join(root, 'web/index.html'), 'utf8').includes('/internal/app-showcase'), 'Public navigation exposes internal page');
const config = JSON.parse(fs.readFileSync(path.join(root, 'firebase.json'), 'utf8'));
assert(config.hosting.headers.some((rule) => rule.source === '/internal/app-showcase{,/**}' && rule.headers.some((header) => header.key === 'X-Robots-Tag' && header.value.includes('noindex'))), 'Missing hosting noindex header');
assert(fs.existsSync(path.join(pageRoot, 'capture-guide.md')), 'Capture guide is not staged');
console.log(`Validated ${ids.size} feature flows, ${chapters.size} chapters and ${assets} media references.`);

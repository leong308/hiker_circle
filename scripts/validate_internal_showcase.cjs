const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const pageRoot = path.join(root, 'web/internal-showcase');
const catalog = JSON.parse(fs.readFileSync(path.join(pageRoot, 'catalog.json'), 'utf8'));
const chapters = new Set(catalog.chapters.map((chapter) => chapter.id));
const ids = new Set();
let assets = 0;
let screenshots = 0;
let recordings = 0;
const captureFiles = new Set();
assert.equal(catalog.mediaPolicy, 'fresh-captures-only', 'Internal showcase requires fresh captures');
for (const item of catalog.items) {
  assert(!ids.has(item.id), `Duplicate feature: ${item.id}`);
  ids.add(item.id);
  assert(chapters.has(item.chapter), `Unknown chapter: ${item.id}`);
  assert(item.title && item.description && item.capture && item.captureFile, `Incomplete feature: ${item.id}`);
  assert(item.description.split(/\s+/).length <= 20, `Description too long: ${item.id}`);
  assert(item.flow.length >= 3 && item.flow.length <= 6, `Invalid flow: ${item.id}`);
  assert(['device', 'needed'].includes(item.source), `Invalid source: ${item.id}`);
  assert(Array.isArray(item.points) && item.points.length >= 2 && item.points.length <= 4, `Invalid feature points: ${item.id}`);
  for (const point of item.points) {
    assert(point.label && point.detail, `Incomplete feature point: ${item.id}`);
    assert(point.label.split(/\s+/).length <= 6, `Point label too long: ${item.id}`);
  }
  const plan = item.capturePlan;
  assert(plan && Array.isArray(plan.screenshots), `Missing capture plan: ${item.id}`);
  assert(plan.screenshots.length > 0 || plan.recording, `Capture plan has no media: ${item.id}`);
  const declared = [];
  for (const shot of plan.screenshots) {
    assert(shot.show && /^[a-z0-9-]+\.png$/.test(shot.file), `Invalid screenshot brief: ${item.id}`);
    declared.push(shot.file);
    screenshots++;
  }
  if (plan.recording) {
    const clip = plan.recording;
    assert(/^[a-z0-9-]+\.mp4$/.test(clip.file) && clip.duration, `Invalid recording brief: ${item.id}`);
    assert(Array.isArray(clip.steps) && clip.steps.length >= 3 && clip.steps.length <= 5 && clip.steps.every((step) => typeof step === 'string' && step.trim()), `Invalid recording steps: ${item.id}`);
    declared.push(clip.file);
    recordings++;
  }
  for (const filename of declared) {
    assert(!captureFiles.has(filename), `Duplicate capture filename: ${filename}`);
    captureFiles.add(filename);
  }
  assert(declared.includes(item.captureFile), `Primary capture file not in plan: ${item.id}`);
  assert(item.source !== 'needed' || (!item.image && !item.video && !(item.images || []).length), `Capture-needed feature already has media: ${item.id}`);
  for (const asset of [item.image, item.video, ...(item.images || []).map((image) => image.src)].filter(Boolean)) {
    assert(asset.startsWith('/internal/app-showcase/media/'), `Only fresh internal captures are allowed: ${asset}`);
    const local = path.join(pageRoot, asset.slice('/internal/app-showcase/'.length));
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
console.log(`Validated ${ids.size} features, ${chapters.size} chapters, ${screenshots} screenshot briefs, ${recordings} recording briefs and ${assets} wired media files.`);

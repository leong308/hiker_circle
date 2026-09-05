const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const targetDirectory = path.join(projectRoot, 'build', 'web');
// Publish only the public Mapbox token used by browser maps.
const envPath = path.join(projectRoot, '.env');
const envText = fs.existsSync(envPath) ? fs.readFileSync(envPath, 'utf8') : '';
const envMatch = envText.match(/^MAPBOX_ACCESS_TOKEN\s*=\s*([^\r\n]*)/m);
const mapboxToken = (process.env.MAPBOX_ACCESS_TOKEN || envMatch?.[1] || '')
  .trim().replace(/^['"]|['"]$/g, '');
if (mapboxToken && !mapboxToken.startsWith('pk.')) {
  throw new Error('Browser maps require a public Mapbox token. Refusing to publish a secret token.');
}
fs.mkdirSync(targetDirectory, { recursive: true });
fs.writeFileSync(path.join(targetDirectory, 'map-config.json'),
  JSON.stringify({ mapboxAccessToken: mapboxToken }));
const entries = [
  {
    source: ['assets', 'icons', 'HikerCircle-Loader-Transparent.png'],
    target: ['favicon.png'],
  },
  { source: ['web', 'index.html'], target: ['index.html'] },
  { source: ['web', 'site'], target: ['site'] },
  { source: ['web', 'live-location.html'], target: ['live-location.html'] },
  { source: ['web', 'privacy-policy.html'], target: ['privacy-policy.html'] },
  {
    source: ['web', 'site-assets', 'hiker-circle-hero.jpg'],
    target: ['site-assets', 'hiker-circle-hero.jpg'],
  },
  {
    source: ['web', 'site-assets', 'screens'],
    target: ['site-assets', 'screens'],
  },
  {
    source: ['web', 'site-assets', 'evolution'],
    target: ['site-assets', 'evolution'],
  },
  {
    source: ['assets', 'icons', 'AppIcon-Default-1024.png'],
    target: ['privacy-assets', 'app-icon.png'],
  },
  {
    source: ['assets', 'fonts', 'InterVariable.ttf'],
    target: ['privacy-assets', 'InterVariable.ttf'],
  },
  {
    source: ['web', '.well-known', 'assetlinks.json'],
    target: ['.well-known', 'assetlinks.json'],
  },
  {
    source: ['web', '.well-known', 'apple-app-site-association'],
    target: ['.well-known', 'apple-app-site-association'],
  },
];

for (const entry of entries) {
  const source = path.join(projectRoot, ...entry.source);
  const target = path.join(targetDirectory, ...entry.target);
  if (!fs.existsSync(source)) {
    throw new Error(`Missing hosting file: ${source}`);
  }

  fs.mkdirSync(path.dirname(target), { recursive: true });
  if (fs.statSync(source).isDirectory()) {
    fs.cpSync(source, target, { recursive: true });
  } else {
    fs.copyFileSync(source, target);
  }

  console.log(`Copied ${source} -> ${target}`);
}

const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const targetDirectory = path.join(projectRoot, 'build', 'web');
fs.mkdirSync(targetDirectory, { recursive: true });
const files = [
  ['live-location.html'],
  ['.well-known', 'assetlinks.json'],
  ['.well-known', 'apple-app-site-association'],
];

for (const segments of files) {
  const source = path.join(projectRoot, 'web', ...segments);
  const target = path.join(targetDirectory, ...segments);
  if (!fs.existsSync(source)) {
    throw new Error(`Missing hosting file: ${source}`);
  }
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.copyFileSync(source, target);
  console.log(`Copied ${source} -> ${target}`);
}

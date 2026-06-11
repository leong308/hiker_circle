const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const source = path.join(projectRoot, 'web', 'live-location.html');
const targetDirectory = path.join(projectRoot, 'build', 'web');
const target = path.join(targetDirectory, 'live-location.html');

if (!fs.existsSync(source)) {
  throw new Error(`Missing live location page: ${source}`);
}

fs.mkdirSync(targetDirectory, { recursive: true });
fs.copyFileSync(source, target);
console.log(`Copied ${source} -> ${target}`);

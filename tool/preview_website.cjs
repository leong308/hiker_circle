#!/usr/bin/env node
'use strict';

// Local-only preview of the prepared Firebase Hosting output.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..', 'build', 'web');
const args = process.argv.slice(2);
let port = 4173;
let proxyStats = false;
for (let index = 0; index < args.length; index += 1) {
  if (args[index] === '--port') port = Number(args[++index]);
  else if (args[index] === '--proxy-stats') proxyStats = true;
  else if (args[index] === '--help') {
    console.log('node tool/preview_website.cjs [--port 4173] [--proxy-stats]');
    process.exit(0);
  } else throw new Error(`Unknown argument: ${args[index]}`);
}
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Use a port from 1024 to 65535.');
if (!fs.existsSync(path.join(root, 'index.html'))) throw new Error('Prepare the website before starting its preview.');
const realRoot = fs.realpathSync(root);
const aliases = new Map([
  ['/get-app', '/get-app.html'], ['/privacy', '/privacy-policy.html'],
  ['/privacy-policy', '/privacy-policy.html'], ['/live-location', '/live-location.html'],
  ['/internal/app-showcase', '/internal/app-showcase/index.html'],
]);
const types = new Map(Object.entries({
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp',
  '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.gif': 'image/gif',
  '.mp4': 'video/mp4', '.webm': 'video/webm', '.ttf': 'font/ttf',
  '.woff': 'font/woff', '.woff2': 'font/woff2',
}));
function send(response, status, message) {
  response.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8' });
  response.end(message);
}
const server = http.createServer(async (request, response) => {
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('Referrer-Policy', 'no-referrer');
  if (!['GET', 'HEAD'].includes(request.method)) {
    response.setHeader('Allow', 'GET, HEAD');
    send(response, 405, 'Method not allowed');
    return;
  }
  let url;
  let pathname;
  try {
    url = new URL(request.url, 'http://127.0.0.1');
    pathname = decodeURIComponent(url.pathname);
  } catch { send(response, 400, 'Invalid path'); return; }
  if (pathname === '/api/public-stats') {
    if (!proxyStats) {
      response.writeHead(503, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ error: 'Public stats proxy disabled for local preview.' }));
      return;
    }
    try {
      const upstream = await fetch('https://hiker-circle.web.app/api/public-stats' + url.search,
        { headers: { Accept: 'application/json' }, redirect: 'error', signal: AbortSignal.timeout(10000) });
      if (!upstream.headers.get('content-type')?.includes('application/json')) throw new Error('Unexpected stats response');
      const body = await upstream.text();
      if (body.length > 1024 * 1024) throw new Error('Stats response too large');
      response.writeHead(upstream.status, { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': Buffer.byteLength(body) });
      response.end(request.method === 'HEAD' ? undefined : body);
    } catch { send(response, 502, 'Public stats unavailable'); }
    return;
  }
  const segments = pathname.split('/');
  if (/[\\\0:]/.test(pathname) || segments.some((part) => part === '..' || (part.startsWith('.') && part !== '.well-known'))
      || segments.some((part) => /^capture-(?:log|manifest|guide|status)\./i.test(part))
      || pathname.startsWith('/internal-showcase')) {
    send(response, 404, 'Not found'); return;
  }
  pathname = aliases.get(pathname) || pathname;
  if (pathname.endsWith('/')) pathname += 'index.html';
  const file = path.resolve(root, '.' + pathname);
  if (!file.startsWith(root + path.sep)) { send(response, 404, 'Not found'); return; }
  let stat;
  try {
    if (!fs.realpathSync(file).startsWith(realRoot + path.sep)) throw new Error('Outside preview');
    stat = fs.statSync(file);
    if (!stat.isFile()) throw new Error('Not a file');
  } catch { send(response, 404, 'Not found'); return; }
  if (pathname.startsWith('/internal/app-showcase/')) response.setHeader('X-Robots-Tag', 'noindex, nofollow, noarchive, nosnippet');
  response.setHeader('Content-Type', types.get(path.extname(file).toLowerCase()) || 'application/octet-stream');
  response.setHeader('Accept-Ranges', 'bytes');
  let start = 0;
  let end = stat.size - 1;
  let status = 200;
  if (request.headers.range) {
    const range = /^bytes=(\d*)-(\d*)$/.exec(request.headers.range);
    if (range && (range[1] || range[2])) {
      start = range[1] ? Number(range[1]) : Math.max(0, stat.size - Number(range[2]));
      end = range[1] && range[2] ? Math.min(Number(range[2]), end) : end;
    }
    if (!range || (!range[1] && !range[2]) || !Number.isSafeInteger(start) || !Number.isSafeInteger(end)
        || start < 0 || start > end || start >= stat.size) {
      response.setHeader('Content-Range', `bytes */${stat.size}`);
      send(response, 416, 'Invalid range'); return;
    }
    response.setHeader('Content-Range', `bytes ${start}-${end}/${stat.size}`);
    status = 206;
  }
  response.setHeader('Content-Length', Math.max(0, end - start + 1));
  response.writeHead(status);
  if (request.method === 'HEAD' || stat.size === 0) { response.end(); return; }
  const stream = fs.createReadStream(file, { start, end });
  stream.on('error', () => response.destroy());
  response.on('close', () => stream.destroy());
  stream.pipe(response);
});
server.on('error', (error) => { console.error(error.message); process.exitCode = 1; });
server.listen(port, '127.0.0.1', () => console.log(`Local: http://127.0.0.1:${port}/`));

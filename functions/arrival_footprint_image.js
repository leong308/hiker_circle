// A private, geographic route plot of recorded fixes. The image never invents a basemap or missing footprints.
'use strict';
const {encodePng} = require('./trail_route_cover');
const {validPoint, sampleTime, distanceMeters} = require('./hike_arrival_policy');
const FONT = {
  A:'01110100011000111111100011000110001', B:'11110100011000111110100011000111110',
  C:'01111100001000010000100001000001111', D:'11110100011000110001100011000111110',
  E:'11111100001000011110100001000011111', F:'11111100001000011110100001000010000',
  G:'01111100001000010111100011000101111', H:'10001100011000111111100011000110001',
  I:'11111001000010000100001000010011111', J:'00111000100001000010000101001001100',
  K:'10001100101010011000101001001010001', L:'10000100001000010000100001000011111',
  M:'10001110111010110101100011000110001', N:'10001110011010110011100011000110001',
  O:'01110100011000110001100011000101110', P:'11110100011000111110100001000010000',
  Q:'01110100011000110001101011001001101', R:'11110100011000111110101001001010001',
  S:'01111100001000001110000010000111110', T:'11111001000010000100001000010000100',
  U:'10001100011000110001100011000101110', V:'10001100011000110001100010101000100',
  W:'10001100011000110101101011101110001', X:'10001100010101000100010101000110001',
  Y:'10001100010101000100001000010000100', Z:'11111000010001000100010001000011111',
  '0':'01110100011001110101110011000101110', '1':'00100011000010000100001000010001110',
  '2':'01110100010000100010001000100011111', '3':'11110000010000101110000010000111110',
  '4':'00010001100101010010111110001000010', '5':'11111100001000011110000010000111110',
  '6':'01111100001000011110100011000101110', '7':'11111000010001000100010000100001000',
  '8':'01110100011000101110100011000101110', '9':'01110100011000101111000010000111110',
  '.':'00000000000000000000000000011000110', '-':'00000000000000011111000000000000000',
  ':':'00000001100011000000001100011000000', '/':'00001000100001000100010000100010000',
};

// Render a bounded PNG that contacts can open without an account or a location-sharing session.
function footprintImage(samples, targets = []) {
  const width = 900, height = 900;
  const pixels = Buffer.alloc(width * height * 4, 255);
  const ink = [31, 47, 44], blue = [34, 106, 214], green = [46, 148, 84], red = [208, 53, 53], orange = [224, 144, 35];
  const dot = (x, y, radius, color) => {
    for (let dy = -radius; dy <= radius; dy++) for (let dx = -radius; dx <= radius; dx++) {
      const px = Math.round(x + dx), py = Math.round(y + dy);
      if (dx * dx + dy * dy > radius * radius || px < 0 || py < 0 || px >= width || py >= height) continue;
      const index = (py * width + px) * 4;
      pixels[index] = color[0]; pixels[index + 1] = color[1]; pixels[index + 2] = color[2];
    }
  };
  const line = (a, b, radius, color) => {
    const count = Math.max(1, Math.ceil(Math.hypot(a.x - b.x, a.y - b.y)));
    for (let i = 0; i <= count; i++) dot(a.x + (b.x - a.x) * i / count, a.y + (b.y - a.y) * i / count, radius, color);
  };
  const text = (value, x, y, scale = 3, color = ink) => {
    for (const char of value.toUpperCase()) {
      const glyph = FONT[char];
      if (glyph) for (let i = 0; i < 35; i++) if (glyph[i] === '1') {
        for (let dy = 0; dy < scale; dy++) for (let dx = 0; dx < scale; dx++) dot(x + (i % 5) * scale + dx, y + Math.floor(i / 5) * scale + dy, 0, color);
      }
      x += 6 * scale;
    }
  };
  text('RECORDED FOOTPRINT HISTORY', 36, 28, 4);
  text('ROUTE PLOT - NO BASEMAP', 36, 70, 3);
  const points = (Array.isArray(samples) ? samples : []).filter(point => validPoint(point) && Number.isFinite(sampleTime(point)))
    .sort((a, b) => sampleTime(a) - sampleTime(b));
  const all = [...points, ...targets.filter(validPoint)];
  if (!all.length) text('NO RECORDED GPS', 260, 430, 4);
  else {
    const reference = all[0], cos = Math.max(.05, Math.cos(reference.latitude * Math.PI / 180));
    const projected = all.map(point => ({x: (point.longitude - reference.longitude) * cos, y: point.latitude - reference.latitude}));
    const bounds = projected.reduce((box, p) => ({minX: Math.min(box.minX, p.x), maxX: Math.max(box.maxX, p.x),
      minY: Math.min(box.minY, p.y), maxY: Math.max(box.maxY, p.y)}), {minX: Infinity, maxX: -Infinity, minY: Infinity, maxY: -Infinity});
    const {minX, maxX, minY, maxY} = bounds;
    const span = Math.max(maxX - minX, maxY - minY, .001), scale = 660 / span;
    const project = point => ({x: 450 + (((point.longitude - reference.longitude) * cos) - (minX + maxX) / 2) * scale,
      y: 455 - ((point.latitude - reference.latitude) - (minY + maxY) / 2) * scale});
    for (let grid = 120; grid <= 780; grid += 110) {
      line({x: grid, y: 120}, {x: grid, y: 780}, 0, [228, 236, 233]);
      line({x: 120, y: grid}, {x: 780, y: grid}, 0, [228, 236, 233]);
    }
    // Split at long recording gaps or implausible jumps instead of drawing invented travel.
    const stride = Math.max(1, Math.ceil(points.length / 5000));
    for (let i = stride; i < points.length; i += stride) {
      const before = points[i - stride], after = points[i];
      if (sampleTime(after) - sampleTime(before) <= 10 * 60000 && distanceMeters(before, after) <= 500) line(project(before), project(after), 3, blue);
    }
    for (const target of targets.filter(validPoint)) { const p = project(target); dot(p.x, p.y, 12, orange); dot(p.x, p.y, 5, [255, 255, 255]); }
    if (points.length) {
      const first = project(points[0]), last = project(points.at(-1));
      dot(first.x, first.y, 12, green); dot(last.x, last.y, 12, red);
      text(`LAST ${points.at(-1).latitude.toFixed(5)} ${points.at(-1).longitude.toFixed(5)}`, 36, 795, 3);
    } else text('NO RECORDED GPS', 270, 430, 3);
    text('N', 830, 120, 3); line({x: 839, y: 170}, {x: 839, y: 148}, 2, ink);
    line({x: 839, y: 148}, {x: 832, y: 158}, 2, ink); line({x: 839, y: 148}, {x: 846, y: 158}, 2, ink);
  }
  dot(47, 855, 8, green); text('START', 65, 845, 3);
  dot(214, 855, 8, red); text('LAST FIX', 232, 845, 3);
  dot(445, 855, 8, orange); text('DESTINATION', 463, 845, 3);
  line({x: 713, y: 855}, {x: 743, y: 855}, 3, blue); text('GPS', 760, 845, 3);
  return encodePng(width, height, pixels);
}

module.exports = {footprintImage};

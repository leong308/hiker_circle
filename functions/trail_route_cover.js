// Reuses the original curated route-cover renderer from scripts/curate_trail_images.js.
'use strict';

const crypto = require('node:crypto');
const zlib = require('node:zlib');

function decodePolyline(encoded, precision) {
  if (typeof encoded !== 'string' || encoded.length === 0 || encoded.length > 650000) return [];
  const coordinates = [];
  let index = 0;
  let latitude = 0;
  let longitude = 0;
  const factor = 10 ** precision;
  while (index < encoded.length) {
    let shift = 0;
    let result = 0;
    let byte;
    do {
      if (index >= encoded.length || shift >= 30) return [];
      byte = encoded.charCodeAt(index++) - 63;
      if (byte < 0 || byte > 63) return [];
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    if (byte >= 0x20) return [];
    latitude += result & 1 ? ~(result >> 1) : result >> 1;
    shift = 0;
    result = 0;
    do {
      if (index >= encoded.length || shift >= 30) return [];
      byte = encoded.charCodeAt(index++) - 63;
      if (byte < 0 || byte > 63) return [];
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    if (byte >= 0x20) return [];
    longitude += result & 1 ? ~(result >> 1) : result >> 1;
    coordinates.push([latitude / factor, longitude / factor]);
    if (coordinates.length > 100000) return [];
  }
  return coordinates;
}

function routePoints(trail) {
  const checkpointPoints = (Array.isArray(trail.checkpoints) ? trail.checkpoints : [])
    .filter(checkpoint => checkpoint && typeof checkpoint === 'object')
    .map((checkpoint) => [checkpoint.latitude, checkpoint.longitude])
    .filter(([latitude, longitude]) =>
      Number.isFinite(latitude) && Number.isFinite(longitude),
    );
  const candidates = [5, 6]
    .map((precision) => decodePolyline(trail.routeEncodedPolyline, precision))
    .filter((points) => points.length >= 2)
    .filter((points) =>
      points.every(
        ([latitude, longitude]) =>
          Number.isFinite(latitude) &&
          Number.isFinite(longitude) &&
          Math.abs(latitude) <= 90 &&
          Math.abs(longitude) <= 180,
      ),
    );
  // Covers must follow stored route geometry, never straight lines between checkpoints.
  if (candidates.length === 0) return [];
  const reference = checkpointPoints[0] || [trail.latitude, trail.longitude];
  candidates.sort((first, second) => {
    const distance = (points) =>
      Math.abs(points[0][0] - reference[0]) +
      Math.abs(points[0][1] - reference[1]);
    return distance(first) - distance(second);
  });
  return candidates[0];
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const value of buffer) {
    crc ^= value;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const typeBuffer = Buffer.from(type, 'ascii');
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])));
  return Buffer.concat([length, typeBuffer, data, checksum]);
}

function encodePng(width, height, pixels) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  const rows = Buffer.alloc(height * (width * 4 + 1));
  for (let y = 0; y < height; y += 1) {
    const rowOffset = y * (width * 4 + 1);
    rows[rowOffset] = 0;
    pixels.copy(rows, rowOffset + 1, y * width * 4, (y + 1) * width * 4);
  }
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk('IHDR', header),
    pngChunk('IDAT', zlib.deflateSync(rows, { level: 9 })),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

function routeCover(trail) {
  const width = 1200;
  const height = 675;
  const pixels = Buffer.alloc(width * height * 4);
  const seed = crypto
    .createHash('sha256')
    .update(trail.trailId)
    .digest()
    .readUInt32BE(0);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const index = (y * width + x) * 4;
      const wave =
        Math.sin((x + (seed & 63)) / 67) * 4 +
        Math.cos((y + ((seed >>> 6) & 63)) / 43) * 3;
      const vertical = y / height;
      pixels[index] = Math.max(16, Math.min(42, 28 + wave - vertical * 7));
      pixels[index + 1] = Math.max(58, Math.min(116, 92 + wave * 2 - vertical * 18));
      pixels[index + 2] = Math.max(42, Math.min(84, 67 + wave - vertical * 12));
      pixels[index + 3] = 255;
    }
  }

  const blendPixel = (x, y, red, green, blue, alpha = 255) => {
    const px = Math.round(x);
    const py = Math.round(y);
    if (px < 0 || py < 0 || px >= width || py >= height) return;
    const offset = (py * width + px) * 4;
    const amount = alpha / 255;
    pixels[offset] = Math.round(pixels[offset] * (1 - amount) + red * amount);
    pixels[offset + 1] = Math.round(
      pixels[offset + 1] * (1 - amount) + green * amount,
    );
    pixels[offset + 2] = Math.round(
      pixels[offset + 2] * (1 - amount) + blue * amount,
    );
  };
  const circle = (centerX, centerY, radius, color, alpha = 255) => {
    for (let y = -radius; y <= radius; y += 1) {
      const span = Math.floor(Math.sqrt(radius * radius - y * y));
      for (let x = -span; x <= span; x += 1) {
        blendPixel(centerX + x, centerY + y, ...color, alpha);
      }
    }
  };
  const thickLine = (x0, y0, x1, y1, radius, color, alpha = 255) => {
    const steps = Math.max(1, Math.ceil(Math.hypot(x1 - x0, y1 - y0)));
    for (let step = 0; step <= steps; step += 1) {
      const ratio = step / steps;
      circle(
        x0 + (x1 - x0) * ratio,
        y0 + (y1 - y0) * ratio,
        radius,
        color,
        alpha,
      );
    }
  };

  for (let contour = 0; contour < 12; contour += 1) {
    const phase = ((seed >>> (contour % 16)) & 31) / 5;
    let previousY = null;
    for (let x = -5; x <= width + 5; x += 5) {
      const y =
        30 +
        contour * 58 +
        Math.sin(x / 95 + phase) * 24 +
        Math.cos(x / 41 + phase * 0.7) * 8;
      if (previousY !== null) {
        thickLine(x - 5, previousY, x, y, 1, [190, 225, 178], 42);
      }
      previousY = y;
    }
  }

  const points = routePoints(trail);
  if (points.length < 2) {
    throw new Error(`No usable route geometry for ${trail.trailId}`);
  }
  const latitudes = points.map((point) => point[0]);
  const longitudes = points.map((point) => point[1]);
  const minLatitude = latitudes.reduce((a, b) => Math.min(a, b), Infinity);
  const maxLatitude = latitudes.reduce((a, b) => Math.max(a, b), -Infinity);
  const minLongitude = longitudes.reduce((a, b) => Math.min(a, b), Infinity);
  const maxLongitude = longitudes.reduce((a, b) => Math.max(a, b), -Infinity);
  const padding = 88;
  const longitudeSpan = Math.max(maxLongitude - minLongitude, 0.00001);
  const latitudeSpan = Math.max(maxLatitude - minLatitude, 0.00001);
  const scale = Math.min(
    (width - padding * 2) / longitudeSpan,
    (height - padding * 2) / latitudeSpan,
  );
  const drawnWidth = longitudeSpan * scale;
  const drawnHeight = latitudeSpan * scale;
  const offsetX = (width - drawnWidth) / 2;
  const offsetY = (height - drawnHeight) / 2;
  const canvasPoints = points.map(([latitude, longitude]) => [
    offsetX + (longitude - minLongitude) * scale,
    offsetY + (maxLatitude - latitude) * scale,
  ]);
  const stride = Math.max(1, Math.floor(canvasPoints.length / 2500));
  const simplified = canvasPoints.filter(
    (_, index) => index % stride === 0 || index === canvasPoints.length - 1,
  );
  for (let index = 1; index < simplified.length; index += 1) {
    const previous = simplified[index - 1];
    const current = simplified[index];
    thickLine(...previous, ...current, 10, [8, 35, 25], 150);
  }
  for (let index = 1; index < simplified.length; index += 1) {
    const previous = simplified[index - 1];
    const current = simplified[index];
    thickLine(...previous, ...current, 6, [119, 225, 160], 255);
  }
  const drawPin = ([x, y], color) => {
    circle(x, y, 20, [255, 255, 255], 255);
    circle(x, y, 14, color, 255);
    circle(x, y, 5, [255, 255, 255], 255);
  };
  drawPin(simplified[0], [39, 174, 96]);
  drawPin(simplified[simplified.length - 1], [222, 72, 72]);
  return encodePng(width, height, pixels);
}

function routeCredit(trail) {
  const sourcePageUrl = String(trail.dataSourceUrl || '');
  const isOpenStreetMap = sourcePageUrl.includes('openstreetmap.org');
  return {
    sourceName: isOpenStreetMap
      ? 'OpenStreetMap contributors'
      : 'Hiker Circle route data',
    sourcePageUrl,
    author: isOpenStreetMap
      ? 'OpenStreetMap contributors'
      : 'Generated from the trail route stored by Hiker Circle',
    licenseName: isOpenStreetMap
      ? 'Open Database License (ODbL)'
      : 'Generated route cover',
    licenseUrl: isOpenStreetMap
      ? 'https://www.openstreetmap.org/copyright'
      : '',
    description:
      `Generated route cover for ${trail.name}; no substitute location photo was used.`,
  };
}


module.exports = {decodePolyline, routePoints, routeCover, routeCredit, encodePng};

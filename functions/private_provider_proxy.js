// Private map, geocoding, route, and weather-tile requests validate inputs before attaching server-held credentials.
'use strict';

function coordinate(lat, lon) {
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) throw new Error('Invalid coordinates');
  return {latitude: lat, longitude: lon};
}
function points(value) {
  if (!Array.isArray(value) || value.length < 2 || value.length > 25) throw new Error('Invalid route checkpoints');
  return value.map(point => { coordinate(point?.[1], point?.[0]); return [point[0], point[1]]; });
}
// buildProviderRequest: Select an allowlisted operation and attach credentials only to the matching provider request.
function buildProviderRequest(operation, data, secret) {
  const headers = {'Accept': 'application/json'};
  if (operation === 'googleGeocode') {
    coordinate(data.latitude, data.longitude);
    const url = new URL('https://maps.googleapis.com/maps/api/geocode/json');
    url.search = new URLSearchParams({latlng: `${data.latitude},${data.longitude}`, key: secret, language: 'en', ...(data.countryOnly ? {result_type: 'country'} : {})});
    return {url, headers};
  }
  if (operation === 'googleRoute') {
    const path = points(data.coordinates);
    const location = point => ({location: {latLng: coordinate(point[1], point[0])}});
    return {url: new URL('https://routes.googleapis.com/directions/v2:computeRoutes'), method: 'POST',
      headers: {...headers, 'Content-Type': 'application/json', 'X-Goog-Api-Key': secret,
        'X-Goog-FieldMask': 'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline'},
      body: JSON.stringify({origin: location(path[0]), destination: location(path.at(-1)),
        intermediates: path.slice(1, -1).map(location), travelMode: 'WALK', polylineQuality: 'HIGH_QUALITY',
        polylineEncoding: 'ENCODED_POLYLINE', computeAlternativeRoutes: false})};
  }
  if (operation === 'geoReverse') {
    coordinate(data.latitude, data.longitude);
    const url = new URL('https://api.geoapify.com/v1/geocode/reverse');
    url.search = new URLSearchParams({lat: String(data.latitude), lon: String(data.longitude), apiKey: secret, lang: 'en', limit: '1',
      ...(data.countryOnly ? {type: 'country', format: 'json'} : {})});
    return {url, headers};
  }
  if (operation === 'geoRoute') {
    const path = points(data.coordinates);
    const url = new URL('https://api.geoapify.com/v1/routing');
    url.search = new URLSearchParams({waypoints: path.map(([lon, lat]) => `${lat},${lon}`).join('|'), mode: 'hike', format: 'geojson', details: 'elevation', apiKey: secret});
    return {url, headers};
  }
  if (operation === 'orsRoute') {
    return {url: new URL('https://api.openrouteservice.org/v2/directions/foot-hiking/geojson'), method: 'POST',
      headers: {...headers, 'Authorization': secret, 'Content-Type': 'application/json'},
      body: JSON.stringify({coordinates: points(data.coordinates), elevation: true, format: 'geojson', preference: 'steepest', avoid_features: ['highways', 'tollways']})};
  }
  if (operation === 'weatherTile') {
    const {z, x, y, layer} = data;
    if (!Number.isInteger(z) || z < 0 || z > 10 || !Number.isInteger(x) || !Number.isInteger(y)
      || x < 0 || y < 0 || x >= 2 ** z || y >= 2 ** z
      || !['precipitation_new', 'wind_new', 'temp_new'].includes(layer)) throw new Error('Invalid weather tile');
    const url = new URL(`https://tile.openweathermap.org/map/${layer}/${z}/${x}/${y}.png`);
    url.search = new URLSearchParams({appid: secret});
    return {url, headers: {}, binary: true};
  }
  throw new Error('Unsupported provider operation');
}

module.exports = {buildProviderRequest};

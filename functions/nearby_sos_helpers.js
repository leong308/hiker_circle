// Nearby BLE SOS reports normalize bounded telemetry and hash device/counter identity for deduplication.
const crypto = require('crypto');

// normalizeNearbySosReport: Validate the BLE incident window and derive a privacy-preserving deduplication identity.
function normalizeNearbySosReport(data, nowMillis = Date.now()) {
  const deviceId = String(data?.deviceId || '').trim().toLowerCase();
  if (!/^[a-z0-9_:-]{3,64}$/.test(deviceId)) {
    throw new Error('invalid-device-id');
  }
  const receivedAtMillis = Number(data?.receivedAtMillis);
  if (!Number.isFinite(receivedAtMillis)
      || Math.abs(nowMillis - receivedAtMillis) > 10 * 60 * 1000) {
    throw new Error('invalid-received-at');
  }
  const rawCounter = data?.counter;
  const counter = rawCounter == null ? null : Number(rawCounter);
  if (counter != null
      && (!Number.isInteger(counter) || counter < 0 || counter > 0xffffffff)) {
    throw new Error('invalid-counter');
  }
  const normalizeLocation = (raw) => {
    if (raw == null) return null;
    const latitude = Number(raw.latitude);
    const longitude = Number(raw.longitude);
    const accuracyMeters = raw.accuracyMeters == null
      ? null
      : Number(raw.accuracyMeters);
    if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90
        || !Number.isFinite(longitude) || longitude < -180 || longitude > 180
        || (accuracyMeters != null
          && (!Number.isFinite(accuracyMeters) || accuracyMeters < 0 || accuracyMeters > 10000))) {
      throw new Error('invalid-location');
    }
    return { latitude, longitude, accuracyMeters };
  };
  const incidentCounter = counter ?? Math.floor(receivedAtMillis / 1000);
  const fingerprint = `${deviceId}:${incidentCounter}`;
  const incidentId = crypto.createHash('sha256').update(fingerprint).digest('hex').slice(0, 40);
  const rssi = data?.rssi == null ? null : Number(data.rssi);
  return {
    incidentId,
    deviceIdHash: crypto.createHash('sha256').update(deviceId).digest('hex'),
    counter,
    receivedAtMillis,
    rssi: Number.isInteger(rssi) && rssi >= -127 && rssi <= 20 ? rssi : null,
    reportedLocation: normalizeLocation(data?.reportedLocation),
    detectorLocation: normalizeLocation(data?.detectorLocation),
  };
}

module.exports = { normalizeNearbySosReport };

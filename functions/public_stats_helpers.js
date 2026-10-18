// Public landing-page statistics expose bounded aggregate numbers without source records.
'use strict';

function nonNegativeInteger(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 0;
  return Math.max(0, Math.round(parsed));
}

function nonNegativeDistance(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 0;
  return Math.max(0, Math.round(parsed * 10) / 10);
}

// publicStatsPayload: Normalize aggregate values without exposing counts from malformed source fields.
function publicStatsPayload(raw, calculatedAt = new Date()) {
  const source = raw && typeof raw === 'object' ? raw : {};
  const safeDate = calculatedAt instanceof Date && Number.isFinite(calculatedAt.getTime())
    ? calculatedAt
    : new Date(0);

  return {
    registeredHikers: nonNegativeInteger(source.registeredHikers),
    totalDistanceKm: nonNegativeDistance(source.totalDistanceKm),
    completedHikes: nonNegativeInteger(source.completedHikes),
    soloHikes: nonNegativeInteger(source.soloHikes),
    groupHikes: nonNegativeInteger(source.groupHikes),
    safetyCheckIns: nonNegativeInteger(source.safetyCheckIns),
    calculatedAt: safeDate.toISOString(),
  };
}

module.exports = { publicStatsPayload };

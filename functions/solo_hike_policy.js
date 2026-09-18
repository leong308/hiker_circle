function validateSoloHikeDistance(km, group, acknowledgedKm, HttpsError) {
  if (group) return;
  if (km > 20) throw new HttpsError('failed-precondition', 'Routes over 20 km require group hike setup.');
  if (km > 10 && !(typeof acknowledgedKm === 'number' && Number.isFinite(acknowledgedKm) && Math.abs(km - acknowledgedKm) < .001)) {
    throw new HttpsError('failed-precondition', 'Acknowledge the solo-hike warning for this route before scheduling.');
  }
}
module.exports = { validateSoloHikeDistance };

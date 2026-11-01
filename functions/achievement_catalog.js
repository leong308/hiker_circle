'use strict';
const rules = require('./achievement_rules.json');
const metrics = new Map(rules.metrics.map(metric => [metric.key, metric]));

// Find a supported, implemented metric; arbitrary descriptive text is never executable.
function metricFor(key) { return metrics.get(String(key || '')); }

// Hide retired definitions while preserving their historical awards and point totals.
function visible(definition) {
  return Boolean(metricFor(definition.metricKey))
    && !rules.retiredAchievementIds.includes(definition.achievementId);
}

// Fill legacy presentation fields from the same catalog used by the admin editor.
function contentFor(definition) {
  const metric = metricFor(definition.metricKey);
  const category = rules.categories.find(item => item.id === metric?.categoryId);
  return {
    whyItMatters: String(definition.whyItMatters || category?.description || '').trim(),
    whatCounts: String(definition.whatCounts || metric?.whatCounts || definition.condition || '').trim(),
    rewardRecognition: String(definition.rewardRecognition || rules.defaults.rewardRecognition).trim(),
  };
}

// Validate authored content and the actual measurement separately before persisting a rule.
function validateDefinition(raw) {
  const metric = metricFor(raw?.metricKey);
  if (!metric) throw new Error('Choose a supported tracked activity.');
  const category = rules.categories.find(item => item.id === metric.categoryId);
  const rewardType = raw.rewardType === 'cumulative' || !metric.allowsOneTime ? 'cumulative' : 'one_time';
  const targetCount = rewardType === 'one_time' ? 1 : Number(raw.targetCount);
  if (!Number.isInteger(targetCount) || targetCount < 1 || targetCount > metric.maxTarget) {
    throw new Error(`The target for ${metric.label} must be between 1 and ${metric.maxTarget} stored units.`);
  }
  const result = {metricKey: metric.key, category: category.label, rewardType, targetCount};
  for (const [key, max] of [['title',160],['condition',1000],['whyItMatters',1000],['whatCounts',1000],['rewardRecognition',1000]]) {
    const value = String(raw[key] || '').trim();
    if (!value || value.length > max) throw new Error(`${key} is required and must be at most ${max} characters.`);
    result[key] = value;
  }
  return result;
}

// Bound quantitative events to recorded per-hike values, using integer metres/minutes.
function completedQuantities(hike = {}) {
  const hasReport = hike.summaryReport && typeof hike.summaryReport === 'object';
  const report = hasReport ? hike.summaryReport : hike;
  const distance = metricFor('completed_hike_distance_m'), duration = metricFor('completed_hike_duration_min');
  const bounded = (value, maximum) => Number.isFinite(Number(value)) ? Math.max(0, Math.min(maximum, Number(value))) : 0;
  // Older sessions can retain planned values; require recorded-route evidence or an actual summary.
  const recordedKm = hasReport || Number(hike.routePointCount) > 0 ? report.distanceKm : 0;
  const elapsedMinutes = (Date.parse(hike.endedAtLocal) - Date.parse(hike.startedAtLocal)) / 60000;
  return {distanceMetres: Math.round(bounded(recordedKm, distance.maxIncrement / distance.scale) * distance.scale),
    durationMinutes: Math.floor(bounded(hasReport ? report.durationMinutes ?? Number(report.durationSeconds) / 60 : elapsedMinutes, duration.maxIncrement))};
}

module.exports = {rules, metricFor, visible, contentFor, validateDefinition, completedQuantities};

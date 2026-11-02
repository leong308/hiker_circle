// Compile the single JSON catalog used by Firebase and the bundled admin rule display.
'use strict';
const {createHash} = require('node:crypto');
const policy = require('./community_moderation_policy.json');
const POLICY_HASH = createHash('sha256').update(JSON.stringify(policy)).digest('hex');
const categories = Object.keys(policy.categories);
const labels = {...policy.legacyLabels};
const keywords = new Set();
const evidenceLabels = new Map(policy.recordRules.map(rule => [rule.id, rule.label]));
const rules = [];
const negation = new RegExp(policy.negationPattern, 'iu');

// Normalize common invisible, full-width, case and apostrophe variations before matching.
function normalize(text) {
  return text.normalize('NFKC').toLowerCase().replace(/[\u200b-\u200d\u2060\ufeff]/gu, '')
    .replace(/[’‘`]/gu, "'").replace(/\s+/gu, ' ');
}

// Escape policy phrases so punctuation is literal and adjacent words cannot accidentally match.
function phraseExpression(phrase) {
  const escaped = normalize(phrase).replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/ /g, '[\\s\\p{P}]+');
  return /[\u3400-\u9fff]/u.test(phrase) ? escaped
    : `(?<![\\p{L}\\p{N}_])${escaped}(?![\\p{L}\\p{N}_])`;
}

for (const [category, definition] of Object.entries(policy.categories)) {
  if (!definition.label || !definition.reason || !['low', 'medium', 'high', 'critical'].includes(definition.severity)
    || !Array.isArray(definition.keywords) || !Array.isArray(definition.patterns)
    || definition.keywords.length + definition.patterns.length === 0) throw new Error(`Invalid moderation category: ${category}`);
  labels[category] = definition.reason;
  for (const phrase of definition.keywords) {
    const id = `keyword:${phrase.replaceAll(' ', '_')}`;
    keywords.add(phrase);
    evidenceLabels.set(id, `Matched phrase “${phrase}”`);
    rules.push({category, id, phrase, respectNegation: definition.respectNegation === true,
      expression: new RegExp(phraseExpression(phrase), 'giu')});
  }
  for (const pattern of definition.patterns) {
    if (evidenceLabels.has(pattern.id)) throw new Error(`Duplicate moderation pattern: ${pattern.id}`);
    evidenceLabels.set(pattern.id, pattern.label);
    rules.push({category, id: pattern.id, respectNegation: definition.respectNegation === true,
      expression: new RegExp(pattern.expression, 'giu')});
  }
}

// A nearby explicit warning negates only categories whose catalog entry opts in.
function matches(rule, text) {
  rule.expression.lastIndex = 0;
  for (const match of text.matchAll(rule.expression)) {
    if (!rule.respectNegation || !negation.test(text.slice(Math.max(0, match.index - 48), match.index))) return true;
  }
  return false;
}

// Return static evidence identities and category labels, never matched personal values.
function detect(text) {
  const normalized = normalize(text);
  const hits = rules.filter(rule => matches(rule, normalized));
  if (!hits.length) return null;
  const concerns = [...new Set(hits.map(rule => rule.category))];
  const priority = {low: 0, medium: 1, high: 2, critical: 3};
  const severity = concerns.map(category => policy.categories[category].severity)
    .sort((a, b) => priority[b] - priority[a])[0];
  return {manual: concerns[0], categories: concerns, severity,
    detectionSource: hits.some(rule => rule.phrase) ? 'keywords' : 'pattern',
    detectionEvidence: [...new Set(hits.map(rule => rule.id))],
    matchedKeywords: [...new Set(hits.filter(rule => rule.phrase).map(rule => rule.phrase))]};
}

module.exports = {VERSION: policy.version, POLICY_HASH, categories, labels, keywords, evidenceLabels, detect};

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  AssistantError,
  containsSensitivePersonalData,
  createAssistantHandler,
  isEmergencyQuestion,
  parseGeminiResponse,
  retrieveArticles,
} = require('../hiker_circle_assistant');

function fakeDatabase(initial = {}) {
  let stored = {...initial};
  const reference = {path: 'assistantUsage/test-user'};
  return {
    get stored() {
      return stored;
    },
    collection(name) {
      assert.equal(name, 'assistantUsage');
      return {
        doc(uid) {
          assert.equal(uid, 'test-user');
          return reference;
        },
      };
    },
    async runTransaction(callback) {
      return callback({
        async get(receivedReference) {
          assert.equal(receivedReference, reference);
          return {
            exists: Object.keys(stored).length > 0,
            data: () => ({...stored}),
          };
        },
        set(receivedReference, value) {
          assert.equal(receivedReference, reference);
          stored = {...stored, ...value};
        },
      });
    },
  };
}

test('retrieval selects the reviewed article matching the question', () => {
  const results = retrieveArticles('How do I pair my physical Bluetooth SOS button?');
  assert.equal(results[0].id, 'sos_button');
  assert.ok(results.length <= 3);
});

test('personal data detection blocks common identifiers before Gemini', () => {
  assert.equal(containsSensitivePersonalData('My email is hiker@example.com'), true);
  assert.equal(containsSensitivePersonalData('My number is +60 12 345 6789'), true);
  assert.equal(containsSensitivePersonalData('I am at 5.41640, 100.33270'), true);
  assert.equal(containsSensitivePersonalData('How do I filter hikes within 50 km?'), false);
});

test('emergency language is detected without calling the model', async () => {
  assert.equal(isEmergencyQuestion('I need rescue, this is an emergency'), true);
  let databaseUsed = false;
  const handler = createAssistantHandler({
    db: {
      collection() {
        databaseUsed = true;
        throw new Error('should not be called');
      },
    },
    apiKey: '',
  });
  const result = await handler({
    auth: {uid: 'test-user'},
    data: {question: 'I need rescue, this is an emergency'},
  });
  assert.equal(result.responseMode, 'curated_emergency');
  assert.match(result.answer, /999 or 112/);
  assert.equal(databaseUsed, false);
});

test('Gemini JSON only exposes reviewed source identifiers', () => {
  const articles = retrieveArticles('How do achievements work?');
  const parsed = parseGeminiResponse({
    candidates: [{
      content: {
        parts: [{
          text: JSON.stringify({
            answer: 'Complete eligible activities to earn points.',
            sourceIds: ['achievements', 'invented_source'],
          }),
        }],
      },
    }],
  }, articles);
  assert.equal(parsed.answer, 'Complete eligible activities to earn points.');
  assert.deepEqual(parsed.sources, [
    {id: 'achievements', title: 'Achievements and hiker levels'},
  ]);
});

test('authenticated handler records usage and returns a constrained answer', async () => {
  const db = fakeDatabase();
  const handler = createAssistantHandler({
    db,
    apiKey: 'test-key',
    now: () => Date.UTC(2026, 8, 24, 1, 2, 3),
    fetchImpl: async (url, options) => {
      assert.match(url, /gemini-3\.5-flash-lite:generateContent$/);
      assert.equal(options.headers['x-goog-api-key'], 'test-key');
      const request = JSON.parse(options.body);
      assert.match(request.contents[0].parts[0].text, /Login and account security/);
      return {
        ok: true,
        status: 200,
        async json() {
          return {
            candidates: [{
              content: {
                parts: [{text: JSON.stringify({
                  answer: 'Open Profile, App Settings, then Login security.',
                  sourceIds: ['login_security'],
                })}],
              },
            }],
          };
        },
      };
    },
  });
  const result = await handler({
    auth: {uid: 'test-user'},
    data: {question: 'Where do I manage my passkey?'},
  });
  assert.equal(result.responseMode, 'gemini_free_tier');
  assert.equal(db.stored.dayCount, 1);
  assert.equal(db.stored.minuteCount, 1);
});

test('handler returns reviewed guidance when every free model is busy', async () => {
  const db = fakeDatabase();
  const attemptedModels = [];
  const handler = createAssistantHandler({
    db,
    apiKey: 'test-key',
    fetchImpl: async (url) => {
      attemptedModels.push(url);
      return {
        ok: false,
        status: 503,
        async json() {
          return {error: {status: 'UNAVAILABLE'}};
        },
      };
    },
  });

  const result = await handler({
    auth: {uid: 'test-user'},
    data: {question: 'Where do I manage my passkey?'},
  });

  assert.equal(result.responseMode, 'curated_fallback');
  assert.match(result.answer, /Profile, App Settings, Login security/);
  assert.match(result.notice, /Gemini is busy/);
  assert.equal(attemptedModels.length, 2);
  assert.match(attemptedModels[0], /gemini-3\.5-flash-lite/);
  assert.match(attemptedModels[1], /gemini-3\.1-flash-lite/);
});

test('handler rejects unauthenticated requests', async () => {
  const handler = createAssistantHandler({db: fakeDatabase(), apiKey: 'test'});
  await assert.rejects(
    () => handler({data: {question: 'How do I find a trail?'}}),
    (error) => error instanceof AssistantError && error.code === 'unauthenticated'
  );
});

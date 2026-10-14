'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  AssistantError,
  containsSensitivePersonalData,
  contextualAction,
  createAssistantHandler,
  isEmergencyQuestion,
  findTrails,
  navigationAction,
  normalizeHistory,
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

test('personal data detection blocks common identifiers before answering', () => {
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
  assert.equal(result.action.destinationId, 'sos');
  assert.equal(databaseUsed, false);
});

test('informational emergency and medical questions get deterministic actions', () => {
  assert.deepEqual(
    contextualAction('Who to contact when I faced emergencies?'),
    {type: 'navigate', destinationId: 'sos', label: 'Open SOS'}
  );
  assert.deepEqual(
    contextualAction('What should I do for a sprained ankle?'),
    {
      type: 'navigate',
      destinationId: 'first_aid',
      label: 'Open First-Aid Guide',
    }
  );
});

test('recent context omits sensitive entries before answering', () => {
  assert.deepEqual(normalizeHistory([
    {role: 'user', text: 'How do I join a hike?'},
    {role: 'assistant', text: 'Send a join request.'},
    {role: 'user', text: 'My email is hiker@example.com'},
  ]), [
    {role: 'user', text: 'How do I join a hike?'},
    {role: 'assistant', text: 'Send a join request.'},
  ]);
});

test('emergency contact setup is help, not an active emergency', () => {
  assert.equal(isEmergencyQuestion('How to set my emergency contacts'), false);
  assert.equal(isEmergencyQuestion('I have an emergency right now'), true);
});

test('live trail search ranks nearby and longest trails and returns IDs', async () => {
  const db = {collection(name) {
    assert.equal(name, 'trails');
    return {async get() {return {docs: [
      {id: 'short', data: () => ({name: 'Near Hill', latitude: 3.1,
        longitude: 101.1, distanceKm: 2})},
      {id: 'long', data: () => ({name: 'Far Ridge', latitude: 4,
        longitude: 102, distanceKm: 15})},
    ]};}};
  }};
  const nearby = await findTrails(db, 'nearest hiking trail',
    {latitude: 3.11, longitude: 101.11});
  assert.equal(nearby.trails[0].id, 'short');
  assert.ok(nearby.trails[0].distanceFromUserKm < nearby.trails[1].distanceFromUserKm);
  const longest = await findTrails(db, 'what is the longest trail');
  assert.equal(longest.trails[0].id, 'long');
});

test('Penang trail wording matches trails stored as Pulau Pinang', async () => {
  const db = {collection(name) {
    assert.equal(name, 'trails');
    return {async get() {return {docs: [
      {id: 'penang-1', data: () => ({name: 'Heritage Trail',
        state: 'Pulau Pinang', distanceKm: 4.8})},
      {id: 'selangor-1', data: () => ({name: 'Forest Trail',
        state: 'Selangor', distanceKm: 3.1})},
    ]};}};
  }};
  const result = await findTrails(
    db,
    'What are the available trails in Penang?'
  );
  assert.deepEqual(result.trails.map((trail) => trail.id), ['penang-1']);
});

test('navigation resolves registered destinations without inventing routes', () => {
  assert.equal(navigationAction('Take me to emergency contacts').destinationId,
    'emergency_contacts');
  assert.equal(navigationAction('How to set my emergency contacts').destinationId,
    'emergency_contacts');
  assert.equal(navigationAction('How do emergency contacts work?'), null);
});

test('direct page request returns a button without external calls', async () => {
  const handler = createAssistantHandler({db: fakeDatabase(),
    fetchImpl: () => {throw new Error('External providers must not be called');}});
  const result = await handler({auth: {uid: 'test-user'},
    data: {question: 'Take me to emergency contacts'}});
  assert.equal(result.responseMode, 'curated_navigation');
  assert.equal(result.action.destinationId, 'emergency_contacts');
});

test('reviewed guide answers preserve account navigation and usage without external calls', async () => {
  const db = fakeDatabase();
  const previousFetch = global.fetch;
  global.fetch = async () => assert.fail('Guide help must not contact a provider');
  try {
    const handler = createAssistantHandler({db});
    const result = await handler({auth: {uid: 'test-user'},
      data: {question: 'Where do I manage my passkey?', history: [{role:'user', text:'Where is Login security?'}]}});
    assert.equal(result.responseMode, 'curated_guide');
    assert.match(result.answer, /Profile, App Settings, Login security/);
    assert.ok(result.sources.some(source => source.id === 'login_security'));
    assert.equal(db.stored.dayCount, 1);
  } finally { global.fetch = previousFetch; }
});

test('handler rejects unauthenticated requests', async () => {
  const handler = createAssistantHandler({db: fakeDatabase()});
  await assert.rejects(
    () => handler({data: {question: 'How do I find a trail?'}}),
    (error) => error instanceof AssistantError && error.code === 'unauthenticated'
  );
});

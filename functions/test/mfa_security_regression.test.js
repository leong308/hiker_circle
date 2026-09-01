const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const {
  base32Decode,
  decryptTotpSecret,
  encryptTotpSecret,
  randomOpaqueToken,
  totpAtStep,
  verifyTotp,
} = require('../mfa_helpers');

const source = fs.readFileSync(path.join(__dirname, '..', 'index.js'), 'utf8');
const mobileUserRepositorySource = fs.readFileSync(
  path.join(__dirname, '..', '..', 'lib', 'app', 'Data', 'firebase_user_repository.dart'),
  'utf8'
);

function exportedBlock(name, nextName) {
  const start = source.indexOf(`exports.${name}`);
  const end = source.indexOf(`exports.${nextName}`, start + 1);
  assert.ok(start >= 0 && end > start, `Unable to locate ${name}`);
  return source.slice(start, end);
}

test('pre-MFA WhatsApp verification cannot mint a Firebase token', () => {
  const block = exportedBlock(
    'verifyGreenApiLoginCode',
    'registerWithGreenApiAndPassword'
  );
  assert.doesNotMatch(block, /createCustomToken/);
  assert.match(block, /mfaLoginSessions|mfaSessionReference/);
});

test('legacy password and saved-device token bypasses stay disabled', () => {
  const passwordBlock = exportedBlock('loginWithPassword', 'linkPasswordToAccount');
  const recoveryBlock = exportedBlock('authenticateAppSession', 'fetchWeatherForAllTrails');
  assert.match(passwordBlock, /Password-only login is disabled/);
  assert.match(recoveryBlock, /requires a fresh WhatsApp and second-factor sign-in/);
  assert.ok(passwordBlock.indexOf('throw new HttpsError') < passwordBlock.indexOf('createCustomToken'));
  assert.ok(recoveryBlock.indexOf('throw new HttpsError') < recoveryBlock.indexOf('createCustomToken'));
});

test('mobile post-MFA handoff reuses the authenticated Firebase session', () => {
  assert.doesNotMatch(
    mobileUserRepositorySource,
    /httpsCallable\(\s*['"]authenticateAppSession['"]\s*\)/
  );
  assert.doesNotMatch(mobileUserRepositorySource, /signInWithCustomToken/);
  assert.match(mobileUserRepositorySource, /currentUser/);
  assert.match(mobileUserRepositorySource, /getIdTokenResult/);
  assert.match(mobileUserRepositorySource, /claims\['mfa'\] != true/);
  assert.match(mobileUserRepositorySource, /claims\['phoneNumber'\] != session\.phoneNumber/);
});

test('factor and challenge collections are explicitly denied to mobile SDKs', () => {
  const rules = fs.readFileSync(path.join(__dirname, '..', '..', 'firestore.rules'), 'utf8');
  for (const collection of [
    'authFactors',
    'mfaLoginSessions',
    'mfaEnrollmentChallenges',
    'mfaAuthenticationChallenges',
  ]) {
    const location = rules.indexOf(collection);
    assert.ok(location >= 0, `Missing rules for ${collection}`);
    assert.match(rules.slice(location, location + 180), /allow read, write: if false/);
  }
});

test('opaque challenges have at least 256 bits and do not repeat', () => {
  const samples = new Set(Array.from({ length: 2000 }, () => randomOpaqueToken(32)));
  assert.equal(samples.size, 2000);
  for (const token of samples) assert.ok(token.length >= 43);
});

test('TOTP rejects malformed, stale, future, and replayed values', () => {
  const secret = 'JBSWY3DPEHPK3PXP';
  const currentStep = 1_000_000;
  const nowMillis = currentStep * 30 * 1000;
  assert.deepEqual(
    verifyTotp({ secret, code: '12345x', nowMillis }),
    { valid: false, step: null }
  );
  assert.equal(
    verifyTotp({ secret, code: totpAtStep(secret, currentStep - 2), nowMillis }).valid,
    false
  );
  assert.equal(
    verifyTotp({ secret, code: totpAtStep(secret, currentStep + 2), nowMillis }).valid,
    false
  );
  const accepted = verifyTotp({
    secret,
    code: totpAtStep(secret, currentStep),
    nowMillis,
  });
  assert.equal(accepted.valid, true);
  assert.equal(
    verifyTotp({
      secret,
      code: totpAtStep(secret, currentStep),
      nowMillis,
      lastUsedStep: accepted.step,
    }).valid,
    false
  );
});

test('TOTP ciphertext cannot be decrypted with another key', () => {
  const firstKey = Buffer.alloc(32, 1).toString('base64');
  const otherKey = Buffer.alloc(32, 2).toString('base64');
  const encrypted = encryptTotpSecret('JBSWY3DPEHPK3PXP', firstKey);
  assert.throws(() => decryptTotpSecret(encrypted, otherKey));
  assert.throws(() => base32Decode('NOT*BASE32'));
});

test('WebAuthn validation uses exact RP ID, allowlisted origins, and user verification', () => {
  assert.match(source, /const MFA_RP_ID = 'hiker-circle\.web\.app'/);
  assert.doesNotMatch(source, /MFA_EXPECTED_ORIGINS[\s\S]{0,250}\*/);
  assert.match(source, /android:apk-key-hash:h2Rnre_qN7trjII_aQvnR10eWfZBnmoel4_NUXRj93A/);
  assert.match(source, /android:apk-key-hash:flOmOJZmCgW6d7EWNq5_y29ComAJ7bbBTChNAdUmaYI/);
  assert.ok((source.match(/requireUserVerification: true/g) || []).length >= 2);
  assert.ok((source.match(/userVerification: 'required'/g) || []).length >= 2);
});

test('every Android Digital Asset Link certificate is accepted by WebAuthn', () => {
  const assetLinks = JSON.parse(fs.readFileSync(
    path.join(__dirname, '..', '..', 'web', '.well-known', 'assetlinks.json'),
    'utf8'
  ));
  const fingerprints = assetLinks
    .filter((statement) => statement?.target?.package_name === 'com.leongziqi.hikercircle')
    .flatMap((statement) => statement.target.sha256_cert_fingerprints || []);
  const appStatement = assetLinks.find(
    (statement) => statement?.target?.package_name === 'com.leongziqi.hikercircle'
  );
  assert.ok(
    appStatement?.relation?.includes('delegate_permission/common.handle_all_urls'),
    'Passkeys require the Android App Links relationship for RP ID validation'
  );
  assert.ok(
    appStatement?.relation?.includes('delegate_permission/common.get_login_creds'),
    'Credential sharing relationship must remain declared'
  );
  assert.ok(fingerprints.length >= 2);
  for (const fingerprint of fingerprints) {
    const originHash = Buffer.from(String(fingerprint).replaceAll(':', ''), 'hex')
      .toString('base64url');
    assert.match(source, new RegExp(`android:apk-key-hash:${originHash}`));
  }
});

test('Android passkey transports are normalized before storage and authentication', () => {
  const enrollmentBlock = exportedBlock(
    'finishPasskeyEnrollment',
    'verifyTotpLogin'
  );
  const loginBlock = exportedBlock('beginPasskeyLogin', 'removeMfaFactor');
  assert.match(enrollmentBlock, /normalizeAuthenticatorTransports\(credential\.transports\)/);
  assert.ok(
    (loginBlock.match(/normalizeAuthenticatorTransports/g) || []).length >= 2
  );
  assert.match(loginBlock, /transports\.length > 0/);
});

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'index.js'),
  'utf8'
);

function exportedBlock(name, nextName) {
  const start = source.indexOf('exports.' + name + ' =');
  assert.notEqual(start, -1, 'Missing ' + name);
  const end = nextName
    ? source.indexOf('exports.' + nextName + ' =', start + 1)
    : source.length;
  assert.notEqual(end, -1, 'Missing boundary ' + nextName);
  return source.slice(start, end);
}

test('password reset OTP exposes only enrolled recovery methods', () => {
  const block = exportedBlock(
    'verifyPasswordResetOtp',
    'checkSafetyAnswer'
  );
  assert.match(block, /hasQuestions \? \['secretQuestion'\] : \[\]/);
  assert.match(block, /factorMethods\(await factorDocumentsForUser\(userId\)\)/);
  assert.match(block, /recoveryMethods,/);
  assert.match(block, /recoveryVerified: false/);
});

test('every password reset recovery method records server-side verification', () => {
  const question = exportedBlock(
    'checkSafetyAnswer',
    'verifyPasswordResetTotp'
  );
  const totp = exportedBlock(
    'verifyPasswordResetTotp',
    'beginPasswordResetPasskey'
  );
  const passkey = exportedBlock(
    'finishPasswordResetPasskey',
    'resetPassword'
  );

  assert.match(question, /recoveryMethod: 'secretQuestion'/);
  assert.match(totp, /recoveryMethod: 'totp'/);
  assert.match(passkey, /recoveryMethod: 'passkey'/);
  assert.match(totp, /verifyTotp\(/);
  assert.match(passkey, /requireUserVerification: true/);
  assert.match(passkey, /expectedOrigin: MFA_EXPECTED_ORIGINS/);
});

test('a new password is rejected until an enrolled method was verified', () => {
  const block = exportedBlock('resetPassword', 'loginWithPassword');
  assert.match(block, /session\.recoveryVerified !== true/);
  assert.match(block, /session\.recoveryMethods\.includes\(recoveryMethod\)/);
  assert.doesNotMatch(block, /request\.data\?\.answer/);
});

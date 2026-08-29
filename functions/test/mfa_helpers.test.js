const assert = require('node:assert/strict');
const test = require('node:test');

const {
  base32Decode,
  base32Encode,
  decryptTotpSecret,
  encryptTotpSecret,
  opaqueTokenDigest,
  totpAtStep,
  verifyTotp,
} = require('../mfa_helpers');

test('Base32 encoding round-trips arbitrary bytes', () => {
  const original = Buffer.from('HikerCircle passkey + TOTP');
  assert.deepEqual(base32Decode(base32Encode(original)), original);
});

test('TOTP implementation matches the RFC 6238 SHA-1 test vector prefix', () => {
  // RFC 6238 uses 8 digits. The final six digits remain a useful independent
  // check of dynamic truncation for this application's six-digit profile.
  const secret = base32Encode(Buffer.from('12345678901234567890'));
  assert.equal(totpAtStep(secret, Math.floor(59 / 30)), '287082');
});

test('TOTP is one-time within the accepted clock window', () => {
  const secret = base32Encode(Buffer.from('12345678901234567890'));
  const nowMillis = 59_000;
  const code = totpAtStep(secret, 1);
  const first = verifyTotp({ secret, code, nowMillis, lastUsedStep: -1 });
  assert.deepEqual(first, { valid: true, step: 1 });
  assert.deepEqual(
    verifyTotp({ secret, code, nowMillis, lastUsedStep: first.step }),
    { valid: false, step: null }
  );
});

test('TOTP secrets are authenticated and encrypted at rest', () => {
  const key = Buffer.alloc(32, 7).toString('base64');
  const encrypted = encryptTotpSecret('JBSWY3DPEHPK3PXP', key);
  assert.notEqual(encrypted.ciphertext, 'JBSWY3DPEHPK3PXP');
  assert.equal(decryptTotpSecret(encrypted, key), 'JBSWY3DPEHPK3PXP');
  encrypted.ciphertext = `${encrypted.ciphertext.slice(0, -2)}AA`;
  assert.throws(() => decryptTotpSecret(encrypted, key));
});

test('opaque session tokens are never used as their database identifiers', () => {
  assert.equal(
    opaqueTokenDigest('example-token'),
    '4d1566a1d7df42a8517456d60ea06ed284e535cfe4c956aa6ee172dbcdf945f7'
  );
});

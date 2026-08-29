const crypto = require('crypto');

const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const MFA_SESSION_TTL_MILLIS = 10 * 60 * 1000;
const MFA_CHALLENGE_TTL_MILLIS = 5 * 60 * 1000;
const TOTP_STEP_SECONDS = 30;
const TOTP_DIGITS = 6;
const WEBAUTHN_AUTHENTICATOR_TRANSPORTS = new Set([
  'ble',
  'cable',
  'hybrid',
  'internal',
  'nfc',
  'smart-card',
  'usb',
]);

function randomOpaqueToken(bytes = 32) {
  return crypto.randomBytes(bytes).toString('base64url');
}

function opaqueTokenDigest(token) {
  return crypto.createHash('sha256').update(String(token || '')).digest('hex');
}

function normalizeAuthenticatorTransports(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value
    .map((transport) => String(transport || '').trim().toLowerCase())
    .filter((transport) => WEBAUTHN_AUTHENTICATOR_TRANSPORTS.has(transport)))];
}

function base32Encode(buffer) {
  let bits = 0;
  let value = 0;
  let output = '';
  for (const byte of buffer) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      output += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) {
    output += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  }
  return output;
}

function base32Decode(value) {
  const normalized = String(value || '')
    .toUpperCase()
    .replace(/=+$/g, '')
    .replace(/[\s-]/g, '');
  if (!normalized || /[^A-Z2-7]/.test(normalized)) {
    throw new Error('Invalid Base32 value.');
  }
  let bits = 0;
  let accumulator = 0;
  const bytes = [];
  for (const character of normalized) {
    accumulator = (accumulator << 5) | BASE32_ALPHABET.indexOf(character);
    bits += 5;
    if (bits >= 8) {
      bytes.push((accumulator >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Buffer.from(bytes);
}

function generateTotpSecret() {
  // 160 bits matches the HMAC-SHA1 output size used by RFC 6238.
  return base32Encode(crypto.randomBytes(20));
}

function totpAtStep(secret, step) {
  if (!Number.isSafeInteger(step) || step < 0) {
    throw new Error('Invalid TOTP time step.');
  }
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(step));
  const digest = crypto
    .createHmac('sha1', base32Decode(secret))
    .update(counter)
    .digest();
  const offset = digest[digest.length - 1] & 0x0f;
  const binary =
    ((digest[offset] & 0x7f) << 24) |
    ((digest[offset + 1] & 0xff) << 16) |
    ((digest[offset + 2] & 0xff) << 8) |
    (digest[offset + 3] & 0xff);
  return String(binary % 10 ** TOTP_DIGITS).padStart(TOTP_DIGITS, '0');
}

function verifyTotp({ secret, code, nowMillis = Date.now(), window = 1, lastUsedStep = -1 }) {
  const candidate = String(code || '').trim();
  if (!/^\d{6}$/.test(candidate)) {
    return { valid: false, step: null };
  }
  const currentStep = Math.floor(nowMillis / 1000 / TOTP_STEP_SECONDS);
  for (let delta = -window; delta <= window; delta += 1) {
    const step = currentStep + delta;
    if (step <= lastUsedStep || step < 0) continue;
    const expected = Buffer.from(totpAtStep(secret, step));
    const supplied = Buffer.from(candidate);
    if (expected.length === supplied.length && crypto.timingSafeEqual(expected, supplied)) {
      return { valid: true, step };
    }
  }
  return { valid: false, step: null };
}

function encryptionKeyFromBase64(value) {
  let key;
  try {
    key = Buffer.from(String(value || '').trim(), 'base64');
  } catch (_) {
    key = Buffer.alloc(0);
  }
  if (key.length !== 32) {
    throw new Error('MFA_TOTP_ENCRYPTION_KEY must be a Base64 encoded 32-byte key.');
  }
  return key;
}

function encryptTotpSecret(secret, keyBase64) {
  const key = encryptionKeyFromBase64(keyBase64);
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  cipher.setAAD(Buffer.from('hikercircle:totp:v1'));
  const ciphertext = Buffer.concat([cipher.update(String(secret), 'utf8'), cipher.final()]);
  return {
    version: 1,
    algorithm: 'AES-256-GCM',
    iv: iv.toString('base64'),
    ciphertext: ciphertext.toString('base64'),
    tag: cipher.getAuthTag().toString('base64'),
  };
}

function decryptTotpSecret(record, keyBase64) {
  if (!record || record.version !== 1 || record.algorithm !== 'AES-256-GCM') {
    throw new Error('Unsupported encrypted TOTP record.');
  }
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    encryptionKeyFromBase64(keyBase64),
    Buffer.from(String(record.iv || ''), 'base64')
  );
  decipher.setAAD(Buffer.from('hikercircle:totp:v1'));
  decipher.setAuthTag(Buffer.from(String(record.tag || ''), 'base64'));
  return Buffer.concat([
    decipher.update(Buffer.from(String(record.ciphertext || ''), 'base64')),
    decipher.final(),
  ]).toString('utf8');
}

function otpauthUri({ secret, phoneNumber, issuer = 'HikerCircle' }) {
  const label = `${issuer}:${phoneNumber}`;
  const query = new URLSearchParams({
    secret,
    issuer,
    algorithm: 'SHA1',
    digits: String(TOTP_DIGITS),
    period: String(TOTP_STEP_SECONDS),
  });
  return `otpauth://totp/${encodeURIComponent(label)}?${query.toString()}`;
}

module.exports = {
  MFA_CHALLENGE_TTL_MILLIS,
  MFA_SESSION_TTL_MILLIS,
  TOTP_STEP_SECONDS,
  base32Decode,
  base32Encode,
  decryptTotpSecret,
  encryptTotpSecret,
  generateTotpSecret,
  normalizeAuthenticatorTransports,
  opaqueTokenDigest,
  otpauthUri,
  randomOpaqueToken,
  totpAtStep,
  verifyTotp,
};

// Read-only OTP checks run together while delivery and cooldown writes remain ordered.
'use strict';

const {performance} = require('node:perf_hooks');

const safeErrorCodes = new Set([
  'cancelled', 'unknown', 'invalid-argument', 'deadline-exceeded', 'not-found',
  'already-exists', 'permission-denied', 'resource-exhausted',
  'failed-precondition', 'aborted', 'out-of-range', 'unimplemented', 'internal',
  'unavailable', 'data-loss', 'unauthenticated',
]);

// A provider result must never hide an account eligibility failure.
async function runOtpChecks({checkAccount, checkProvider, timing}) {
  const measure = (stage, operation) => timing
    ? Promise.resolve().then(() => timing.measure(stage, operation))
    : Promise.resolve().then(operation);
  const [account, credentials] = await Promise.allSettled([
    measure('accountCheck', checkAccount),
    measure('providerReadiness', checkProvider),
  ]);
  if (account.status === 'rejected') throw account.reason;
  if (credentials.status === 'rejected') throw credentials.reason;
  return {account: account.value, credentials: credentials.value};
}

// Share only a currently running probe. Every later request checks live readiness.
function createOtpReadinessCheck(probe) {
  let pending = null;
  return function checkReadiness() {
    if (pending) return pending;
    const attempt = Promise.resolve().then(probe);
    const tracked = attempt.then(
      value => {
        if (pending === tracked) pending = null;
        return value;
      },
      error => {
        if (pending === tracked) pending = null;
        throw error;
      },
    );
    pending = tracked;
    return tracked;
  };
}

function sanitizedOutcome(error) {
  const code = typeof error?.code === 'string'
    ? error.code.replace(/^functions\//, '') : '';
  return safeErrorCodes.has(code) ? code : 'internal';
}

// Log fixed flow/stage labels and elapsed times, never request or exception data.
function withOtpTiming(flow, handler, log, {clock = () => performance.now()} = {}) {
  const flowLabel = /^[a-z][a-z0-9_]{0,47}$/.test(flow) ? flow : 'unknown';
  return async function timedOtpHandler(request) {
    const started = clock();
    const stagesMs = Object.create(null);
    let outcome = 'ok';
    const timing = {
      async measure(stage, operation) {
        if (!/^[a-zA-Z][a-zA-Z0-9_]{0,47}$/.test(stage)) {
          throw new TypeError('Expected a fixed OTP timing stage label');
        }
        const stageStarted = clock();
        try {
          return await operation();
        } finally {
          stagesMs[stage] = (stagesMs[stage] || 0)
            + Math.max(0, clock() - stageStarted);
        }
      },
    };
    try {
      return await handler(request, timing);
    } catch (error) {
      outcome = sanitizedOutcome(error);
      throw error;
    } finally {
      try {
        log('OTP delivery timing', {
          flow: flowLabel,
          outcome,
          stagesMs: {...stagesMs},
          totalMs: Math.max(0, clock() - started),
        });
      } catch (_) {
        // Optional telemetry must not change the authentication outcome.
      }
    }
  };
}

module.exports = {runOtpChecks, createOtpReadinessCheck, withOtpTiming};

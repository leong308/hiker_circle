const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const {
  onDocumentCreated,
  onDocumentUpdated,
} = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions/v2');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const crypto = require('crypto');
const argon2 = require('argon2');

admin.initializeApp();

const greenApiInstanceId = defineSecret('GREEN_API_INSTANCE_ID');
const greenApiToken = defineSecret('GREEN_API_TOKEN');

function userDocumentIdForPhone(phoneNumber) {
  return String(phoneNumber || '').replace(/\//g, '_');
}

function isAdminUser(user) {
  const role = String(user.role || '').toLowerCase();
  const roles = Array.isArray(user.roles)
    ? user.roles.map((value) => String(value || '').toLowerCase())
    : [];
  return (
    user.isAdmin === true ||
    role === 'admin' ||
    role === 'super_admin' ||
    roles.includes('admin')
  );
}

exports.sendGreenApiLoginCode = onCall(
  { secrets: [greenApiInstanceId, greenApiToken] },
  async (request) => {
    const phoneNumber = String(request.data?.phoneNumber || '').trim();
    if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
      throw new HttpsError(
        'invalid-argument',
        'Enter a valid international phone number.'
      );
    }

    const challengeId = crypto
      .createHash('sha256')
      .update(phoneNumber)
      .digest('hex');
    const challengeReference = admin
      .firestore()
      .collection('greenApiLoginChallenges')
      .doc(challengeId);
    const previousChallenge = await challengeReference.get();
    const previous = previousChallenge.data() || {};
    const previousSentAt = Number(previous.sentAtMillis || 0);
    if (Date.now() - previousSentAt < 60 * 1000) {
      throw new HttpsError(
        'resource-exhausted',
        'Wait one minute before requesting another WhatsApp code.'
      );
    }

    const code = crypto.randomInt(0, 1000000).toString().padStart(6, '0');
    const expiresAtMillis = Date.now() + 5 * 60 * 1000;
    const instanceId = greenApiInstanceId.value();
    const token = greenApiToken.value();
    const digitsOnly = phoneNumber.replace(/\D/g, '');
    const response = await fetch(
      `https://api.green-api.com/waInstance${instanceId}/sendMessage/${token}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          chatId: `${digitsOnly}@c.us`,
          message:
            `Your HikerCircle verification code is ${code}. ` +
            'It expires in 5 minutes.',
        }),
      }
    );
    if (!response.ok) {
      logger.error('GreenAPI login message failed', {
        status: response.status,
        challengeId,
      });
      throw new HttpsError(
        'unavailable',
        'WhatsApp verification is temporarily unavailable.'
      );
    }

    const codeHash = crypto
      .createHmac('sha256', greenApiToken.value())
      .update(`${challengeId}:${code}`)
      .digest('hex');

    await challengeReference.set({
      phoneNumber,
      codeHash,
      attemptsRemaining: 5,
      consumed: false,
      sentAtMillis: Date.now(),
      expiresAtMillis,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { challengeId, expiresAtMillis };
  }
);

exports.verifyGreenApiLoginCode = onCall(
  { secrets: [greenApiToken] },
  async (request) => {
    const challengeId = String(request.data?.challengeId || '').trim();
    const code = String(request.data?.code || '').trim();
    if (!/^[a-f0-9]{64}$/.test(challengeId) || !/^\d{6}$/.test(code)) {
      throw new HttpsError('invalid-argument', 'Enter the 6-digit code.');
    }

    const challengeReference = admin
      .firestore()
      .collection('greenApiLoginChallenges')
      .doc(challengeId);
    const verification = await admin.firestore().runTransaction(
      async (transaction) => {
        const snapshot = await transaction.get(challengeReference);
        const challenge = snapshot.data();
        if (!snapshot.exists || !challenge) {
          return {
            errorCode: 'not-found',
            errorMessage:
              'This WhatsApp verification request no longer exists.',
          };
        }
        if (
          challenge.consumed === true ||
          Date.now() > Number(challenge.expiresAtMillis || 0)
        ) {
          return {
            errorCode: 'deadline-exceeded',
            errorMessage: 'The WhatsApp verification code has expired.',
          };
        }
        const attemptsRemaining = Number(challenge.attemptsRemaining || 0);
        if (attemptsRemaining <= 0) {
          return {
            errorCode: 'permission-denied',
            errorMessage: 'Too many incorrect attempts. Request a new code.',
          };
        }

        const expected = Buffer.from(String(challenge.codeHash || ''), 'hex');
        const candidateHash = crypto
          .createHmac('sha256', greenApiToken.value())
          .update(`${challengeId}:${code}`)
          .digest();
        const matches =
          expected.length === candidateHash.length &&
          crypto.timingSafeEqual(expected, candidateHash);
        if (!matches) {
          transaction.update(challengeReference, {
            attemptsRemaining: attemptsRemaining - 1,
          });
          return {
            errorCode: 'permission-denied',
            errorMessage: 'The WhatsApp verification code is incorrect.',
          };
        }

        transaction.update(challengeReference, {
          consumed: true,
          verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          codeHash: admin.firestore.FieldValue.delete(),
        });
        return { phoneNumber: String(challenge.phoneNumber || '') };
      }
    );
    if (verification.errorCode) {
      throw new HttpsError(
        verification.errorCode,
        verification.errorMessage
      );
    }
    const phoneNumber = verification.phoneNumber;
    if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
      throw new HttpsError('internal', 'Invalid phone number on record.');
    }
    const userId = userDocumentIdForPhone(phoneNumber);
    const customToken = await admin.auth().createCustomToken(userId, {
      phoneNumber,
      verificationProvider: 'green_api',
    });
    return { customToken, phoneNumber };
  }
);

exports.registerWithGreenApiAndPassword = onCall(
  { secrets: [greenApiToken] },
  async (request) => {
    const challengeId = String(request.data?.challengeId || '').trim();
    const code = String(request.data?.code || '').trim();
    const password = String(request.data?.password || '');
    if (
      !/^[a-f0-9]{64}$/.test(challengeId) ||
      !/^\d{6}$/.test(code) ||
      password.length < 8
    ) {
      throw new HttpsError(
        'invalid-argument',
        'Enter the 6-digit code and a strong password (min 8 characters).'
      );
    }

    const challengeReference = admin
      .firestore()
      .collection('greenApiLoginChallenges')
      .doc(challengeId);
    const verification = await admin.firestore().runTransaction(
      async (transaction) => {
        const snapshot = await transaction.get(challengeReference);
        const challenge = snapshot.data();
        if (!snapshot.exists || !challenge) {
          return {
            errorCode: 'not-found',
            errorMessage:
              'This WhatsApp verification request no longer exists.',
          };
        }
        if (
          challenge.consumed === true ||
          Date.now() > Number(challenge.expiresAtMillis || 0)
        ) {
          return {
            errorCode: 'deadline-exceeded',
            errorMessage: 'The WhatsApp verification code has expired.',
          };
        }
        const attemptsRemaining = Number(challenge.attemptsRemaining || 0);
        if (attemptsRemaining <= 0) {
          return {
            errorCode: 'permission-denied',
            errorMessage: 'Too many incorrect attempts. Request a new code.',
          };
        }

        const expected = Buffer.from(String(challenge.codeHash || ''), 'hex');
        const candidateHash = crypto
          .createHmac('sha256', greenApiToken.value())
          .update(`${challengeId}:${code}`)
          .digest();
        const matches =
          expected.length === candidateHash.length &&
          crypto.timingSafeEqual(expected, candidateHash);
        if (!matches) {
          transaction.update(challengeReference, {
            attemptsRemaining: attemptsRemaining - 1,
          });
          return {
            errorCode: 'permission-denied',
            errorMessage: 'The WhatsApp verification code is incorrect.',
          };
        }

        transaction.update(challengeReference, {
          consumed: true,
          verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          codeHash: admin.firestore.FieldValue.delete(),
        });
        return { phoneNumber: String(challenge.phoneNumber || '') };
      }
    );
    if (verification.errorCode) {
      throw new HttpsError(
        verification.errorCode,
        verification.errorMessage
      );
    }
    const phoneNumber = verification.phoneNumber;
    if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
      throw new HttpsError('internal', 'Invalid phone number on record.');
    }

    const userId = userDocumentIdForPhone(phoneNumber);
    const passwordHash = await argon2.hash(password, {
      type: argon2.argon2id,
    });

    const now = new Date();
    await admin
      .firestore()
      .collection('users')
      .doc(userId)
      .set(
        {
          phoneNumber,
          passwordHash,
          requiresOnboarding: true,
          profileSetupCompleted: false,
          onboardingVersion: 1,
          firebaseUid: userId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAtLocal: now.toISOString(),
          lastSignedInAt: admin.firestore.FieldValue.serverTimestamp(),
          lastSignedInAtLocal: now.toISOString(),
        },
        { merge: true }
      );

    const customToken = await admin.auth().createCustomToken(userId, {
      phoneNumber,
      verificationProvider: 'green_api_password',
    });
    return { customToken, phoneNumber };
  }
);

const SAFETY_QUESTIONS = [
  "What is the name of your first pet?",
  "What city were you born in?",
  "What is your mother's maiden name?",
  "What was the name of your first school?",
  "What is your favorite book?",
  "What is the name of your best childhood friend?",
  "What was the make and model of your first car?",
  "What is the name of the street you grew up on?",
  "What is your favorite food?",
  "What year did you graduate high school?",
  "What is the name of your favorite teacher?",
  "What is your dream travel destination?",
  "What is your favorite movie?",
  "What is your favourite colour?",
  "What is your father's middle name?",
];

exports.registerSafetyQuestions = onCall(
  { secrets: [] },
  async (request) => {
    const phoneNumber = String(request.auth?.token?.phoneNumber || '');
    if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
      throw new HttpsError(
        'unauthenticated',
        'You must be signed in to set safety questions.'
      );
    }

    const q1 = String(request.data?.q1 || '').trim();
    const a1 = String(request.data?.a1 || '');
    const q2 = String(request.data?.q2 || '').trim();
    const a2 = String(request.data?.a2 || '');

    if (!SAFETY_QUESTIONS.includes(q1) || !SAFETY_QUESTIONS.includes(q2) || q1 === q2) {
      throw new HttpsError(
        'invalid-argument',
        'Select two different safety questions from the list.'
      );
    }
    if (a1.length < 2 || a2.length < 2) {
      throw new HttpsError(
        'invalid-argument',
        'Each answer must be at least 2 characters.'
      );
    }

    const userId = userDocumentIdForPhone(phoneNumber);
    const a1Hash = await argon2.hash(a1.toLowerCase(), { type: argon2.argon2id });
    const a2Hash = await argon2.hash(a2.toLowerCase(), { type: argon2.argon2id });

    await admin
      .firestore()
      .collection('users')
      .doc(userId)
      .set(
        {
          safetyQuestions: {
            q1,
            a1Hash,
            q2,
            a2Hash,
          },
        },
        { merge: true }
      );

    return { success: true };
  }
);

exports.sendPasswordResetCode = onCall(
  { secrets: [greenApiInstanceId, greenApiToken] },
  async (request) => {
    const phoneNumber = String(request.data?.phoneNumber || '').trim();
    if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
      throw new HttpsError(
        'invalid-argument',
        'Enter a valid international phone number.'
      );
    }

    const userId = userDocumentIdForPhone(phoneNumber);
    try {
      await admin.auth().getUser(userId);
    } catch (authError) {
      if (authError.code === 'auth/user-not-found') {
        throw new HttpsError(
          'not-found',
          'This phone number is not registered in the system.'
        );
      }
      throw new HttpsError(
        'internal',
        'Unable to verify account. Please try again.'
      );
    }

    const userSnapshot = await admin
      .firestore()
      .collection('users')
      .doc(userId)
      .get();
    const user = userSnapshot.data() || {};
    if (!user.passwordHash) {
      throw new HttpsError(
        'failed-precondition',
        'This account does not have a password set.'
      );
    }
    if (user.accountDisabled === true || user.status === 'disabled') {
      throw new HttpsError(
        'permission-denied',
        'This HikerCircle account has been disabled.'
      );
    }

    const challengeId = crypto
      .createHash('sha256')
      .update(`reset_${phoneNumber}`)
      .digest('hex');
    const challengeReference = admin
      .firestore()
      .collection('passwordResetChallenges')
      .doc(challengeId);
    const previousChallenge = await challengeReference.get();
    const previous = previousChallenge.data() || {};
    const previousSentAt = Number(previous.sentAtMillis || 0);
    if (Date.now() - previousSentAt < 60 * 1000) {
      throw new HttpsError(
        'resource-exhausted',
        'Wait one minute before requesting another code.'
      );
    }

    const code = crypto.randomInt(0, 1000000).toString().padStart(6, '0');
    const expiresAtMillis = Date.now() + 5 * 60 * 1000;
    const instanceId = greenApiInstanceId.value();
    const token = greenApiToken.value();
    const digitsOnly = phoneNumber.replace(/\D/g, '');
    const response = await fetch(
      `https://api.green-api.com/waInstance${instanceId}/sendMessage/${token}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          chatId: `${digitsOnly}@c.us`,
          message:
            `Your HikerCircle password reset code is ${code}. ` +
            'It expires in 5 minutes.',
        }),
      }
    );
    if (!response.ok) {
      logger.error('GreenAPI password reset message failed', {
        status: response.status,
        challengeId,
      });
      throw new HttpsError(
        'unavailable',
        'WhatsApp verification is temporarily unavailable.'
      );
    }

    const codeHash = crypto
      .createHmac('sha256', greenApiToken.value())
      .update(`${challengeId}:${code}`)
      .digest('hex');

    await challengeReference.set({
      phoneNumber,
      codeHash,
      attemptsRemaining: 5,
      consumed: false,
      sentAtMillis: Date.now(),
      expiresAtMillis,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { challengeId, expiresAtMillis };
  }
);

exports.verifyPasswordResetOtp = onCall(
  { secrets: [greenApiToken] },
  async (request) => {
    const challengeId = String(request.data?.challengeId || '').trim();
    const code = String(request.data?.code || '').trim();
    if (!/^[a-f0-9]{64}$/.test(challengeId) || !/^\d{6}$/.test(code)) {
      throw new HttpsError('invalid-argument', 'Enter the 6-digit code.');
    }

    const challengeReference = admin
      .firestore()
      .collection('passwordResetChallenges')
      .doc(challengeId);
    const verification = await admin.firestore().runTransaction(
      async (transaction) => {
        const snapshot = await transaction.get(challengeReference);
        const challenge = snapshot.data();
        if (!snapshot.exists || !challenge) {
          return {
            errorCode: 'not-found',
            errorMessage: 'This verification request no longer exists.',
          };
        }
        if (
          challenge.consumed === true ||
          Date.now() > Number(challenge.expiresAtMillis || 0)
        ) {
          return {
            errorCode: 'deadline-exceeded',
            errorMessage: 'The verification code has expired.',
          };
        }
        const attemptsRemaining = Number(challenge.attemptsRemaining || 0);
        if (attemptsRemaining <= 0) {
          return {
            errorCode: 'permission-denied',
            errorMessage: 'Too many incorrect attempts. Request a new code.',
          };
        }

        const expected = Buffer.from(String(challenge.codeHash || ''), 'hex');
        const candidateHash = crypto
          .createHmac('sha256', greenApiToken.value())
          .update(`${challengeId}:${code}`)
          .digest();
        const matches =
          expected.length === candidateHash.length &&
          crypto.timingSafeEqual(expected, candidateHash);
        if (!matches) {
          transaction.update(challengeReference, {
            attemptsRemaining: attemptsRemaining - 1,
          });
          return {
            errorCode: 'permission-denied',
            errorMessage: 'The verification code is incorrect.',
          };
        }

        transaction.update(challengeReference, {
          consumed: true,
          verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          codeHash: admin.firestore.FieldValue.delete(),
        });
        return { phoneNumber: String(challenge.phoneNumber || '') };
      }
    );
    if (verification.errorCode) {
      throw new HttpsError(
        verification.errorCode,
        verification.errorMessage
      );
    }
    const phoneNumber = verification.phoneNumber;
    if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
      throw new HttpsError('internal', 'Invalid phone number on record.');
    }

    const userId = userDocumentIdForPhone(phoneNumber);
    const userSnapshot = await admin
      .firestore()
      .collection('users')
      .doc(userId)
      .get();
    const user = userSnapshot.data() || {};
    const questions = user.safetyQuestions;
    const hasQuestions =
      questions && questions.q1 && questions.q2 && questions.a1Hash && questions.a2Hash;

    let questionField = null;
    let questionText = null;
    if (hasQuestions) {
      const fields = ['q1', 'q2'];
      const shuffled = fields.sort(() => Math.random() - 0.5);
      const chosenField = shuffled[0];
      questionField = chosenField;
      questionText = questions[chosenField];
    }

    const resetToken = crypto.randomBytes(32).toString('hex');
    const resetExpiresAt = Date.now() + 10 * 60 * 1000;
    await admin
      .firestore()
      .collection('passwordResetSessions')
      .doc(resetToken)
      .set({
        phoneNumber,
        challengeId,
        verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        used: false,
        expiresAtMillis: resetExpiresAt,
        safetyQuestionField: questionField,
        skipQuestion: !hasQuestions,
        attemptsRemaining: 3,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    return {
      resetToken,
      questionField,
      questionText,
      skipQuestion: !hasQuestions,
      expiresAtMillis: resetExpiresAt,
    };
  }
);

exports.checkSafetyAnswer = onCall(
  { secrets: [] },
  async (request) => {
    const resetToken = String(request.data?.resetToken || '').trim();
    const answer = String(request.data?.answer || '');

    if (resetToken.length < 10) {
      throw new HttpsError('invalid-argument', 'Invalid reset token.');
    }
    if (!answer || answer.length < 2) {
      throw new HttpsError('invalid-argument', 'Please enter your safety answer.');
    }

    const sessionRef = admin
      .firestore()
      .collection('passwordResetSessions')
      .doc(resetToken);
    const result = await admin.firestore().runTransaction(async (transaction) => {
      const snapshot = await transaction.get(sessionRef);
      const session = snapshot.data();
      if (!snapshot.exists || !session) {
        return { errorCode: 'not-found', errorMessage: 'Reset session not found. Start the password reset again.' };
      }
      if (session.used === true) {
        return { errorCode: 'already-exists', errorMessage: 'This reset session has already been used.' };
      }
      if (Date.now() > Number(session.expiresAtMillis || 0)) {
        return { errorCode: 'deadline-exceeded', errorMessage: 'The reset session has expired. Start again.' };
      }
      if (session.skipQuestion === true) {
        return { valid: true };
      }

      const phoneNumber = String(session.phoneNumber || '');
      const userId = userDocumentIdForPhone(phoneNumber);
      const userSnapshot = await transaction.get(
        admin.firestore().collection('users').doc(userId)
      );
      const user = userSnapshot.data() || {};
      const questions = user.safetyQuestions;
      if (!questions) {
        return { errorCode: 'failed-precondition', errorMessage: 'Safety questions not found.' };
      }

      const questionField = String(session.safetyQuestionField || 'q1');
      const answerField = questionField === 'q1' ? 'a1Hash' : 'a2Hash';
      const storedHash = questions[answerField];

      if (!storedHash) {
        return { errorCode: 'failed-precondition', errorMessage: 'Safety question data is corrupted.' };
      }

      let answerValid;
      try {
        answerValid = await argon2.verify(storedHash, answer.toLowerCase());
      } catch (_) {
        return { errorCode: 'internal', errorMessage: 'Answer verification failed. Try again.' };
      }
      if (!answerValid) {
        const remaining = Number(session.attemptsRemaining || 0) - 1;
        if (remaining <= 0) {
          transaction.update(sessionRef, { used: true, attemptsRemaining: 0 });
          return { errorCode: 'permission-denied', errorMessage: 'Too many incorrect answers. Start the password reset again.' };
        }
        transaction.update(sessionRef, { attemptsRemaining: remaining });
        return { errorCode: 'permission-denied', errorMessage: 'The answer is incorrect.' };
      }

      return { valid: true };
    });

    if (result.errorCode) {
      throw new HttpsError(result.errorCode, result.errorMessage);
    }
    return { valid: true };
  }
);

exports.resetPassword = onCall(
  { secrets: [] },
  async (request) => {
    const resetToken = String(request.data?.resetToken || '').trim();
    const answer = String(request.data?.answer || '');
    const newPassword = String(request.data?.newPassword || '');

    if (resetToken.length < 10) {
      throw new HttpsError('invalid-argument', 'Invalid reset token.');
    }
    if (newPassword.length < 8) {
      throw new HttpsError('invalid-argument', 'New password must be at least 8 characters.');
    }

    const sessionRef = admin
      .firestore()
      .collection('passwordResetSessions')
      .doc(resetToken);
    const result = await admin.firestore().runTransaction(async (transaction) => {
      const snapshot = await transaction.get(sessionRef);
      const session = snapshot.data();
      if (!snapshot.exists || !session) {
        return { errorCode: 'not-found', errorMessage: 'Reset session not found. Start the password reset again.' };
      }
      if (session.used === true) {
        return { errorCode: 'already-exists', errorMessage: 'This reset session has already been used.' };
      }
      if (Date.now() > Number(session.expiresAtMillis || 0)) {
        return { errorCode: 'deadline-exceeded', errorMessage: 'The reset session has expired. Start again.' };
      }

      const phoneNumber = String(session.phoneNumber || '');
      const userId = userDocumentIdForPhone(phoneNumber);

      if (!session.skipQuestion) {
        if (!answer || answer.length < 2) {
          return { errorCode: 'invalid-argument', errorMessage: 'Answer must be at least 2 characters.' };
        }
        const userSnapshot = await transaction.get(
          admin.firestore().collection('users').doc(userId)
        );
        const user = userSnapshot.data() || {};
        const questions = user.safetyQuestions;
        if (!questions) {
          return { errorCode: 'failed-precondition', errorMessage: 'Safety questions not found.' };
        }

        const questionField = String(session.safetyQuestionField || 'q1');
        const answerField = questionField === 'q1' ? 'a1Hash' : 'a2Hash';
        const storedHash = questions[answerField];

        if (!storedHash) {
          return { errorCode: 'failed-precondition', errorMessage: 'Safety question data is corrupted.' };
        }

        let answerValid;
        try {
          answerValid = await argon2.verify(storedHash, answer.toLowerCase());
        } catch (_) {
          return { errorCode: 'internal', errorMessage: 'Answer verification failed. Try again.' };
        }
        if (!answerValid) {
          const remaining = Number(session.attemptsRemaining || 0) - 1;
          if (remaining <= 0) {
            transaction.update(sessionRef, { used: true, attemptsRemaining: 0 });
            return { errorCode: 'permission-denied', errorMessage: 'Too many incorrect answers. Start the password reset again.' };
          }
          transaction.update(sessionRef, { attemptsRemaining: remaining });
          return { errorCode: 'permission-denied', errorMessage: 'The answer is incorrect.' };
        }
      }

      const passwordHash = await argon2.hash(newPassword, { type: argon2.argon2id });
      transaction.update(
        admin.firestore().collection('users').doc(userId),
        { passwordHash }
      );
      transaction.update(sessionRef, { used: true });
      return { success: true };
    });

    if (result.errorCode) {
      throw new HttpsError(result.errorCode, result.errorMessage);
    }
    return { success: true };
  }
);

exports.loginWithPassword = onCall(async (request) => {
  const phoneNumber = String(request.data?.phoneNumber || '').trim();
  if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
    throw new HttpsError(
      'invalid-argument',
      'Enter a valid international phone number.'
    );
  }
  const password = String(request.data?.password || '');
  if (!password) {
    throw new HttpsError('invalid-argument', 'Enter your password.');
  }

  const userId = userDocumentIdForPhone(phoneNumber);
  const userRef = admin.firestore().collection('users').doc(userId);

  const now = new Date();
  const cooldownResult = await admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(userRef);
    if (!snapshot.exists) {
      return { errorCode: 'not-found', errorMessage: 'No account found with this phone number. Please sign up first.' };
    }
    const user = snapshot.data() || {};

    // Check cooldown
    const cooldownUntil = user.loginCooldownUntil;
    if (cooldownUntil) {
      const cooldownMillis =
        typeof cooldownUntil.toDate === 'function'
          ? cooldownUntil.toDate().getTime()
          : Date.parse(String(cooldownUntil));
      if (Number.isFinite(cooldownMillis) && cooldownMillis > now.getTime()) {
        const expiryDate = new Date(cooldownMillis);
        const day = String(expiryDate.getDate()).padStart(2, '0');
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        const month = months[expiryDate.getMonth()];
        const year = expiryDate.getFullYear();
        const hours = expiryDate.getHours();
        const minutes = String(expiryDate.getMinutes()).padStart(2, '0');
        const ampm = hours >= 12 ? 'PM' : 'AM';
        const hour12 = hours % 12 || 12;
        const formatted = `${day} ${month} ${year}, ${hour12}:${minutes} ${ampm}`;
        return {
          errorCode: 'resource-exhausted',
          errorMessage: `Login is temporary disabled as there are too many attempts at ${formatted}. Please retry later.`,
          cooldownExpiresAtMillis: cooldownMillis,
        };
      }
    }

    // Check account
    if (user.accountDisabled === true || user.status === 'disabled') {
      return { errorCode: 'permission-denied', errorMessage: 'This HikerCircle account has been disabled.' };
    }

    const storedHash = user.passwordHash;
    if (!storedHash) {
      return { errorCode: 'unauthenticated', errorMessage: 'This account does not have a password set. Please sign up via GreenAPI.' };
    }

    let passwordValid;
    try {
      passwordValid = await argon2.verify(storedHash, password);
    } catch (_) {
      return { errorCode: 'internal', errorMessage: 'Password verification failed. Please try again.' };
    }

    if (!passwordValid) {
      const attempts = (user.loginFailedAttempts || 0) + 1;
      const updates = { loginFailedAttempts: attempts };
      if (attempts >= 5) {
        const cooldownUntilDate = new Date(now.getTime() + 30 * 60 * 1000);
        updates.loginCooldownUntil = cooldownUntilDate;
        updates.loginFailedAttempts = 0;
      }
      transaction.update(userRef, updates);
      return { errorCode: 'permission-denied', errorMessage: 'The password is incorrect.' };
    }

    // Success: reset attempts
    transaction.update(userRef, {
      loginFailedAttempts: 0,
      loginCooldownUntil: admin.firestore.FieldValue.delete(),
      lastSignedInAt: admin.firestore.FieldValue.serverTimestamp(),
      lastSignedInAtLocal: now.toISOString(),
    });
    return { success: true, user };
  });

  if (cooldownResult.errorCode) {
    throw new HttpsError(cooldownResult.errorCode, cooldownResult.errorMessage);
  }

  const user = cooldownResult.user;
  const isAdmin = isAdminUser(user);
  const customToken = await admin.auth().createCustomToken(userId, {
    phoneNumber,
    isAdmin,
    verificationProvider: 'password',
  });
  return { customToken, phoneNumber };
});

exports.linkPasswordToAccount = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError(
      'unauthenticated',
      'You must be signed in to set a password.'
    );
  }
  const phoneNumber = String(request.auth?.token?.phoneNumber || '');
  if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber)) {
    throw new HttpsError(
      'unauthenticated',
      'No verified phone number found. Sign in again.'
    );
  }
  const password = String(request.data?.password || '');
  const username = String(request.data?.username || '').trim();
  if (password.length < 8) {
    throw new HttpsError(
      'invalid-argument',
      'Password must be at least 8 characters.'
    );
  }
  if (!username || username.length < 3) {
    throw new HttpsError(
      'invalid-argument',
      'Username must be at least 3 characters.'
    );
  }

  const userId = userDocumentIdForPhone(phoneNumber);
  const passwordHash = await argon2.hash(password, {
    type: argon2.argon2id,
  });

  const now = new Date();
  await admin
    .firestore()
    .collection('users')
    .doc(userId)
    .set(
      {
        phoneNumber,
        passwordHash,
        username,
        requiresOnboarding: true,
        profileSetupCompleted: false,
        onboardingVersion: 1,
        firebaseUid: userId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAtLocal: now.toISOString(),
        lastSignedInAt: admin.firestore.FieldValue.serverTimestamp(),
        lastSignedInAtLocal: now.toISOString(),
      },
      { merge: true }
    );

  const customToken = await admin.auth().createCustomToken(userId, {
    phoneNumber,
    username,
    verificationProvider: 'green_api_password',
  });
  return { customToken, phoneNumber };
});

exports.authenticateAppSession = onCall(async (request) => {
  const phoneNumber = String(request.data?.phoneNumber || '').trim();
  const appInstanceId = String(request.data?.appInstanceId || '').trim();
  if (!/^\+[1-9]\d{7,14}$/.test(phoneNumber) || appInstanceId.length < 20) {
    throw new HttpsError(
      'invalid-argument',
      'The saved HikerCircle credentials are invalid.'
    );
  }

  const userId = userDocumentIdForPhone(phoneNumber);
  const userDocument = await admin
    .firestore()
    .collection('users')
    .doc(userId)
    .get();
  if (!userDocument.exists) {
    throw new HttpsError(
      'unauthenticated',
      'This HikerCircle account no longer exists.'
    );
  }

  const user = userDocument.data() || {};
  const boundAppInstanceId = String(user.boundAppInstanceId || '');
  if (!boundAppInstanceId || boundAppInstanceId !== appInstanceId) {
    throw new HttpsError(
      'permission-denied',
      'This account is bound to another device. Sign in again.'
    );
  }
  if (user.accountDisabled === true || user.status === 'disabled') {
    throw new HttpsError(
      'permission-denied',
      'This HikerCircle account has been disabled.'
    );
  }

  const isAdmin = isAdminUser(user);
  const customToken = await admin.auth().createCustomToken(userId, {
    phoneNumber,
    isAdmin,
    appInstanceId,
  });
  await userDocument.ref.set(
    {
      firebaseUid: userId,
      lastFirebaseAuthenticatedAt:
        admin.firestore.FieldValue.serverTimestamp(),
      lastFirebaseAuthenticatedAtLocal: new Date().toISOString(),
    },
    { merge: true }
  );
  return { customToken, userId };
});

// ─── Weather ────────────────────────────────────────────────────

const WMO_MAP = {
  0: 'Clear sky',
  1: 'Mainly clear',
  2: 'Partly cloudy',
  3: 'Overcast',
  45: 'Foggy',
  48: 'Depositing rime fog',
  51: 'Light drizzle',
  53: 'Moderate drizzle',
  55: 'Dense drizzle',
  56: 'Light freezing drizzle',
  57: 'Dense freezing drizzle',
  61: 'Slight rain',
  63: 'Moderate rain',
  65: 'Heavy rain',
  66: 'Light freezing rain',
  67: 'Heavy freezing rain',
  71: 'Slight snow',
  73: 'Moderate snow',
  75: 'Heavy snow',
  77: 'Snow grains',
  80: 'Slight rain showers',
  81: 'Moderate rain showers',
  82: 'Violent rain showers',
  85: 'Slight snow showers',
  86: 'Heavy snow showers',
  95: 'Thunderstorm',
  96: 'Thunderstorm with slight hail',
  99: 'Thunderstorm with heavy hail',
};

function wmoSummary(code) {
  return WMO_MAP[code] || 'Unknown';
}

exports.fetchWeatherForAllTrails = onSchedule(
  'every 60 minutes',
  async (event) => {
    const db = admin.firestore();
    const trailsSnapshot = await db.collection('trails').get();

    if (trailsSnapshot.empty) {
      logger.log('No trails found.');
      return;
    }

    const batch = db.batch();
    let updatedCount = 0;

    for (const doc of trailsSnapshot.docs) {
      const data = doc.data();
      const latitude = data.latitude;
      const longitude = data.longitude;

      if (typeof latitude !== 'number' || typeof longitude !== 'number') {
        continue;
      }

      try {
        const url = new URL('https://api.open-meteo.com/v1/forecast');
        url.searchParams.set('latitude', latitude.toFixed(4));
        url.searchParams.set('longitude', longitude.toFixed(4));
        url.searchParams.set(
          'current',
          'temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,uv_index'
        );
        url.searchParams.set(
          'daily',
          'temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code'
        );
        url.searchParams.set(
          'hourly',
          'temperature_2m,precipitation_probability,weather_code'
        );
        url.searchParams.set('timezone', 'auto');
        url.searchParams.set('forecast_hours', '12');

        const response = await fetch(url.toString());
        if (!response.ok) {
          logger.warn(
            `OpenMeteo ${response.status} for trail ${doc.id}`
          );
          continue;
        }

        const body = await response.json();
        const weather = buildWeatherFromApi(body);

        batch.update(doc.ref, { weather });
        updatedCount++;
      } catch (error) {
        logger.error(`Failed to fetch weather for trail ${doc.id}:`, error);
      }
    }

    if (updatedCount > 0) {
      await batch.commit();
    }

    logger.log(`Updated weather for ${updatedCount} trails.`);
  }
);

function buildWeatherFromApi(body) {
  const current = body.current || {};
  const daily = body.daily || {};
  const hourly = body.hourly || {};

  const currentTemp = current.temperature_2m;
  const currentCode = current.weather_code || 0;
  const tempMax = Array.isArray(daily.temperature_2m_max)
    ? daily.temperature_2m_max[0]
    : currentTemp;
  const tempMin = Array.isArray(daily.temperature_2m_min)
    ? daily.temperature_2m_min[0]
    : currentTemp;
  const precipProb = Array.isArray(daily.precipitation_probability_max)
    ? daily.precipitation_probability_max[0]
    : 0;
  const dailyCodes = Array.isArray(daily.weather_code)
    ? daily.weather_code[0]
    : currentCode;

  const maxTemp = typeof tempMax === 'number' ? tempMax : 0;
  const minTemp = typeof tempMin === 'number' ? tempMin : 0;
  const dailyCode = typeof dailyCodes === 'number' ? dailyCodes : 0;
  const rainProb =
    typeof precipProb === 'number'
      ? Math.max(0, Math.min(100, Math.round(precipProb)))
      : 0;

  const now = new Date();
  const hourlyTimes = hourly.time || [];
  const hourlyTemps = hourly.temperature_2m || [];
  const hourlyCodes = hourly.weather_code || [];
  const hourlyPrecipProbs = hourly.precipitation_probability || [];
  const hourlyForecast = [];
  let started = false;

  for (let i = 0; i < hourlyTimes.length && hourlyForecast.length < 24; i++) {
    const timeStr = hourlyTimes[i];
    const temp = hourlyTemps[i];
    const code = hourlyCodes[i];

    if (typeof timeStr !== 'string' || typeof temp !== 'number' || typeof code !== 'number') {
      continue;
    }

    const time = new Date(timeStr);
    if (isNaN(time.getTime())) continue;

    if (!started) {
      if (time <= now) continue;
      started = true;
    }

    const precip =
      Array.isArray(hourlyPrecipProbs) && i < hourlyPrecipProbs.length
        ? hourlyPrecipProbs[i]
        : 0;

    hourlyForecast.push({
      timeLocal: time.toISOString(),
      temperature: temp,
      precipitationProbability:
        typeof precip === 'number'
          ? Math.max(0, Math.min(100, Math.round(precip)))
          : 0,
      weatherCode: code,
    });
  }

  return {
    summary: wmoSummary(dailyCode),
    temperatureRange: `${Math.round(minTemp)} °C - ${Math.round(maxTemp)} °C`,
    rainProbability: rainProb,
    cachedAtLocal: new Date().toISOString(),
    humidity:
      typeof current.relative_humidity_2m === 'number'
        ? current.relative_humidity_2m
        : null,
    windSpeed:
      typeof current.wind_speed_10m === 'number'
        ? current.wind_speed_10m
        : null,
    uvIndex:
      typeof current.uv_index === 'number' ? current.uv_index : null,
    feelsLike:
      typeof current.apparent_temperature === 'number'
        ? current.apparent_temperature
        : null,
    hourlyForecast:
      hourlyForecast.length > 0 ? hourlyForecast : null,
  };
}

exports.fetchWeatherForTrail = onCall(
  { secrets: [] },
  async (request) => {
    const { trailId } = request.data;
    if (!trailId || typeof trailId !== 'string') {
      throw new Error('trailId must be a non-empty string');
    }

    const db = admin.firestore();
    const doc = await db.collection('trails').doc(trailId).get();

    if (!doc.exists) {
      throw new Error(`Trail ${trailId} not found`);
    }

    const data = doc.data();
    const latitude = data.latitude;
    const longitude = data.longitude;

    if (typeof latitude !== 'number' || typeof longitude !== 'number') {
      throw new Error(`Trail ${trailId} has no valid coordinates`);
    }

    const url = new URL('https://api.open-meteo.com/v1/forecast');
    url.searchParams.set('latitude', latitude.toFixed(4));
    url.searchParams.set('longitude', longitude.toFixed(4));
    url.searchParams.set(
      'current',
      'temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,uv_index'
    );
    url.searchParams.set(
      'daily',
      'temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code'
    );
    url.searchParams.set(
      'hourly',
      'temperature_2m,precipitation_probability,weather_code'
    );
    url.searchParams.set('timezone', 'auto');
    url.searchParams.set('forecast_hours', '12');

    const response = await fetch(url.toString());
    if (!response.ok) {
      throw new Error(`OpenMeteo returned ${response.status}`);
    }

    const body = await response.json();
    const weather = buildWeatherFromApi(body);

    await db.collection('trails').doc(trailId).update({ weather });

    logger.log(`Fetched and saved weather for trail ${trailId}`);

    return { weather };
  }
);

// ─── Notifications ──────────────────────────────────────────────

async function sendActiveHikeReopenReminder(
  sessionRef,
  sessionData,
  reason
) {
  const token = sessionData.monitoringFcmToken;
  if (!token || typeof token !== 'string') {
    logger.warn(`No FCM token for active hike ${sessionRef.id}.`);
    return false;
  }

  const lastReminder = sessionData.lastMonitoringReminderAt;
  if (
    lastReminder &&
    typeof lastReminder.toDate === 'function' &&
    Date.now() - lastReminder.toDate().getTime() < 10 * 60 * 1000
  ) {
    return false;
  }

  try {
    await admin.messaging().send({
      token,
      notification: {
        title: 'Hike monitoring stopped',
        body:
          'Reopen HikerCircle and leave it running in the background to continue hike monitoring.',
      },
      data: {
        type: 'active_hike_monitoring_stopped',
        sessionId: sessionRef.id,
        deepLink: `hikercircle://hike/active?sessionId=${encodeURIComponent(
          sessionRef.id
        )}`,
        reason,
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'hiker_circle_active_hike',
          priority: 'high',
        },
      },
      apns: {
        headers: {
          'apns-priority': '10',
        },
        payload: {
          aps: {
            sound: 'default',
          },
        },
      },
    });
    await sessionRef.set(
      {
        lastMonitoringReminderAt:
          admin.firestore.FieldValue.serverTimestamp(),
        lastMonitoringReminderAtLocal: new Date().toISOString(),
        lastMonitoringReminderReason: reason,
      },
      { merge: true }
    );
    return true;
  } catch (error) {
    logger.error(
      `Unable to send active hike reminder for ${sessionRef.id}:`,
      error
    );
    return false;
  }
}

function distanceKm(firstLatitude, firstLongitude, secondLatitude, secondLongitude) {
  const radians = (degrees) => (degrees * Math.PI) / 180;
  const latitudeDelta = radians(secondLatitude - firstLatitude);
  const longitudeDelta = radians(secondLongitude - firstLongitude);
  const firstLatitudeRadians = radians(firstLatitude);
  const secondLatitudeRadians = radians(secondLatitude);
  const value =
    Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(firstLatitudeRadians) *
      Math.cos(secondLatitudeRadians) *
      Math.sin(longitudeDelta / 2) ** 2;
  return 6371 * 2 * Math.asin(Math.sqrt(value));
}

function dateMillis(value) {
  if (value && typeof value.toDate === 'function') {
    return value.toDate().getTime();
  }
  if (typeof value === 'string') {
    return Date.parse(value);
  }
  if (typeof value === 'number') {
    return value;
  }
  return Number.NaN;
}

function groupChatMessagePreview(message) {
  const text = String(message.text || '').replace(/\s+/g, ' ').trim();
  if (text) {
    return text.length > 120 ? `${text.slice(0, 117)}...` : text;
  }
  const type = String(message.attachment?.type || '');
  if (type === 'image') {
    return 'Photo';
  }
  if (type === 'video') {
    return 'Video';
  }
  if (type === 'document') {
    return 'Document';
  }
  return 'New message';
}

exports.notifyGroupMembersAboutMessage = onDocumentCreated(
  'groupChats/{chatId}/messages/{messageId}',
  async (event) => {
    const message = event.data.data() || {};
    if (message.isSystemMessage === true) {
      return;
    }

    const chatReference = event.data.ref.parent.parent;
    if (!chatReference) {
      return;
    }
    const chatSnapshot = await chatReference.get();
    const chat = chatSnapshot.data() || {};
    const senderPhone = String(message.senderPhone || '');
    const senderPhoneDigits = senderPhone.replace(/\D/g, '');
    const participantPhones = [
      ...new Set(
        (Array.isArray(chat.participantPhones)
          ? chat.participantPhones
          : []
        )
          .map((phone) => String(phone || ''))
          .filter((phone) => {
            if (!phone) return false;
            if (phone.replace(/\D/g, '') === senderPhoneDigits) return false;
            return true;
          })
      ),
    ];
    if (participantPhones.length === 0) {
      return;
    }

    const db = admin.firestore();
    const userReferences = participantPhones.map((phone) =>
      db.collection('users').doc(phone.replace(/\//g, '_'))
    );
    const userSnapshots = await db.getAll(...userReferences);
    const tokens = new Set();
    let eligibleUsers = 0;
    const now = Date.now();

    for (const userSnapshot of userSnapshots) {
      if (!userSnapshot.exists) {
        continue;
      }
      const user = userSnapshot.data() || {};
      if (user.groupChatNotificationsEnabled === false) {
        continue;
      }
      const mutedChats =
        user.groupChatMutedUntil &&
        typeof user.groupChatMutedUntil === 'object'
          ? user.groupChatMutedUntil
          : {};
      const mutedUntil = dateMillis(mutedChats[event.params.chatId]);
      if (Number.isFinite(mutedUntil) && mutedUntil > now) {
        continue;
      }

      const boundAppInstanceId = user.boundAppInstanceId ||
        user.currentAppId || null;
      const fcmTokenByAppId = user.fcmTokenByAppId || {};
      const hasAppTokenMap = typeof user.fcmTokenByAppId === 'object' &&
        user.fcmTokenByAppId !== null &&
        Object.keys(user.fcmTokenByAppId).length > 0;
      const userTokens = new Set();
      if (hasAppTokenMap) {
        if (boundAppInstanceId && fcmTokenByAppId[boundAppInstanceId]) {
          userTokens.add(fcmTokenByAppId[boundAppInstanceId]);
        }
      } else {
        if (Array.isArray(user.fcmTokens)) {
          for (const t of user.fcmTokens) {
            if (typeof t === 'string') userTokens.add(t);
          }
        }
        if (typeof user.lastFcmToken === 'string' && user.lastFcmToken) {
          userTokens.add(user.lastFcmToken);
        }
      }
      const validTokens = [...userTokens].filter(
        (token) => typeof token === 'string' && token.length > 20
      );
      if (validTokens.length === 0) {
        continue;
      }
      eligibleUsers++;
      for (const token of validTokens) {
        tokens.add(token);
      }
    }

    const tokenList = [...tokens];
    const deepLink =
      `hikercircle://group-chat/view?chatId=` +
      encodeURIComponent(event.params.chatId);
    let successCount = 0;
    let failureCount = 0;
    for (let index = 0; index < tokenList.length; index += 500) {
      const response = await admin.messaging().sendEachForMulticast({
        tokens: tokenList.slice(index, index + 500),
        notification: {
          title:
            chat.chatType === 'direct'
              ? String(message.senderName || 'New private message')
              : `${message.senderName || 'A hiker'} - ${
                  chat.trailName || 'Group chat'
                }`,
          body: groupChatMessagePreview(message),
        },
        data: {
          type: 'group_chat_message',
          chatId: event.params.chatId,
          messageId: event.params.messageId,
          deepLink,
        },
        android: {
          priority: 'high',
          notification: {
            priority: 'high',
          },
        },
        apns: {
          headers: {
            'apns-priority': '10',
          },
          payload: {
            aps: {
              sound: 'default',
            },
          },
        },
      });
      successCount += response.successCount;
      failureCount += response.failureCount;
    }

    // Fallback: ensure chat document has lastMessage metadata so
    // recipient circle page snapshot listeners fire with the update
    // even if the sender's client-side .set(merge:true) failed.
    await chatReference.set(
      {
        lastMessage: String(message.text || message.attachmentType || ''),
        lastMessageAtLocal: String(
          message.sentAtLocal || new Date().toISOString()
        ),
        lastMessageSenderPhone: String(message.senderPhone || ''),
      },
      { merge: true }
    );

    // Use a transaction to atomically read lastReadAt and increment unreadCount.
    // This eliminates the race where markGroupChatAsRead (unreadCount = 0,
    // lastReadAt = now) commits between the re-read and the update — the
    // transaction retries with the latest data, ensuring we never increment
    // for messages the user has already seen.
    const messageTimeMs = new Date(
      message.sentAtLocal || message.createdAt || new Date().toISOString()
    ).getTime();
    await db.runTransaction(async (transaction) => {
      const freshChatSnapshot = await transaction.get(chatReference);
      const freshChat = freshChatSnapshot.data() || {};
      const unreadUpdates = {};
      for (const phone of participantPhones) {
        const lastReadAt = freshChat.lastReadAt && freshChat.lastReadAt[phone];
        const lastReadAtMs = lastReadAt
          ? new Date(lastReadAt).getTime()
          : 0;
        if (messageTimeMs > lastReadAtMs) {
          unreadUpdates[`unreadCount.${phone}`] =
            admin.firestore.FieldValue.increment(1);
        }
      }
      if (Object.keys(unreadUpdates).length > 0) {
        transaction.update(chatReference, unreadUpdates);
      }
    });

    await event.data.ref.set(
      {
        notificationEligibleUsers: eligibleUsers,
        notificationTokenCount: tokenList.length,
        notificationSuccessCount: successCount,
        notificationFailureCount: failureCount,
        notificationProcessedAt:
          admin.firestore.FieldValue.serverTimestamp(),
        notificationProcessedAtLocal: new Date().toISOString(),
      },
      { merge: true }
    );
    logger.log(
      `Group chat ${event.params.chatId} message ${event.params.messageId}: ${successCount} notifications sent, ${failureCount} failed.`
    );
  }
);

exports.deliverFcmOutboxMessage = onDocumentCreated(
  'fcmOutbox/{messageId}',
  async (event) => {
    const payload = event.data.data() || {};
    if (payload.status && payload.status !== 'pending') {
      return;
    }
    const recipientPhone = String(payload.recipientPhoneNumber || '');
    if (!recipientPhone) {
      await event.data.ref.set(
        { status: 'failed', error: 'Missing recipient phone number' },
        { merge: true }
      );
      return;
    }
    const userSnapshot = await admin
      .firestore()
      .collection('users')
      .doc(recipientPhone.replace(/\//g, '_'))
      .get();
    const user = userSnapshot.data() || {};
    const boundAppInstanceId = user.boundAppInstanceId ||
      user.currentAppId || null;
    const fcmTokenByAppId = user.fcmTokenByAppId || {};
    const hasAppTokenMap = typeof user.fcmTokenByAppId === 'object' &&
      user.fcmTokenByAppId !== null &&
      Object.keys(user.fcmTokenByAppId).length > 0;
    const userTokens = new Set();
    if (hasAppTokenMap) {
      if (boundAppInstanceId && fcmTokenByAppId[boundAppInstanceId]) {
        userTokens.add(fcmTokenByAppId[boundAppInstanceId]);
      }
    } else {
      if (Array.isArray(user.fcmTokens)) {
        for (const t of user.fcmTokens) {
          if (typeof t === 'string') userTokens.add(t);
        }
      }
      if (typeof user.lastFcmToken === 'string' && user.lastFcmToken) {
        userTokens.add(user.lastFcmToken);
      }
    }
    const tokenList = [...userTokens].filter(
      (token) => typeof token === 'string' && token.length > 20
    );
    if (tokenList.length === 0) {
      await event.data.ref.set(
        {
          status: 'no_token',
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          processedAtLocal: new Date().toISOString(),
        },
        { merge: true }
      );
      return;
    }
    const data = {};
    for (const [key, value] of Object.entries(payload.data || {})) {
      data[key] = typeof value === 'string' ? value : JSON.stringify(value);
    }
    if (payload.deepLink) {
      data.deepLink = String(payload.deepLink);
    }
    if (payload.type) {
      data.type = String(payload.type);
    }
    let successCount = 0;
    let failureCount = 0;
    for (let index = 0; index < tokenList.length; index += 500) {
      const response = await admin.messaging().sendEachForMulticast({
        tokens: tokenList.slice(index, index + 500),
        notification: {
          title: String(payload.title || 'HikerCircle'),
          body: String(payload.body || 'Open HikerCircle to respond.'),
        },
        data,
        android: { priority: 'high' },
        apns: {
          headers: { 'apns-priority': '10' },
          payload: { aps: { sound: 'default' } },
        },
      });
      successCount += response.successCount;
      failureCount += response.failureCount;
    }
    await event.data.ref.set(
      {
        status: failureCount === 0 ? 'sent' : 'partial',
        successCount,
        failureCount,
        attemptCount: admin.firestore.FieldValue.increment(1),
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        processedAtLocal: new Date().toISOString(),
      },
      { merge: true }
    );
  }
);

exports.notifyNearbyHikersAboutUpcomingHike = onDocumentCreated(
  'upcomingHikes/{hikeId}',
  async (event) => {
    const hike = event.data.data() || {};
    const hikeLatitude = Number(hike.latitude);
    const hikeLongitude = Number(hike.longitude);
    if (!Number.isFinite(hikeLatitude) || !Number.isFinite(hikeLongitude)) {
      logger.warn(`Upcoming hike ${event.params.hikeId} has no coordinates.`);
      return;
    }

    const radiusKm = 20;
    const creatorPhone = String(hike.creatorPhone || '');
    const participantPhones = new Set(
      Array.isArray(hike.participantPhones) ? hike.participantPhones : []
    );
    const usersSnapshot = await admin.firestore().collection('users').get();
    const tokens = new Set();
    let nearbyUserCount = 0;

    for (const userDocument of usersSnapshot.docs) {
      const user = userDocument.data() || {};
      const profile =
        user.profile && typeof user.profile === 'object' ? user.profile : {};
      const latitude = Number(
        profile.residentialLatitude ?? user.residentialLatitude
      );
      const longitude = Number(
        profile.residentialLongitude ?? user.residentialLongitude
      );
      const phoneNumber = String(user.phoneNumber || '');
      if (
        !Number.isFinite(latitude) ||
        !Number.isFinite(longitude) ||
        phoneNumber === creatorPhone ||
        participantPhones.has(phoneNumber) ||
        distanceKm(hikeLatitude, hikeLongitude, latitude, longitude) > radiusKm
      ) {
        continue;
      }

      const boundAppInstanceId = user.boundAppInstanceId ||
        user.currentAppId || null;
      const fcmTokenByAppId = user.fcmTokenByAppId || {};
      const hasAppTokenMap = typeof user.fcmTokenByAppId === 'object' &&
        user.fcmTokenByAppId !== null &&
        Object.keys(user.fcmTokenByAppId).length > 0;
      const userTokens = new Set();
      if (hasAppTokenMap) {
        if (boundAppInstanceId && fcmTokenByAppId[boundAppInstanceId]) {
          userTokens.add(fcmTokenByAppId[boundAppInstanceId]);
        }
      } else {
        if (Array.isArray(user.fcmTokens)) {
          for (const t of user.fcmTokens) {
            if (typeof t === 'string') userTokens.add(t);
          }
        }
        if (typeof user.lastFcmToken === 'string' && user.lastFcmToken) {
          userTokens.add(user.lastFcmToken);
        }
      }
      const validTokens = [...userTokens].filter(
        (token) => typeof token === 'string' && token.length > 20
      );
      if (validTokens.length === 0) {
        continue;
      }
      nearbyUserCount++;
      for (const token of validTokens) {
        tokens.add(token);
      }
    }

    const tokenList = [...tokens];
    let successCount = 0;
    let failureCount = 0;
    const deepLink =
      `hikercircle://upcoming-hike/view?upcomingHikeId=` +
      encodeURIComponent(event.params.hikeId);
    for (let index = 0; index < tokenList.length; index += 500) {
      const response = await admin.messaging().sendEachForMulticast({
        tokens: tokenList.slice(index, index + 500),
        notification: {
          title: 'Upcoming hike near you',
          body: `${hike.trailName || 'A hike'} in ${
            hike.area || 'your area'
          } is open to join.`,
        },
        data: {
          type: 'nearby_upcoming_hike',
          upcomingHikeId: event.params.hikeId,
          deepLink,
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'hiker_circle_upcoming_hikes',
            priority: 'high',
          },
        },
        apns: {
          headers: {
            'apns-priority': '10',
          },
          payload: {
            aps: {
              sound: 'default',
            },
          },
        },
      });
      successCount += response.successCount;
      failureCount += response.failureCount;
    }

    await event.data.ref.set(
      {
        nearbyNotificationRadiusKm: radiusKm,
        nearbyNotificationEligibleUsers: nearbyUserCount,
        nearbyNotificationTokenCount: tokenList.length,
        nearbyNotificationSuccessCount: successCount,
        nearbyNotificationFailureCount: failureCount,
        nearbyNotificationSentAt:
          admin.firestore.FieldValue.serverTimestamp(),
        nearbyNotificationSentAtLocal: new Date().toISOString(),
      },
      { merge: true }
    );
    logger.log(
      `Upcoming hike ${event.params.hikeId}: ${successCount} nearby notifications sent, ${failureCount} failed.`
    );
  }
);

exports.sendReminderOnActiveHikeTerminationSignal = onDocumentUpdated(
  'hikeSessions/{sessionId}',
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    if (
      after.status !== 'active' ||
      after.monitoringExpected !== true ||
      !after.terminationSignalNonce ||
      after.terminationSignalNonce === before.terminationSignalNonce
    ) {
      return;
    }
    await sendActiveHikeReopenReminder(
      event.data.after.ref,
      after,
      'app_detached'
    );
  }
);

exports.checkActiveHikeMonitoringHeartbeats = onSchedule(
  'every 1 minutes',
  async () => {
    const snapshot = await admin
      .firestore()
      .collection('hikeSessions')
      .where('status', '==', 'active')
      .get();
    const staleBefore = Date.now() - 5 * 60 * 1000;
    let reminderCount = 0;

    for (const document of snapshot.docs) {
      const data = document.data();
      if (data.monitoringExpected !== true) {
        continue;
      }

      // Only send reminders for apps that were supposed to be actively monitoring.
      // If lifecycleState is 'background', the app intentionally paused monitoring.
      if (data.monitoringLifecycleState === 'background') {
        continue;
      }

      // Skip sessions that started more than 24 hours ago — likely a stale/abandoned session.
      const startedAt = data.startedAt;
      const startedAtMillis =
        startedAt && typeof startedAt.toDate === 'function'
          ? startedAt.toDate().getTime()
          : Date.parse(data.startedAtLocal || data.createdAtLocal || '');
      if (
        Number.isFinite(startedAtMillis) &&
        Date.now() - startedAtMillis > 24 * 60 * 60 * 1000
      ) {
        // Clean up: mark as abandoned so it stops being checked.
        await document.ref.set(
          {
            status: 'abandoned',
            monitoringExpected: false,
            monitoringLifecycleState: 'abandoned',
          },
          { merge: true }
        );
        continue;
      }

      const heartbeat = data.monitoringHeartbeatAt;
      const heartbeatMillis =
        heartbeat && typeof heartbeat.toDate === 'function'
          ? heartbeat.toDate().getTime()
          : Date.parse(data.monitoringHeartbeatAtLocal || '');
      if (!Number.isFinite(heartbeatMillis) || heartbeatMillis >= staleBefore) {
        continue;
      }

      // Re-read the document to verify the hike is still active and not completed.
      const freshSnapshot = await document.ref.get();
      const freshData = freshSnapshot.data();
      if (!freshData || freshData.status !== 'active') {
        continue;
      }

      if (
        await sendActiveHikeReopenReminder(
          document.ref,
          freshData,
          'heartbeat_stale'
        )
      ) {
        reminderCount++;
      }
    }
    logger.log(`Sent ${reminderCount} stale hike monitoring reminders.`);
  }
);

// ─── Stale Hike Session Cleaner ──────────────────────────────────
// Runs every 15 minutes to find and clean up hike sessions that are stuck
// in 'active' status but no longer have an active monitoring loop.

exports.cleanStaleHikeSessions = onSchedule('every 15 minutes', async () => {
  const snapshot = await admin
    .firestore()
    .collection('hikeSessions')
    .where('status', '==', 'active')
    .get();

  let cleanedCount = 0;
  const now = Date.now();
  const staleThreshold = now - 12 * 60 * 60 * 1000; // 12 hours

  for (const document of snapshot.docs) {
    const data = document.data();

    // Skip if monitoring is still expected and heartbeat is recent.
    if (data.monitoringExpected === true) {
      const heartbeat = data.monitoringHeartbeatAt;
      const heartbeatMillis =
        heartbeat && typeof heartbeat.toDate === 'function'
          ? heartbeat.toDate().getTime()
          : Date.parse(data.monitoringHeartbeatAtLocal || '');
      if (Number.isFinite(heartbeatMillis) && heartbeatMillis > now - 6 * 60 * 1000) {
        continue;
      }
    }

    // Check startedAt or createdAt age.
    const startedAt = data.startedAt;
    const startedAtMillis =
      startedAt && typeof startedAt.toDate === 'function'
        ? startedAt.toDate().getTime()
        : Date.parse(data.startedAtLocal || data.createdAtLocal || '');
    if (!Number.isFinite(startedAtMillis) || startedAtMillis > staleThreshold) {
      continue;
    }

    await document.ref.set(
      {
        status: 'abandoned',
        monitoringExpected: false,
        monitoringLifecycleState: 'abandoned',
      },
      { merge: true }
    );
    cleanedCount++;

    logger.log(
      `Cleaned stale hike session ${document.id} (started ${new Date(startedAtMillis).toISOString()}).`
    );
  }

  logger.log(`Cleaned ${cleanedCount} stale hike sessions.`);
});

'use strict';

const GEMINI_MODEL = 'gemini-3.5-flash-lite';
const GEMINI_FALLBACK_MODEL = 'gemini-3.1-flash-lite';
const GEMINI_MODELS = Object.freeze([GEMINI_MODEL, GEMINI_FALLBACK_MODEL]);
const MAX_QUESTION_LENGTH = 480;
const MAX_REQUESTS_PER_MINUTE = 6;
const MAX_REQUESTS_PER_DAY = 40;

const KNOWLEDGE_ARTICLES = Object.freeze([
  {
    id: 'assistant_scope',
    title: 'What the HikerCircle assistant can answer',
    keywords: ['help', 'assistant', 'question', 'support', 'what can you do'],
    content:
      'The HikerCircle assistant explains how to use features already available in the app. It does not diagnose injuries, replace emergency services, choose a trail for the user, or provide live trail conditions. For account-specific problems, use in-app feedback without including passwords, verification codes, precise locations, or phone numbers.',
  },
  {
    id: 'finding_trails',
    title: 'Finding trails and upcoming hikes',
    keywords: ['trail', 'find hike', 'nearest', 'state', 'filter', 'upcoming hike'],
    content:
      'On Home, Find a Hike can be filtered by All, Nearest, or State. Nearest asks for a distance and uses the device location. State uses the same Malaysia location naming used when trails are created. Open a trail to review its route, forecast, elevation range, cautions, and preparation guidance before scheduling or starting a hike.',
  },
  {
    id: 'creating_hikes',
    title: 'Creating solo and group hikes',
    keywords: ['create hike', 'solo', 'group', 'approval', 'open to join', 'schedule'],
    content:
      'An upcoming hike can start as solo or group. Group hikes can require host approval or allow open joining. A solo hike becomes a team hike after the host accepts the first join request. The host then chooses the join policy and confirms the group chat name before team coordination continues.',
  },
  {
    id: 'joining_hikes',
    title: 'Joining a hike and team readiness',
    keywords: ['join', 'request', 'accept', 'ready', 'readiness', 'participant', 'team launch'],
    content:
      'For approval-based hikes, send a join request and wait for the host. After acceptance, the hike group chat is available. When the host starts team preparation, each participant completes the safety checks and taps Ready. The active hike opens for everyone once the host starts it. If a request or readiness state looks stale, reopen that hike or use in-app feedback.',
  },
  {
    id: 'group_chat',
    title: 'Circles, buddies, and hike group chats',
    keywords: ['circle', 'buddy', 'friend', 'group chat', 'message', 'chat'],
    content:
      'Circle contains community relationships, friend requests, buddies, and hike group chats. Tap another hiker profile image to view their public overview. Hike group chats are tied to their team hike so members can coordinate preparation and review the related hike.',
  },
  {
    id: 'login_security',
    title: 'Login and account security',
    keywords: ['login', 'password', 'whatsapp', 'otp', 'passkey', 'authenticator', '2fa', 'mfa'],
    content:
      'Login requires the account password before WhatsApp verification. A second bound method can be an authenticator code or a device passkey. Security methods are managed in Profile, App Settings, Login security. Keep at least one supported verification method bound, and never share a password, OTP, authenticator code, recovery answer, or passkey prompt.',
  },
  {
    id: 'password_recovery',
    title: 'Resetting a forgotten password',
    keywords: ['forgot password', 'reset code', 'recover', 'secret question', 'resend code'],
    content:
      'Forgot Password first sends a WhatsApp reset code. After the code is verified, the app offers only recovery methods already bound to that account, such as a secret question, authenticator, or passkey. If a code expires, use Resend and use only the newest code.',
  },
  {
    id: 'sos_safety',
    title: 'SOS and emergency safety',
    keywords: ['sos', 'emergency', 'danger', 'lost', 'injured', 'medical', 'help me'],
    content:
      'HikerCircle SOS can alert configured contacts and share emergency location information, but it is not a replacement for Malaysian emergency services. In immediate danger or a serious medical emergency, call 999 or 112 first when possible. Keep precise location, Bluetooth, notifications, and background permissions available for the SOS features you use.',
  },
  {
    id: 'sos_button',
    title: 'Physical SOS button',
    keywords: ['physical button', 'bluetooth', 'pair', 'add sos button', 'nearby button'],
    content:
      'Add a supported physical SOS button from the SOS section and follow the nearby-device pairing flow. Bluetooth and the required nearby-device permission must be enabled. Test the configured actions before a hike and keep the phone charged and within Bluetooth range.',
  },
  {
    id: 'hike_preparation',
    title: 'Preparing for a hike',
    keywords: ['prepare', 'preparation', 'checklist', 'weather', 'caution', 'battery', 'shirt color', 'power bank'],
    content:
      'Preparation combines the trail checklist, forecast, trail cautions, emergency contacts, battery guidance, and team readiness when applicable. Warnings can change with rain, temperature, humidity, wind, sunset timing, elevation, water exposure, and route hazards. Recheck close to departure. For hikes longer than three hours, bring a suitable power bank. Daytime clothing guidance favours visible, lighter colours that absorb less solar heat and can make the hiker easier to locate.',
  },
  {
    id: 'trail_cautions',
    title: 'Trail map cautions',
    keywords: ['caution', 'hazard', 'bridge', 'river crossing', 'steep', 'rope', 'ladder', 'scramble', 'mud', 'loose rock'],
    content:
      'Trail maps can mark route-relevant river crossings without a bridge, bridges on the route, steep ascent or descent, rope or ladder and scrambling sections, and loose rock, scree, muddy, or rough surfaces. These pins are planning aids derived from available route and map data; conditions can change, so follow closures and on-site instructions.',
  },
  {
    id: 'hike_history',
    title: 'Hike history and sharing',
    keywords: ['history', 'completed hike', 'share hike', 'route record', 'checkpoint', 'pace'],
    content:
      'Profile, Hike History lists completed hikes for the signed-in user. A history detail can include the recorded route, checkpoint timing, segment pace, elevation, weather, and group information when collected. Share Hike lets the user review the post preview and choose whether to publish; Back to Home skips sharing.',
  },
  {
    id: 'achievements',
    title: 'Achievements and hiker levels',
    keywords: ['achievement', 'badge', 'points', 'level', 'leaderboard', 'rank'],
    content:
      'Achievements award points for eligible hike, safety, security, and community milestones. The Achievements page shows earned and locked badges, current hiker level progress, and monthly or yearly leaderboard views. Open a badge to review its requirements; progress updates only after the qualifying action is recorded.',
  },
  {
    id: 'offline_data',
    title: 'Offline maps and trail hazards',
    keywords: ['offline', 'download map', 'hazard dataset', 'no connection', 'cache'],
    content:
      'Profile, App Settings contains Malaysia offline map and trail hazard downloads. Download them before travelling into weak-coverage areas and periodically refresh the data. Offline content assists navigation and preparation but cannot provide live weather, closures, or emergency connectivity.',
  },
  {
    id: 'first_aid',
    title: 'First-aid guide',
    keywords: ['first aid', 'tutorial', 'injury', 'kkm', 'treatment'],
    content:
      'The First-Aid Guide provides concise Malaysia-oriented educational material based primarily on KKM guidance. It is not a diagnosis or a substitute for trained medical care. For a serious injury, breathing problem, severe bleeding, loss of consciousness, or rapidly worsening condition, call 999 or 112.',
  },
  {
    id: 'feedback',
    title: 'Sending app feedback',
    keywords: ['feedback', 'bug', 'problem', 'report', 'screenshot'],
    content:
      'Use in-app Feedback to report a bug or suggest an improvement. Include what you were doing, what you expected, and what happened. A screenshot can help, but review it first and remove phone numbers, OTPs, exact home locations, medical details, or other sensitive information.',
  },
]);

class AssistantError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'AssistantError';
    this.code = code;
  }
}

function normalizeQuestion(value) {
  if (typeof value !== 'string') {
    throw new AssistantError('invalid-argument', 'Enter a question about HikerCircle.');
  }
  const question = value.replace(/\s+/g, ' ').trim();
  if (question.length < 3) {
    throw new AssistantError('invalid-argument', 'Enter a little more detail in your question.');
  }
  if (question.length > MAX_QUESTION_LENGTH) {
    throw new AssistantError(
      'invalid-argument',
      `Keep the question under ${MAX_QUESTION_LENGTH} characters.`
    );
  }
  return question;
}

function containsSensitivePersonalData(question) {
  const email = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i;
  const phone = /(?:^|\s)(?:\+?\d[\d\s()-]{7,}\d)(?:\s|$)/;
  const coordinates = /\b-?\d{1,2}\.\d{4,}\s*[,/]\s*-?\d{1,3}\.\d{4,}\b/;
  const verificationCode = /\b(?:otp|verification code|authenticator code)\D{0,12}\d{6}\b/i;
  return email.test(question)
    || phone.test(question)
    || coordinates.test(question)
    || verificationCode.test(question);
}

function isEmergencyQuestion(question) {
  return /\b(?:emergency|immediate danger|severe bleeding|not breathing|unconscious|lost now|need rescue|sos now|call ambulance)\b/i
    .test(question);
}

function emergencyResponse() {
  return {
    answer:
      'If this is happening now, call Malaysia emergency services on 999 or 112 first when possible. Move only if staying there is unsafe, use HikerCircle SOS to alert your configured contacts, and share your precise location with responders. Do not wait for this assistant in an emergency.',
    sources: [{id: 'sos_safety', title: 'SOS and emergency safety'}],
    responseMode: 'curated_emergency',
  };
}

function tokenize(value) {
  return new Set(
    value.toLowerCase()
      .replace(/[^a-z0-9\s-]/g, ' ')
      .split(/\s+/)
      .filter((token) => token.length >= 3)
  );
}

function retrieveArticles(question, limit = 3) {
  const normalized = question.toLowerCase();
  const questionTokens = tokenize(question);
  const scored = KNOWLEDGE_ARTICLES.map((article, index) => {
    let score = 0;
    for (const keyword of article.keywords) {
      const lowerKeyword = keyword.toLowerCase();
      if (normalized.includes(lowerKeyword)) {
        score += lowerKeyword.includes(' ') ? 8 : 5;
      }
      for (const token of tokenize(lowerKeyword)) {
        if (questionTokens.has(token)) score += 2;
      }
    }
    for (const token of tokenize(`${article.title} ${article.content}`)) {
      if (questionTokens.has(token)) score += 1;
    }
    return {article, score, index};
  }).sort((left, right) => right.score - left.score || left.index - right.index);

  const relevant = scored.filter((entry) => entry.score > 0).slice(0, limit);
  if (relevant.length > 0) return relevant.map((entry) => entry.article);
  return [KNOWLEDGE_ARTICLES[0]];
}

function utcDayBucket(nowMillis) {
  return new Date(nowMillis).toISOString().slice(0, 10);
}

async function consumeRateLimit(db, uid, nowMillis = Date.now()) {
  const document = db.collection('assistantUsage').doc(uid);
  const minuteBucket = Math.floor(nowMillis / 60000);
  const dayBucket = utcDayBucket(nowMillis);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(document);
    const current = snapshot.exists ? (snapshot.data() || {}) : {};
    const minuteCount = current.minuteBucket === minuteBucket
      ? Number(current.minuteCount || 0)
      : 0;
    const dayCount = current.dayBucket === dayBucket
      ? Number(current.dayCount || 0)
      : 0;

    if (minuteCount >= MAX_REQUESTS_PER_MINUTE) {
      throw new AssistantError(
        'resource-exhausted',
        'You have asked several questions quickly. Wait a minute and try again.'
      );
    }
    if (dayCount >= MAX_REQUESTS_PER_DAY) {
      throw new AssistantError(
        'resource-exhausted',
        'Your free assistant allowance is used for today. Try again tomorrow.'
      );
    }

    transaction.set(document, {
      minuteBucket,
      minuteCount: minuteCount + 1,
      dayBucket,
      dayCount: dayCount + 1,
      updatedAt: new Date(nowMillis).toISOString(),
    }, {merge: true});
  });
}

function buildPrompt(question, articles) {
  const sources = articles.map((article) => (
    `[${article.id}] ${article.title}\n${article.content}`
  )).join('\n\n');
  return [
    'Answer the user question using only the reviewed HikerCircle sources below.',
    'If the sources do not answer it, say that HikerCircle cannot verify that information and suggest in-app Feedback.',
    'Use clear Malaysian English, be concise, and give at most four short paragraphs or steps.',
    'Never invent live conditions, account state, medical advice, or features.',
    'Return JSON only with this shape: {"answer":"...","sourceIds":["source_id"]}.',
    `Question: ${question}`,
    `Reviewed sources:\n${sources}`,
  ].join('\n\n');
}

function parseGeminiResponse(payload, articles) {
  const rawText = payload?.candidates?.[0]?.content?.parts
    ?.map((part) => typeof part?.text === 'string' ? part.text : '')
    .join('')
    .trim();
  if (!rawText) {
    throw new AssistantError('unavailable', 'The assistant returned no answer. Try again.');
  }
  const cleaned = rawText
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/\s*```$/i, '')
    .trim();
  let decoded;
  try {
    decoded = JSON.parse(cleaned);
  } catch (_) {
    throw new AssistantError('unavailable', 'The assistant answer could not be read. Try again.');
  }
  const answer = typeof decoded.answer === 'string' ? decoded.answer.trim() : '';
  if (!answer) {
    throw new AssistantError('unavailable', 'The assistant returned no answer. Try again.');
  }
  const allowed = new Map(articles.map((article) => [article.id, article]));
  const requestedIds = Array.isArray(decoded.sourceIds) ? decoded.sourceIds : [];
  const chosen = requestedIds
    .map((id) => allowed.get(String(id)))
    .filter(Boolean);
  const sources = (chosen.length > 0 ? chosen : articles).map((article) => ({
    id: article.id,
    title: article.title,
  }));
  return {answer, sources, responseMode: 'gemini_free_tier'};
}

function curatedFallbackResponse(articles, reason = 'unavailable') {
  const selected = articles.length > 0 ? articles : [KNOWLEDGE_ARTICLES[0]];
  return {
    answer: selected[0].content,
    sources: selected.map((article) => ({
      id: article.id,
      title: article.title,
    })),
    responseMode: 'curated_fallback',
    notice: reason === 'resource-exhausted'
      ? 'Gemini’s unpaid quota is currently unavailable, so this answer comes directly from HikerCircle’s reviewed guide.'
      : 'Gemini is busy right now, so this answer comes directly from HikerCircle’s reviewed guide.',
  };
}

async function callGemini({apiKey, question, articles, fetchImpl = fetch}) {
  if (!apiKey || !String(apiKey).trim()) {
    throw new AssistantError(
      'failed-precondition',
      'The HikerCircle assistant is not configured yet.'
    );
  }
  const requestBody = JSON.stringify({
    systemInstruction: {
      parts: [{
        text: 'You are the HikerCircle in-app help assistant. Treat the supplied sources as the complete and only source of truth. Do not ask for or expose personal data.',
      }],
    },
    contents: [{
      role: 'user',
      parts: [{text: buildPrompt(question, articles)}],
    }],
    generationConfig: {
      maxOutputTokens: 420,
      responseMimeType: 'application/json',
    },
  });

  let lastAvailabilityError = null;
  for (const model of GEMINI_MODELS) {
    const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
    let response;
    try {
      response = await fetchImpl(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': String(apiKey).trim(),
        },
        body: requestBody,
        signal: AbortSignal.timeout(9000),
      });
    } catch (error) {
      lastAvailabilityError = new AssistantError(
        error?.name === 'TimeoutError' || error?.name === 'AbortError'
          ? 'deadline-exceeded'
          : 'unavailable',
        'The assistant service is temporarily unavailable.'
      );
      continue;
    }

    let payload = {};
    try {
      payload = await response.json();
    } catch (_) {
      // The status-specific message below is safer than exposing upstream text.
    }
    if (response.ok) {
      return {
        ...parseGeminiResponse(payload, articles),
        model,
      };
    }
    if (response.status === 429) {
      throw new AssistantError(
        'resource-exhausted',
        'The unpaid Gemini quota is currently exhausted.'
      );
    }
    if (response.status === 401 || response.status === 403) {
      throw new AssistantError(
        'failed-precondition',
        'The HikerCircle assistant API key is missing or not permitted.'
      );
    }
    if (response.status >= 500) {
      lastAvailabilityError = new AssistantError(
        'unavailable',
        'The assistant service is temporarily unavailable.'
      );
      continue;
    }
    throw new AssistantError('internal', 'The assistant request could not be completed.');
  }
  throw lastAvailabilityError || new AssistantError(
    'unavailable',
    'The assistant service is temporarily unavailable.'
  );
}

function createAssistantHandler({db, apiKey, fetchImpl = fetch, now = Date.now}) {
  return async (request) => {
    const uid = String(request?.auth?.uid || '').trim();
    if (!uid) {
      throw new AssistantError('unauthenticated', 'Sign in before using the HikerCircle assistant.');
    }
    const question = normalizeQuestion(request?.data?.question);
    if (isEmergencyQuestion(question)) return emergencyResponse();
    if (containsSensitivePersonalData(question)) {
      throw new AssistantError(
        'invalid-argument',
        'Remove phone numbers, email addresses, verification codes, and precise coordinates before asking.'
      );
    }
    await consumeRateLimit(db, uid, now());
    const articles = retrieveArticles(question);
    try {
      return await callGemini({apiKey, question, articles, fetchImpl});
    } catch (error) {
      if (
        error instanceof AssistantError
        && ['unavailable', 'deadline-exceeded', 'resource-exhausted']
          .includes(error.code)
      ) {
        return curatedFallbackResponse(articles, error.code);
      }
      throw error;
    }
  };
}

module.exports = {
  AssistantError,
  GEMINI_FALLBACK_MODEL,
  GEMINI_MODEL,
  GEMINI_MODELS,
  KNOWLEDGE_ARTICLES,
  MAX_QUESTION_LENGTH,
  MAX_REQUESTS_PER_DAY,
  MAX_REQUESTS_PER_MINUTE,
  buildPrompt,
  callGemini,
  containsSensitivePersonalData,
  createAssistantHandler,
  curatedFallbackResponse,
  emergencyResponse,
  isEmergencyQuestion,
  normalizeQuestion,
  parseGeminiResponse,
  retrieveArticles,
};

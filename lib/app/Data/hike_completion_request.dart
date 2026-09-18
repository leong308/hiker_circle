import 'dart:async';

// Completion includes a transaction and server-side follow-up work. Production
// requests have taken 12–20 seconds, so the ordinary 8-second write deadline
// incorrectly marked successful completions as pending.
const hikeCompletionTimeout = Duration(seconds: 45);

Future<T> waitForHikeCompletion<T>(Future<T> request) =>
    request.timeout(hikeCompletionTimeout);

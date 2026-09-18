import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/hike_completion_request.dart';

void main() {
  for (final serverDelay in [
    const Duration(milliseconds: 12553),
    const Duration(milliseconds: 19614),
  ]) {
    testWidgets(
      'successful completion after ${serverDelay.inMilliseconds} ms is accepted',
      (tester) async {
        Object? failure;
        String? result;
        final response = Completer<String>();
        waitForHikeCompletion(response.future).then<void>(
          (value) {
            result = value;
          },
          onError: (Object error) {
            failure = error;
          },
        );
        await tester.pump(const Duration(seconds: 8));
        expect(failure, isNull);
        expect(result, isNull);
        await tester.pump(serverDelay - const Duration(seconds: 8));
        response.complete('completed');
        await tester.pump();
        expect(result, 'completed');
        expect(failure, isNull);
      },
    );
  }

  testWidgets('an unresponsive completion still has a bounded deadline', (
    tester,
  ) async {
    final response = Completer<String>();
    Object? failure;
    String? result;
    waitForHikeCompletion(response.future).then<void>(
      (value) {
        result = value;
      },
      onError: (Object error) {
        failure = error;
      },
    );
    await tester.pump(const Duration(seconds: 44));
    expect(failure, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(failure, isA<TimeoutException>());
    // A late response does not re-complete the abandoned request.
    response.complete('completed');
    await tester.pump();
    expect(result, isNull);
  });

  testWidgets('a server rejection is delivered immediately', (tester) async {
    final response = Completer<void>();
    Object? failure;
    waitForHikeCompletion(response.future).catchError((Object error) {
      failure = error;
    });
    final rejection = StateError('Hike does not match its cloud session');
    response.completeError(rejection);
    await tester.pump();
    expect(failure, same(rejection));
  });
}

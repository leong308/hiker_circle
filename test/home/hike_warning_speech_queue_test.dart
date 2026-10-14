import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/ModelView/hike_warning_speech_queue.dart';
import 'package:hiker_circle/sos/Data/sos_device_alert_service.dart';

class Speech {
  final calls = <String>[];
  final messages = <String>[];
  final stops = <String>[];
  final pending = <String, Completer<bool>>{};
  Completer<void>? stopAcknowledgement;

  Future<bool> speak(String id, String message) {
    calls.add(id);
    messages.add(message);
    return (pending[id] = Completer<bool>()).future;
  }

  Future<void> stop(String id) async {
    stops.add(id);
    if (stopAcknowledgement != null) await stopAcknowledgement!.future;
  }

  void finish(String id, [bool completed = true]) {
    pending[id]!.complete(completed);
  }

  HikeWarningSpeechQueue queue() =>
      HikeWarningSpeechQueue(speak: speak, stop: stop);
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('off-trail speech waits for the whole ongoing precaution', () async {
    final speech = Speech();
    final queue = speech.queue()..synchronizeSession('hike');
    final precaution = queue.enqueue(
      requestId: 'weather',
      message: 'Wet trail expected.',
      canSpeak: () => true,
    );
    final alert = PathDeviationAlertMessage(128.6);
    final deviation = queue.enqueue(
      requestId: 'off-trail',
      message: alert.speech,
      canSpeak: () => true,
    );
    await flush();
    expect(speech.calls, ['weather']);
    expect(speech.stops, isEmpty);
    speech.finish('weather');
    expect(await precaution, isTrue);
    await flush();
    expect(speech.calls, ['weather', 'off-trail']);
    expect(speech.messages.last, contains('You may be off the planned trail'));
    expect(speech.messages.last, contains('deviated about 129 meters'));
    expect(alert.body, contains('deviated about 129 m'));
    expect(alert.body, isNot(contains('remained')));
    speech.finish('off-trail');
    expect(await deviation, isTrue);
    queue.dispose();
  });

  test(
    'closing a precaution waits for its native stop before the next warning',
    () async {
      final speech = Speech()..stopAcknowledgement = Completer<void>();
      final queue = speech.queue();
      final first = queue.enqueue(
        requestId: 'weather',
        message: 'Rain.',
        canSpeak: () => true,
      );
      final next = queue.enqueue(
        requestId: 'off-trail',
        message: 'Check your route.',
        canSpeak: () => true,
      );
      await flush();
      final cancelled = queue.cancel('weather');
      // A native completion callback can arrive before the stop is acknowledged.
      speech.finish('weather', false);
      await flush();
      expect(speech.calls, ['weather']);
      speech.stopAcknowledgement!.complete();
      await cancelled;
      expect(await first, isFalse);
      await flush();
      expect(speech.calls, ['weather', 'off-trail']);
      expect(speech.stops, ['weather']);
      speech.finish('off-trail');
      expect(await next, isTrue);
      queue.dispose();
    },
  );

  test(
    'ending the hike cancels active and queued alerts; late speech cannot block a new hike',
    () async {
      final speech = Speech();
      final queue = speech.queue()..synchronizeSession('first');
      final old = queue.enqueue(
        requestId: 'old-weather',
        message: 'Rain.',
        canSpeak: () => true,
      );
      final stale = queue.enqueue(
        requestId: 'old-off-trail',
        message: 'Check route.',
        canSpeak: () => true,
      );
      await flush();
      queue.synchronizeSession(null);
      expect(await old, isFalse);
      expect(await stale, isFalse);
      queue.synchronizeSession('second');
      final next = queue.enqueue(
        requestId: 'new-off-trail',
        message: 'Check route.',
        canSpeak: () => true,
      );
      await flush();
      expect(speech.calls, ['old-weather', 'new-off-trail']);
      expect(speech.stops, ['old-weather']);
      speech.finish('old-weather');
      await flush();
      speech.finish('new-off-trail');
      expect(await next, isTrue);
      queue.dispose();
    },
  );

  test(
    'an SOS starting while queued suppresses the routine off-trail voice',
    () async {
      final speech = Speech();
      final queue = speech.queue();
      var safetyReady = true;
      final first = queue.enqueue(
        requestId: 'weather',
        message: 'Rain.',
        canSpeak: () => true,
      );
      final offTrail = queue.enqueue(
        requestId: 'off-trail',
        message: 'Check route.',
        canSpeak: () => safetyReady,
      );
      await flush();
      safetyReady = false;
      speech.finish('weather', false);
      await first;
      expect(await offTrail, isFalse);
      expect(speech.calls, ['weather']);
      expect(speech.stops, isEmpty);
      queue.dispose();
    },
  );

  test(
    'cloud ID changes for the same hike do not cancel or repeat speech',
    () async {
      final speech = Speech();
      final queue = speech.queue()..synchronizeSession('trail:start-time');
      final voice = queue.enqueue(
        requestId: 'off-trail',
        message: 'Check route.',
        canSpeak: () => true,
      );
      await flush();
      queue.synchronizeSession('trail:start-time');
      final duplicate = queue.enqueue(
        requestId: 'off-trail',
        message: 'Check route.',
        canSpeak: () => true,
      );
      expect(speech.calls, ['off-trail']);
      expect(speech.stops, isEmpty);
      speech.finish('off-trail');
      expect(await voice, isTrue);
      expect(await duplicate, isTrue);
      queue.dispose();
    },
  );

  test('speech failure does not poison later warning delivery', () async {
    final calls = <String>[];
    final stops = <String>[];
    final queue = HikeWarningSpeechQueue(
      speak: (id, _) async {
        calls.add(id);
        if (id == 'failed') throw PlatformException(code: 'unavailable');
        return true;
      },
      stop: (id) async => stops.add(id),
    );
    final failed = queue.enqueue(
      requestId: 'failed',
      message: 'Rain.',
      canSpeak: () => true,
    );
    final next = queue.enqueue(
      requestId: 'off-trail',
      message: 'Check route.',
      canSpeak: () => true,
    );
    expect(await failed, isFalse);
    expect(await next, isTrue);
    expect(calls, ['failed', 'off-trail']);
    expect(stops, ['failed']);
    queue.dispose();
  });

  test(
    'disposal stops only the current owned warning and drops queued speech',
    () async {
      final speech = Speech();
      final queue = speech.queue();
      final first = queue.enqueue(
        requestId: 'weather',
        message: 'Rain.',
        canSpeak: () => true,
      );
      final second = queue.enqueue(
        requestId: 'off-trail',
        message: 'Check route.',
        canSpeak: () => true,
      );
      await flush();
      queue.dispose();
      expect(await first, isFalse);
      expect(await second, isFalse);
      expect(speech.stops, ['weather']);
      expect(speech.calls, ['weather']);
      final afterDispose = queue.enqueue(
        requestId: 'late',
        message: 'Check route.',
        canSpeak: () => true,
      );
      expect(await afterDispose, isFalse);
    },
  );

  test(
    'off-trail alert reaches the existing native speech channel with spoken distance',
    () async {
      const channel = MethodChannel('hiker_circle/sos_device_alerts');
      final calls = <MethodCall>[];
      final nativeCompletion = Completer<bool>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'speakHikePrecaution'
                ? nativeCompletion.future
                : null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      const service = SosDeviceAlertService();
      final queue = HikeWarningSpeechQueue(
        speak: (id, message) =>
            service.speakHikePrecaution(requestId: id, message: message),
        stop: service.stopHikePrecaution,
      );
      final voice = queue.enqueue(
        requestId: 'off-trail',
        message: PathDeviationAlertMessage(88).speech,
        canSpeak: () => true,
      );
      await flush();
      expect(calls.single.method, 'speakHikePrecaution');
      expect(
        calls.single.arguments['message'],
        contains('deviated about 88 meters'),
      );
      nativeCompletion.complete(true);
      expect(await voice, isTrue);
      queue.dispose();
    },
  );
}

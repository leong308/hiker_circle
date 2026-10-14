import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/app_toast.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/ModelView/active_hike_precaution_announcer.dart';
import 'package:hiker_circle/home/View/active_hike_precaution_notice.dart';
import 'package:hiker_circle/sos/Data/sos_device_alert_service.dart';
import 'package:hiker_circle/trail/Model/trail_precautions.dart';

const wet = TrailPrecaution(
  'rain',
  1,
  'Wet trail expected',
  'Watch slippery roots and rocks.',
);
const heavy = TrailPrecaution(
  'rain',
  3,
  'Heavy rain',
  'Avoid streams and unstable slopes.',
);

class Speech {
  final calls = <String>[];
  final messages = <String>[];
  final stops = <String>[];
  final pending = <String, Completer<bool>>{};
  bool completeOnStop = true;

  Future<bool> speak(String id, String message) {
    calls.add(id);
    messages.add(message);
    return (pending[id] = Completer<bool>()).future;
  }

  void complete(String id, bool finished) {
    final future = pending[id]!;
    if (!future.isCompleted) future.complete(finished);
  }

  Future<void> stop(String id) async {
    stops.add(id);
    if (completeOnStop) complete(id, false);
  }
}

Future<BuildContext> open(
  WidgetTester tester,
  ActiveHikePrecautionAnnouncer announcer, {
  double scale = 1,
}) async {
  late BuildContext page;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        extendBody: true,
        body: Builder(
          builder: (context) {
            page = context;
            return Stack(
              fit: StackFit.expand,
              children: [
                const Center(child: Text('Active hike map')),
                ActiveHikePrecautionNoticeView(announcer: announcer),
              ],
            );
          },
        ),
        bottomNavigationBar: const SizedBox(
          height: 80,
          child: Center(child: Text('Home · SOS · Profile')),
        ),
      ),
    ),
  );
  return page;
}

void main() {
  testWidgets(
    'long speech stays visible until actual completion and cannot be replaced by a toast',
    (tester) async {
      final speech = Speech();
      final announcer = ActiveHikePrecautionAnnouncer(
        speak: speech.speak,
        stop: speech.stop,
      );
      final page = await open(tester, announcer);
      announcer.synchronizeSession('hike');
      final finished = announcer.announce(
        sessionKey: 'hike',
        cautions: [wet],
        canPresent: () => true,
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 120));
      expect(find.text('Hike precautions'), findsOneWidget);
      expect(speech.calls, hasLength(1));

      HikerCircleToast.show(page, 'Live sharing is active');
      await tester.pumpAndSettle();
      expect(find.text('Hike precautions'), findsOneWidget);
      ScaffoldMessenger.of(page).clearSnackBars();
      await tester.pumpAndSettle();
      expect(find.text('Hike precautions'), findsOneWidget);

      speech.complete(speech.calls.single, true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Hike precautions'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await finished;
      expect(find.text('Hike precautions'), findsNothing);
      expect(speech.stops, isEmpty);
      announcer.dispose();
    },
  );

  testWidgets(
    'overlapping checks and cloud ID remaps do not repeat a warning',
    (tester) async {
      final speech = Speech();
      final announcer = ActiveHikePrecautionAnnouncer(
        speak: speech.speak,
        stop: speech.stop,
      );
      await open(tester, announcer);
      final hike = ActiveHikeSession.fromPersistence({
        'sessionId': 'offline-start',
        'startedAt': '2026-10-12T08:50:00Z',
      });
      final key = ActiveHikePrecautionAnnouncer.sessionKey(hike);
      announcer.synchronizeSession(key);
      final finished = announcer.announce(
        sessionKey: key,
        cautions: [wet],
        canPresent: () => true,
      );
      await tester.pumpAndSettle();
      await announcer.announce(
        sessionKey: key,
        cautions: [wet],
        canPresent: () => true,
      );
      final remappedKey = ActiveHikePrecautionAnnouncer.sessionKey(
        hike.copyWith(sessionId: 'cloud-canonical'),
      );
      expect(remappedKey, key);
      announcer.synchronizeSession(remappedKey);
      expect(announcer.notice, isNotNull);
      expect(speech.calls, hasLength(1));
      speech.complete(speech.calls.single, true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await finished;
      await announcer.announce(
        sessionKey: remappedKey,
        cautions: [wet],
        canPresent: () => true,
      );
      expect(speech.calls, hasLength(1));
      expect(announcer.notice, isNull);

      // A genuine increase in severity must still be announced.
      final escalated = announcer.announce(
        sessionKey: key,
        cautions: [heavy],
        canPresent: () => true,
      );
      await tester.pumpAndSettle();
      expect(speech.calls, hasLength(2));
      expect(speech.messages.last, contains('Heavy rain'));
      announcer.dismiss();
      await escalated;
      announcer.dispose();
    },
  );

  testWidgets(
    'manual close stops only its utterance and never replays the same warning',
    (tester) async {
      final speech = Speech();
      final announcer = ActiveHikePrecautionAnnouncer(
        speak: speech.speak,
        stop: speech.stop,
      );
      await open(tester, announcer);
      announcer.synchronizeSession('hike');
      final finished = announcer.announce(
        sessionKey: 'hike',
        cautions: [wet],
        canPresent: () => true,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hiker-circle-toast-close')));
      await tester.pump();
      await finished;
      expect(speech.stops, [speech.calls.single]);
      expect(find.text('Hike precautions'), findsNothing);
      await announcer.announce(
        sessionKey: 'hike',
        cautions: [wet],
        canPresent: () => true,
      );
      expect(speech.calls, hasLength(1));
      announcer.dispose();
    },
  );

  testWidgets('new hike cancels old speech and ignores its late completion', (
    tester,
  ) async {
    final speech = Speech()..completeOnStop = false;
    final announcer = ActiveHikePrecautionAnnouncer(
      speak: speech.speak,
      stop: speech.stop,
    );
    await open(tester, announcer);
    announcer.synchronizeSession('first-hike');
    final first = announcer.announce(
      sessionKey: 'first-hike',
      cautions: [wet],
      canPresent: () => true,
    );
    announcer.synchronizeSession('second-hike');
    await first;
    final second = announcer.announce(
      sessionKey: 'second-hike',
      cautions: [heavy],
      canPresent: () => true,
    );
    await tester.pumpAndSettle();
    expect(speech.calls, hasLength(2));
    speech.complete(speech.calls.first, true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(announcer.notice!.message, contains('Heavy rain'));
    announcer.synchronizeSession(null);
    speech.complete(speech.calls.last, false);
    await tester.pump();
    await second;
    expect(speech.stops, speech.calls);
    announcer.dispose();
  });

  testWidgets(
    'interrupted speech keeps the written warning available without restarting',
    (tester) async {
      final speech = Speech();
      final announcer = ActiveHikePrecautionAnnouncer(
        speak: speech.speak,
        stop: speech.stop,
      );
      await open(tester, announcer);
      announcer.synchronizeSession('hike');
      final finished = announcer.announce(
        sessionKey: 'hike',
        cautions: [wet],
        canPresent: () => true,
      );
      await tester.pumpAndSettle();
      speech.complete(speech.calls.single, false);
      await tester.pump();
      await tester.pump(const Duration(minutes: 2));
      expect(find.text('Hike precautions'), findsOneWidget);
      await announcer.announce(
        sessionKey: 'hike',
        cautions: [wet],
        canPresent: () => true,
      );
      expect(speech.calls, hasLength(1));
      announcer.dismiss();
      await finished;
      announcer.dispose();
    },
  );

  testWidgets(
    'speech failure leaves readable precautions and does not clear another notification',
    (tester) async {
      final stopped = <String>[];
      final announcer = ActiveHikePrecautionAnnouncer(
        speak: (_, _) async =>
            throw PlatformException(code: 'speech_unavailable'),
        stop: (id) async => stopped.add(id),
      );
      final page = await open(tester, announcer);
      announcer.synchronizeSession('hike');
      final finished = announcer.announce(
        sessionKey: 'hike',
        cautions: [wet],
        canPresent: () => true,
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 100));
      expect(find.text('Hike precautions'), findsOneWidget);
      HikerCircleToast.show(
        page,
        'Tracking saved',
        duration: const Duration(minutes: 1),
      );
      await tester.pumpAndSettle();
      announcer.dismiss();
      await finished;
      await tester.pump();
      expect(find.text('Tracking saved'), findsOneWidget);
      expect(stopped, isNotEmpty);
      ScaffoldMessenger.of(page).clearSnackBars();
      await tester.pumpAndSettle();
      announcer.dispose();
    },
  );

  testWidgets(
    'stale checks do not claim warnings for another hike or while safety UI is active',
    (tester) async {
      final speech = Speech();
      final announcer = ActiveHikePrecautionAnnouncer(
        speak: speech.speak,
        stop: speech.stop,
      );
      await open(tester, announcer);
      announcer.synchronizeSession('current');
      await announcer.announce(
        sessionKey: 'old',
        cautions: [wet],
        canPresent: () => true,
      );
      await announcer.announce(
        sessionKey: 'current',
        cautions: [wet],
        canPresent: () => false,
      );
      expect(speech.calls, isEmpty);
      final valid = announcer.announce(
        sessionKey: 'current',
        cautions: [wet],
        canPresent: () => true,
      );
      expect(speech.calls, hasLength(1));
      announcer.dispose();
      await tester.pump();
      await valid;
      expect(speech.stops, [speech.calls.single]);
    },
  );

  testWidgets(
    'long warning is scrollable above the navigation bar at large text sizes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final speech = Speech();
      final announcer = ActiveHikePrecautionAnnouncer(
        speak: speech.speak,
        stop: speech.stop,
      );
      await open(tester, announcer, scale: 2);
      announcer.synchronizeSession('hike');
      final valid = announcer.announce(
        sessionKey: 'hike',
        cautions: [
          wet,
          const TrailPrecaution(
            'wind',
            2,
            'Strong wind',
            'Avoid exposed sections and damaged trees. Gusts may affect balance.',
          ),
          const TrailPrecaution(
            'dark',
            3,
            'Past sunset',
            'Carry a headlamp and spare power. Finish before sunset.',
          ),
        ],
        canPresent: () => true,
      );
      await tester.pumpAndSettle();
      expect(find.text('Hike precautions'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester.getBottomLeft(find.byType(HikerCircleToastCard)).dy,
        greaterThan(400),
      );
      await tester.tap(find.byKey(const ValueKey('hiker-circle-toast-close')));
      await tester.pump();
      await valid;
      announcer.dispose();
    },
  );

  testWidgets(
    'native speech API completes only after playback and sends a scoped stop',
    (tester) async {
      const channel = MethodChannel('hiker_circle/sos_device_alerts');
      final pending = Completer<bool>();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'speakHikePrecaution'
                ? await pending.future
                : null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      const service = SosDeviceAlertService();
      bool? completed;
      final playback = service
          .speakHikePrecaution(
            requestId: 'spoken-1',
            message: 'Watch slippery footing.',
          )
          .then((result) => completed = result);
      await tester.pump();
      expect(completed, isNull);
      expect(calls.single.arguments, {
        'requestId': 'spoken-1',
        'message': 'Watch slippery footing.',
      });
      pending.complete(true);
      await tester.pump();
      await playback;
      expect(completed, isTrue);
      await service.stopHikePrecaution('spoken-1');
      expect(calls.last.method, 'stopHikePrecaution');
      expect(calls.last.arguments, {'requestId': 'spoken-1'});
    },
  );
}

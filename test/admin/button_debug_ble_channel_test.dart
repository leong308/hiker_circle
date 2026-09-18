import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/services/hiker_ble_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'debug tap shares native stream and does not consume or inject SOS events',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = EventChannel('hiker_circle/ble_events');
      final ready = Completer<MockStreamHandlerEventSink>();
      var listens = 0;
      messenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(
          onListen: (_, sink) {
            listens++;
            ready.complete(sink);
          },
        ),
      );
      const ble = HikerBleService();
      final normal = <HikerBleEvent>[];
      final debug = <Map<Object?, Object?>>[];
      final sosSub = ble.events.listen(normal.add);
      final debugSub = ble.buttonDebugEvents.listen(debug.add);
      final sink = await ready.future;
      sink.success({
        'type': 'buttonDebug',
        'direction': 'RX',
        'bytes': [72, 67],
      });
      sink.success({'type': 'sosButton', 'counter': 7});
      await Future<void>.delayed(Duration.zero);
      expect(listens, 1);
      expect(debug.single['bytes'], [72, 67]);
      expect(normal.single, isA<HikerBleSosButtonEvent>());
      await debugSub.cancel();
      sink.success({'type': 'sosButton', 'counter': 8});
      await Future<void>.delayed(Duration.zero);
      expect(normal.length, 2);
      expect((normal.last as HikerBleSosButtonEvent).counter, 8);
      await sosSub.cancel();
      sink.endOfStream();
      messenger.setMockStreamHandler(channel, null);
    },
  );
}

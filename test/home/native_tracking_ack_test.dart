import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Data/active_hike_live_status_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('hiker_circle/active_hike_live_status');
  const service = ActiveHikeLiveStatusService();
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('native safety acknowledgement failure stays retryable', () async {
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'acknowledgeSafetyEvent');
          expect(call.arguments, {'eventId': 'event-1'});
          if (++attempts == 1) {
            throw PlatformException(code: 'temporarily-unavailable');
          }
          return null;
        });
    expect(await service.acknowledgeSafetyEvent('event-1'), isFalse);
    expect(await service.acknowledgeSafetyEvent('event-1'), isTrue);
  });

  test(
    'native stop surfaces failure so durable local stop can retry',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: 'stop-failed'),
          );
      expect(await service.stop(), isFalse);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
      expect(await service.stop(), isTrue);
    },
  );
}

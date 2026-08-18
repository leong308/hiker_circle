import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/services/hiker_ble_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'incompatible setup tables are terminal instead of infinitely retryable',
    () {
      expect(
        HikerBleService.isTerminalPairingCompatibilityError(
          'paired_button_firmware_incompatible',
        ),
        isTrue,
      );
      expect(
        HikerBleService.isTerminalPairingCompatibilityError(
          'paired_button_bluetooth_cache_stale',
        ),
        isTrue,
      );
      expect(
        HikerBleService.isTerminalPairingCompatibilityError(
          'paired_button_disconnected',
        ),
        isFalse,
      );
    },
  );

  test('pairing preserves native incompatibility error codes', () async {
    const channel = MethodChannel('hiker_circle/ble_bridge');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'pairSosButton') {
            throw PlatformException(
              code: 'paired_button_firmware_incompatible',
              message: 'Pairing status is missing.',
            );
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await expectLater(
      const HikerBleService().pairSosButton(
        address: 'AA:BB:CC:DD:EE:FF',
        displayName: 'Backpack SOS',
      ),
      throwsA(
        isA<HikerBleException>()
            .having(
              (error) => error.code,
              'code',
              'paired_button_firmware_incompatible',
            )
            .having(
              (error) => error.message,
              'message',
              'Pairing status is missing.',
            ),
      ),
    );
  });

  test('paired SOS button test events retain verified press details', () {
    final receivedAt = DateTime.utc(2026, 8, 18, 4, 5, 6);
    final event = HikerBleEvent.fromPlatform({
      'type': 'pairedSosButtonTest',
      'deviceId': 'AABBCCDDEEFF',
      'displayName': 'Backpack SOS',
      'counter': 42,
      'rssi': -51,
      'receivedAtMillis': receivedAt.millisecondsSinceEpoch,
    });

    expect(event, isA<HikerBlePairedSosButtonTestEvent>());
    final testEvent = event as HikerBlePairedSosButtonTestEvent;
    expect(testEvent.deviceId, 'AABBCCDDEEFF');
    expect(testEvent.displayName, 'Backpack SOS');
    expect(testEvent.counter, 42);
    expect(testEvent.rssi, -51);
    expect(testEvent.receivedAt, receivedAt);
  });

  test('setup discovery retains the firmware setup-mode countdown', () {
    final event = HikerBleEvent.fromPlatform({
      'type': 'pairedButtonSetupDevice',
      'address': 'AA:BB:CC:DD:EE:FF',
      'displayName': 'HikerCircle Setup',
      'rssi': -48,
      'setupModeState': 1,
      'setupModeRemainingSeconds': 117,
      'receivedAtMillis': DateTime.utc(2026, 8, 18).millisecondsSinceEpoch,
    });

    expect(event, isA<HikerBlePairedButtonSetupEvent>());
    final setupEvent = event as HikerBlePairedButtonSetupEvent;
    expect(setupEvent.setupModeState, 1);
    expect(setupEvent.setupModeRemainingSeconds, 117);
  });

  test(
    'arming and cancelling paired SOS button test calls native bridge',
    () async {
      const channel = MethodChannel('hiker_circle/ble_bridge');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      const service = HikerBleService();
      await service.armPairedSosButtonTest(
        '  aabbccddeeff  ',
        duration: const Duration(seconds: 45),
      );
      await service.cancelPairedSosButtonTest();

      expect(calls, hasLength(2));
      expect(calls.first.method, 'armPairedSosButtonTest');
      expect(calls.first.arguments, {
        'deviceId': 'AABBCCDDEEFF',
        'durationMillis': 30000,
      });
      expect(calls.last.method, 'cancelPairedSosButtonTest');
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/services/hiker_ble_service.dart';
import 'package:hiker_circle/sos/View/sos_button_pairing_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'guided pairing instructions remain reachable on a phone screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SosButtonPairingSheet(
              ble: const HikerBleService(),
              onPaired: () async {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Add SOS button'), findsOneWidget);
      expect(find.text('Put the button in setup mode'), findsOneWidget);
      expect(find.text('Press and hold'), findsOneWidget);
      expect(find.text('Release it'), findsOneWidget);
      expect(find.text('Press twice'), findsOneWidget);

      await tester.ensureVisible(find.text('My button is ready'));
      await tester.pump();
      expect(find.text('My button is ready'), findsOneWidget);
    },
  );

  testWidgets('scan failure becomes an actionable in-modal recovery step', (
    tester,
  ) async {
    const channel = MethodChannel('hiker_circle/ble_bridge');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'startPairedButtonSetupScan') {
            throw PlatformException(
              code: 'bluetooth_unavailable',
              message: 'Bluetooth is off.',
            );
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SosButtonPairingSheet(
            ble: const HikerBleService(),
            onPaired: () async {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.ensureVisible(find.text('My button is ready'));
    await tester.pump();
    await tester.tap(find.text('My button is ready'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Pairing needs attention'), findsOneWidget);
    expect(find.text('Try scanning again'), findsOneWidget);
    expect(find.text('Back to instructions'), findsOneWidget);
  });

  testWidgets('stopping a scan cancels its delayed empty-result failure', (
    tester,
  ) async {
    const channel = MethodChannel('hiker_circle/ble_bridge');
    var stopCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'stopPairedButtonSetupScan') stopCalls += 1;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SosButtonPairingSheet(
            ble: const HikerBleService(),
            onPaired: () async {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.ensureVisible(find.text('My button is ready'));
    await tester.tap(find.text('My button is ready'));
    await tester.pump();
    expect(find.text('Searching nearby…'), findsOneWidget);
    expect(find.text('App scan: 0:30 remaining'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('App scan: 0:29 remaining'), findsOneWidget);

    await tester.ensureVisible(find.text('Stop and try again'));
    await tester.tap(find.text('Stop and try again'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Put the button in setup mode'), findsOneWidget);
    expect(stopCalls, greaterThanOrEqualTo(1));

    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Put the button in setup mode'), findsOneWidget);
    expect(find.text('Pairing needs attention'), findsNothing);
  });
}

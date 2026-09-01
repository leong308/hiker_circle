import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/View/start_hike_wizard_page.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  testWidgets('a blocked native setting check keeps the hike draft open', (
    tester,
  ) async {
    const bleChannel = MethodChannel('hiker_circle/ble_bridge');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bleChannel, (call) async {
          if (call.method == 'getSosButtonReadiness') {
            return <String, Object?>{};
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bleChannel, null),
    );

    var startAttempts = 0;
    bool? submittedShareLiveLocation;
    await tester.pumpWidget(
      MaterialApp(
        home: StartHikeWizardPage(
          availableTrails: [_trail()],
          onStartNow: (draft) async {
            startAttempts += 1;
            submittedShareLiveLocation = draft.shareLiveLocation;
            return false;
          },
        ),
      ),
    );

    for (var step = 0; step < 3; step += 1) {
      final continueButton = find.widgetWithText(FilledButton, 'Continue');
      await tester.ensureVisible(continueButton);
      tester.widget<FilledButton>(continueButton).onPressed!();
      await tester.pump();
    }

    final startButton = find.widgetWithText(
      FilledButton,
      'Start Hiking Session',
    );
    await tester.ensureVisible(startButton);
    tester.widget<FilledButton>(startButton).onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final confirmStart = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    );
    expect(confirmStart, findsOneWidget);
    tester.widget<FilledButton>(confirmStart).onPressed!();
    await tester.pump();

    expect(startAttempts, 1);
    expect(submittedShareLiveLocation, isFalse);
    expect(find.text('Safety Settings'), findsOneWidget);
    expect(
      find.text('Share live location with SOS contacts when hike starts'),
      findsOneWidget,
    );
    expect(find.text('Start Hiking Session'), findsOneWidget);
    expect(find.text('Create Hiking Session'), findsOneWidget);
  });
}

Trail _trail() {
  return Trail(
    trailId: 'wizard-trail',
    name: 'Wizard Trail',
    area: 'George Town',
    state: 'Penang',
    country: 'Malaysia',
    latitude: 5.4141,
    longitude: 100.3288,
    distanceKm: 4.2,
    difficulty: 'Moderate',
    estimatedDurationMinutes: 120,
    elevationGainMeters: 180,
    ratingAverage: 4.6,
    offlineMapAvailable: false,
    offlineMapDownloaded: false,
    isVerifiedTrail: true,
    routeFilePath: '',
    coverColorValue: 0xFF3F8F5E,
    checkpoints: const [
      TrailCheckpoint(
        name: 'Trailhead',
        latitude: 5.4141,
        longitude: 100.3288,
        order: 0,
      ),
      TrailCheckpoint(
        name: 'Ridge',
        latitude: 5.418,
        longitude: 100.331,
        order: 1,
      ),
      TrailCheckpoint(
        name: 'Summit',
        latitude: 5.421,
        longitude: 100.334,
        order: 2,
      ),
    ],
    weather: TrailWeather(
      summary: 'Clear',
      temperatureRange: '25–31°C',
      rainProbability: 20,
      cachedAt: DateTime.utc(2026, 8, 20),
    ),
    hazards: const [],
  );
}

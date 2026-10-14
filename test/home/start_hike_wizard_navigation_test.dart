import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/View/start_hike_wizard_page.dart';
import 'package:hiker_circle/home/View/hike_start_navigation.dart';
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
    int? submittedDeviationDistance;
    await tester.pumpWidget(
      MaterialApp(
        home: StartHikeWizardPage(
          availableTrails: [_trail()],
          onStartNow: (draft) async {
            startAttempts += 1;
            submittedShareLiveLocation = draft.shareLiveLocation;
            submittedDeviationDistance = draft.pathDeviationDistanceMeters;
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

    final distanceSlider = find.byKey(
      const ValueKey('path-deviation-distance-slider'),
    );
    expect(distanceSlider, findsOneWidget);
    tester.widget<Slider>(distanceSlider).onChanged!(35);
    await tester.pump();
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
    expect(submittedDeviationDistance, 35);
    expect(find.text('Safety Settings'), findsOneWidget);
    expect(
      find.text('Share live location with SOS contacts when hike starts'),
      findsOneWidget,
    );
    expect(find.text('Start Hiking Session'), findsOneWidget);
    expect(find.text('Create Hiking Session'), findsOneWidget);
  });

  testWidgets('successful callback reveals Home without a late extra pop', (
    tester,
  ) async {
    const bleChannel = MethodChannel('hiker_circle/ble_bridge');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bleChannel, (call) async {
          return call.method == 'getSosButtonReadiness'
              ? <String, Object?>{}
              : null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bleChannel, null),
    );
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext homeContext;
    var active = false;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) {
            homeContext = context;
            return const Scaffold(body: Text('Home'));
          },
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Trail details')),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => StartHikeWizardPage(
          availableTrails: [_trail()],
          onStartNow: (_) async {
            active = true;
            HikeStartNavigation.revealHome(homeContext);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var step = 0; step < 3; step++) {
      final button = find.widgetWithText(FilledButton, 'Continue');
      await tester.ensureVisible(button);
      tester.widget<FilledButton>(button).onPressed!();
      await tester.pump();
    }
    final button = find.widgetWithText(FilledButton, 'Start Hiking Session');
    await tester.ensureVisible(button);
    tester.widget<FilledButton>(button).onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final confirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    );
    tester.widget<FilledButton>(confirm).onPressed!();
    await tester.pumpAndSettle();
    expect(active, isTrue);
    expect(find.text('Home'), findsOneWidget);
    expect(find.byType(StartHikeWizardPage), findsNothing);
    expect(navigator.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
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

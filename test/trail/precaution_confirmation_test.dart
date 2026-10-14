import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'package:hiker_circle/trail/Model/trail_precautions.dart';
import 'package:hiker_circle/trail/View/precaution_confirmation.dart';

List<TrailPrecaution> hikeChecks({bool evening = true}) {
  final now = DateTime.utc(2026, 10, 12);
  final midnight = now.millisecondsSinceEpoch ~/ 1000;
  final weather = TrailWeather(
    summary: '',
    temperatureRange: '',
    rainProbability: 68,
    cachedAt: now,
    forecastData: {
      'utc_offset_seconds': 0,
      'daily': {
        'time': [midnight],
        'sunrise': [midnight + 6 * 3600],
        'sunset': [midnight + 19 * 3600],
      },
      'hourly': {
        'time': List.generate(48, (i) => midnight + i * 3600),
        'temperature_2m': List.filled(48, 25),
        'apparent_temperature': List.filled(48, 26),
        'relative_humidity_2m': List.filled(48, 70),
        'precipitation_probability': List.filled(48, 68),
        'precipitation': List.filled(48, .2),
        'weather_code': List.filled(48, 3),
        'wind_speed_10m': List.filled(48, 10),
        'wind_gusts_10m': List.filled(48, 15),
        'visibility': List.filled(48, 10000),
        'uv_index': List.filled(48, 0),
      },
    },
  );
  return trailPrecautions(
    weather: weather,
    day: 0,
    now: now,
    elevationGain: 769,
    durationMinutes: 90,
    departureMinute: evening ? 18 * 60 : 5 * 60,
  );
}

Future<void> openDialog(
  WidgetTester tester,
  Future<List<TrailPrecaution>> checks, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool reducedMotion = false,
  ValueChanged<bool?>? onResult,
  GlobalKey? captureKey,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: 'Inter',
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3F8F5E),
            brightness: brightness,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reducedMotion,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  final result = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => HikePrecautionDialog(precautions: checks),
                  );
                  onResult?.call(result);
                },
                child: const Text('Review precautions'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Review precautions'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

Future<void> capturePreview(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  if (!const bool.fromEnvironment('CAPTURE_PRECAUTION_PREVIEW')) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage(pixelRatio: 2);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    await Directory('tmp').create(recursive: true);
    await File('tmp/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  setUpAll(() async {
    final text = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([text.load(), icons.load()]);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'concise ${brightness.name} overview keeps full advice available without rechecking',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var checks = 0;
        final cautions = hikeChecks();
        final future = Future<List<TrailPrecaution>>(() {
          checks++;
          return cautions;
        });
        final key = GlobalKey();
        await openDialog(
          tester,
          future,
          brightness: brightness,
          captureKey: key,
        );
        await tester.pumpAndSettle();
        expect(find.text('Peak chance 68%'), findsOneWidget);
        expect(find.text('Climb 769 m'), findsOneWidget);
        expect(find.text('Finish 19:30'), findsOneWidget);
        expect(find.text('Sunset 19:00'), findsOneWidget);
        final rain = cautions.firstWhere((c) => c.id == 'rain');
        expect(find.text(rain.message), findsNothing);
        await capturePreview(
          tester,
          key,
          'precaution-popup-${brightness.name}',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('precaution-rain')),
        );
        await tester.tap(find.byKey(const ValueKey('precaution-rain')));
        await tester.pumpAndSettle();
        expect(find.text(rain.message), findsOneWidget);
        expect(checks, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'no continue action during loading; failed checks cannot become an all-clear',
    (tester) async {
      final pending = Completer<List<TrailPrecaution>>();
      await openDialog(tester, pending.future);
      expect(
        find.byKey(const ValueKey('confirm-hike-precautions')),
        findsNothing,
      );
      pending.completeError(StateError('Forecast unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('Forecast unavailable'), findsOneWidget);
      expect(find.text('No forecast alerts found'), findsNothing);
      expect(find.text('Important'), findsOneWidget);
      expect(
        find.text('Check local conditions and official alerts.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'early departure summary names sunrise and does not recommend changing start time',
    (tester) async {
      await openDialog(tester, Future.value(hikeChecks(evening: false)));
      await tester.pumpAndSettle();
      expect(find.text('Start 05:00'), findsOneWidget);
      expect(find.text('Sunrise 06:00'), findsOneWidget);
      expect(find.text('Finish 06:30'), findsOneWidget);
      expect(find.textContaining('Leave earlier'), findsNothing);
      expect(find.textContaining('Sunset 19:00'), findsNothing);
    },
  );

  testWidgets(
    'small screen and large text keep all cautions scrollable and actions reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool? result;
      await openDialog(
        tester,
        Future.value(hikeChecks()),
        textScale: 1.8,
        onResult: (value) => result = value,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Peak chance 68%'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-hike-precautions')));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion reveals the full overview immediately and go back cancels',
    (tester) async {
      bool? result;
      await openDialog(
        tester,
        Future.value(hikeChecks()),
        reducedMotion: true,
        onResult: (value) => result = value,
      );
      final opacities = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(opacities.where((w) => w.opacity < 1), isEmpty);
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a calm forecast still reminds users to check local conditions', (
    tester,
  ) async {
    await openDialog(tester, Future.value([]));
    await tester.pumpAndSettle();
    expect(find.text('No forecast alerts found'), findsOneWidget);
    expect(
      find.text('Conditions can change. Check the trail locally.'),
      findsOneWidget,
    );
    expect(find.textContaining('All clear'), findsNothing);
  });
  testWidgets(
    'hikers can go back during a slow forecast check without continuing later',
    (tester) async {
      final pending = Completer<List<TrailPrecaution>>();
      bool? result;
      await openDialog(
        tester,
        pending.future,
        onResult: (value) => result = value,
      );
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      pending.complete(hikeChecks());
      await tester.pumpAndSettle();
      expect(find.byType(HikePrecautionDialog), findsNothing);
      expect(result, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}

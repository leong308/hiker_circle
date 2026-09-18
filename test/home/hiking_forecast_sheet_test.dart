import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hiker_circle/home/View/hiking_forecast_sheet.dart';
import 'next_hike_briefing_test.dart' as fixtures;
import 'session_weather_forecast_test.dart' as data;

Future<void> showForecast(
  WidgetTester tester, {
  double scale = 1,
  Brightness brightness = Brightness.light,
  bool reducedMotion = true,
  bool gap = false,
  bool autoplay = false,
}) async {
  final hike = fixtures.testHike(
    departure: data.midnight.add(const Duration(hours: 8, minutes: 30)),
  );
  final weather = data.sessionWeather(gap: gap);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: HikingForecastSheet(
          hike: hike,
          weather: weather,
          service: fixtures.TestWeatherService(weather),
          elevationGain: 769,
          autoplay: autoplay,
        ),
      ),
    ),
  );
  if (reducedMotion) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
  await tester.scrollUntilVisible(
    find.byType(LineChart),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'graph clips to buffered window, highlights the hike and switches metrics',
    (tester) async {
      await showForecast(tester);
      var chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.minX, 0);
      expect(chart.data.maxX, 7);
      final band = chart.data.rangeAnnotations.verticalRangeAnnotations.single;
      expect(band.x1, 2);
      expect(band.x2, 5);
      final context = tester.element(find.byType(HikingForecastSheet));
      expect(
        chart.data.lineBarsData.single.color,
        Theme.of(context).colorScheme.primary,
      );
      expect(chart.data.lineBarsData.single.barWidth, 2.5);
      expect(chart.data.lineBarsData.single.belowBarData.show, isTrue);
      await Scrollable.ensureVisible(
        tester.element(find.byTooltip('Next weather metric')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next weather metric'));
      await tester.pumpAndSettle();
      chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.maxY, 100);
      expect(chart.data.lineTouchData.enabled, isFalse);
      await Scrollable.ensureVisible(
        tester.element(find.byType(LineChart)),
        alignment: .7,
      );
      await tester.pumpAndSettle();
      final plot = tester.getRect(find.byType(LineChart));
      // The 07:00 buffer sample has 80% rain, versus 20% during the hike.
      await tester.tapAt(
        Offset(
          plot.left + 44 + (plot.width - 44) * .5 / 7,
          plot.top + (plot.height - 28) * .2,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('forecast-hour-value')))
            .data,
        '80%',
      );
      await Scrollable.ensureVisible(
        tester.element(find.byTooltip('Next weather metric')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next weather metric'));
      await tester.pumpAndSettle();
      chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(
        chart.data.lineBarsData.single.spots
            .where((p) => !p.isNull())
            .every((p) => p.y == 10),
        isTrue,
      );
      await tester.scrollUntilVisible(
        find.textContaining('Before departure: rain may leave the trail wet'),
        -220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('Before departure: rain may leave the trail wet'),
        findsOneWidget,
      );
      expect(find.text('Demanding ascent'), findsOneWidget);
      expect(
        find.widgetWithText(ExpansionTile, 'Before you set off'),
        findsOneWidget,
      );
      expect(find.textContaining('relevant precautions'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'preview, slider, jumps and metric swipes share the selected hour',
    (tester) async {
      await showForecast(tester);
      final service =
          tester
                  .widget<HikingForecastSheet>(find.byType(HikingForecastSheet))
                  .service
              as fixtures.TestWeatherService;
      final initialCalls = service.calls;
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('forecast-metric-swipe'))),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.fling(
        find.byKey(const ValueKey('forecast-metric-swipe')),
        const Offset(-140, 0),
        600,
      );
      await tester.pumpAndSettle();
      expect(find.text('Rain'), findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(find.byTooltip('Play hourly preview')),
        alignment: .6,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Play hourly preview'));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('forecast-hour-value')))
            .data,
        '80%',
      );
      await tester.tap(find.byTooltip('Pause hourly preview'));
      await tester.pump(const Duration(seconds: 3));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('forecast-hour-value')))
            .data,
        '80%',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('forecast-time-slider')),
      );
      await tester.drag(
        find.byKey(const ValueKey('forecast-time-slider')),
        const Offset(500, 0),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('After return'), findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(find.byTooltip('Jump to departure')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Jump to departure'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Departure hour'), findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(find.byTooltip('Play hourly preview')),
        alignment: .6,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Play hourly preview'));
      await tester.pump(const Duration(seconds: 20));
      expect(find.byTooltip('Play hourly preview'), findsOneWidget);
      expect(find.textContaining('After return'), findsOneWidget);
      await tester.tap(find.byTooltip('Play hourly preview'));
      await tester.pump();
      expect(find.byTooltip('Pause hourly preview'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.byTooltip('Play hourly preview'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.tap(find.byTooltip('Play hourly preview'));
      await tester.pump();
      expect(find.byTooltip('Pause hourly preview'), findsOneWidget);
      expect(service.calls, initialCalls);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'playback moves continuously without rebuilding the chart each frame',
    (tester) async {
      await showForecast(tester, reducedMotion: false);
      await Scrollable.ensureVisible(
        tester.element(find.byTooltip('Play hourly preview')),
        alignment: .6,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Play hourly preview'));
      await tester.pump();
      double position() => tester
          .widget<Slider>(find.byKey(const ValueKey('forecast-time-slider')))
          .value;
      double cursor() =>
          (tester
                      .widget<Align>(
                        find.byKey(const ValueKey('forecast-time-cursor')),
                      )
                      .alignment
                  as Alignment)
              .x;
      final start = position(), startCursor = cursor();
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      await tester.pump(const Duration(milliseconds: 200));
      final first = position(), firstCursor = cursor();
      expect(first, greaterThan(start));
      expect(first, lessThan(start + 3600000));
      expect(firstCursor, greaterThan(startCursor));
      await tester.pump(const Duration(milliseconds: 200));
      expect(position(), greaterThan(first));
      expect(cursor(), greaterThan(firstCursor));
      expect(
        identical(chart, tester.widget<LineChart>(find.byType(LineChart))),
        isTrue,
      );
      await tester.tap(find.byTooltip('Pause hourly preview'));
      await tester.pump();
      final paused = position();
      await tester.pump(const Duration(seconds: 3));
      expect(position(), paused);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'autoplay starts automatically; holding and hovering inspect and pause',
    (tester) async {
      await showForecast(tester, autoplay: true, reducedMotion: false);
      expect(find.byTooltip('Pause hourly preview'), findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('forecast-touch-surface'))),
        alignment: .5,
      );
      await tester.pump();
      double position() => tester
          .widget<Slider>(find.byKey(const ValueKey('forecast-time-slider')))
          .value;
      final initial = position();
      await tester.pump(const Duration(milliseconds: 200));
      expect(position(), greaterThan(initial));
      final rect = tester.getRect(
        find.byKey(const ValueKey('forecast-touch-surface')),
      );
      final pointer = await tester.startGesture(
        Offset(rect.left + rect.width * .4, rect.center.dy),
      );
      await tester.pump();
      expect(find.byTooltip('Play hourly preview'), findsOneWidget);
      final held = position();
      await tester.pump(const Duration(seconds: 2));
      expect(position(), held);
      await pointer.moveTo(Offset(rect.left + rect.width * .7, rect.center.dy));
      await tester.pump();
      expect(position(), greaterThan(held));
      await pointer.up();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(Offset(rect.left + rect.width * .3, rect.center.dy));
      await tester.pump();
      expect(position(), lessThan(held));
      await mouse.removePointer();
      expect(find.text('Departure'), findsOneWidget);
      expect(find.text('Estimated finish'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('continuous preview labels missing hours as unavailable', (
    tester,
  ) async {
    await showForecast(tester, reducedMotion: false, gap: true);
    await Scrollable.ensureVisible(
      tester.element(find.byTooltip('Play hourly preview')),
      alignment: .6,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Play hourly preview'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 3600));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('forecast-hour-value')))
          .data,
      'Unavailable',
    );
    expect(find.textContaining('No hourly data available'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'forecast is scrollable on narrow screens with large text in both themes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final brightness in Brightness.values) {
        await showForecast(tester, scale: 1.6, brightness: brightness);
        await tester.scrollUntilVisible(
          find.text('More session conditions'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('More session conditions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('More session conditions'));
        await tester.pumpAndSettle();
        expect(find.text('Peak gusts'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
    },
  );
}

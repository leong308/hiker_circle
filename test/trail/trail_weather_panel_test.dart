import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hiker_circle/core/widgets/running_border.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'package:hiker_circle/trail/View/trail_weather_panel.dart';

void main() {
  testWidgets('departure and selected day propagate to route preview in UTC', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final midnight = DateTime.utc(2026, 9, 13, 16);
    final epoch = midnight.millisecondsSinceEpoch ~/ 1000;
    DateTime? departure;
    final weather = TrailWeather.fromPersistence({
      'cachedAtLocal': DateTime.now().toIso8601String(),
      'forecastData': {
        'utc_offset_seconds': 28800,
        'daily': {
          'time': [epoch, epoch + 86400],
        },
        'hourly': {
          'time': [epoch],
          'precipitation_probability': [10],
        },
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TrailWeatherPanel(
              weather: weather,
              durationMinutes: 210,
              onDepartureChanged: (time) => departure = time,
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Set departure time'));
    await tester.tap(find.text('Set departure time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(departure, DateTime.utc(2026, 9, 14)); // 08:00 in Malaysia.
    await tester.ensureVisible(find.text('Tue 15/9'));
    await tester.tap(find.text('Tue 15/9'));
    await tester.pumpAndSettle();
    expect(departure, DateTime.utc(2026, 9, 15));
    await tester.ensureVisible(find.text('Daily outlook'));
    await tester.tap(find.text('Daily outlook'));
    await tester.pumpAndSettle();
    expect(departure, isNull);
  });

  testWidgets(
    'humidity replaces gusts and wind requires elevation above 250m',
    (tester) async {
      final epoch = DateTime.utc(2026, 9, 7).millisecondsSinceEpoch ~/ 1000;
      final weather = TrailWeather.fromPersistence({
        'forecastData': {
          'daily': {
            'time': [epoch],
          },
          'hourly': {
            'time': [epoch, epoch + 3600],
            'relative_humidity_2m': [72, 80],
            'wind_speed_10m': [12, 15],
          },
        },
      });
      Future<void> show(int elevation) => tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: TrailWeatherPanel(
                weather: weather,
                elevationGainMeters: elevation,
              ),
            ),
          ),
        ),
      );
      await show(250);
      expect(find.text('Gusts'), findsNothing);
      expect(find.text('Wind'), findsNothing);
      await tester.tap(find.text('Humidity'));
      await tester.pumpAndSettle();
      var chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.maxY, 100);
      expect(chart.data.lineBarsData.single.spots.first.y, 72);
      await show(251);
      await tester.tap(find.text('Wind'));
      await tester.pumpAndSettle();
      chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.single.spots.first.y, 12);
      await show(250);
      await tester.pumpAndSettle();
      expect(find.text('Wind'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets('day selection shows correct conditions in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final epoch = DateTime.utc(2026, 9, 6, 16).millisecondsSinceEpoch ~/ 1000;
      final weather = TrailWeather.fromPersistence({
        'summary': 'Forecast',
        'cachedAtLocal': DateTime.now().toIso8601String(),
        'forecastData': {
          'timezone': 'Asia/Kuala_Lumpur',
          'utc_offset_seconds': 28800,
          'daily': {
            'time': [epoch, epoch + 86400],
            'weather_code': [0, 95],
            'temperature_2m_max': [30, 25],
            'uv_index_max': [null, 8],
          },
          'hourly': {
            'time': [epoch, epoch + 3600, epoch + 86400, epoch + 90000],
            'weather_code': [0, 0, 95, 95],
            'temperature_2m': [24, 25, 23, 24],
            'precipitation_probability': [0, 10, 80, 90],
            'wind_gusts_10m': [10, 12, 25, 30],
          },
        },
      });
      expect(
        TrailWeather.fromPersistence(weather.toFirestore()).forecastData,
        weather.forecastData,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: TrailWeatherPanel(weather: weather),
            ),
          ),
        ),
      );
      expect(find.text('Mon 7/9'), findsOneWidget);
      expect(find.text('Clear sky'), findsOneWidget);
      await tester.tap(find.text('Tue 8/9'));
      await tester.pumpAndSettle();
      expect(find.text('Thunderstorm'), findsOneWidget);
      expect(
        find.text('Thunderstorms forecast — consider postponing'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Water crossings, steep sections'),
        findsOneWidget,
      );
      expect(find.text('25.0 °C'), findsOneWidget);
      await tester.ensureVisible(find.text('Rain'));
      await tester.tap(find.text('Rain'));
      await tester.pumpAndSettle();
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.maxY, 100);
      expect(
        chart.data.titlesData.leftTitles.sideTitles.reservedSize,
        inInclusiveRange(44, 55),
      );
      expect(chart.data.lineBarsData.single.spots.first.y, 80);
      expect(
        find.text('Latest model conditions · not the selected day'),
        findsNothing,
      );
      expect(find.text('Hourly readings'), findsNothing);
      expect(find.byType(RunningBorder), findsOneWidget);
      expect(find.text('Before you set off now'), findsOneWidget);
      expect(find.text('Forecast is up to date'), findsOneWidget);
      expect(find.text('Weather data: Open-Meteo'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/weather_map_overlay.dart';
import 'package:hiker_circle/core/services/weather_map_service.dart';

void main() {
  testWidgets('missing configuration is visible and does not enable a layer', (
    tester,
  ) async {
    dotenv.testLoad(fileInput: '');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 320,
            child: WeatherMapOverlay(
              map: null,
              latitude: 5.4,
              longitude: 100.3,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Weather layers'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('Rain'),
        matching: find.byType(CheckedPopupMenuItem<WeatherMapLayer>),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Weather maps are not available yet.'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('Weather maps are not available yet.'), findsNothing);
  });

  testWidgets('weather selector, legend, opacity and errors fit a small map', (
    tester,
  ) async {
    dotenv.testLoad(fileInput: 'OPENWEATHER_API_KEY=test');
    final key = GlobalKey<WeatherMapOverlayState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 280,
            child: WeatherMapOverlay(
              key: key,
              map: null,
              latitude: 5.4,
              longitude: 100.3,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Weather layers'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('Temperature'),
        matching: find.byType(CheckedPopupMenuItem<WeatherMapLayer>),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Temperature · current conditions'), findsOneWidget);
    expect(find.text('Weather data © OpenWeather'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(tester.takeException(), isNull);
    key.currentState!.reportMapError('unrelated-base-map');
    await tester.pump();
    expect(find.byType(Slider), findsOneWidget);
    key.currentState!.reportMapError(WeatherMapOverlayState.sourceId);
    await tester.pumpAndSettle();
    expect(find.text('Weather unavailable. Try again later.'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  });
}

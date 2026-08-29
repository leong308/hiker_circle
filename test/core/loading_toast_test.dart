import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/loading_toast.dart';
import 'package:lottie/lottie.dart';

void main() {
  test('embeds the app icon in the original moving Lottie layer', () async {
    final raw = await rootBundle.loadString(
      'assets/animations/hiker_circle_loading.json',
    );
    final animation = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final layers = List<Map<String, dynamic>>.from(
      (animation['layers'] as List).map(
        (layer) => Map<String, dynamic>.from(layer as Map),
      ),
    );
    final logoLayer = layers.singleWhere(
      (layer) => layer['nm'] == 'HikerCircle App Icon',
    );
    final assets = List<Map<String, dynamic>>.from(
      (animation['assets'] as List).map(
        (asset) => Map<String, dynamic>.from(asset as Map),
      ),
    );

    expect(logoLayer['ty'], 2);
    expect(logoLayer['parent'], 10);
    expect(logoLayer['ip'], 162);
    expect(logoLayer['refId'], 'hiker_circle_app_icon');
    expect(layers.where((layer) => layer['nm'] == 'SENZO'), isEmpty);
    expect(
      assets.singleWhere((asset) => asset['id'] == 'hiker_circle_app_icon'),
      containsPair('p', 'HikerCircle-Loader-Transparent.png'),
    );
  });

  testWidgets('shows the Senzo-style animation with HikerCircle progress UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HikerCircleLoadingView(
            message: 'Loading nearby trails…',
            detail: 'Checking current route information.',
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('hiker-circle-loading-toast')), findsOneWidget);
    expect(
      find.byKey(const Key('hiker-circle-loading-animation')),
      findsOneWidget,
    );
    expect(find.byType(Lottie), findsOneWidget);
    expect(
      find.byKey(const Key('hiker-circle-loading-branded-animation')),
      findsOneWidget,
    );
    expect(find.text('Loading nearby trails…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('uses determinate progress when an operation reports it', (
    tester,
  ) async {
    final progress = ValueNotifier<double>(0.35);
    addTearDown(progress.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HikerCircleLoadingView(
            message: 'Preparing hike…',
            progress: progress,
          ),
        ),
      ),
    );

    var indicator = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('hiker-circle-loading-progress')),
    );
    expect(indicator.value, 0.35);

    progress.value = 0.8;
    await tester.pump();
    indicator = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('hiker-circle-loading-progress')),
    );
    expect(indicator.value, 0.8);
  });
}

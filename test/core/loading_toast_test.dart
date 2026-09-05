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
    final animationScale = tester.widget<Transform>(
      find.byKey(const Key('hiker-circle-loading-animation-scale')),
    );
    expect(animationScale.transform.getMaxScaleOnAxis(), 2);
    expect(find.text('Loading nearby trails…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets(
    'enlarges the compact branded animation without growing its card',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HikerCircleLoadingView(
              message: 'Searching documents…',
              compact: true,
            ),
          ),
        ),
      );

      expect(
        tester
            .getSize(find.byKey(const Key('hiker-circle-loading-animation')))
            .height,
        108,
      );
      final animationScale = tester.widget<Transform>(
        find.byKey(const Key('hiker-circle-loading-animation-scale')),
      );
      expect(animationScale.transform.getMaxScaleOnAxis(), 2);
    },
  );

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

  testWidgets('uses the linked compact Lottie for constrained loading states', (
    tester,
  ) async {
    final raw = await rootBundle.loadString(
      'assets/animations/loading_spinner.json',
    );
    final animation = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    expect(animation['layers'], isA<List>());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 20,
              child: HikerCircleMinorLoadingIndicator(size: 20),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Lottie), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.getSize(find.byType(HikerCircleMinorLoadingIndicator)),
      const Size.square(20),
    );
  });

  testWidgets('keeps measurable progress determinate', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HikerCircleMinorLoadingIndicator(value: 0.6)),
      ),
    );

    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, 0.6);
    expect(find.byType(Lottie), findsNothing);
  });

  testWidgets('auto-closes through the timeout callback', (tester) async {
    var timedOut = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              HikerCircleLoadingToastOverlay(
                message: 'Working…',
                timeout: const Duration(seconds: 30),
                onTimeout: () => timedOut = true,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 30));
    expect(timedOut, isTrue);
  });
}

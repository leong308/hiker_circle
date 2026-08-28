import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/loading_toast.dart';
import 'package:lottie/lottie.dart';

void main() {
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

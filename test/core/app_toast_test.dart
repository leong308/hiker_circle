import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/app_toast.dart';

void main() {
  testWidgets('shows an actionable HikerCircle glass toast', (tester) async {
    var actionCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => HikerCircleToast.show(
                  context,
                  'Your hike reminder is ready.',
                  tone: HikerCircleToastTone.success,
                  actionLabel: 'View',
                  onAction: () => actionCount += 1,
                ),
                child: const Text('Show toast'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show toast'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));

    expect(
      find.byKey(const ValueKey('hiker-circle-toast-glass')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(
      find.byKey(const ValueKey('hiker-circle-toast-close')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('hiker-circle-toast-action')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('hiker-circle-toast-action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    expect(actionCount, 1);
    expect(find.text('Your hike reminder is ready.'), findsNothing);
  });

  testWidgets('close button dismisses the toast', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => HikerCircleToast.show(
                  context,
                  'Swipe down or close this message.',
                ),
                child: const Text('Show toast'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show toast'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));
    await tester.tap(find.byKey(const ValueKey('hiker-circle-toast-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();

    expect(find.text('Swipe down or close this message.'), findsNothing);
  });
}

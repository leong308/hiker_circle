import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/verification_code_input.dart';

void main() {
  testWidgets('accepts a complete pasted verification code', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? completedCode;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 330,
              child: VerificationCodeInput(
                controller: controller,
                onCompleted: (value) => completedCode = value,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsNWidgets(6));
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.textAlign, TextAlign.center);
      expect(field.textAlignVertical, TextAlignVertical.center);
      expect(field.expands, isFalse);
    }
    await tester.enterText(find.byType(TextField).first, '079927');
    await tester.pump();

    expect(controller.text, '079927');
    expect(completedCode, '079927');
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .map((field) => field.controller?.text)
          .toList(),
      ['0', '7', '9', '9', '2', '7'],
    );
  });

  testWidgets('advances between slots and follows external controller clears', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VerificationCodeInput(controller: controller)),
      ),
    );

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '1');
    await tester.pump();
    expect(controller.text, '1');
    expect(tester.widget<TextField>(fields.at(1)).focusNode?.hasFocus, isTrue);

    controller.text = '123456';
    await tester.pump();
    expect(find.widgetWithText(TextField, '6'), findsOneWidget);

    controller.clear();
    await tester.pump();
    expect(
      tester
          .widgetList<TextField>(fields)
          .every((field) => field.controller?.text.isEmpty ?? false),
      isTrue,
    );
  });
  testWidgets('Paste code reads only on tap and handles copied messages', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var reads = 0;
    String? completed;
    String clipboard =
        'Your HikerCircle code is 012345. It expires in 5 minutes.';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          reads++;
          return {'text': clipboard};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VerificationCodeInput(
            controller: controller,
            onCompleted: (value) => completed = value,
          ),
        ),
      ),
    );
    expect(reads, 0);
    await tester.tap(find.text('Paste code'));
    await tester.pump();
    expect(controller.text, '012345');
    expect(completed, '012345');
    clipboard = '123456 and 654321';
    await tester.tap(find.text('Paste code'));
    await tester.pump();
    expect(controller.text, '012345');
    expect(find.textContaining('Copy the 6-digit code'), findsOneWidget);
    clipboard = '98 76 54';
    await tester.tap(find.text('Paste code'));
    await tester.pump();
    expect(controller.text, '987654');
  });

  testWidgets(
    'returning to the active code field restores focus without reading clipboard',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VerificationCodeInput(controller: controller)),
        ),
      );
      await tester.tap(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, '1');
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byType(TextField).at(1))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      expect(controller.text, '1');
    },
  );

  testWidgets('disabled verification does not offer paste', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VerificationCodeInput(controller: controller, enabled: false),
        ),
      ),
    );
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
  });
}

import 'package:flutter/material.dart';
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
}

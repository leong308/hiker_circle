import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/assistant/Data/hiker_circle_assistant_repository.dart';
import 'package:hiker_circle/assistant/View/hiker_circle_assistant_page.dart';

void main() {
  testWidgets('shows the AI thinking bubble and then the reviewed answer', (
    tester,
  ) async {
    final result = Completer<Map<String, dynamic>>();
    final repository = HikerCircleAssistantRepository(
      callable: (_) => result.future,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFF34A853)),
        home: HikerCircleAssistantPage(repository: repository),
      ),
    );

    expect(find.text('HikerCircle Assistant'), findsOneWidget);
    expect(find.text('UNPAID'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('hiker-circle-assistant-question')),
      'Where can I manage my passkey?',
    );
    await tester.tap(find.byKey(const Key('hiker-circle-assistant-send')));
    await tester.pump();

    expect(find.byKey(const Key('ai-thinking-indicator')), findsOneWidget);
    expect(find.text('Thinking'), findsOneWidget);

    result.complete(<String, dynamic>{
      'answer': 'Open Profile, App Settings, then Login security.',
      'responseMode': 'gemini_free_tier',
      'sources': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'login_security',
          'title': 'Login and account security',
        },
      ],
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-thinking-indicator')), findsNothing);
    expect(
      find.text('Open Profile, App Settings, then Login security.'),
      findsOneWidget,
    );
    expect(find.text('Login and account security'), findsOneWidget);
  });
}

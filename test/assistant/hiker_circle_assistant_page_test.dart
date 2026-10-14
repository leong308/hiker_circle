import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/assistant/Data/hiker_circle_assistant_history_store.dart';
import 'package:hiker_circle/assistant/Data/hiker_circle_assistant_repository.dart';
import 'package:hiker_circle/assistant/View/hiker_circle_assistant_page.dart';

void main() {
  testWidgets('conversation survives reopening and can be cleared', (
    tester,
  ) async {
    final history = _MemoryAssistantHistoryStore();
    List<Map<String, String>>? receivedHistory;
    final repository = HikerCircleAssistantRepository(
      callable: (_, location, context) async {
        receivedHistory = context;
        return {
          'answer': 'Open the trail card.',
          'responseMode': 'trail_search',
          'trails': [
            {
              'id': 'ridge-1',
              'name': 'Ridge Walk',
              'area': 'KL',
              'state': 'KL',
              'distanceKm': 4.2,
              'difficulty': 'easy',
              'estimatedDurationMinutes': 90,
            },
          ],
        };
      },
    );
    Widget page() => MaterialApp(
      home: HikerCircleAssistantPage(
        key: UniqueKey(),
        repository: repository,
        historyStore: history,
        onOpenTrail: (_) async {},
      ),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('hiker-circle-assistant-question')),
      'Find a trail',
    );
    await tester.tap(find.byKey(const Key('hiker-circle-assistant-send')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('Find a trail'), findsOneWidget);
    expect(find.text('Ridge Walk'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('hiker-circle-assistant-question')),
      'What about that one?',
    );
    await tester.tap(find.byKey(const Key('hiker-circle-assistant-send')));
    await tester.pumpAndSettle();
    expect(
      receivedHistory,
      contains(equals({'role': 'user', 'text': 'Find a trail'})),
    );
    await tester.tap(find.byKey(const Key('assistant-clear-chat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear chat'));
    await tester.pumpAndSettle();
    expect(find.text('Find a trail'), findsNothing);
    expect(history.messages, isEmpty);
  });

  testWidgets(
    'renders trail cards and navigation buttons as tappable actions',
    (tester) async {
      String? openedTrail;
      String? openedPage;
      final navigatorKey = GlobalKey<NavigatorState>();
      final repository = HikerCircleAssistantRepository(
        callable: (_, location, history) async => {
          'answer': 'Here is a trail and a page.',
          'responseMode': 'trail_search',
          'sources': <Map<String, dynamic>>[],
          'trails': [
            {
              'id': 'ridge-1',
              'name': 'Ridge Walk',
              'area': 'Kuala Lumpur',
              'state': 'KL',
              'distanceKm': 4.2,
              'difficulty': 'moderate',
              'estimatedDurationMinutes': 90,
            },
          ],
          'action': {
            'type': 'navigate',
            'destinationId': 'trails',
            'label': 'Open Explore trails',
          },
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: HikerCircleAssistantPage(
            repository: repository,
            onOpenTrail: (id) async {
              openedTrail = id;
              await navigatorKey.currentState!.push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: Center(child: Text('Trail details')),
                  ),
                ),
              );
            },
            onNavigate: (id) {
              openedPage = id;
            },
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('hiker-circle-assistant-question')),
        'What are the available trails in Penang?',
      );
      await tester.tap(find.byKey(const Key('hiker-circle-assistant-send')));
      await tester.pumpAndSettle();
      expect(find.text('Ridge Walk'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('assistant-trail-ridge-1')),
      );
      await tester.tap(find.byKey(const Key('assistant-trail-ridge-1')));
      await tester.pumpAndSettle();
      expect(openedTrail, 'ridge-1');
      expect(find.text('Trail details'), findsOneWidget);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('HikerCircle Assistant'), findsOneWidget);
      expect(find.text('Ridge Walk'), findsOneWidget);
      await tester.tap(find.text('Open Explore trails'));
      expect(openedPage, 'trails');
    },
  );

  testWidgets('adds SOS and First-Aid buttons from the question context', (
    tester,
  ) async {
    final destinations = <String>[];
    final repository = HikerCircleAssistantRepository(
      callable: (question, location, history) async => {
        'answer': question.contains('medical')
            ? 'Review the matching first-aid guidance.'
            : 'Call 999 or 112 when there is immediate danger.',
        'responseMode': 'curated_guide',
        'sources': <Map<String, dynamic>>[],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HikerCircleAssistantPage(
          repository: repository,
          onNavigate: destinations.add,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('hiker-circle-assistant-question')),
      'Who to contact when I faced emergencies?',
    );
    await tester.tap(find.byKey(const Key('hiker-circle-assistant-send')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open SOS'));
    await tester.tap(find.text('Open SOS'));
    expect(destinations, ['sos']);

    await tester.enterText(
      find.byKey(const Key('hiker-circle-assistant-question')),
      'Where is the medical first-aid guide?',
    );
    await tester.tap(find.byKey(const Key('hiker-circle-assistant-send')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open First-Aid Guide'));
    await tester.tap(find.text('Open First-Aid Guide'));
    expect(destinations, ['sos', 'first_aid']);
  });

  testWidgets('shows the AI thinking bubble and then the reviewed answer', (
    tester,
  ) async {
    final result = Completer<Map<String, dynamic>>();
    final repository = HikerCircleAssistantRepository(
      callable: (_, location, history) => result.future,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFF34A853)),
        home: HikerCircleAssistantPage(repository: repository),
      ),
    );

    expect(find.text('HikerCircle Assistant'), findsOneWidget);
    expect(find.text('GUIDES'), findsOneWidget);
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
      'responseMode': 'curated_guide',
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

class _MemoryAssistantHistoryStore extends HikerCircleAssistantHistoryStore {
  _MemoryAssistantHistoryStore() : super(ownerPhoneNumber: 'test-account');
  List<Map<String, dynamic>> messages = [];

  @override
  Future<List<Map<String, dynamic>>> load() async => messages;

  @override
  Future<void> save(List<Map<String, dynamic>> value) async {
    messages = value;
  }

  @override
  Future<void> clear() async {
    messages = [];
  }
}

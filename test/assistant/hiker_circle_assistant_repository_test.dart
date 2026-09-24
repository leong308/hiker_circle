import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/assistant/Data/hiker_circle_assistant_repository.dart';

void main() {
  test('normalizes a question and parses reviewed sources', () async {
    String? receivedQuestion;
    final repository = HikerCircleAssistantRepository(
      callable: (question) async {
        receivedQuestion = question;
        return <String, dynamic>{
          'answer': 'Open Profile, App Settings, then Login security.',
          'responseMode': 'gemini_free_tier',
          'sources': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'login_security',
              'title': 'Login and account security',
            },
          ],
        };
      },
    );

    final result = await repository.ask('  How   do I manage my passkey?  ');

    expect(receivedQuestion, 'How do I manage my passkey?');
    expect(result.answer, contains('Login security'));
    expect(result.sources.single.id, 'login_security');
    expect(result.isEmergency, isFalse);
  });

  test('identifies a curated emergency answer', () async {
    final repository = HikerCircleAssistantRepository(
      callable: (_) async => <String, dynamic>{
        'answer': 'Call 999 or 112.',
        'responseMode': 'curated_emergency',
        'notice': 'Answered locally.',
        'sources': <Map<String, dynamic>>[],
      },
    );

    final result = await repository.ask('I need emergency help');

    expect(result.isEmergency, isTrue);
    expect(result.notice, 'Answered locally.');
  });

  test('rejects a question before invoking the callable', () async {
    var called = false;
    final repository = HikerCircleAssistantRepository(
      callable: (_) async {
        called = true;
        return <String, dynamic>{};
      },
    );

    await expectLater(
      repository.ask('x'),
      throwsA(
        isA<HikerCircleAssistantException>().having(
          (error) => error.code,
          'code',
          'invalid-argument',
        ),
      ),
    );
    expect(called, isFalse);
  });
}

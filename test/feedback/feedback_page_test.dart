import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/feedback/feedback_page.dart';
import 'package:hiker_circle/feedback/feedback_capture_form.dart';
import 'package:hiker_circle/feedback/feedback_repository.dart';
import 'package:hiker_circle/core/widgets/loading_toast.dart';
import 'package:hiker_circle/core/widgets/page_header_style.dart';

class TestFeedbackRepository extends FeedbackRepository {
  final pending = Completer<void>();
  final drafts = <FeedbackDraft>[];
  int historyRequests = 0;
  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> reports({required bool admin}) {
    historyRequests++;
    return Stream<QuerySnapshot<Map<String, dynamic>>>.error(
      StateError('test history'),
    );
  }

  @override
  FeedbackDraft draft(String category, String message, Uint8List? screenshot) =>
      FeedbackDraft(
        id: 'same-report',
        uid: 'test-user',
        category: category,
        message: message,
        screenshot: screenshot,
      );
  @override
  Future<void> submit(FeedbackDraft draft) {
    drafts.add(draft);
    return pending.future;
  }
}

void main() {
  test('permission denial is not mislabeled as a connection failure', () {
    for (final code in ['unauthorized', 'permission-denied']) {
      expect(
        feedbackSubmissionError(
          FirebaseException(plugin: 'firebase_storage', code: code),
        ),
        contains('permission issue, not your connection'),
      );
    }
    expect(
      feedbackSubmissionError(TimeoutException('timeout')),
      contains('could not confirm delivery'),
    );
    expect(
      feedbackSubmissionError(
        FirebaseException(plugin: 'firebase_auth', code: 'unauthenticated'),
      ),
      contains('sign in again'),
    );
  });
  testWidgets('capture preview button prevents duplicate requests', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HikerFeedbackCaptureForm(
            onSubmit: (text, {extras}) {
              calls++;
              return pending.future;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Review screenshot'));
    await tester.pump();
    await tester.tap(find.text('Preparing preview…'));
    expect(calls, 1);
    pending.complete();
    await tester.pump();
  });
  testWidgets('capture returns to the app and opens annotation mode', (
    tester,
  ) async {
    late BuildContext homeContext;
    await tester.pumpWidget(
      BetterFeedback(
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              homeContext = context;
              return Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const FeedbackPage(),
                    ),
                  ),
                  child: const Text('Open feedback'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open feedback'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark a screenshot'));
    await tester.pumpAndSettle();
    expect(BetterFeedback.of(homeContext).isVisible, isTrue);
    expect(find.byType(FeedbackPage), findsNothing);
    BetterFeedback.of(homeContext).hide();
    await tester.pumpAndSettle();
    expect(find.text('Open feedback'), findsOneWidget);
  });
  test('feedback validation enforces trimmed content and length', () {
    expect(validateFeedback('          '), isNotNull);
    expect(validateFeedback('too short'), isNotNull);
    expect(validateFeedback('The trail page did not load.'), isNull);
    expect(validateFeedback('x' * 4001), isNotNull);
  });

  testWidgets('feedback landing has text, annotation, and history options', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: FeedbackPage()));
    expect(find.text('Write feedback'), findsOneWidget);
    expect(find.text('Mark a screenshot'), findsOneWidget);
    expect(find.byTooltip('My feedback'), findsOneWidget);
    expect(find.text('My feedback'), findsNothing);
    expect(find.byTooltip('Feedback inbox'), findsNothing);
    expect(find.byType(PageHeaderAppBar), findsOneWidget);
  });

  testWidgets(
    'top-right history icon opens My feedback and returns to the landing page',
    (tester) async {
      final repository = TestFeedbackRepository();
      await tester.pumpWidget(
        MaterialApp(home: FeedbackPage(repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.history_rounded), findsOneWidget);
      final header = find.byType(PageHeaderAppBar);
      expect(
        tester.getCenter(find.byTooltip('My feedback')).dx,
        greaterThan(tester.getCenter(header).dx),
      );
      await tester.tap(find.byTooltip('My feedback'));
      await tester.pumpAndSettle();
      expect(repository.historyRequests, 1);
      expect(find.text('My feedback'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Ideas & issues'), findsOneWidget);
    },
  );

  testWidgets('empty feedback cannot be submitted', (tester) async {
    final repository = TestFeedbackRepository();
    await tester.pumpWidget(
      MaterialApp(home: FeedbackComposePage(repository: repository)),
    );
    await tester.ensureVisible(find.text('Send feedback'));
    await tester.tap(find.text('Send feedback'));
    await tester.pump();
    expect(repository.drafts, isEmpty);
    expect(
      find.text('Please add at least 10 characters of detail.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'submission shows primary popup then success after acknowledgment',
    (tester) async {
      final repository = TestFeedbackRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: FeedbackComposePage(
            repository: repository,
            initialText: 'The trail page did not load.',
          ),
        ),
      );
      await tester.ensureVisible(find.text('Send feedback'));
      await tester.tap(find.text('Send feedback'));
      await tester.pump();
      expect(find.byType(HikerCircleLoadingToast), findsOneWidget);
      expect(find.text('Thank you'), findsNothing);
      repository.pending.complete();
      await tester.pump();
      expect(find.byType(HikerCircleLoadingToast), findsNothing);
      expect(find.text('Thank you'), findsOneWidget);
    },
  );

  testWidgets('timeout unlocks screen and retry reuses immutable draft', (
    tester,
  ) async {
    final repository = TestFeedbackRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: FeedbackComposePage(
          repository: repository,
          initialText: 'The trail page did not load.',
        ),
      ),
    );
    await tester.ensureVisible(find.text('Send feedback'));
    await tester.tap(find.text('Send feedback'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    expect(find.byType(HikerCircleLoadingToast), findsNothing);
    expect(find.textContaining('could not confirm delivery'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Retry delivery'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Retry delivery'));
    await tester.pump();
    expect(repository.drafts.length, 2);
    expect(identical(repository.drafts.first, repository.drafts.last), isTrue);
    repository.pending.complete();
    await tester.pump();
    expect(find.text('Thank you'), findsOneWidget);
  });
}

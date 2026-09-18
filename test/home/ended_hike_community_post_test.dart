import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/hiker_circle_firebase_repository.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/home/Data/planned_hike_state_service.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/View/hike_share_preview_page.dart';
import 'next_hike_briefing_test.dart' as fixtures;

const pending = ActiveHikeEndResult(
  cloudSynced: false,
  sessionId: 'local-hike',
  completed: false,
  status: 'pending',
);
const completed = ActiveHikeEndResult(
  cloudSynced: true,
  sessionId: 'cloud-hike',
  completed: true,
  status: 'completed',
);
const abandoned = ActiveHikeEndResult(
  cloudSynced: true,
  sessionId: 'local-hike',
  completed: false,
  status: 'abandoned',
);

class SharingRepository extends HikerCircleFirebaseRepository {
  ActiveHikeEndResult nextCompletion = completed;
  int syncs = 0;
  int posts = 0;
  HikeSummaryReport? submittedSummary;
  ActiveHikeSession? submittedHike;
  String? submittedCaption;
  DateTime? retriedEnd;

  @override
  Future<ActiveHikeEndResult> endHikeSession({
    required AppSession session,
    required ActiveHikeSession activeHike,
    HikeSummaryReport? summary,
  }) async {
    syncs++;
    retriedEnd = summary?.endedAt;
    return nextCompletion;
  }

  @override
  Future<void> createCompletedHikePost({
    required AppSession session,
    required ActiveHikeSession activeHike,
    HikeSummaryReport? summary,
    String caption = 'Trail completed safely.',
    String postType = 'completed_hike',
    List<CommunityPostImageUpload> images = const [],
  }) async {
    posts++;
    submittedSummary = summary;
    submittedHike = activeHike;
    submittedCaption = caption;
  }
}

void main() {
  final plan = PlannedHikeStateResolver.resolve(
    upcomingHike: fixtures.testHike(),
    liveTrails: [],
    emergencyContactsSelected: true,
    phoneBatteryLevel: 80,
  );
  final now = DateTime.utc(2026, 9, 18, 8);
  final session = AppSession(phoneNumber: '+60123456789', signedInAt: now);
  final hike = ActiveHikeSession(
    sessionId: 'local-hike',
    draft: HikeSessionDraft.fromTrail(plan.trail),
    startedAt: now,
    batteryLevel: 80,
    queuedUpdates: 0,
    manualPins: 0,
    checkIns: 0,
  );
  final report = HikeSummaryReport.fromActiveHike(
    activeHike: hike,
    endedAt: now.add(const Duration(minutes: 3)),
  );
  Future<void> post(SharingRepository repository, ActiveHikeEndResult result) =>
      repository.createEndedHikePost(
        session: session,
        activeHike: hike,
        summary: report,
        endResult: result,
        caption: 'My short hike',
      );

  test(
    'pending completion retries and posts with canonical cloud session',
    () async {
      final repository = SharingRepository();
      await post(repository, pending);
      expect(repository.syncs, 1);
      expect(repository.posts, 1);
      expect(repository.submittedHike!.sessionId, 'cloud-hike');
      expect(repository.submittedSummary!.sessionId, 'cloud-hike');
      expect(repository.retriedEnd, report.endedAt);
      expect(repository.submittedSummary!.duration, report.duration);
      expect(repository.submittedCaption, 'My short hike');
    },
  );

  test('offline failure keeps posting retryable; reconnect succeeds', () async {
    final repository = SharingRepository()..nextCompletion = pending;
    await expectLater(
      post(repository, pending),
      throwsA(
        isA<HikerCircleFirebaseRepositoryException>().having(
          (error) => error.message,
          'actionable message',
          contains('Post to Community again'),
        ),
      ),
    );
    expect(repository.posts, 0);
    repository.nextCompletion = completed;
    await post(repository, pending);
    expect(repository.syncs, 2);
    expect(repository.posts, 1);
  });

  test('confirmed completion does not require ending the hike again', () async {
    final repository = SharingRepository();
    await post(repository, completed);
    expect(repository.syncs, 0);
    expect(repository.posts, 1);
  });

  test('abandoned result never publishes a completed hike', () async {
    final repository = SharingRepository()..nextCompletion = abandoned;
    await expectLater(
      post(repository, pending),
      throwsA(isA<HikerCircleFirebaseRepositoryException>()),
    );
    await expectLater(
      post(repository, abandoned),
      throwsA(isA<HikerCircleFirebaseRepositoryException>()),
    );
    expect(repository.syncs, 1);
    expect(repository.posts, 0);
  });

  testWidgets('posting failure preserves caption and offers another attempt', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HikeSharePreviewPage(
          session: session,
          report: report,
          activeHike: hike,
          onPostToCommunity: (caption, images) async {
            attempts++;
            expect(caption, 'Keep this caption');
            throw const HikerCircleFirebaseRepositoryException(
              'Reconnect and try again.',
            );
          },
          onShareExternally: (_) async {},
        ),
      ),
    );
    expect(
      find.textContaining('Community posting is unavailable'),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const Key('hike-share-caption')),
      'Keep this caption',
    );
    await tester.tap(find.byKey(const Key('post-hike-to-community')));
    await tester.pumpAndSettle();
    expect(find.text('Reconnect and try again.'), findsOneWidget);
    expect(find.text('Keep this caption'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('post-hike-to-community')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  testWidgets('slow request stays single-flight after overlay timeout', (
    tester,
  ) async {
    var attempts = 0;
    final response = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: HikeSharePreviewPage(
          session: session,
          report: report,
          activeHike: hike,
          onPostToCommunity: (_, _) {
            attempts++;
            return response.future;
          },
          onShareExternally: (_) async {},
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('post-hike-to-community')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('post-hike-to-community')))
          .onPressed,
      isNull,
    );
    expect(attempts, 1);
    response.completeError(
      const HikerCircleFirebaseRepositoryException('Try again.'),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('post-hike-to-community')))
          .onPressed,
      isNotNull,
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/View/upcoming_hike_join_request_dialog.dart';

void main() {
  testWidgets('host can accept a pending solo-hike join request', (
    tester,
  ) async {
    bool? accepted;
    const review = UpcomingHikeJoinRequestReview(
      requestId: 'join_1',
      hikeId: 'hike_1',
      status: 'pending',
      reason: '',
      requesterName: 'Aina',
      trailName: 'Bukit Gasing',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: UpcomingHikeJoinRequestDialog(
          review: review,
          onResolve: (accept) async {
            accepted = accept;
            return const UpcomingHikeJoinRequestReview(
              requestId: 'join_1',
              hikeId: 'hike_1',
              status: 'accepted',
              reason: 'accepted',
              requesterName: 'Aina',
              trailName: 'Bukit Gasing',
            );
          },
        ),
      ),
    );

    expect(find.text('New hike join request'), findsOneWidget);
    expect(
      find.text('Aina would like to join your solo hike.'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('accept-upcoming-hike-join-request')),
    );
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
  });

  testWidgets('removed hike link is clearly identified as expired', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UpcomingHikeJoinRequestDialog(
          review: const UpcomingHikeJoinRequestReview(
            requestId: 'join_1',
            hikeId: 'hike_1',
            status: 'expired',
            reason: 'hike_removed',
            requesterName: 'Aina',
            trailName: 'Bukit Gasing',
          ),
          onResolve: (_) => throw StateError('must not resolve'),
        ),
      ),
    );

    expect(find.text('Hike no longer available'), findsOneWidget);
    expect(find.textContaining('request has expired'), findsOneWidget);
    expect(
      find.byKey(const Key('accept-upcoming-hike-join-request')),
      findsNothing,
    );
  });
}

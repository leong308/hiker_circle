import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/View/trail_rating_dialog.dart';

void main() {
  testWidgets('requires stars and difficulty and submits route feedback', (
    tester,
  ) async {
    TrailRatingFeedback? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => TrailRatingDialog(
                  trailName: 'Pine Ridge Trail',
                  onSubmit: (feedback) async => submitted = feedback,
                ),
              ),
              child: const Text('Finish hike'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Finish hike'));
    await tester.pumpAndSettle();

    expect(find.text('Rate this route'), findsOneWidget);
    final submitButton = tester.widget<FilledButton>(
      find.byKey(const Key('submit-trail-rating')),
    );
    expect(submitButton.onPressed, isNull);

    await tester.tap(find.byKey(const Key('trail-rating-star-4')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('submit-trail-rating')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('trail-difficulty-moderate')));
    await tester.enterText(
      find.byKey(const Key('trail-rating-comment')),
      'Clear route with a muddy section near the summit.',
    );
    await tester.tap(find.byKey(const Key('submit-trail-rating')));
    await tester.pumpAndSettle();

    expect(submitted?.rating, 4);
    expect(submitted?.difficulty, 'moderate');
    expect(
      submitted?.comment,
      'Clear route with a muddy section near the summit.',
    );
    expect(find.text('Rate this route'), findsNothing);
  });
}

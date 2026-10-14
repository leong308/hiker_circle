import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/admin/View/community_integrity_panel.dart';

class _Document extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Document(this.value);
  final Map<String, dynamic> value;
  @override
  Map<String, dynamic> data() => value;
}

class _Review extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Review(this.value);
  final Map<String, dynamic> value;
  @override
  Map<String, dynamic> data() => value;
  @override
  String get id => 'a' * 64;
}

class _Queue extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  _Queue(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'review queue uses the app theme and advisory language in $brightness',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: SingleChildScrollView(
                child: CommunityIntegrityPanel(
                  reviews: Stream.value(
                    _Queue([
                      _Review({
                        'status': 'pending',
                        'contentType': 'comment',
                        'flaggedAtMillis': 1,
                        'model': 'local-rules',
                        'reasons': ['Possible spam or scam'],
                      }),
                    ]),
                  ),
                  health: Stream.value(
                    _Document({
                      'status': 'completed',
                      'lastRunAtMillis': 1791160000000,
                    }),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Every 30 min'), findsOneWidget);
        expect(find.text('1 awaiting review'), findsOneWidget);
        expect(find.text('Possible spam or scam'), findsOneWidget);
        expect(find.textContaining('Content stays visible'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'sensitive flags appear without an AI model even when checks are deferred',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CommunityIntegrityPanel(
                reviews: Stream.value(
                  _Queue([
                    _Review({
                      'status': 'pending',
                      'contentType': 'post',
                      'flaggedAtMillis': 1,
                      'model': null,
                      'reasons': [
                        'Sensitive information: manual review required',
                      ],
                    }),
                  ]),
                ),
                health: Stream.value(
                  _Document({
                    'status': 'deferred',
                    'errorCode': 'daily-budget',
                    'lastRunAtMillis': 1791160000000,
                    'checked': 1,
                    'flagged': 1,
                    'deferred': 2,
                  }),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('Sensitive information: manual review required'),
        findsOneWidget,
      );
      expect(find.text('Post · Manual check'), findsOneWidget);
      expect(find.text('1 awaiting review'), findsOneWidget);
      expect(find.textContaining('2 items remain queued'), findsOneWidget);
      expect(
        find.textContaining('Content scan failed'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'provider outage displays deferred status without blocking manual moderation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommunityIntegrityPanel(
              reviews: Stream.value(_Queue([])),
              health: Stream.value(
                _Document({
                  'status': 'deferred',
                  'lastRunAtMillis': 1791160000000,
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('items remain queued'), findsOneWidget);
      expect(
        find.textContaining('Unchecked content has not passed'),
        findsOneWidget,
      );
      expect(
        find.textContaining('No detected flags awaiting review.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

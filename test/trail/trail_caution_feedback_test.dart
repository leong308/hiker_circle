import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hiker_circle/core/widgets/community_hazard_marker.dart';
import 'package:hiker_circle/trail/Data/trail_caution_service.dart';
import 'package:hiker_circle/trail/View/caution_media.dart';
import 'package:hiker_circle/trail/View/trail_caution_details.dart';

class CautionService extends TrailCautionService {
  final calls = <Map<String, dynamic>>[];
  bool failOnce = false;
  @override
  Future<bool> update(
    String id,
    String action, {
    required String requestId,
    String description = '',
    List<PendingCautionMedia> files = const [],
    bool confirmed = false,
  }) async {
    calls.add({
      'id': id,
      'action': action,
      'requestId': requestId,
      'description': description,
      'files': files,
      'confirmed': confirmed,
    });
    if (failOnce) {
      failOnce = false;
      throw StateError('Connection interrupted');
    }
    return true;
  }
}

const report = CommunityHazard(
  id: 'caution',
  type: 'Fallen tree',
  latitude: 3,
  longitude: 101,
  status: 'resolved',
);
Future<void> open(
  WidgetTester tester,
  CautionService service,
  String action,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showCautionEvidenceDialog(
                context,
                report,
                action,
                service: service,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'reopening requires explicit confirmation and evidence, then sends both together',
    (tester) async {
      final service = CautionService();
      await open(tester, service, 'reopen');
      await tester.tap(find.text('Reopen with evidence'));
      await tester.pumpAndSettle();
      expect(service.calls, isEmpty);
      expect(
        find.textContaining('Confirm the caution is present and add a note'),
        findsOneWidget,
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reopen with evidence'));
      await tester.pumpAndSettle();
      expect(service.calls, isEmpty);
      await tester.enterText(
        find.byType(TextField),
        'The tree is still blocking the route.',
      );
      await tester.tap(find.text('Reopen with evidence'));
      await tester.pumpAndSettle();
      expect(service.calls, hasLength(1));
      expect(service.calls.single['confirmed'], isTrue);
      expect(service.calls.single['description'], contains('tree'));
      expect(service.calls.single['action'], 'reopen');
      expect(find.text('Is this caution present again?'), findsNothing);
    },
  );
  testWidgets('a resolution can be submitted without optional text or media', (
    tester,
  ) async {
    final service = CautionService();
    await open(tester, service, 'resolve');
    expect(find.text('Add photos or videos'), findsOneWidget);
    await tester.tap(find.text('Submit update'));
    await tester.pumpAndSettle();
    expect(service.calls.single['description'], '');
    expect(service.calls.single['files'], isEmpty);
    expect(service.calls.single['action'], 'resolve');
  });
  testWidgets(
    'failed evidence upload keeps the draft and retries with the same request identity',
    (tester) async {
      final service = CautionService()..failOnce = true;
      await open(tester, service, 'resolve');
      await tester.enterText(
        find.byType(TextField),
        'The damaged bridge has been repaired.',
      );
      await tester.tap(find.text('Submit update'));
      await tester.pumpAndSettle();
      expect(find.text('Connection interrupted'), findsOneWidget);
      expect(
        find.text('The damaged bridge has been repaired.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Submit update'));
      await tester.pumpAndSettle();
      expect(service.calls, hasLength(2));
      expect(service.calls.first['requestId'], service.calls.last['requestId']);
      expect(
        service.calls.first['description'],
        service.calls.last['description'],
      );
    },
  );
  test(
    'combined media larger than fifty MB is rejected before any upload',
    () async {
      final file = XFile.fromData(Uint8List(1), name: 'proof.jpg');
      final files = [
        PendingCautionMedia(
          file: file,
          sizeBytes: 30 * 1024 * 1024,
          contentType: 'image/jpeg',
        ),
        PendingCautionMedia(
          file: file,
          sizeBytes: 21 * 1024 * 1024,
          contentType: 'image/jpeg',
        ),
      ];
      await expectLater(
        TrailCautionService().upload('caution', files),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('50 MB'),
          ),
        ),
      );
    },
  );
  testWidgets(
    'photo preview opens a full screen zoomable viewer and returns to the caution',
    (tester) async {
      final media = [
        {'url': 'https://example.test/photo.jpg', 'contentType': 'image/jpeg'},
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CautionMediaStrip(media: media)),
        ),
      );
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(find.byType(CautionMediaViewer), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('1 / 1'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(CautionMediaStrip), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

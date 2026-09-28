import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every first-aid topic uses the scenario response guide', () async {
    final raw = await File('assets/guides/first_aid_guide.json').readAsString();
    final document = jsonDecode(raw) as Map<String, dynamic>;
    final topics = (document['topics'] as List).cast<Map<String, dynamic>>();

    expect(document['region'], 'MY');
    expect(topics, hasLength(7));
    expect(
      topics.map((topic) => topic['id']),
      containsAll(<String>{
        'falls_injury',
        'bleeding',
        'sprain',
        'heat_exhaustion',
        'snake_bite',
        'lost_stranded',
        'severe_weather',
      }),
    );

    final scenarioIds = <String>{};
    for (final topic in topics) {
      expect(topic.containsKey('video'), isFalse, reason: '${topic['id']}');
      expect(
        topic.containsKey('videoUnavailableReason'),
        isFalse,
        reason: '${topic['id']}',
      );

      final steps = (topic['steps'] as List).cast<String>();
      expect(
        steps,
        hasLength(greaterThanOrEqualTo(5)),
        reason: '${topic['id']}',
      );

      final scenarios = (topic['scenarios'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        scenarios,
        hasLength(greaterThanOrEqualTo(4)),
        reason: '${topic['id']}',
      );
      for (final scenario in scenarios) {
        final id = scenario['id'] as String;
        expect(scenarioIds.add(id), isTrue, reason: 'Duplicate scenario $id');
        expect(scenario['title'], isNotEmpty, reason: id);
        expect(scenario['summary'], isNotEmpty, reason: id);
        expect(scenario['urgency'], isNotEmpty, reason: id);
        expect((scenario['steps'] as List), hasLength(5), reason: id);
        expect((scenario['avoid'] as List), isNotEmpty, reason: id);
        expect(scenario['referenceName'], isNotEmpty, reason: id);
        final reference = Uri.parse(scenario['referenceUrl'] as String);
        expect(reference.scheme, 'https', reason: id);
        expect(reference.host, isNotEmpty, reason: id);
      }
    }

    expect(scenarioIds, hasLength(36));
  });

  test('retired tutorial media is absent from the manifest', () async {
    final raw = await File('assets/guides/first_aid_guide.json').readAsString();

    expect(raw, isNot(contains('first_aid/videos/')));
    expect(raw, isNot(contains('storagePath')));
    expect(raw, isNot(contains('downloadUrl')));
    expect(raw, isNot(contains('.mp4')));
  });
}

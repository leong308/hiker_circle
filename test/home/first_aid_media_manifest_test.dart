import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'every first-aid category has a complete offline video manifest',
    () async {
      final raw = await File(
        'assets/guides/first_aid_guide.json',
      ).readAsString();
      final document = jsonDecode(raw) as Map<String, dynamic>;
      final topics = (document['topics'] as List).cast<Map<String, dynamic>>();

      expect(topics, hasLength(7));
      final paths = <String>{};
      for (final topic in topics) {
        final steps = (topic['steps'] as List).cast<String>();
        final video = topic['video'] as Map<String, dynamic>;
        final storagePath = video['storagePath'] as String;

        expect(
          steps.length,
          greaterThanOrEqualTo(5),
          reason: '${topic['id']} needs a complete response guide',
        );
        expect(topic['guidanceSourceUrl'], startsWith('https://'));
        expect(
          storagePath,
          matches(RegExp(r'^first_aid/videos/[a-z0-9_-]+_v\d+\.mp4$')),
        );
        expect(
          paths.add(storagePath),
          isTrue,
          reason: 'Each category must have its own tutorial object',
        );
        expect(
          video['sourceUrl'],
          startsWith('https://www.dvidshub.net/video/'),
        );
        expect(video['license'], contains('Public domain'));
        expect(video['expectedBytes'], greaterThan(0));
        expect(video['version'], greaterThan(0));
      }
    },
  );
}

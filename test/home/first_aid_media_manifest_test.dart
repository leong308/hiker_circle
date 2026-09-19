import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Data/first_aid_video_cache_service.dart';
import 'package:hiker_circle/home/Model/first_aid_video.dart';

void main() {
  test('cached tutorial opens with no initialized Firebase app', () async {
    final directory = await Directory.systemTemp.createTemp(
      'first_aid_no_firebase_',
    );
    addTearDown(() => directory.delete(recursive: true));
    const video = FirstAidVideo(
      title: 'Offline tutorial',
      storagePath: 'first_aid/video.mp4',
      durationLabel: '',
      attribution: '',
      license: '',
      sourceUrl: '',
      version: 1,
      expectedBytes: 4,
    );
    final file = File(
      '${directory.path}/first_aid/videos/${video.cacheFileName('topic')}',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3, 4]);
    final service = FirstAidVideoCacheService(
      supportDirectory: () async => directory,
    );
    expect(
      (await service.cache(topicId: 'topic', video: video)).path,
      file.path,
    );
    await file.delete();
    await expectLater(
      service.cache(topicId: 'topic', video: video),
      throwsA(anything),
    );
  });

  test(
    'only verified KKM media is offered; unmatched topics stay explicit',
    () async {
      final raw = await File(
        'assets/guides/first_aid_guide.json',
      ).readAsString();
      final document = jsonDecode(raw) as Map<String, dynamic>;
      final topics = (document['topics'] as List).cast<Map<String, dynamic>>();
      expect(document['region'], 'MY');
      expect(topics, hasLength(7));
      expect(raw, isNot(contains('dvidshub')));
      final approved = <String>{};
      for (final topic in topics) {
        expect((topic['steps'] as List).length, greaterThanOrEqualTo(5));
        if (topic['video'] == null) {
          expect(topic['videoUnavailableReason'], contains('No matching KKM'));
          continue;
        }
        approved.add(topic['id'] as String);
        final data = topic['video'] as Map<String, dynamic>;
        final video = FirstAidVideo.fromJson(data);
        expect(Uri.parse(video.sourceUrl).host, 'infosihat.moh.gov.my');
        expect(
          Uri.parse(data['downloadUrl'] as String).host,
          'infosihat.moh.gov.my',
        );
        expect(video.licenseUrl, 'https://infosihat.moh.gov.my/faq.html');
        expect(video.version, 2);
        expect(
          video.storagePath,
          matches(r'^first_aid/videos/kkm_[a-z_]+_v2\.mp4$'),
        );
        expect(video.sha256, matches(r'^[a-f0-9]{64}$'));
        expect(video.expectedBytes, greaterThan(0));
        expect(video.scopeNote, isNotEmpty);
        expect(video.language, 'Bahasa Melayu');
        expect(video.cacheFileName(topic['id'] as String), endsWith('_v2.mp4'));
      }
      expect(approved, {'heat_exhaustion', 'severe_weather'});
    },
  );

  test('cache rejects altered bytes even when length matches', () async {
    final directory = await Directory.systemTemp.createTemp(
      'first_aid_integrity_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/video.mp4');
    final bytes = utf8.encode('approved original');
    final video = FirstAidVideo(
      title: '',
      storagePath: '',
      durationLabel: '',
      attribution: '',
      license: '',
      sourceUrl: '',
      version: 2,
      expectedBytes: bytes.length,
      sha256: crypto.sha256.convert(bytes).toString(),
    );
    expect(await isFirstAidVideoCacheValid(file, video), isFalse);
    await file.writeAsBytes(bytes);
    expect(await isFirstAidVideoCacheValid(file, video), isTrue);
    await file.writeAsBytes(List.filled(bytes.length, 0));
    expect(await isFirstAidVideoCacheValid(file, video), isFalse);
    await file.writeAsBytes([1]);
    expect(await isFirstAidVideoCacheValid(file, video), isFalse);
  });
}

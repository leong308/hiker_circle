import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../Model/first_aid_video.dart';

class FirstAidVideoCacheService {
  FirstAidVideoCacheService({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  static final FirstAidVideoCacheService instance = FirstAidVideoCacheService();

  final FirebaseStorage _storage;
  final Map<String, Future<File>> _downloads = <String, Future<File>>{};

  Future<File> cache({required String topicId, required FirstAidVideo video}) {
    final key = '${video.storagePath}#${video.version}';
    return _downloads.putIfAbsent(key, () async {
      try {
        return await _cache(topicId: topicId, video: video);
      } catch (_) {
        _downloads.remove(key);
        rethrow;
      }
    });
  }

  Future<bool> isCached({
    required String topicId,
    required FirstAidVideo video,
  }) async {
    final file = await _cachedFile(topicId: topicId, video: video);
    return _isValid(file, video.expectedBytes);
  }

  Future<File> _cache({
    required String topicId,
    required FirstAidVideo video,
  }) async {
    if (video.storagePath.isEmpty) {
      throw const FormatException('The tutorial storage path is missing.');
    }

    final target = await _cachedFile(topicId: topicId, video: video);
    if (await _isValid(target, video.expectedBytes)) return target;

    await target.parent.create(recursive: true);
    final partial = File('${target.path}.part');
    if (await partial.exists()) await partial.delete();

    try {
      await _storage
          .ref(video.storagePath)
          .writeToFile(partial)
          .timeout(const Duration(minutes: 4));
      if (!await _isValid(partial, video.expectedBytes)) {
        throw const FileSystemException(
          'The downloaded tutorial is incomplete.',
        );
      }

      if (await target.exists()) await target.delete();
      final completed = await partial.rename(target.path);
      await _removeOlderVersions(topicId: topicId, keep: completed.path);
      return completed;
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  Future<File> _cachedFile({
    required String topicId,
    required FirstAidVideo video,
  }) async {
    final support = await getApplicationSupportDirectory();
    return File(
      '${support.path}${Platform.pathSeparator}first_aid${Platform.pathSeparator}videos${Platform.pathSeparator}${video.cacheFileName(topicId)}',
    );
  }

  Future<bool> _isValid(File file, int? expectedBytes) async {
    if (!await file.exists()) return false;
    final length = await file.length();
    if (length <= 0) return false;
    return expectedBytes == null ||
        expectedBytes <= 0 ||
        length == expectedBytes;
  }

  Future<void> _removeOlderVersions({
    required String topicId,
    required String keep,
  }) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}first_aid${Platform.pathSeparator}videos',
    );
    if (!await directory.exists()) return;

    final prefix = FirstAidVideo(
      title: '',
      storagePath: '',
      durationLabel: '',
      attribution: '',
      license: '',
      sourceUrl: '',
      version: 0,
    ).cacheFileName(topicId).split('_v').first;

    await for (final entity in directory.list()) {
      if (entity is File &&
          entity.path != keep &&
          entity.uri.pathSegments.last.startsWith('${prefix}_v')) {
        await entity.delete();
      }
    }
  }
}

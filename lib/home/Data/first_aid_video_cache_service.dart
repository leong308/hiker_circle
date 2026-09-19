import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../Model/first_aid_video.dart';

class FirstAidVideoCacheService {
  FirstAidVideoCacheService({
    FirebaseStorage? storage,
    Future<Directory> Function()? supportDirectory,
  }) : _storage = storage,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  static final FirstAidVideoCacheService instance = FirstAidVideoCacheService();

  final FirebaseStorage? _storage;
  final Future<Directory> Function() _supportDirectory;
  final Map<String, Future<File>> _downloads = <String, Future<File>>{};

  Future<File> cache({required String topicId, required FirstAidVideo video}) {
    final key = '$topicId#${video.storagePath}#${video.version}';
    return _downloads.putIfAbsent(key, () async {
      try {
        return await _cache(topicId: topicId, video: video);
      } finally {
        _downloads.remove(key);
      }
    });
  }

  Future<bool> isCached({
    required String topicId,
    required FirstAidVideo video,
  }) async {
    final file = await _cachedFile(topicId: topicId, video: video);
    return isFirstAidVideoCacheValid(file, video);
  }

  Future<File> _cache({
    required String topicId,
    required FirstAidVideo video,
  }) async {
    if (video.storagePath.isEmpty) {
      throw const FormatException('The tutorial storage path is missing.');
    }

    final target = await _cachedFile(topicId: topicId, video: video);
    if (await isFirstAidVideoCacheValid(target, video)) return target;

    await target.parent.create(recursive: true);
    final partial = File('${target.path}.part');
    if (await partial.exists()) await partial.delete();

    try {
      final task = (_storage ?? FirebaseStorage.instance)
          .ref(video.storagePath)
          .writeToFile(partial);
      try {
        await task.timeout(const Duration(minutes: 4));
      } on TimeoutException {
        await task.cancel();
        rethrow;
      }
      if (!await isFirstAidVideoCacheValid(partial, video)) {
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
    final support = await _supportDirectory();
    return File(
      '${support.path}${Platform.pathSeparator}first_aid${Platform.pathSeparator}videos${Platform.pathSeparator}${video.cacheFileName(topicId)}',
    );
  }

  Future<void> _removeOlderVersions({
    required String topicId,
    required String keep,
  }) async {
    final support = await _supportDirectory();
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

/// Verify both completeness and the approved source's exact bytes.
Future<bool> isFirstAidVideoCacheValid(File file, FirstAidVideo video) async {
  if (!await file.exists()) return false;
  final length = await file.length();
  if (length <= 0) return false;
  final expected = video.expectedBytes;
  if (expected != null && expected > 0 && length != expected) return false;
  if (video.sha256.isEmpty) return true;
  final digest = await crypto.sha256.bind(file.openRead()).first;
  return digest.toString() == video.sha256.toLowerCase();
}

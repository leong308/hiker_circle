// TrailCautionService uploads report evidence and calls the backend caution workflow.
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

const cautionMediaLimit = 50 * 1024 * 1024;
const cautionMediaTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'm4v': 'video/x-m4v',
};

/// Represents pending caution media.
class PendingCautionMedia {
  /// Creates pending caution media.
  PendingCautionMedia({
    required this.file,
    required this.sizeBytes,
    required this.contentType,
    String? key,
  }) : key =
           key ??
           'media_${DateTime.now().microsecondsSinceEpoch}_${_sequence++}_${math.Random.secure().nextInt(0x7fffffff).toRadixString(16)}';
  static int _sequence = 0;
  final XFile file;
  final int sizeBytes;
  final String contentType;
  final String key;
  String? storagePath;

  /// Returns is video.
  bool get isVideo => contentType.startsWith('video/');
}

/// Represents trail caution service.
class TrailCautionService {
  /// Upload selected evidence and return the metadata consumed by the caution backend.
  Future<List<Map<String, dynamic>>> upload(
    String hazardId,
    List<PendingCautionMedia> files, {
    String? expectedUid,
  }) async {
    if (files.length > 6 ||
        files.fold<int>(0, (a, b) => a + b.sizeBytes) > cautionMediaLimit) {
      throw StateError(
        'Choose up to six photos or videos, totaling at most 50 MB.',
      );
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to report a caution.');
    if (expectedUid != null && uid != expectedUid) {
      throw StateError('The reporting account changed.');
    }
    final result = <Map<String, dynamic>>[];
    for (final item in files) {
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('The reporting account changed.');
      }
      var path = item.storagePath;
      if (path == null) {
        final extension = cautionMediaTypes.entries
            .firstWhere((e) => e.value == item.contentType)
            .key;
        path = 'trail_cautions/$uid/$hazardId/${item.key}.$extension';
        final reference = FirebaseStorage.instance.ref(path);
        FullMetadata? existing;
        try {
          existing = await reference.getMetadata();
        } on FirebaseException catch (e) {
          if (e.code != 'object-not-found') rethrow;
        }
        if (existing != null) {
          if (existing.size != item.sizeBytes ||
              existing.contentType != item.contentType ||
              existing.customMetadata?['ownerUid'] != uid ||
              existing.customMetadata?['hazardId'] != hazardId) {
            throw StateError('This attachment changed. Choose it again.');
          }
        } else {
          final bytes = await item.file.readAsBytes();
          if (bytes.isEmpty || bytes.length != item.sizeBytes) {
            throw StateError(
              'The selected file changed. Please choose it again.',
            );
          }
          await reference.putData(
            bytes,
            SettableMetadata(
              contentType: item.contentType,
              customMetadata: {'ownerUid': uid, 'hazardId': hazardId},
            ),
          );
        }
        item.storagePath = path;
      }
      result.add({'storagePath': path, 'name': item.file.name});
    }
    return result;
  }

  /// Updates.
  Future<bool> update(
    String hazardId,
    String action, {
    required String requestId,
    String description = '',
    List<PendingCautionMedia> files = const [],
    bool confirmed = false,
  }) async {
    final media = await upload(hazardId, files);
    final response = await FirebaseFunctions.instance
        .httpsCallable('updateTrailCaution')
        .call({
          'hazardId': hazardId,
          'requestId': requestId,
          'action': action,
          'description': description.trim(),
          'media': media,
          'confirmed': confirmed,
        });
    return response.data is Map && response.data['duplicate'] != true;
  }
}

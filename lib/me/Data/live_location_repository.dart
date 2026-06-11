import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/firebase_user_repository.dart';
import '../../sos/Model/sos_models.dart';
import '../Model/live_location_models.dart';

class LiveLocationRepositoryException implements Exception {
  const LiveLocationRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LiveLocationRepository {
  LiveLocationRepository({
    FirebaseFirestore? firestore,
    FirebaseBootstrapResult firebaseBootstrapResult =
        const FirebaseBootstrapResult.available(),
  }) : _firestore = firestore,
       _firebaseBootstrapResult = firebaseBootstrapResult;

  static const String _hostingBaseUrl =
      'https://hiker-circle.web.app/live-location';

  final FirebaseFirestore? _firestore;
  final FirebaseBootstrapResult _firebaseBootstrapResult;

  FirebaseFirestore get _resolvedFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users {
    return _resolvedFirestore.collection('users');
  }

  CollectionReference<Map<String, dynamic>> get _liveLocationShares {
    return _resolvedFirestore.collection('live_location_shares');
  }

  Future<LiveLocationShare?> loadForUser({required String phoneNumber}) async {
    _throwIfFirebaseUnavailable();

    try {
      final snapshot = await _userDocumentFor(phoneNumber).get();
      final data = snapshot.data();
      if (data == null || data['liveLocationEnabled'] != true) {
        return null;
      }

      final shareId = data['liveLocationShareId'];
      final shareUrl = data['liveLocationShareUrl'];
      if (shareId is! String || shareId.isEmpty) {
        return null;
      }

      return LiveLocationShare(
        id: shareId,
        shareUrl: shareUrl is String && shareUrl.isNotEmpty
            ? shareUrl
            : _shareUrlFor(shareId),
        isActive: true,
      );
    } on FirebaseException catch (error) {
      throw LiveLocationRepositoryException(
        'Firestore ${error.code}: ${error.message ?? 'No details provided.'}',
      );
    }
  }

  Future<LiveLocationShare> activate({
    required String phoneNumber,
    required SosTriggerLocation location,
  }) async {
    _throwIfFirebaseUnavailable();

    try {
      final userDocument = _userDocumentFor(phoneNumber);
      final userSnapshot = await userDocument.get();
      final existingShareId = userSnapshot.data()?['liveLocationShareId'];
      final shareDocument =
          existingShareId is String && existingShareId.isNotEmpty
          ? _liveLocationShares.doc(existingShareId)
          : _liveLocationShares.doc();
      final shareId = shareDocument.id;
      final shareUrl = _shareUrlFor(shareId);
      final now = DateTime.now().toUtc();

      final batch = _resolvedFirestore.batch();
      batch.set(userDocument, {
        'phoneNumber': phoneNumber,
        'liveLocationEnabled': true,
        'liveLocationShareId': shareId,
        'liveLocationShareUrl': shareUrl,
        'liveLocation': location.toFirestore(),
        'liveLocationUpdatedAt': FieldValue.serverTimestamp(),
        'liveLocationUpdatedAtLocal': now.toIso8601String(),
      }, SetOptions(merge: true));

      batch.set(shareDocument, {
        'shareId': shareId,
        'ownerUserId': _userIdFor(phoneNumber),
        'ownerUserDocumentPath': userDocument.path,
        'phoneNumber': phoneNumber,
        'isActive': true,
        'latestLocation': location.toFirestore(),
        'shareUrl': shareUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtLocal': now.toIso8601String(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtLocal': now.toIso8601String(),
      }, SetOptions(merge: true));

      await batch.commit();
      return LiveLocationShare(
        id: shareId,
        shareUrl: shareUrl,
        isActive: true,
        latestLocation: location,
      );
    } on FirebaseException catch (error) {
      throw LiveLocationRepositoryException(
        'Firestore ${error.code}: ${error.message ?? 'No details provided.'}',
      );
    }
  }

  Future<void> updateLocation({
    required String phoneNumber,
    required LiveLocationShare share,
    required SosTriggerLocation location,
  }) async {
    _throwIfFirebaseUnavailable();

    try {
      final now = DateTime.now().toUtc();
      final userDocument = _userDocumentFor(phoneNumber);
      final shareDocument = _liveLocationShares.doc(share.id);
      final batch = _resolvedFirestore.batch();

      batch.set(userDocument, {
        'phoneNumber': phoneNumber,
        'liveLocationEnabled': true,
        'liveLocationShareId': share.id,
        'liveLocationShareUrl': share.shareUrl,
        'liveLocation': location.toFirestore(),
        'liveLocationUpdatedAt': FieldValue.serverTimestamp(),
        'liveLocationUpdatedAtLocal': now.toIso8601String(),
      }, SetOptions(merge: true));

      batch.set(shareDocument, {
        'shareId': share.id,
        'ownerUserId': _userIdFor(phoneNumber),
        'ownerUserDocumentPath': userDocument.path,
        'phoneNumber': phoneNumber,
        'isActive': true,
        'latestLocation': location.toFirestore(),
        'shareUrl': share.shareUrl,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtLocal': now.toIso8601String(),
      }, SetOptions(merge: true));

      await batch.commit();
    } on FirebaseException catch (error) {
      throw LiveLocationRepositoryException(
        'Firestore ${error.code}: ${error.message ?? 'No details provided.'}',
      );
    }
  }

  Future<void> deactivate({
    required String phoneNumber,
    required LiveLocationShare? share,
  }) async {
    _throwIfFirebaseUnavailable();

    try {
      final userDocument = _userDocumentFor(phoneNumber);
      final shareId = share?.id ?? await _shareIdForUser(userDocument);
      final now = DateTime.now().toUtc();
      final batch = _resolvedFirestore.batch();

      batch.set(userDocument, {
        'phoneNumber': phoneNumber,
        'liveLocationEnabled': false,
        'liveLocationUpdatedAt': FieldValue.serverTimestamp(),
        'liveLocationUpdatedAtLocal': now.toIso8601String(),
      }, SetOptions(merge: true));

      if (shareId != null && shareId.isNotEmpty) {
        batch.set(_liveLocationShares.doc(shareId), {
          'isActive': false,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedAtLocal': now.toIso8601String(),
        }, SetOptions(merge: true));
      }

      await batch.commit();
    } on FirebaseException catch (error) {
      throw LiveLocationRepositoryException(
        'Firestore ${error.code}: ${error.message ?? 'No details provided.'}',
      );
    }
  }

  Future<String?> _shareIdForUser(
    DocumentReference<Map<String, dynamic>> userDocument,
  ) async {
    final snapshot = await userDocument.get();
    final shareId = snapshot.data()?['liveLocationShareId'];
    return shareId is String ? shareId : null;
  }

  DocumentReference<Map<String, dynamic>> _userDocumentFor(String phoneNumber) {
    return _users.doc(_userIdFor(phoneNumber));
  }

  String _userIdFor(String phoneNumber) {
    return FirebaseUserRepository.documentIdForPhoneNumber(phoneNumber);
  }

  String _shareUrlFor(String shareId) {
    return '$_hostingBaseUrl?share=${Uri.encodeComponent(shareId)}';
  }

  void _throwIfFirebaseUnavailable() {
    if (_firebaseBootstrapResult.isAvailable) {
      return;
    }

    throw LiveLocationRepositoryException(
      'Firebase is not ready yet. ${_firebaseBootstrapResult.errorMessage ?? ''}'
          .trim(),
    );
  }
}

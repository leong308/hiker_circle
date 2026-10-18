// LiveLocationRepository manages authenticated live-share records and durable stop requests.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../app/Data/user_module_paths.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/firebase_user_repository.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart'
    show LiveLocationContactNotificationResult;
import '../../app/Data/local_session_database.dart';
import '../../sos/Model/sos_models.dart';
import '../Model/live_location_models.dart';

class LiveLocationRepositoryException implements Exception {
  const LiveLocationRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LiveLocationStopPersistenceException implements Exception {
  const LiveLocationStopPersistenceException();
}

class LiveLocationRepository {
  LiveLocationRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    LocalSessionDatabase? localDatabase,
    Duration cloudTimeout = const Duration(seconds: 5),
    Duration activationTimeout = const Duration(seconds: 30),
    FirebaseBootstrapResult firebaseBootstrapResult =
        const FirebaseBootstrapResult.available(),
  }) : _firestore = firestore,
       _functions = functions,
       _localDatabase = localDatabase ?? LocalSessionDatabase(),
       _cloudTimeout = cloudTimeout,
       _activationTimeout = activationTimeout,
       _firebaseBootstrapResult = firebaseBootstrapResult;

  static const String _hostingBaseUrl =
      'https://hiker-circle.web.app/live-location';
  static const pendingStopPreferenceKey = 'pending_live_location_stop';
  static final Map<String, int> _stopGenerations = {};
  final FirebaseFunctions? _functions;
  final LocalSessionDatabase _localDatabase;
  final Duration _cloudTimeout;
  final Duration _activationTimeout;

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

  Future<bool> loadAutoShareOnHikeStart({required String phoneNumber}) async {
    _throwIfFirebaseUnavailable();
    try {
      final snapshot = await userModuleDocument(
        _users.doc(_userIdFor(phoneNumber)),
        UserModule.preferences,
      ).get().timeout(_cloudTimeout);
      return snapshot.data()?['autoShareLiveLocationOnHikeStart'] == true;
    } on FirebaseException catch (error) {
      throw LiveLocationRepositoryException(
        'Cloud sync failed (${error.code}). ${error.message ?? 'Please try again.'}',
      );
    }
  }

  Future<void> setAutoShareOnHikeStart({
    required String phoneNumber,
    required bool enabled,
  }) async {
    _throwIfFirebaseUnavailable();
    try {
      final now = DateTime.now().toUtc();
      await userModuleDocument(
            _users.doc(_userIdFor(phoneNumber)),
            UserModule.preferences,
          )
          .set({
            'autoShareLiveLocationOnHikeStart': enabled,
            'autoShareLiveLocationPreferenceUpdatedAt':
                FieldValue.serverTimestamp(),
            'autoShareLiveLocationPreferenceUpdatedAtLocal': now
                .toIso8601String(),
          }, SetOptions(merge: true))
          .timeout(_cloudTimeout);
    } on FirebaseException catch (error) {
      throw LiveLocationRepositoryException(
        'Cloud sync failed (${error.code}). ${error.message ?? 'Please try again.'}',
      );
    }
  }

  Future<LiveLocationShare?> loadForUser({required String phoneNumber}) async {
    if (await hasPendingStop(phoneNumber)) {
      try {
        await retryPendingStop(phoneNumber);
      } catch (_) {}
      return null;
    }
    _throwIfFirebaseUnavailable();

    try {
      final snapshot = await _userDocumentFor(
        phoneNumber,
      ).get(const GetOptions(source: Source.server)).timeout(_cloudTimeout);
      final data = snapshot.data();
      if (data == null || data['liveLocationEnabled'] != true) {
        return null;
      }

      final shareId = data['liveLocationShareId'];
      final shareUrl = data['liveLocationShareUrl'];
      final expiresAt =
          _dateFromValue(data['liveLocationExpiresAt']) ??
          _dateFromValue(data['liveLocationExpiresAtLocal']);
      if (shareId is! String || shareId.isEmpty) {
        return null;
      }
      if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
        await deactivate(phoneNumber: phoneNumber, share: null);
        return null;
      }

      return LiveLocationShare(
        id: shareId,
        shareUrl: shareUrl is String && shareUrl.isNotEmpty
            ? shareUrl
            : _shareUrlFor(shareId),
        isActive: true,
        expiresAt: expiresAt,
        startedAt:
            _dateFromValue(data['liveLocationStartedAt']) ??
            _dateFromValue(data['liveLocationStartedAtLocal']),
      );
    } on FirebaseException catch (error) {
      throw LiveLocationRepositoryException(
        'Cloud sync failed (${error.code}). ${error.message ?? 'Please try again.'}',
      );
    }
  }

  Future<LiveLocationShare> activate({
    required String phoneNumber,
    required SosTriggerLocation location,
  }) async {
    _throwIfFirebaseUnavailable();
    await retryPendingStop(phoneNumber);
    try {
      final data = await activateCloudShare(
        location,
      ).timeout(_activationTimeout);
      final shareId = data['shareId'];
      final shareUrl = data['shareUrl'];
      final expiresMillis = data['expiresAtMillis'];
      final startedMillis = data['startedAtMillis'];
      if (shareId is! String ||
          shareId.isEmpty ||
          shareUrl is! String ||
          shareUrl.isEmpty ||
          expiresMillis is! num ||
          !expiresMillis.isFinite ||
          expiresMillis <= 0 ||
          expiresMillis > 8640000000000000 ||
          (startedMillis != null &&
              (startedMillis is! num ||
                  !startedMillis.isFinite ||
                  startedMillis <= 0 ||
                  startedMillis > expiresMillis))) {
        throw const LiveLocationRepositoryException(
          'The sharing server returned an invalid response.',
        );
      }
      return LiveLocationShare(
        id: shareId,
        shareUrl: shareUrl,
        isActive: true,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          expiresMillis.toInt(),
          isUtc: true,
        ),
        startedAt: startedMillis is num
            ? DateTime.fromMillisecondsSinceEpoch(
                startedMillis.toInt(),
                isUtc: true,
              )
            : null,
        latestLocation: location,
      );
    } on TimeoutException {
      final confirmed = await _reconcileActivation(phoneNumber);
      if (confirmed != null) return confirmed;
      throw const LiveLocationRepositoryException(
        'Live sharing could not be confirmed yet. Check your connection and try again.',
      );
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'deadline-exceeded' || error.code == 'unavailable') {
        final confirmed = await _reconcileActivation(phoneNumber);
        if (confirmed != null) return confirmed;
      }
      throw LiveLocationRepositoryException(
        error.message ?? 'Unable to activate live location.',
      );
    }
  }

  // A response can be lost after the server commits. Read its authoritative
  // result before reporting failure; never issue a second activation here.
  Future<LiveLocationShare?> _reconcileActivation(String phoneNumber) async {
    try {
      return await loadForUser(phoneNumber: phoneNumber);
    } catch (_) {
      return null;
    }
  }

  @protected
  Future<Map<String, dynamic>> activateCloudShare(
    SosTriggerLocation location,
  ) async {
    final result = await (_functions ?? FirebaseFunctions.instance)
        .httpsCallable(
          'activateLiveLocationShare',
          options: HttpsCallableOptions(timeout: _activationTimeout),
        )
        .call<Map<String, dynamic>>(location.toFirestore());
    return result.data;
  }

  /// The backend chooses saved SOS contacts and canonical message details.
  /// Repeating this request checks the same per-share delivery identities.
  Future<LiveLocationContactNotificationResult> notifyStandaloneContacts({
    required String shareId,
  }) async {
    _throwIfFirebaseUnavailable();
    if (!RegExp(r'^[A-Za-z0-9_-]{8,240}$').hasMatch(shareId)) {
      throw const LiveLocationRepositoryException(
        'The live location link is invalid.',
      );
    }
    try {
      final data = await notifyStandaloneContactsCloud(
        shareId,
      ).timeout(const Duration(seconds: 120));
      int count(String key) {
        final value = data[key];
        return value is num && value.isFinite && value >= 0 ? value.toInt() : 0;
      }

      return LiveLocationContactNotificationResult(
        contactCount: count('contactCount'),
        sentCount: count('sentCount'),
        retryableFailureCount: count('retryableFailureCount'),
        uncertainCount: count('uncertainCount'),
        inProgressCount: count('inProgressCount'),
        failedCount: count('failedCount'),
      );
    } on FirebaseFunctionsException catch (error) {
      throw LiveLocationRepositoryException(
        error.message ?? 'The WhatsApp contact update could not be confirmed.',
      );
    } on TimeoutException {
      throw const LiveLocationRepositoryException(
        'WhatsApp delivery is still being processed. Retry the contact notification to check its status.',
      );
    }
  }

  @protected
  Future<Map<String, dynamic>> notifyStandaloneContactsCloud(
    String shareId,
  ) async {
    final response = await (_functions ?? FirebaseFunctions.instance)
        .httpsCallable(
          'notifyEmergencyContactsOfLiveLocation',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
        )
        .call<Map<String, dynamic>>({'mode': 'standalone', 'shareId': shareId});
    return response.data;
  }

  Future<void> updateLocation({
    required String phoneNumber,
    required LiveLocationShare share,
    required SosTriggerLocation location,
  }) async {
    final generation = _stopGenerations[phoneNumber] ?? 0;
    if (await hasPendingStop(phoneNumber) ||
        generation != (_stopGenerations[phoneNumber] ?? 0)) {
      return;
    }
    _throwIfFirebaseUnavailable();

    try {
      final now = DateTime.now().toUtc();
      final userDocument = _userDocumentFor(phoneNumber);
      final shareDocument = _liveLocationShares.doc(share.id);
      final batch = _resolvedFirestore.batch();

      batch.set(userDocument, {
        'liveLocationEnabled': true,
        'liveLocationShareId': share.id,
        'liveLocationShareUrl': share.shareUrl,
        'liveLocation': location.toFirestore(),
        'liveLocationUpdatedAt': FieldValue.serverTimestamp(),
        'liveLocationUpdatedAtLocal': now.toIso8601String(),
        'liveLocationExpiresAt': Timestamp.fromDate(share.expiresAt),
        'liveLocationExpiresAtLocal': share.expiresAt.toIso8601String(),
      }, SetOptions(merge: true));

      batch.set(shareDocument, {
        'shareId': share.id,
        'ownerUserId': _userIdFor(phoneNumber),
        'ownerUserDocumentPath': _users.doc(_userIdFor(phoneNumber)).path,
        'phoneNumber': phoneNumber,
        'isActive': true,
        'latestLocation': location.toFirestore(),
        'shareUrl': share.shareUrl,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtLocal': now.toIso8601String(),
        'expiresAt': Timestamp.fromDate(share.expiresAt),
        'expiresAtLocal': share.expiresAt.toIso8601String(),
      }, SetOptions(merge: true));

      await batch.commit().timeout(_cloudTimeout);
    } on FirebaseException catch (error) {
      throw LiveLocationRepositoryException(
        'Cloud sync failed (${error.code}). ${error.message ?? 'Please try again.'}',
      );
    }
  }

  Future<bool> hasPendingStop(String phoneNumber) async {
    final value = await _localDatabase.loadLocalPreference(
      ownerPhoneNumber: phoneNumber,
      key: pendingStopPreferenceKey,
    );
    return value is Map && value['pending'] == true;
  }

  /// Persist the stop request before contacting the backend so an offline opt-out remains retryable.
  Future<void> deactivate({
    required String phoneNumber,
    required LiveLocationShare? share,
  }) async {
    _stopGenerations[phoneNumber] = (_stopGenerations[phoneNumber] ?? 0) + 1;
    final pending = <String, Object?>{
      'pending': true,
      'shareId': share?.id,
      'revision': DateTime.now().microsecondsSinceEpoch.toString(),
    };
    // This must precede the remote request so a process exit cannot restore
    // sharing that the user already stopped.
    try {
      await _localDatabase.saveLocalPreference(
        ownerPhoneNumber: phoneNumber,
        key: pendingStopPreferenceKey,
        value: pending,
      );
    } catch (_) {
      throw const LiveLocationStopPersistenceException();
    }
    await _sendStop(phoneNumber, pending);
  }

  /// Retry the saved stop identity before allowing a stale cloud share to be treated as active.
  Future<void> retryPendingStop(String phoneNumber) async {
    final value = await _localDatabase.loadLocalPreference(
      ownerPhoneNumber: phoneNumber,
      key: pendingStopPreferenceKey,
    );
    if (value is Map && value['pending'] == true) {
      await _sendStop(phoneNumber, value);
    }
  }

  Future<void> _sendStop(String phoneNumber, Map pending) async {
    _throwIfFirebaseUnavailable();
    final shareId = pending['shareId'];
    await deactivateCloudShare(
      phoneNumber,
      shareId is String ? shareId : null,
    ).timeout(_cloudTimeout);
    await _localDatabase.clearLocalPreferenceIfValue(
      ownerPhoneNumber: phoneNumber,
      key: pendingStopPreferenceKey,
      expectedValue: pending,
    );
  }

  @protected
  Future<void> deactivateCloudShare(
    String phoneNumber,
    String? savedShareId,
  ) async {
    final userDocument = _userDocumentFor(phoneNumber);
    final shareId = savedShareId ?? await _shareIdForUser(userDocument);
    final now = DateTime.now().toUtc();
    final batch = _resolvedFirestore.batch();
    batch.set(userDocument, {
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
    await batch.commit().timeout(_cloudTimeout);
  }

  Future<String?> _shareIdForUser(
    DocumentReference<Map<String, dynamic>> userDocument,
  ) async {
    final snapshot = await userDocument.get().timeout(_cloudTimeout);
    final shareId = snapshot.data()?['liveLocationShareId'];
    return shareId is String ? shareId : null;
  }

  DocumentReference<Map<String, dynamic>> _userDocumentFor(String phoneNumber) {
    return userModuleDocument(
      _users.doc(_userIdFor(phoneNumber)),
      UserModule.location,
    );
  }

  String _userIdFor(String phoneNumber) {
    return FirebaseUserRepository.documentIdForPhoneNumber(phoneNumber);
  }

  String _shareUrlFor(String shareId) {
    return '$_hostingBaseUrl?share=${Uri.encodeComponent(shareId)}';
  }

  DateTime? _dateFromValue(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    return null;
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

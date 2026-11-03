// SosAlertRepository durably queues emergency alerts and reconciles backend delivery acknowledgements.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../app/Data/conditional_cloud_cache.dart';
import '../../app/Data/user_module_paths.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/app_settings_controller.dart';
import '../../app/Data/firebase_user_repository.dart';
import '../../app/Data/local_session_database.dart';
import '../../app/Model/app_session.dart';
import '../../authentication/Data/green_api_client.dart';
import '../../authentication/Data/phone_number_formatter.dart';
import '../Model/sos_models.dart';
import '../Model/sos_delivery_policy.dart';
import 'sos_confirmation_store.dart';
import '../../home/Model/hike_shirt_color.dart';
import '../../core/services/network_reachability_service.dart';

/// Represents sos alert repository exception.
class SosAlertRepositoryException implements Exception {
  /// Creates sos alert repository exception.
  const SosAlertRepositoryException(this.message);

  final String message;

  /// Converts to string.
  @override
  String toString() => message;
}

/// Represents sos queue flush result.
class SosQueueFlushResult {
  /// Creates sos queue flush result.
  const SosQueueFlushResult({
    required this.attempted,
    required this.sent,
    required this.remaining,
  });

  final int attempted;
  final int sent;
  final int remaining;

  /// Returns did flush any.
  bool get didFlushAny => sent > 0;
}

/// Represents sos queue change.
class SosQueueChange {
  /// Creates sos queue change.
  const SosQueueChange({
    required this.phoneNumber,
    this.alert,
    this.queuedForRetry = false,
  });

  final String phoneNumber;
  final SosAlert? alert;
  final bool queuedForRetry;
}

/// A note actually stored on this device, scoped to its owner and SOS mode.
class SosCustomNoteChange {
  const SosCustomNoteChange({
    required this.phoneNumber,
    required this.mode,
    required this.note,
    required this.revision,
    this.isSynced = false,
    this.syncedAfterRetry = false,
  });
  final String phoneNumber;
  final SosAlertMode mode;
  final String note;
  final int revision;
  final bool isSynced;
  final bool syncedAfterRetry;

  /// A queued broadcast cannot undo a newer local edit before it is delivered.
  bool get isCurrent =>
      revision ==
      (SosAlertRepository._noteRevisions['$phoneNumber:${mode.name}'] ?? 0);
}

/// A durable local SOS submission and its eventual Firebase/provider result.
///
/// [submittedResult] records local queueing, never successful delivery.
/// [acknowledgement] replaces that pending state with the
/// authoritative sent, failed, or queued result.
class SosAlertSubmission {
  /// Creates sos alert submission.
  const SosAlertSubmission({
    required this.submittedResult,
    required this.acknowledgement,
  });

  final SosAlertResult submittedResult;
  final Future<SosAlertResult> acknowledgement;
}

/// Represents sos alert repository.
class SosAlertRepository {
  static final _queueChanges = StreamController<SosQueueChange>.broadcast();
  static final _customNoteChanges =
      StreamController<SosCustomNoteChange>.broadcast();
  static final _queueDrains = <String, Future<SosQueueFlushResult>>{};
  static final _activeAlertIds = <String, Set<String>>{};

  /// Returns queue changes.
  static Stream<SosQueueChange> get queueChanges => _queueChanges.stream;
  static Stream<SosCustomNoteChange> get customNoteChanges =>
      _customNoteChanges.stream;

  /// Notifies queue changed.
  void _notifyQueueChanged(
    AppSession session, {
    SosAlert? alert,
    bool queuedForRetry = false,
  }) {
    _queueChanges.add(
      SosQueueChange(
        phoneNumber: session.phoneNumber,
        alert: alert,
        queuedForRetry: queuedForRetry,
      ),
    );
  }

  static const int _maxImmediateSendAttempts = 1;
  static final Map<String, int> _noteRevisions = {};
  static final Map<String, Future<bool>> _notePushes = {};
  static const _customNoteModes = [
    SosAlertMode.manual,
    SosAlertMode.duress,
    SosAlertMode.medical,
  ];

  static const int _maxRecentSosAlertReferences = 30;

  /// Creates sos alert repository.
  SosAlertRepository({
    FirebaseFirestore? firestore,
    GreenApiClient? greenApiClient,
    LocalSessionDatabase? localDatabase,
    ConditionalCloudCache? readCache,
    Duration sendAttemptTimeout = const Duration(seconds: 15),
    Duration cloudWriteTimeout = const Duration(seconds: 4),
    Duration customNoteWriteTimeout = const Duration(seconds: 40),
    bool Function()? customNoteCanSync,
    FirebaseBootstrapResult firebaseBootstrapResult =
        const FirebaseBootstrapResult.available(),
  }) : _firestore = firestore,
       _greenApiClient = greenApiClient ?? GreenApiClient(),
       _localDatabase = localDatabase ?? LocalSessionDatabase(),
       _providedReadCache = readCache,
       _sendAttemptTimeout = sendAttemptTimeout,
       _cloudWriteTimeout = cloudWriteTimeout,
       _customNoteWriteTimeout = customNoteWriteTimeout,
       _customNoteCanSync = customNoteCanSync,
       _firebaseBootstrapResult = firebaseBootstrapResult;

  final FirebaseFirestore? _firestore;
  final GreenApiClient _greenApiClient;
  final LocalSessionDatabase _localDatabase;
  final ConditionalCloudCache? _providedReadCache;
  late final _readCache =
      _providedReadCache ??
      ConditionalCloudCache(_localDatabase, () => FirebaseFunctions.instance);

  Future<Map<String, dynamic>> _readSosPreferences(
    AppSession session, {
    bool force = false,
    bool cacheOnly = false,
    bool registerOnly = false,
  }) => _readCache.read(
    owner: session.phoneNumber,
    type: 'mobile_sos_preferences',
    id: 'current',
    callable: 'readMobileResource',
    arguments: const {'resourceType': 'sos_preferences'},
    freshness: const Duration(minutes: 2),
    online: _firebaseBootstrapResult.isAvailable && !registerOnly,
    force: force,
    cacheOnly: cacheOnly,
  );
  final Duration _sendAttemptTimeout;
  final Duration _cloudWriteTimeout;
  final Duration _customNoteWriteTimeout;
  final bool Function()? _customNoteCanSync;
  final FirebaseBootstrapResult _firebaseBootstrapResult;

  /// Returns resolved firestore.
  FirebaseFirestore get _resolvedFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  /// Shares authoritative contact receipts across the home overlay and SOS history.
  SosConfirmationStore get _confirmations =>
      SosConfirmationStore(_resolvedFirestore);

  /// Resolves the owner using the same phone identity as Firebase authentication.
  String _owner(AppSession session) =>
      FirebaseUserRepository.documentIdForPhoneNumber(session.phoneNumber);

  /// Applies late results without creating a new SOS popup for a historic alert.
  Stream<SosAlert> watchDeliveryConfirmations(AppSession session) {
    if (!_firebaseBootstrapResult.isAvailable) return const Stream.empty();
    return _confirmations.watch(_owner(session)).map((alert) {
      _notifyQueueChanged(
        session,
        alert: alert,
        queuedForRetry: alert.dispatches.any(SosDeliveryPolicy.canRetry),
      );
      return alert;
    });
  }

  /// Overlays owner-only server receipts when reopening SOS history.
  Future<List<SosAlert>> _confirmedLogs(
    AppSession session,
    List<SosAlert> alerts,
  ) async {
    try {
      await _confirmations.refresh(_owner(session));
    } catch (_) {
      // Retain the local log when the device is offline.
    }
    return alerts
        .map((a) => _confirmations.remember(_owner(session), a))
        .toList();
  }

  /// Returns users.
  CollectionReference<Map<String, dynamic>> get _users {
    return _resolvedFirestore.collection('users');
  }

  /// Returns sos alerts.
  CollectionReference<Map<String, dynamic>> get _sosAlerts {
    return _resolvedFirestore.collection('sosAlerts');
  }

  /// Loads custom whats app notes.
  Future<Map<SosAlertMode, String>> loadCustomWhatsAppNotes({
    required AppSession session,
    bool cacheOnly = false,
  }) async {
    final saved = <SosAlertMode, String>{};
    for (final mode in _customNoteModes) {
      final value = await _localDatabase.loadLocalPreference(
        ownerPhoneNumber: session.phoneNumber,
        key: 'sos_whatsapp_note_${mode.firestoreValue}',
      );
      if (value is String) saved[mode] = value;
    }
    if (cacheOnly) {
      await _refreshCustomWhatsAppNotes(session, cacheOnly: true);
      return _loadSavedCustomNotes(session);
    }
    if (saved.isNotEmpty) {
      unawaited(
        _refreshCustomWhatsAppNotes(session).catchError((Object _) => saved),
      );
      return saved;
    }
    return _refreshCustomWhatsAppNotes(session);
  }

  Future<Map<SosAlertMode, String>> _loadSavedCustomNotes(
    AppSession session,
  ) async {
    final saved = <SosAlertMode, String>{};
    for (final mode in _customNoteModes) {
      final value = await _localDatabase.loadLocalPreference(
        ownerPhoneNumber: session.phoneNumber,
        key: 'sos_whatsapp_note_${mode.firestoreValue}',
      );
      if (value is String) saved[mode] = value;
    }
    return saved;
  }

  /// Dirty flags survive app restarts and distinguish device saves from Firebase acknowledgements.
  Future<Map<SosAlertMode, bool>> loadCustomWhatsAppNoteSyncStates({
    required AppSession session,
  }) async {
    final saved = await _loadSavedCustomNotes(session);
    final dirty = await _localDatabase.loadDirtyLocalPreferences(
      ownerPhoneNumber: session.phoneNumber,
    );
    return {
      for (final mode in saved.keys)
        mode: !dirty.containsKey('sos_whatsapp_note_${mode.firestoreValue}'),
    };
  }

  Future<Map<SosAlertMode, String>> _refreshCustomWhatsAppNotes(
    AppSession session, {
    bool cacheOnly = false,
  }) async {
    if (!cacheOnly) await flushPendingCustomWhatsAppNotes(session: session);
    final local = <SosAlertMode, String>{};
    final revisions = <SosAlertMode, int>{};
    for (final mode in _customNoteModes) {
      revisions[mode] =
          _noteRevisions['${session.phoneNumber}:${mode.name}'] ?? 0;
      final value = await _localDatabase.loadLocalPreference(
        ownerPhoneNumber: session.phoneNumber,
        key: 'sos_whatsapp_note_${mode.firestoreValue}',
      );
      if (value is String) local[mode] = value;
    }
    if (!_firebaseBootstrapResult.isAvailable && !cacheOnly) return local;
    try {
      final snapshot = cacheOnly
          ? await _readSosPreferences(session, cacheOnly: true)
          : null;
      final notes = cacheOnly
          ? (snapshot?['sosWhatsappNotes'] is Map
                ? Map<String, dynamic>.from(
                    snapshot!['sosWhatsappNotes'] as Map,
                  )
                : <String, dynamic>{})
          : await fetchCloudCustomNotes(session).timeout(_cloudWriteTimeout);
      final dirty = await _localDatabase.loadDirtyLocalPreferences(
        ownerPhoneNumber: session.phoneNumber,
      );
      for (final mode in _customNoteModes) {
        final key = 'sos_whatsapp_note_${mode.firestoreValue}';
        if (dirty.containsKey(key) ||
            revisions[mode] !=
                (_noteRevisions['${session.phoneNumber}:${mode.name}'] ?? 0)) {
          final latest = await _localDatabase.loadLocalPreference(
            ownerPhoneNumber: session.phoneNumber,
            key: key,
          );
          if (latest is String) local[mode] = latest;
          continue;
        }
        final value = notes[mode.firestoreValue];
        if (value is! String) continue;
        final bounded = _boundedCustomWhatsAppNote(value);
        final saved = await _localDatabase.saveLocalPreferenceIfClean(
          ownerPhoneNumber: session.phoneNumber,
          key: key,
          value: bounded,
        );
        if (saved) {
          final changed = local[mode] != bounded;
          local[mode] = bounded;
          if (changed &&
              revisions[mode] ==
                  (_noteRevisions['${session.phoneNumber}:${mode.name}'] ??
                      0)) {
            _customNoteChanges.add(
              SosCustomNoteChange(
                phoneNumber: session.phoneNumber,
                mode: mode,
                note: bounded,
                revision: revisions[mode] ?? 0,
                isSynced: true,
              ),
            );
          }
        } else {
          final latest = await _localDatabase.loadLocalPreference(
            ownerPhoneNumber: session.phoneNumber,
            key: key,
          );
          if (latest is String) local[mode] = latest;
        }
      }
    } catch (_) {
      // Local safety instructions remain available when cloud reads fail.
    }
    return local;
  }

  /// Flushes pending custom whats app notes.
  Future<void> flushPendingCustomWhatsAppNotes({
    required AppSession session,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) return;
    final dirty = await _localDatabase.loadDirtyLocalPreferences(
      ownerPhoneNumber: session.phoneNumber,
    );
    for (final mode in _customNoteModes) {
      final key = 'sos_whatsapp_note_${mode.firestoreValue}';
      final note = dirty[key];
      if (note is! String) continue;
      try {
        await _pushCustomNote(session, mode, note, fromRetry: true);
      } catch (_) {
        // Keep this mode dirty; another independent mode may still sync.
      }
    }
  }

  /// Fetches cloud custom notes.
  @protected
  Future<Map<String, dynamic>> fetchCloudCustomNotes(AppSession session) async {
    final paused = _readCache.isRevalidationPausedFor(session.phoneNumber);
    final data = await _readSosPreferences(
      session,
      force: !paused,
      registerOnly: paused,
    );
    final notes = data['sosWhatsappNotes'];
    return notes is Map ? Map<String, dynamic>.from(notes) : {};
  }

  /// Computes push cloud custom note.
  @protected
  Future<void> pushCloudCustomNote(
    AppSession session,
    SosAlertMode mode,
    String note, {
    int? operationSeq,
  }) async {
    final response = await FirebaseFunctions.instance
        .httpsCallable(
          'syncSafetyPreferences',
          options: HttpsCallableOptions(timeout: _customNoteWriteTimeout),
        )
        .call<Map<String, dynamic>>({
          'expectedOwner': session.phoneNumber,
          'field': 'sosWhatsappNotes.${mode.firestoreValue}',
          'value': note,
          'operationSeq': operationSeq,
        })
        .timeout(_customNoteWriteTimeout);
    if (response.data['confirmed'] != true ||
        response.data['superseded'] == true) {
      throw const SosAlertRepositoryException('The note was not acknowledged.');
    }
  }

  /// Computes push custom note.
  Future<bool> _pushCustomNote(
    AppSession session,
    SosAlertMode mode,
    String note, {
    bool fromRetry = false,
  }) async {
    final key = 'sos_whatsapp_note_${mode.firestoreValue}';
    final snapshot = await _localDatabase.loadVersionedPreference(
      session.phoneNumber,
      key,
    );
    final flightKey =
        '${session.phoneNumber}:${mode.name}:${snapshot.sequence}';
    final existing = _notePushes[flightKey];
    if (existing != null) return existing;
    final work = _pushCustomNoteNow(session, mode, note, fromRetry: fromRetry);
    _notePushes[flightKey] = work;
    try {
      return await work;
    } finally {
      if (identical(_notePushes[flightKey], work)) {
        _notePushes.remove(flightKey);
      }
    }
  }

  Future<bool> _pushCustomNoteNow(
    AppSession session,
    SosAlertMode mode,
    String note, {
    required bool fromRetry,
  }) async {
    final revision = _noteRevisions['${session.phoneNumber}:${mode.name}'] ?? 0;
    final key = 'sos_whatsapp_note_${mode.firestoreValue}';
    final snapshot = await _localDatabase.loadVersionedPreference(
      session.phoneNumber,
      key,
    );
    final pending = snapshot.value;
    final dirtyBefore = await _localDatabase.loadDirtyLocalPreferences(
      ownerPhoneNumber: session.phoneNumber,
    );
    if (!dirtyBefore.containsKey(key)) {
      // Another drain may have already confirmed this exact revision while
      // the explicit save was awaiting its local snapshot.
      return pending == note &&
          revision ==
              (_noteRevisions['${session.phoneNumber}:${mode.name}'] ?? 0);
    }
    if (pending != note ||
        revision !=
            (_noteRevisions['${session.phoneNumber}:${mode.name}'] ?? 0)) {
      return false;
    }
    await pushCloudCustomNote(
      session,
      mode,
      note,
      operationSeq: snapshot.sequence,
    ).timeout(_customNoteWriteTimeout);
    final latest = await _localDatabase.loadLocalPreference(
      ownerPhoneNumber: session.phoneNumber,
      key: key,
    );
    if ((await _localDatabase.loadVersionedPreference(
              session.phoneNumber,
              key,
            )).sequence ==
            snapshot.sequence &&
        latest == note &&
        revision ==
            (_noteRevisions['${session.phoneNumber}:${mode.name}'] ?? 0)) {
      await _localDatabase.markLocalPreferenceSynced(
        ownerPhoneNumber: session.phoneNumber,
        key: key,
        expectedValue: note,
        expectedSequence: snapshot.sequence,
      );
      final dirty = await _localDatabase.loadDirtyLocalPreferences(
        ownerPhoneNumber: session.phoneNumber,
      );
      if (dirty.containsKey(key) ||
          revision !=
              (_noteRevisions['${session.phoneNumber}:${mode.name}'] ?? 0)) {
        return false;
      }
      _customNoteChanges.add(
        SosCustomNoteChange(
          phoneNumber: session.phoneNumber,
          mode: mode,
          note: note,
          revision: revision,
          isSynced: true,
          syncedAfterRetry: fromRetry,
        ),
      );
      try {
        await _readCache.invalidate(
          owner: session.phoneNumber,
          type: 'mobile_sos_preferences',
          id: 'current',
        );
      } catch (_) {
        // Cache invalidation cannot undo a confirmed note acknowledgement.
      }
      return true;
    }
    return false;
  }

  /// Saves custom whats app note.
  Future<SosCustomNoteChange> saveCustomWhatsAppNote({
    required AppSession session,
    required SosAlertMode mode,
    required String note,
  }) async {
    if (!const {
      SosAlertMode.manual,
      SosAlertMode.duress,
      SosAlertMode.medical,
    }.contains(mode)) {
      throw const SosAlertRepositoryException(
        'Custom notes are not supported for this SOS mode.',
      );
    }
    final normalizedNote = note.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalizedNote.length > 240) {
      throw const SosAlertRepositoryException(
        'The custom SOS note must be 240 characters or fewer.',
      );
    }

    final preferenceKey = 'sos_whatsapp_note_${mode.firestoreValue}';
    final revisionKey = '${session.phoneNumber}:${mode.name}';
    final revision = (_noteRevisions[revisionKey] ?? 0) + 1;
    _noteRevisions[revisionKey] = revision;
    await _localDatabase.saveVersionedDirtyPreference(
      session.phoneNumber,
      preferenceKey,
      normalizedNote,
    );
    if (_noteRevisions[revisionKey] == revision) {
      _customNoteChanges.add(
        SosCustomNoteChange(
          phoneNumber: session.phoneNumber,
          mode: mode,
          note: normalizedNote,
          revision: revision,
        ),
      );
    }
    var synced = false;
    if (_firebaseBootstrapResult.isAvailable &&
        (_customNoteCanSync?.call() ??
            NetworkReachabilityService.instance.latest.state !=
                NetworkReachabilityState.offline)) {
      try {
        synced = await _pushCustomNote(session, mode, normalizedNote);
      } catch (_) {
        // Persisted dirty notes are replayed on load and reconnection.
      }
    }
    return SosCustomNoteChange(
      phoneNumber: session.phoneNumber,
      mode: mode,
      note: normalizedNote,
      revision: revision,
      isSynced: synced,
    );
  }

  /// Loads alert logs.
  Future<List<SosAlert>> loadAlertLogs({
    required AppSession session,
    int limit = 30,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return const [];
    }

    try {
      final referencedAlerts = await _loadReferencedAlertLogs(
        session: session,
        limit: limit,
      );
      if (referencedAlerts.isNotEmpty) {
        return _confirmedLogs(session, referencedAlerts);
      }
      final snapshot = await _sosAlerts
          .where(
            'userId',
            isEqualTo: FirebaseUserRepository.documentIdForPhoneNumber(
              session.phoneNumber,
            ),
          )
          .limit(limit)
          .get();
      final alerts = snapshot.docs
          .map((document) => SosAlert.fromFirestore(document.data()))
          .toList();
      alerts.sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
      return _confirmedLogs(session, alerts);
    } catch (_) {
      return const [];
    }
  }

  /// Loads referenced alert logs.
  Future<List<SosAlert>> _loadReferencedAlertLogs({
    required AppSession session,
    required int limit,
  }) async {
    final userSnapshot = await _userDocumentFor(session).get();
    final rawPaths = userSnapshot.data()?['recentSosAlertPaths'];
    if (rawPaths is! Iterable) return const [];
    final paths = rawPaths
        .whereType<String>()
        .where((path) => path.startsWith('sosAlerts/'))
        .take(
          limit < 0
              ? 0
              : limit > _maxRecentSosAlertReferences
              ? _maxRecentSosAlertReferences
              : limit,
        )
        .toList();
    if (paths.isEmpty) return const [];
    final snapshots = await Future.wait(
      paths.map((path) => _resolvedFirestore.doc(path).get()),
    );
    final alerts = snapshots
        .where((snapshot) => snapshot.exists && snapshot.data() != null)
        .map((snapshot) => SosAlert.fromFirestore(snapshot.data()!))
        .toList();
    alerts.sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
    return alerts;
  }

  /// Captures only the active hike's clothing; storage failure must not block SOS delivery.
  Future<HikeShirtColor?> _shirtColorAtTrigger(
    String phone,
    DateTime triggeredAt,
  ) async {
    try {
      final hike = await _localDatabase
          .loadActiveHikeSession(phoneNumber: phone)
          .timeout(const Duration(milliseconds: 750));
      if (hike == null || hike.startedAt.isAfter(triggeredAt)) return null;
      return HikeShirtColor.fromPreferences(hike.draft.completedChecklistItems);
    } catch (_) {
      return null;
    }
  }

  /// Computes trigger alert.
  Future<SosAlertResult> triggerAlert({
    required AppSession session,
    required SosAlertMode mode,
    required DateTime triggeredAt,
    required SosTriggerLocation? triggerLocation,
    required List<EmergencyContact> contacts,
    String? customMessageNote,
    SosAlertTriggerSource? triggerSource,
  }) async {
    final submission = await submitAlert(
      session: session,
      mode: mode,
      triggeredAt: triggeredAt,
      triggerLocation: triggerLocation,
      contacts: contacts,
      customMessageNote: customMessageNote,
      triggerSource: triggerSource,
    );
    return submission.acknowledgement;
  }

  /// Attempt durable queuing first; the returned pending submission still awaits delivery acknowledgement.
  Future<SosAlertSubmission> submitAlert({
    required AppSession session,
    required SosAlertMode mode,
    required DateTime triggeredAt,
    required SosTriggerLocation? triggerLocation,
    required List<EmergencyContact> contacts,
    String? customMessageNote,
    SosAlertTriggerSource? triggerSource,
  }) async {
    final resolvedTriggerSource =
        triggerSource ?? SosAlertTriggerSource.mobilePhone;
    final alertId = _alertIdFor(triggeredAt, mode);
    final activeIds = _activeAlertIds.putIfAbsent(
      session.phoneNumber,
      () => {},
    );
    activeIds.add(alertId);
    final shirtColor = await _shirtColorAtTrigger(
      session.phoneNumber,
      triggeredAt,
    );
    final message = SosAlertMessageComposer.compose(
      mode: mode,
      phoneNumber: session.phoneNumber,
      triggeredAt: triggeredAt,
      triggerLocation: triggerLocation,
      customNote: customMessageNote,
      triggerSource: resolvedTriggerSource,
      preferredTimeZone: AppSettingsController.instance.preferredTimeZone,
      shirtColor: shirtColor,
    );

    final pendingAlert = SosAlert(
      id: alertId,
      mode: mode,
      status: SosAlertStatus.queued,
      triggeredAt: triggeredAt,
      triggeredByPhoneNumber: session.phoneNumber,
      contactCount: contacts.length,
      sentCount: 0,
      failedCount: 0,
      dispatches: const [],
      message: message,
      triggerLocation: triggerLocation,
      triggerSource: resolvedTriggerSource,
      shirtColor: shirtColor,
    );
    int? durableQueueId;
    try {
      durableQueueId = await _queueAlertForRetry(
        session: session,
        alert: pendingAlert,
        contacts: contacts,
        dispatches: const [],
        customMessageNote: customMessageNote,
        failureReason: 'SOS contact dispatch is pending.',
      );
    } catch (_) {
      // Emergency delivery still takes priority if local storage is unavailable.
    }

    var queuedCount = 0;
    try {
      queuedCount = await countQueuedAlerts(session: session);
    } catch (_) {
      // A local counter failure must not prevent the emergency submission.
    }
    final submittedAlert = SosAlert(
      id: alertId,
      mode: mode,
      status: contacts.isEmpty
          ? SosAlertStatus.noContacts
          : SosAlertStatus.queued,
      triggeredAt: triggeredAt,
      triggeredByPhoneNumber: session.phoneNumber,
      contactCount: contacts.length,
      sentCount: 0,
      failedCount: 0,
      dispatches: const [],
      message: message,
      triggerLocation: triggerLocation,
      triggerSource: resolvedTriggerSource,
      shirtColor: shirtColor,
    );
    _confirmations.remember(_owner(session), pendingAlert);
    final acknowledgement =
        _completeSubmittedAlert(
          session: session,
          mode: mode,
          triggeredAt: triggeredAt,
          triggerLocation: triggerLocation,
          contacts: contacts,
          customMessageNote: customMessageNote,
          resolvedTriggerSource: resolvedTriggerSource,
          alertId: alertId,
          message: message,
          pendingAlert: pendingAlert,
          durableQueueId: durableQueueId,
        ).whenComplete(() {
          if (activeIds.remove(alertId)) _notifyQueueChanged(session);
        });
    return SosAlertSubmission(
      submittedResult: SosAlertResult(
        alert: submittedAlert,
        // The just-created durability row is an in-flight submission, not a
        // visible retry. It becomes Queued only if acknowledgement fails.
        queuedAlertCount: queuedCount,
      ),
      acknowledgement: acknowledgement,
    );
  }

  /// Computes complete submitted alert.
  Future<SosAlertResult> _completeSubmittedAlert({
    required AppSession session,
    required SosAlertMode mode,
    required DateTime triggeredAt,
    required SosTriggerLocation? triggerLocation,
    required List<EmergencyContact> contacts,
    required String? customMessageNote,
    required SosAlertTriggerSource resolvedTriggerSource,
    required String alertId,
    required String message,
    required SosAlert pendingAlert,
    required int? durableQueueId,
  }) async {
    var queueId = durableQueueId;

    final dispatches = <SosContactDispatch>[];
    if (contacts.isNotEmpty) {
      // Submit immediately instead of blocking on a separate connectivity
      // probe. Firebase is the source of truth, and the bounded callable ACK
      // below decides whether this row is completed or remains retryable.
      dispatches.addAll(
        await Future.wait(
          contacts.map(
            (contact) => _sendToContact(
              contact: contact,
              alertId: alertId,
              mode: mode,
              triggeredAt: triggeredAt,
              triggerLocation: triggerLocation,
              customMessageNote: customMessageNote,
              triggerSource: resolvedTriggerSource,
              shirtColor: pendingAlert.shirtColor,
            ),
          ),
        ),
      );
      await _checkpointQueuedAlert(
        queueId: queueId,
        alert: pendingAlert,
        contacts: _contactsRequiringRetry(contacts, dispatches),
        dispatches: dispatches,
        customMessageNote: customMessageNote,
        failureReason: 'Waiting for the Firebase SOS acknowledgement.',
      );
    }

    final reconciled = _confirmations.contacts(
      _owner(session),
      alertId,
      dispatches,
    );
    dispatches
      ..clear()
      ..addAll(reconciled);
    final sentCount = dispatches.where((dispatch) => dispatch.wasSent).length;
    final failedCount = dispatches
        .where((p) => !p.wasSent && !p.isUnconfirmed && !p.isConfirming)
        .length;
    final status = _statusFor(
      contactCount: contacts.length,
      sentCount: sentCount,
      failedCount: failedCount,
      dispatches: dispatches,
    );

    final alert = _confirmations.remember(
      _owner(session),
      SosAlert(
        id: alertId,
        mode: mode,
        status: status,
        triggeredAt: triggeredAt,
        triggeredByPhoneNumber: session.phoneNumber,
        contactCount: contacts.length,
        sentCount: sentCount,
        failedCount: failedCount,
        dispatches: dispatches,
        message: message,
        triggerLocation: triggerLocation,
        triggerSource: resolvedTriggerSource,
        shirtColor: pendingAlert.shirtColor,
      ),
    );

    if (sentCount > 0) {
      // Contact confirmation must not wait for cloud-log synchronization.
      _notifyQueueChanged(session, alert: alert, queuedForRetry: true);
    }

    Object? cloudSaveError;
    try {
      _throwIfFirebaseUnavailable();
      await saveAlert(session: session, alert: alert);
    } catch (error) {
      cloudSaveError = error;
    }

    final contactsRequiringRetry = _contactsRequiringRetry(
      contacts,
      dispatches,
    );
    final queuedForRetry =
        cloudSaveError != null ||
        (_shouldQueueDispatchRetry(status) &&
            contactsRequiringRetry.isNotEmpty);
    if (queuedForRetry) {
      final failureReason = cloudSaveError == null
          ? 'One or more SOS contact dispatches failed.'
          : _queueFailureMessage(cloudSaveError);
      if (queueId == null) {
        queueId = await _queueAlertForRetry(
          session: session,
          alert: alert,
          contacts: contactsRequiringRetry,
          dispatches: dispatches,
          customMessageNote: customMessageNote,
          failureReason: failureReason,
        );
      } else {
        await _checkpointQueuedAlert(
          queueId: queueId,
          alert: alert,
          contacts: contactsRequiringRetry,
          dispatches: dispatches,
          customMessageNote: customMessageNote,
          failureReason: failureReason,
          sendStatus: 'retry',
        );
      }
    } else if (queueId != null) {
      await _localDatabase.markQueuedAlertSent(queueId);
    }

    _activeAlertIds[session.phoneNumber]?.remove(alertId);
    final queuedCount = await countQueuedAlerts(session: session);
    final freshAlert = _confirmations.remember(_owner(session), alert);
    final effectiveAlert =
        queuedForRetry &&
            freshAlert.sentCount == 0 &&
            !freshAlert.dispatches.any((p) => p.isUnconfirmed || p.isConfirming)
        ? _alertWithStatus(freshAlert, SosAlertStatus.queued)
        : freshAlert;
    _notifyQueueChanged(
      session,
      alert: effectiveAlert,
      queuedForRetry: queuedForRetry,
    );
    return SosAlertResult(
      alert: effectiveAlert,
      queuedForRetry: queuedForRetry,
      queuedAlertCount: queuedCount,
    );
  }

  /// Computes count queued alerts.
  Future<int> countQueuedAlerts({required AppSession session}) async {
    final activeIds = _activeAlertIds[session.phoneNumber];
    if (activeIds != null && activeIds.isNotEmpty) {
      final rows = await _localDatabase.loadQueuedAlerts(
        ownerPhoneNumber: session.phoneNumber,
        limit: null,
      );
      return rows
          .where(
            (row) => !activeIds.contains(
              _queuedPayloadFrom(row.payloadJson)['alertId'],
            ),
          )
          .length;
    }
    return _localDatabase.countQueuedAlerts(
      ownerPhoneNumber: session.phoneNumber,
    );
  }

  /// Loads queued dispatches.
  Future<List<SosQueuedDispatch>> loadQueuedDispatches({
    required AppSession session,
    int? limit,
  }) async {
    final queuedAlerts = await _localDatabase.loadQueuedAlerts(
      ownerPhoneNumber: session.phoneNumber,
      limit: limit,
    );
    final activeIds = _activeAlertIds[session.phoneNumber] ?? const <String>{};
    return queuedAlerts
        .where(
          (row) => !activeIds.contains(
            _queuedPayloadFrom(row.payloadJson)['alertId'],
          ),
        )
        .map((queuedAlert) {
          final payload = _queuedPayloadFrom(queuedAlert.payloadJson);
          final contacts = _contactsFromPayload(payload['contacts']);
          final triggerLocation = _triggerLocationFromPayload(
            payload['triggerLocation'],
            fallbackLatitude: queuedAlert.triggerLatitude,
            fallbackLongitude: queuedAlert.triggerLongitude,
          );
          final rawTriggeredAt = payload['triggeredAtLocal'];
          final triggeredAt =
              (rawTriggeredAt is String
                  ? DateTime.tryParse(rawTriggeredAt)
                  : null) ??
              queuedAlert.triggerTime;
          final contactCount = switch (payload['contactCount']) {
            final num value when value.isFinite && value >= 0 => value.toInt(),
            _ => contacts.length,
          };
          final payloadError = payload['lastFailure'];
          return SosQueuedDispatch(
            id: queuedAlert.id,
            alertId: payload['alertId'] as String? ?? '',
            mode: _modeFromFirestoreValue(
              payload['mode'] is String
                  ? payload['mode'] as String
                  : queuedAlert.alertType,
            ),
            triggeredAt: triggeredAt,
            createdAt: queuedAlert.createdAt,
            sendStatus: queuedAlert.sendStatus,
            retryCount: queuedAlert.retryCount,
            contactCount: contactCount,
            pendingContactCount: contacts.length,
            lastError: queuedAlert.lastError.trim().isNotEmpty
                ? queuedAlert.lastError.trim()
                : payloadError is String
                ? payloadError.trim()
                : '',
            message: payload['message'] is String
                ? (payload['message'] as String).trim()
                : '',
            triggerLocation: triggerLocation,
          );
        })
        .toList(growable: false);
  }

  /// Share one sequential drain across the home shell and SOS screen. The
  /// actual dispatch request checks connectivity without a separate DNS wait.
  Future<SosQueueFlushResult> flushQueuedAlerts({
    required AppSession session,
    required List<EmergencyContact> contacts,
    int? limit,
  }) {
    final existing = _queueDrains[session.phoneNumber];
    if (existing != null) return existing;
    final drain = _flushQueuedAlerts(
      session: session,
      contacts: contacts,
      limit: limit,
    );
    _queueDrains[session.phoneNumber] = drain;
    return drain.whenComplete(() {
      if (identical(_queueDrains[session.phoneNumber], drain)) {
        _queueDrains.remove(session.phoneNumber);
      }
    });
  }

  /// Flushes queued alerts.
  Future<SosQueueFlushResult> _flushQueuedAlerts({
    required AppSession session,
    required List<EmergencyContact> contacts,
    required int? limit,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return SosQueueFlushResult(
        attempted: 0,
        sent: 0,
        remaining: await countQueuedAlerts(session: session),
      );
    }

    try {
      await _confirmations.refresh(_owner(session));
    } catch (_) {
      // The callable still enforces per-contact idempotency if receipts are temporarily unavailable.
    }
    var attempted = 0;
    var sent = 0;
    final attemptedIds = <int>{};

    while (limit == null || attempted < limit) {
      final rows = await _localDatabase.loadQueuedAlerts(
        ownerPhoneNumber: session.phoneNumber,
        limit: null,
      );
      final activeIds =
          _activeAlertIds[session.phoneNumber] ?? const <String>{};
      final pending = rows
          .where(
            (row) =>
                !attemptedIds.contains(row.id) &&
                !activeIds.contains(
                  _queuedPayloadFrom(row.payloadJson)['alertId'],
                ),
          )
          .toList();
      if (pending.isEmpty) break;
      for (final queuedAlert in pending) {
        if (limit != null && attempted >= limit) break;
        attemptedIds.add(queuedAlert.id);
        attempted += 1;
        var checkpointPayload = queuedAlert.payloadJson;
        SosAlert? completedAlert;
        var queuedForRetry = true;
        try {
          final payload = _queuedPayloadFrom(queuedAlert.payloadJson);
          final mode = _modeFromFirestoreValue(
            payload['mode'] as String? ?? queuedAlert.alertType,
          );
          final triggeredAt =
              DateTime.tryParse(payload['triggeredAtLocal'] as String? ?? '') ??
              queuedAlert.triggerTime;
          final triggerLocation = _triggerLocationFromPayload(
            payload['triggerLocation'],
            fallbackLatitude: queuedAlert.triggerLatitude,
            fallbackLongitude: queuedAlert.triggerLongitude,
          );
          final triggerSource = SosAlertTriggerSource.fromFirestore(
            payload['triggerSource'],
          );
          final shirtColor = HikeShirtColor.fromName(payload['shirtColor']);
          final message =
              payload['message'] as String? ??
              SosAlertMessageComposer.compose(
                mode: mode,
                phoneNumber: session.phoneNumber,
                triggeredAt: triggeredAt,
                triggerLocation: triggerLocation,
                customNote: payload['customMessageNote'] as String?,
                triggerSource: triggerSource,
                preferredTimeZone:
                    AppSettingsController.instance.preferredTimeZone,
                shirtColor: shirtColor,
              );
          final alertId =
              payload['alertId'] as String? ?? _alertIdFor(triggeredAt, mode);
          final previousDispatches = _confirmations.contacts(
            _owner(session),
            alertId,
            _dispatchesFromPayload(payload['dispatches']),
          );
          final contactsForRetry = _contactsFromPayload(payload['contacts']);
          final candidateContacts =
              contactsForRetry.isEmpty && previousDispatches.isEmpty
              ? contacts
              : contactsForRetry;
          final retryContacts = _contactsRequiringRetry(
            candidateContacts,
            previousDispatches,
          );
          final contactUniverse = retryContacts.isNotEmpty
              ? retryContacts
              : contacts;

          final retryDispatches = <SosContactDispatch>[];
          for (final contact in retryContacts) {
            retryDispatches.add(
              await _sendToContact(
                contact: contact,
                alertId: alertId,
                mode: mode,
                triggeredAt: triggeredAt,
                triggerLocation: triggerLocation,
                customMessageNote: payload['customMessageNote'] as String?,
                triggerSource: triggerSource,
                shirtColor: shirtColor,
              ),
            );
          }

          final allDispatches = _confirmations.contacts(
            _owner(session),
            alertId,
            _latestDispatchesByPhone([
              ...previousDispatches,
              ...retryDispatches,
            ]),
          );
          final latestSentCount = allDispatches
              .where((dispatch) => dispatch.wasSent)
              .length;
          final latestFailedCount = allDispatches
              .where((p) => !p.wasSent && !p.isUnconfirmed && !p.isConfirming)
              .length;
          final originalContactCount = switch (payload['contactCount']) {
            final num value when value.isFinite && value >= 0 => value.toInt(),
            _ =>
              contactUniverse.isEmpty
                  ? allDispatches.length
                  : contactUniverse.length,
          };
          final alert = SosAlert(
            id: alertId,
            mode: mode,
            status: _statusFor(
              contactCount: originalContactCount,
              sentCount: latestSentCount,
              failedCount: latestFailedCount,
              dispatches: allDispatches,
            ),
            triggeredAt: triggeredAt,
            triggeredByPhoneNumber: session.phoneNumber,
            contactCount: originalContactCount,
            sentCount: latestSentCount,
            failedCount: latestFailedCount,
            dispatches: allDispatches,
            message: message,
            triggerLocation: triggerLocation,
            triggerSource: triggerSource,
            shirtColor: shirtColor,
          );

          final remainingRetryContacts = _contactsRequiringRetry(
            contactUniverse,
            allDispatches,
          );
          checkpointPayload = jsonEncode({
            ...payload,
            'dispatches': allDispatches
                .map((dispatch) => dispatch.toFirestore())
                .toList(),
            'contacts': remainingRetryContacts
                .map((contact) => contact.toFirestore())
                .toList(),
          });
          // Keep recipient acknowledgements even if saving the cloud log fails.
          await _localDatabase.updateQueuedAlertPayload(
            id: queuedAlert.id,
            payloadJson: checkpointPayload,
            sendStatus: 'retry',
          );
          // Provider acknowledgements are useful immediately, even when
          // cloud-log synchronization or other recipients still need retry.
          completedAlert = alert;
          if (alert.sentCount > 0) {
            _notifyQueueChanged(session, alert: alert, queuedForRetry: true);
          }
          await saveAlert(session: session, alert: alert);
          if (alert.status == SosAlertStatus.sent ||
              remainingRetryContacts.isEmpty) {
            await _localDatabase.markQueuedAlertSent(queuedAlert.id);
            if (alert.status == SosAlertStatus.sent) {
              sent += 1;
            }
            queuedForRetry = false;
          } else {
            await _localDatabase.updateQueuedAlertRetry(
              id: queuedAlert.id,
              payloadJson: checkpointPayload,
              lastError: 'SOS retry is still not fully sent.',
            );
          }
        } catch (error) {
          await _localDatabase.updateQueuedAlertRetry(
            id: queuedAlert.id,
            payloadJson: checkpointPayload,
            lastError: _queueFailureMessage(error),
          );
        }
        _notifyQueueChanged(
          session,
          alert: completedAlert,
          queuedForRetry: queuedForRetry,
        );
      }
    }

    return SosQueueFlushResult(
      attempted: attempted,
      sent: sent,
      remaining: await countQueuedAlerts(session: session),
    );
  }

  /// Sends whats app test message.
  Future<List<SosContactDispatch>> sendWhatsAppTestMessage({
    required AppSession session,
    required List<EmergencyContact> contacts,
  }) async {
    _throwIfFirebaseUnavailable();

    final sentAt = DateTime.now().toUtc();
    final testDispatchId = 'sos_test_${sentAt.microsecondsSinceEpoch}';
    final dispatches = <SosContactDispatch>[];
    for (final contact in contacts) {
      dispatches.add(
        await _sendToContact(
          contact: contact,
          alertId: testDispatchId,
          mode: SosAlertMode.manual,
          triggeredAt: sentAt,
          triggerLocation: null,
          triggerSource: SosAlertTriggerSource.mobilePhone,
          isTest: true,
        ),
      );
    }
    return dispatches;
  }

  /// Computes queue alert for retry.
  Future<int> _queueAlertForRetry({
    required AppSession session,
    required SosAlert alert,
    required List<EmergencyContact> contacts,
    required List<SosContactDispatch> dispatches,
    required String? customMessageNote,
    required String failureReason,
  }) async {
    final triggerLocation = alert.triggerLocation;
    return _localDatabase.insertQueuedAlert(
      ownerPhoneNumber: session.phoneNumber,
      sessionId:
          'sos_${FirebaseUserRepository.documentIdForPhoneNumber(session.phoneNumber)}',
      alertType: alert.mode.firestoreValue,
      triggerLatitude: triggerLocation?.latitude ?? 0,
      triggerLongitude: triggerLocation?.longitude ?? 0,
      payloadJson: jsonEncode(
        _queuedAlertPayload(
          session: session,
          alert: alert,
          contacts: contacts,
          dispatches: dispatches,
          customMessageNote: customMessageNote,
          failureReason: failureReason,
        ),
      ),
    );
  }

  /// Persist recipient progress so later retries do not repeat already completed dispatches.
  Future<void> _checkpointQueuedAlert({
    required int? queueId,
    required SosAlert alert,
    required List<EmergencyContact> contacts,
    required List<SosContactDispatch> dispatches,
    required String? customMessageNote,
    required String failureReason,
    String sendStatus = 'queued',
  }) async {
    if (queueId == null) return;
    try {
      await _localDatabase.updateQueuedAlertPayload(
        id: queueId,
        sendStatus: sendStatus,
        payloadJson: jsonEncode(
          _queuedAlertPayload(
            sessionPhoneNumber: alert.triggeredByPhoneNumber,
            alert: alert,
            contacts: contacts,
            dispatches: dispatches,
            customMessageNote: customMessageNote,
            failureReason: failureReason,
          ),
        ),
        lastError: failureReason,
      );
    } catch (_) {
      // Continue contacting the remaining recipients even if checkpointing fails.
    }
  }

  /// Computes queued alert payload.
  Map<String, dynamic> _queuedAlertPayload({
    AppSession? session,
    String? sessionPhoneNumber,
    required SosAlert alert,
    required List<EmergencyContact> contacts,
    required List<SosContactDispatch> dispatches,
    required String? customMessageNote,
    required String failureReason,
  }) {
    final triggerLocation = alert.triggerLocation;
    return {
      'schemaVersion': 4,
      'alertId': alert.id,
      'mode': alert.mode.firestoreValue,
      'triggerSource': alert.triggerSource.firestoreValue,
      if (alert.shirtColor != null) 'shirtColor': alert.shirtColor!.name,
      'triggeredAtLocal': alert.triggeredAt.toUtc().toIso8601String(),
      'phoneNumber': session?.phoneNumber ?? sessionPhoneNumber ?? '',
      'message': alert.message,
      'contactCount': alert.contactCount,
      if (triggerLocation != null)
        'triggerLocation': triggerLocation.toFirestore(),
      if (customMessageNote != null) 'customMessageNote': customMessageNote,
      'contacts': contacts.map((contact) => contact.toFirestore()).toList(),
      'dispatches': dispatches
          .map((dispatch) => dispatch.toFirestore())
          .toList(),
      'lastFailure': failureReason,
    };
  }

  /// Computes queued payload from.
  Map<String, dynamic> _queuedPayloadFrom(String payloadJson) {
    try {
      final decoded = jsonDecode(payloadJson);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  /// Computes contacts from payload.
  List<EmergencyContact> _contactsFromPayload(Object? value) {
    if (value is! Iterable) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map(
          (item) =>
              EmergencyContact.fromFirestore(Map<String, dynamic>.from(item)),
        )
        .where((contact) => contact.phoneNumber.trim().isNotEmpty)
        .toList();
  }

  /// Computes dispatches from payload.
  List<SosContactDispatch> _dispatchesFromPayload(Object? value) {
    if (value is! Iterable) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map(
          (item) =>
              SosContactDispatch.fromFirestore(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  /// Computes latest dispatches by phone.
  List<SosContactDispatch> _latestDispatchesByPhone(
    List<SosContactDispatch> dispatches,
  ) {
    final byPhone = <String, SosContactDispatch>{};
    for (final dispatch in dispatches) {
      final key = PhoneNumberFormatter.normalize(
        dispatch.phoneNumber,
      ).replaceAll(RegExp(r'[^0-9A-Za-z]+'), '');
      byPhone[key.isEmpty ? dispatch.phoneNumber : key] = dispatch;
    }
    return byPhone.values.toList();
  }

  /// Computes contacts requiring retry.
  List<EmergencyContact> _contactsRequiringRetry(
    List<EmergencyContact> contacts,
    List<SosContactDispatch> dispatches,
  ) {
    if (contacts.isEmpty) {
      return const [];
    }
    final latestByPhone = <String, SosContactDispatch>{};
    for (final dispatch in dispatches) {
      final key = PhoneNumberFormatter.normalize(
        dispatch.phoneNumber,
      ).replaceAll(RegExp(r'[^0-9A-Za-z]+'), '');
      if (key.isNotEmpty) {
        latestByPhone[key] = dispatch;
      }
    }
    return contacts.where((contact) {
      final key = PhoneNumberFormatter.normalize(
        contact.phoneNumber,
      ).replaceAll(RegExp(r'[^0-9A-Za-z]+'), '');
      final latest = latestByPhone[key];
      return key.isEmpty ||
          latest == null ||
          (SosDeliveryPolicy.canRetry(latest) &&
              latest.nextRetryAtMillis <=
                  DateTime.now().millisecondsSinceEpoch);
    }).toList();
  }

  /// Computes trigger location from payload.
  SosTriggerLocation? _triggerLocationFromPayload(
    Object? value, {
    required double fallbackLatitude,
    required double fallbackLongitude,
  }) {
    if (value is Map) {
      return SosTriggerLocation.fromFirestore(Map<String, dynamic>.from(value));
    }
    if (fallbackLatitude == 0 && fallbackLongitude == 0) {
      return null;
    }
    return SosTriggerLocation(
      latitude: fallbackLatitude,
      longitude: fallbackLongitude,
    );
  }

  /// Computes alert with status.
  SosAlert _alertWithStatus(SosAlert alert, SosAlertStatus status) {
    return SosAlert(
      id: alert.id,
      mode: alert.mode,
      status: status,
      triggeredAt: alert.triggeredAt,
      triggeredByPhoneNumber: alert.triggeredByPhoneNumber,
      contactCount: alert.contactCount,
      sentCount: alert.sentCount,
      failedCount: alert.failedCount,
      dispatches: alert.dispatches,
      message: alert.message,
      triggerLocation: alert.triggerLocation,
      triggerSource: alert.triggerSource,
      shirtColor: alert.shirtColor,
    );
  }

  /// Computes should queue dispatch retry.
  bool _shouldQueueDispatchRetry(SosAlertStatus status) {
    return status == SosAlertStatus.partial ||
        status == SosAlertStatus.failed ||
        status == SosAlertStatus.noContacts;
  }

  /// Computes queue failure message.
  String _queueFailureMessage(Object error) {
    if (error is SosAlertRepositoryException) {
      return error.message;
    }
    if (error is GreenApiException) {
      return error.message;
    }
    if (error is FirebaseException) {
      return error.message ?? error.code;
    }
    if (error is String && error.trim().isNotEmpty) {
      return error.trim();
    }
    return 'SOS alert could not be fully sent.';
  }

  /// Sends to contact.
  Future<SosContactDispatch> _sendToContact({
    required EmergencyContact contact,
    required String alertId,
    required SosAlertMode mode,
    required DateTime triggeredAt,
    required SosTriggerLocation? triggerLocation,
    required SosAlertTriggerSource triggerSource,
    String? customMessageNote,
    bool isTest = false,
    HikeShirtColor? shirtColor,
  }) async {
    final normalizedPhoneNumber = PhoneNumberFormatter.normalize(
      contact.phoneNumber,
    );

    if (!PhoneNumberFormatter.isValid(normalizedPhoneNumber)) {
      return SosContactDispatch(
        contactName: contact.name,
        phoneNumber: contact.phoneNumber,
        wasSent: false,
        retryable: false,
        errorMessage: 'Invalid phone number',
      );
    }

    Object? lastError;
    var retryable = true;
    for (var attempt = 1; attempt <= _maxImmediateSendAttempts; attempt++) {
      try {
        final dispatchId = _dispatchIdFor(alertId, normalizedPhoneNumber);
        final result = await _greenApiClient
            .sendMessage(
              chatId: PhoneNumberFormatter.toWhatsAppChatId(
                normalizedPhoneNumber,
              ),
              dispatchId: dispatchId,
              mode: isTest ? 'test' : mode.firestoreValue,
              triggeredAt: triggeredAt,
              latitude: triggerLocation?.latitude,
              longitude: triggerLocation?.longitude,
              accuracyMeters: triggerLocation?.accuracyMeters,
              customNote: customMessageNote,
              triggerSource: triggerSource.firestoreValue,
              isTest: isTest,
              shirtColor: shirtColor?.name,
            )
            .timeout(isTest ? const Duration(seconds: 4) : _sendAttemptTimeout);

        if (result.wasSent) {
          return SosContactDispatch(
            contactName: contact.name,
            phoneNumber: normalizedPhoneNumber,
            wasSent: true,
            retryable: false,
            providerMessageId: result.providerMessageId,
          );
        }
        if (!isTest &&
            (result.deliveryUncertain ||
                result.confirmationStatus == 'sending')) {
          return SosContactDispatch(
            contactName: contact.name,
            phoneNumber: normalizedPhoneNumber,
            wasSent: false,
            retryable: false,
            confirmationStatus: result.confirmationStatus == 'sending'
                ? 'sending'
                : 'unconfirmed',
            errorMessage: result.message,
          );
        }
        retryable = result.retryable;
        lastError = result.message ?? 'Emergency message was not confirmed.';
        if (!retryable || result.deliveryUncertain) {
          break;
        }
      } on TimeoutException catch (error) {
        if (!isTest) {
          return SosContactDispatch(
            contactName: contact.name,
            phoneNumber: normalizedPhoneNumber,
            wasSent: false,
            retryable: false,
            confirmationStatus: 'unconfirmed',
            errorMessage: 'No confirmation within 15 seconds. Still checking.',
          );
        }
        lastError = error;
      } on GreenApiException catch (error) {
        lastError = error;
        retryable = error.retryable;
        if (!retryable) {
          break;
        }
      } catch (error) {
        lastError = error;
      }

      if (attempt < _maxImmediateSendAttempts) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }

    return _failedDispatch(
      contact,
      retryable
          ? 'Unable to confirm WhatsApp delivery after $_maxImmediateSendAttempts attempts. ${_queueFailureMessage(lastError ?? Object())}'
          : _queueFailureMessage(lastError ?? Object()),
      retryable: retryable,
    );
  }

  /// Computes failed dispatch.
  SosContactDispatch _failedDispatch(
    EmergencyContact contact,
    String message, {
    bool retryable = true,
  }) {
    final normalizedPhoneNumber = PhoneNumberFormatter.normalize(
      contact.phoneNumber,
    );
    return SosContactDispatch(
      contactName: contact.name,
      phoneNumber: normalizedPhoneNumber.isEmpty
          ? contact.phoneNumber
          : normalizedPhoneNumber,
      wasSent: false,
      retryable: retryable,
      errorMessage: message,
    );
  }

  /// Dispatches id for.
  String _dispatchIdFor(String alertId, String phoneNumber) {
    final safeAlert = alertId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final phoneDigits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    final raw = '${safeAlert}_$phoneDigits';
    return raw.length <= 180 ? raw : raw.substring(0, 180);
  }

  /// Saves alert.
  @protected
  Future<void> saveAlert({
    required AppSession session,
    required SosAlert alert,
  }) async {
    try {
      final logTimeout = _cloudWriteTimeout < const Duration(seconds: 15)
          ? const Duration(seconds: 15)
          : _cloudWriteTimeout;
      final result = await FirebaseFunctions.instance
          .httpsCallable(
            'saveSosAlertLog',
            options: HttpsCallableOptions(timeout: logTimeout),
          )
          .call<Map<String, dynamic>>({'alert': alert.toFirestore()})
          .timeout(logTimeout);
      if (result.data['saved'] != true || result.data['alertId'] != alert.id) {
        throw const SosAlertRepositoryException(
          'The SOS history save was not confirmed.',
        );
      }
    } on FirebaseException catch (error) {
      throw SosAlertRepositoryException(
        'Cloud sync failed (${error.code}). ${error.message ?? 'Please try again.'}',
      );
    } on TimeoutException {
      throw const SosAlertRepositoryException('Cloud sync timed out.');
    }
  }

  /// Computes user document for.
  DocumentReference<Map<String, dynamic>> _userDocumentFor(AppSession session) {
    return userModuleDocument(
      _users.doc(
        FirebaseUserRepository.documentIdForPhoneNumber(session.phoneNumber),
      ),
      UserModule.sos,
    );
  }

  /// Computes status for.
  SosAlertStatus _statusFor({
    required int contactCount,
    required int sentCount,
    required int failedCount,
    List<SosContactDispatch>? dispatches,
  }) {
    if (dispatches != null) {
      return SosDeliveryPolicy.status(contactCount, dispatches);
    }
    if (contactCount == 0) {
      return SosAlertStatus.noContacts;
    }
    if (sentCount == contactCount) {
      return SosAlertStatus.sent;
    }
    if (sentCount > 0 && failedCount > 0) {
      return SosAlertStatus.partial;
    }
    return SosAlertStatus.failed;
  }

  /// Computes mode from firestore value.
  SosAlertMode _modeFromFirestoreValue(String value) {
    for (final mode in SosAlertMode.values) {
      if (mode.firestoreValue == value) {
        return mode;
      }
    }
    return SosAlertMode.manual;
  }

  /// Computes bounded custom whats app note.
  String _boundedCustomWhatsAppNote(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= 240 ? normalized : normalized.substring(0, 240);
  }

  /// Computes alert id for.
  String _alertIdFor(DateTime triggeredAt, SosAlertMode mode) {
    return '${mode.firestoreValue}_${triggeredAt.microsecondsSinceEpoch}';
  }

  /// Computes throw if firebase unavailable.
  void _throwIfFirebaseUnavailable() {
    if (_firebaseBootstrapResult.isAvailable) {
      return;
    }

    throw SosAlertRepositoryException(
      'Firebase is not ready yet. ${_firebaseBootstrapResult.errorMessage ?? ''}'
          .trim(),
    );
  }
}

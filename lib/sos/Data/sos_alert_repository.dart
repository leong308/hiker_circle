// SosAlertRepository durably queues emergency alerts and reconciles backend delivery acknowledgements.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../app/Data/user_module_paths.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/app_settings_controller.dart';
import '../../app/Data/firebase_user_repository.dart';
import '../../app/Data/local_session_database.dart';
import '../../app/Model/app_session.dart';
import '../../authentication/Data/green_api_client.dart';
import '../../authentication/Data/phone_number_formatter.dart';
import '../../core/services/network_reachability_service.dart';
import '../Model/sos_models.dart';

class SosAlertRepositoryException implements Exception {
  const SosAlertRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SosQueueFlushResult {
  const SosQueueFlushResult({
    required this.attempted,
    required this.sent,
    required this.remaining,
  });

  final int attempted;
  final int sent;
  final int remaining;

  bool get didFlushAny => sent > 0;
}

/// A durable local SOS submission and its eventual Firebase/provider result.
///
/// [submittedResult] records local queueing, never successful delivery.
/// [acknowledgement] replaces that pending state with the
/// authoritative sent, failed, or queued result.
class SosAlertSubmission {
  const SosAlertSubmission({
    required this.submittedResult,
    required this.acknowledgement,
  });

  final SosAlertResult submittedResult;
  final Future<SosAlertResult> acknowledgement;
}

class SosAlertRepository {
  static const int _maxImmediateSendAttempts = 1;
  static final Map<String, int> _noteRevisions = {};
  static const _customNoteModes = [
    SosAlertMode.manual,
    SosAlertMode.duress,
    SosAlertMode.medical,
  ];

  static const int _maxRecentSosAlertReferences = 30;

  SosAlertRepository({
    FirebaseFirestore? firestore,
    GreenApiClient? greenApiClient,
    LocalSessionDatabase? localDatabase,
    Duration sendAttemptTimeout = const Duration(seconds: 4),
    Duration cloudWriteTimeout = const Duration(seconds: 4),
    FirebaseBootstrapResult firebaseBootstrapResult =
        const FirebaseBootstrapResult.available(),
  }) : _firestore = firestore,
       _greenApiClient = greenApiClient ?? GreenApiClient(),
       _localDatabase = localDatabase ?? LocalSessionDatabase(),
       _sendAttemptTimeout = sendAttemptTimeout,
       _cloudWriteTimeout = cloudWriteTimeout,
       _firebaseBootstrapResult = firebaseBootstrapResult;

  final FirebaseFirestore? _firestore;
  final GreenApiClient _greenApiClient;
  final LocalSessionDatabase _localDatabase;
  final Duration _sendAttemptTimeout;
  final Duration _cloudWriteTimeout;
  final FirebaseBootstrapResult _firebaseBootstrapResult;

  FirebaseFirestore get _resolvedFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users {
    return _resolvedFirestore.collection('users');
  }

  CollectionReference<Map<String, dynamic>> get _sosAlerts {
    return _resolvedFirestore.collection('sosAlerts');
  }

  Future<Map<SosAlertMode, String>> loadCustomWhatsAppNotes({
    required AppSession session,
  }) async {
    await flushPendingCustomWhatsAppNotes(session: session);
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
    if (!_firebaseBootstrapResult.isAvailable) return local;
    try {
      final notes = await fetchCloudCustomNotes(
        session,
      ).timeout(_cloudWriteTimeout);
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
          local[mode] = bounded;
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
        await _pushCustomNote(session, mode, note);
      } catch (_) {
        // Keep this mode dirty; another independent mode may still sync.
      }
    }
  }

  @protected
  Future<Map<String, dynamic>> fetchCloudCustomNotes(AppSession session) async {
    final data = (await _userDocumentFor(session).get()).data();
    final notes = data?['sosWhatsappNotes'];
    return notes is Map ? Map<String, dynamic>.from(notes) : {};
  }

  @protected
  Future<void> pushCloudCustomNote(
    AppSession session,
    SosAlertMode mode,
    String note,
  ) async {
    await _userDocumentFor(session).set({
      'sosWhatsappNotes': {mode.firestoreValue: note},
      'sosWhatsappNotesUpdatedAt': FieldValue.serverTimestamp(),
      'sosWhatsappNotesUpdatedAtLocal': DateTime.now()
          .toUtc()
          .toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> _pushCustomNote(
    AppSession session,
    SosAlertMode mode,
    String note,
  ) async {
    final revision = _noteRevisions['${session.phoneNumber}:${mode.name}'] ?? 0;
    final key = 'sos_whatsapp_note_${mode.firestoreValue}';
    final pending = await _localDatabase.loadLocalPreference(
      ownerPhoneNumber: session.phoneNumber,
      key: key,
    );
    if (pending != note ||
        revision !=
            (_noteRevisions['${session.phoneNumber}:${mode.name}'] ?? 0)) {
      return;
    }
    await pushCloudCustomNote(session, mode, note).timeout(_cloudWriteTimeout);
    final latest = await _localDatabase.loadLocalPreference(
      ownerPhoneNumber: session.phoneNumber,
      key: key,
    );
    if (latest == note &&
        revision ==
            (_noteRevisions['${session.phoneNumber}:${mode.name}'] ?? 0)) {
      await _localDatabase.markLocalPreferenceSynced(
        ownerPhoneNumber: session.phoneNumber,
        key: key,
        expectedValue: note,
      );
    }
  }

  Future<void> saveCustomWhatsAppNote({
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
    _noteRevisions[revisionKey] = (_noteRevisions[revisionKey] ?? 0) + 1;
    await _localDatabase.saveLocalPreference(
      ownerPhoneNumber: session.phoneNumber,
      key: preferenceKey,
      value: normalizedNote,
      isDirty: true,
    );
    if (!_firebaseBootstrapResult.isAvailable) return;
    try {
      await _pushCustomNote(session, mode, normalizedNote);
    } catch (_) {
      // Persisted dirty notes are replayed on load and reconnection.
    }
  }

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
        return referencedAlerts;
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
      return alerts;
    } catch (_) {
      return const [];
    }
  }

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
    final message = SosAlertMessageComposer.compose(
      mode: mode,
      phoneNumber: session.phoneNumber,
      triggeredAt: triggeredAt,
      triggerLocation: triggerLocation,
      customNote: customMessageNote,
      triggerSource: resolvedTriggerSource,
      preferredTimeZone: AppSettingsController.instance.preferredTimeZone,
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
    final previouslyQueuedCount = durableQueueId == null
        ? queuedCount
        : (queuedCount - 1).clamp(0, queuedCount);
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
    );
    final acknowledgement = _completeSubmittedAlert(
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
    );
    return SosAlertSubmission(
      submittedResult: SosAlertResult(
        alert: submittedAlert,
        // The just-created durability row is an in-flight submission, not a
        // visible retry. It becomes Queued only if acknowledgement fails.
        queuedAlertCount: previouslyQueuedCount,
      ),
      acknowledgement: acknowledgement,
    );
  }

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

    final sentCount = dispatches.where((dispatch) => dispatch.wasSent).length;
    final failedCount = dispatches.length - sentCount;
    final status = _statusFor(
      contactCount: contacts.length,
      sentCount: sentCount,
      failedCount: failedCount,
    );

    final alert = SosAlert(
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
    );

    Object? cloudSaveError;
    try {
      _throwIfFirebaseUnavailable();
      await _saveAlert(session: session, alert: alert);
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

    final queuedCount = await countQueuedAlerts(session: session);
    final effectiveAlert = queuedForRetry && sentCount == 0
        ? _alertWithStatus(alert, SosAlertStatus.queued)
        : alert;
    return SosAlertResult(
      alert: effectiveAlert,
      queuedForRetry: queuedForRetry,
      queuedAlertCount: queuedCount,
    );
  }

  Future<int> countQueuedAlerts({required AppSession session}) {
    return _localDatabase.countQueuedAlerts(
      ownerPhoneNumber: session.phoneNumber,
    );
  }

  Future<List<SosQueuedDispatch>> loadQueuedDispatches({
    required AppSession session,
    int limit = 20,
  }) async {
    final queuedAlerts = await _localDatabase.loadQueuedAlerts(
      ownerPhoneNumber: session.phoneNumber,
      limit: limit,
    );
    return queuedAlerts
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

  /// Retry account-owned queued alerts only when reachability permits, retaining incomplete dispatch work.
  Future<SosQueueFlushResult> flushQueuedAlerts({
    required AppSession session,
    required List<EmergencyContact> contacts,
    int limit = 10,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return SosQueueFlushResult(
        attempted: 0,
        sent: 0,
        remaining: await countQueuedAlerts(session: session),
      );
    }

    final network = await NetworkReachabilityService.instance.refresh();
    if (!network.isOnline) {
      return SosQueueFlushResult(
        attempted: 0,
        sent: 0,
        remaining: await countQueuedAlerts(session: session),
      );
    }

    final queuedAlerts = await _localDatabase.loadQueuedAlerts(
      ownerPhoneNumber: session.phoneNumber,
      limit: limit,
    );
    var attempted = 0;
    var sent = 0;

    for (final queuedAlert in queuedAlerts) {
      attempted += 1;
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
            );
        final previousDispatches = _dispatchesFromPayload(
          payload['dispatches'],
        );
        final alertId =
            payload['alertId'] as String? ?? _alertIdFor(triggeredAt, mode);
        final contactsForRetry = _contactsFromPayload(payload['contacts']);
        final retryContacts =
            contactsForRetry.isEmpty && previousDispatches.isEmpty
            ? contacts
            : contactsForRetry;
        final contactUniverse = retryContacts.isNotEmpty
            ? retryContacts
            : contacts;

        final retryDispatches = <SosContactDispatch>[];
        final network = await _retryNetworkReachability();
        if (!network.isOnline) {
          retryDispatches.addAll(
            retryContacts.map(
              (contact) => _failedDispatch(
                contact,
                'No internet after $_maxImmediateSendAttempts retries. ${network.message ?? ''}'
                    .trim(),
              ),
            ),
          );
        } else {
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
              ),
            );
          }
        }

        final allDispatches = _latestDispatchesByPhone([
          ...previousDispatches,
          ...retryDispatches,
        ]);
        final latestSentCount = allDispatches
            .where((dispatch) => dispatch.wasSent)
            .length;
        final latestFailedCount = allDispatches.length - latestSentCount;
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
        );

        await _saveAlert(session: session, alert: alert);

        final remainingRetryContacts = _contactsRequiringRetry(
          contactUniverse,
          allDispatches,
        );
        if (alert.status == SosAlertStatus.sent ||
            remainingRetryContacts.isEmpty) {
          await _localDatabase.markQueuedAlertSent(queuedAlert.id);
          if (alert.status == SosAlertStatus.sent) {
            sent += 1;
          }
        } else {
          await _localDatabase.updateQueuedAlertRetry(
            id: queuedAlert.id,
            payloadJson: jsonEncode({
              ...payload,
              'dispatches': allDispatches
                  .map((dispatch) => dispatch.toFirestore())
                  .toList(),
              'contacts': remainingRetryContacts
                  .map((contact) => contact.toFirestore())
                  .toList(),
              'lastFailure': 'SOS retry is still not fully sent.',
            }),
            lastError: 'SOS retry is still not fully sent.',
          );
        }
      } catch (error) {
        await _localDatabase.updateQueuedAlertRetry(
          id: queuedAlert.id,
          payloadJson: queuedAlert.payloadJson,
          lastError: _queueFailureMessage(error),
        );
      }
    }

    return SosQueueFlushResult(
      attempted: attempted,
      sent: sent,
      remaining: await countQueuedAlerts(session: session),
    );
  }

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
      'schemaVersion': 3,
      'alertId': alert.id,
      'mode': alert.mode.firestoreValue,
      'triggerSource': alert.triggerSource.firestoreValue,
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

  Map<String, dynamic> _queuedPayloadFrom(String payloadJson) {
    try {
      final decoded = jsonDecode(payloadJson);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

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
          (!latest.wasSent && latest.retryable);
    }).toList();
  }

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
    );
  }

  bool _shouldQueueDispatchRetry(SosAlertStatus status) {
    return status == SosAlertStatus.partial ||
        status == SosAlertStatus.failed ||
        status == SosAlertStatus.noContacts;
  }

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

  Future<NetworkReachabilitySnapshot> _retryNetworkReachability() async {
    var latest = NetworkReachabilityService.instance.latest;
    for (var attempt = 0; attempt < _maxImmediateSendAttempts; attempt++) {
      latest = await NetworkReachabilityService.instance.refresh();
      if (latest.isOnline) {
        return latest;
      }
      if (attempt < _maxImmediateSendAttempts - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
    return latest;
  }

  Future<SosContactDispatch> _sendToContact({
    required EmergencyContact contact,
    required String alertId,
    required SosAlertMode mode,
    required DateTime triggeredAt,
    required SosTriggerLocation? triggerLocation,
    required SosAlertTriggerSource triggerSource,
    String? customMessageNote,
    bool isTest = false,
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
            )
            .timeout(_sendAttemptTimeout);

        if (result.wasSent) {
          return SosContactDispatch(
            contactName: contact.name,
            phoneNumber: normalizedPhoneNumber,
            wasSent: true,
            retryable: false,
            providerMessageId: result.providerMessageId,
          );
        }
        retryable = result.retryable;
        lastError = result.message ?? 'Emergency message was not confirmed.';
        if (!retryable || result.deliveryUncertain) {
          break;
        }
      } on TimeoutException catch (error) {
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

  String _dispatchIdFor(String alertId, String phoneNumber) {
    final safeAlert = alertId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final phoneDigits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    final raw = '${safeAlert}_$phoneDigits';
    return raw.length <= 180 ? raw : raw.substring(0, 180);
  }

  Future<void> _saveAlert({
    required AppSession session,
    required SosAlert alert,
  }) async {
    try {
      final userReference = _userDocumentFor(session);
      final alertReference = _sosAlerts.doc(alert.id);
      final alertPath = 'sosAlerts/${alert.id}';
      await _resolvedFirestore
          .runTransaction<void>((transaction) async {
            final userSnapshot = await transaction.get(userReference);
            final alertSnapshot = await transaction.get(alertReference);
            final user = userSnapshot.data() ?? const <String, dynamic>{};
            final existingPaths = user['recentSosAlertPaths'];
            final previousLatestAt = DateTime.tryParse(
              user['sosAlertsUpdatedAtLocal'] is String
                  ? user['sosAlertsUpdatedAtLocal'] as String
                  : '',
            );
            final isLatest =
                previousLatestAt == null ||
                !alert.triggeredAt.toUtc().isBefore(previousLatestAt.toUtc());
            final existingRecentPaths = existingPaths is Iterable
                ? existingPaths.whereType<String>()
                : const Iterable<String>.empty();
            final recentPaths = isLatest
                ? <String>[alertPath, ...existingRecentPaths]
                : <String>[...existingRecentPaths, alertPath];
            final uniqueRecentPaths = <String>[];
            for (final path in recentPaths) {
              if (!path.startsWith('sosAlerts/') ||
                  uniqueRecentPaths.contains(path)) {
                continue;
              }
              uniqueRecentPaths.add(path);
              if (uniqueRecentPaths.length >= _maxRecentSosAlertReferences) {
                break;
              }
            }
            transaction.set(alertReference, {
              ...alert.toFirestore(),
              'userId': FirebaseUserRepository.documentIdForPhoneNumber(
                session.phoneNumber,
              ),
              'phoneNumber': session.phoneNumber,
              'cloudLogPath': 'sosAlerts/${alert.id}',
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            transaction.set(userReference, {
              if (isLatest) 'latestSosAlertPath': alertPath,
              'recentSosAlertPaths': uniqueRecentPaths,
              if (!alertSnapshot.exists)
                'sosAlertsCount': FieldValue.increment(1),
              'sosAlertsUpdatedAt': FieldValue.serverTimestamp(),
              if (isLatest)
                'sosAlertsUpdatedAtLocal': alert.triggeredAt
                    .toUtc()
                    .toIso8601String(),
            }, SetOptions(merge: true));
          })
          .timeout(_cloudWriteTimeout);
    } on FirebaseException catch (error) {
      throw SosAlertRepositoryException(
        'Cloud sync failed (${error.code}). ${error.message ?? 'Please try again.'}',
      );
    } on TimeoutException {
      throw const SosAlertRepositoryException('Cloud sync timed out.');
    }
  }

  DocumentReference<Map<String, dynamic>> _userDocumentFor(AppSession session) {
    return userModuleDocument(
      _users.doc(
        FirebaseUserRepository.documentIdForPhoneNumber(session.phoneNumber),
      ),
      UserModule.sos,
    );
  }

  SosAlertStatus _statusFor({
    required int contactCount,
    required int sentCount,
    required int failedCount,
  }) {
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

  SosAlertMode _modeFromFirestoreValue(String value) {
    for (final mode in SosAlertMode.values) {
      if (mode.firestoreValue == value) {
        return mode;
      }
    }
    return SosAlertMode.manual;
  }

  String _boundedCustomWhatsAppNote(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= 240 ? normalized : normalized.substring(0, 240);
  }

  String _alertIdFor(DateTime triggeredAt, SosAlertMode mode) {
    return '${mode.firestoreValue}_${triggeredAt.microsecondsSinceEpoch}';
  }

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

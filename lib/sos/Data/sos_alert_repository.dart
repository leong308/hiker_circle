import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/firebase_user_repository.dart';
import '../../app/Data/local_session_database.dart';
import '../../app/Model/app_session.dart';
import '../../authentication/Data/green_api_client.dart';
import '../../authentication/Data/green_api_config.dart';
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

class SosAlertRepository {
  static const int _maxImmediateSendAttempts = 3;
  static const Duration _sendAttemptTimeout = Duration(seconds: 4);
  static const Duration _cloudWriteTimeout = Duration(seconds: 5);

  SosAlertRepository({
    FirebaseFirestore? firestore,
    GreenApiClient? greenApiClient,
    LocalSessionDatabase? localDatabase,
    FirebaseBootstrapResult firebaseBootstrapResult =
        const FirebaseBootstrapResult.available(),
  }) : _firestore = firestore,
       _greenApiClient =
           greenApiClient ?? GreenApiClient(config: const GreenApiConfig()),
       _localDatabase = localDatabase ?? LocalSessionDatabase(),
       _firebaseBootstrapResult = firebaseBootstrapResult;

  final FirebaseFirestore? _firestore;
  final GreenApiClient _greenApiClient;
  final LocalSessionDatabase _localDatabase;
  final FirebaseBootstrapResult _firebaseBootstrapResult;

  FirebaseFirestore get _resolvedFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users {
    return _resolvedFirestore.collection('users');
  }

  CollectionReference<Map<String, dynamic>> get _sosAlerts {
    return _resolvedFirestore.collection('sosAlerts');
  }

  CollectionReference<Map<String, dynamic>> get _whatsAppMessageLogs {
    return _resolvedFirestore.collection('whatsAppMessageLogs');
  }

  Future<Map<SosAlertMode, String>> loadCustomWhatsAppNotes({
    required AppSession session,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return const {};
    }

    final snapshot = await _userDocumentFor(session).get();
    final data = snapshot.data();
    final notes = data?['sosWhatsappNotes'];
    if (notes is! Map) {
      return const {};
    }

    return {
      for (final mode in [
        SosAlertMode.manual,
        SosAlertMode.duress,
        SosAlertMode.medical,
      ])
        if (notes[mode.firestoreValue] is String)
          mode: notes[mode.firestoreValue] as String,
    };
  }

  Future<void> saveCustomWhatsAppNote({
    required AppSession session,
    required SosAlertMode mode,
    required String note,
  }) async {
    _throwIfFirebaseUnavailable();

    await _userDocumentFor(session).set({
      'sosWhatsappNotes': {mode.firestoreValue: note.trim()},
      'sosWhatsappNotesUpdatedAt': FieldValue.serverTimestamp(),
      'sosWhatsappNotesUpdatedAtLocal': DateTime.now()
          .toUtc()
          .toIso8601String(),
      'phoneNumber': session.phoneNumber,
    }, SetOptions(merge: true));
  }

  Future<List<SosAlert>> loadAlertLogs({
    required AppSession session,
    int limit = 30,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return const [];
    }

    try {
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

  Future<SosAlertResult> triggerAlert({
    required AppSession session,
    required SosAlertMode mode,
    required DateTime triggeredAt,
    required SosTriggerLocation? triggerLocation,
    required List<EmergencyContact> contacts,
    String? customMessageNote,
  }) async {
    final alertId = _alertIdFor(triggeredAt, mode);
    final message = SosAlertMessageComposer.compose(
      mode: mode,
      phoneNumber: session.phoneNumber,
      triggeredAt: triggeredAt,
      triggerLocation: triggerLocation,
      customNote: customMessageNote,
    );

    final dispatches = <SosContactDispatch>[];
    String? immediateQueueReason;
    if (contacts.isNotEmpty) {
      final network = await _retryNetworkReachability();
      if (!network.isOnline) {
        immediateQueueReason =
            'No internet after $_maxImmediateSendAttempts retries. ${network.message ?? ''}'
                .trim();
        dispatches.addAll(
          contacts.map(
            (contact) => _failedDispatch(contact, immediateQueueReason!),
          ),
        );
      } else {
        for (final contact in contacts) {
          dispatches.add(
            await _sendToContact(contact: contact, message: message),
          );
        }
      }
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
    );

    var queuedForRetry = false;
    try {
      if (immediateQueueReason != null) {
        throw SosAlertRepositoryException(immediateQueueReason);
      }
      _throwIfFirebaseUnavailable();
      await _saveWhatsAppMessageLogs(
        session: session,
        messageType: 'sos_alert',
        sourceId: alertId,
        mode: mode.firestoreValue,
        message: message,
        dispatches: dispatches,
        sentAt: triggeredAt,
      );
      await _saveAlert(session: session, alert: alert);
    } catch (error) {
      queuedForRetry = true;
      await _queueAlertForRetry(
        session: session,
        alert: alert,
        contacts: _contactsRequiringRetry(contacts, dispatches),
        dispatches: dispatches,
        customMessageNote: customMessageNote,
        failureReason: _queueFailureMessage(error),
      );
    }

    if (!queuedForRetry && _shouldQueueDispatchRetry(status)) {
      queuedForRetry = true;
      await _queueAlertForRetry(
        session: session,
        alert: alert,
        contacts: _contactsRequiringRetry(contacts, dispatches),
        dispatches: dispatches,
        customMessageNote: customMessageNote,
        failureReason: 'One or more SOS contact dispatches failed.',
      );
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
        final message =
            payload['message'] as String? ??
            SosAlertMessageComposer.compose(
              mode: mode,
              phoneNumber: session.phoneNumber,
              triggeredAt: triggeredAt,
              triggerLocation: triggerLocation,
              customNote: payload['customMessageNote'] as String?,
            );
        final previousDispatches = _dispatchesFromPayload(
          payload['dispatches'],
        );
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
              await _sendToContact(contact: contact, message: message),
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
        final alert = SosAlert(
          id: payload['alertId'] as String? ?? _alertIdFor(triggeredAt, mode),
          mode: mode,
          status: _statusFor(
            contactCount: contactUniverse.isEmpty
                ? allDispatches.length
                : contactUniverse.length,
            sentCount: latestSentCount,
            failedCount: latestFailedCount,
          ),
          triggeredAt: triggeredAt,
          triggeredByPhoneNumber: session.phoneNumber,
          contactCount: contactUniverse.isEmpty
              ? allDispatches.length
              : contactUniverse.length,
          sentCount: latestSentCount,
          failedCount: latestFailedCount,
          dispatches: allDispatches,
          message: message,
          triggerLocation: triggerLocation,
        );

        await _saveWhatsAppMessageLogs(
          session: session,
          messageType: 'sos_alert_retry',
          sourceId: '${alert.id}_retry_${queuedAlert.id}',
          mode: mode.firestoreValue,
          message: message,
          dispatches: retryDispatches,
          sentAt: DateTime.now().toUtc(),
        );
        await _saveAlert(session: session, alert: alert);

        if (alert.status == SosAlertStatus.sent) {
          await _localDatabase.markQueuedAlertSent(queuedAlert.id);
          sent += 1;
        } else {
          await _localDatabase.updateQueuedAlertRetry(
            id: queuedAlert.id,
            payloadJson: jsonEncode({
              ...payload,
              'dispatches': allDispatches
                  .map((dispatch) => dispatch.toFirestore())
                  .toList(),
              'contacts': _contactsRequiringRetry(
                contactUniverse,
                allDispatches,
              ).map((contact) => contact.toFirestore()).toList(),
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
    final message = [
      'HikerCircle cloud messaging TEST',
      'Hiker: ${session.phoneNumber}',
      'Sent: ${sentAt.toIso8601String()}',
      'This is NOT an emergency or SOS alert.',
      'The hiker is testing cloud messaging during pre-hike preparation so emergency contacts can receive real alerts later.',
      'No action is required.',
    ].join('\n');
    final dispatches = <SosContactDispatch>[];
    for (final contact in contacts) {
      dispatches.add(await _sendToContact(contact: contact, message: message));
    }
    await _saveWhatsAppMessageLogs(
      session: session,
      messageType: 'sos_test',
      sourceId: 'sos_test_${sentAt.microsecondsSinceEpoch}',
      mode: 'test',
      message: message,
      dispatches: dispatches,
      sentAt: sentAt,
    );

    await _userDocumentFor(session).set({
      'latest_sos_messaging_test': {
        'sentAtLocal': sentAt.toIso8601String(),
        'contactCount': contacts.length,
        'sentCount': dispatches.where((dispatch) => dispatch.wasSent).length,
        'dispatches': dispatches
            .map((dispatch) => dispatch.toFirestore())
            .toList(),
      },
      'sosMessagingTestUpdatedAt': FieldValue.serverTimestamp(),
      'sosMessagingTestUpdatedAtLocal': sentAt.toIso8601String(),
      'phoneNumber': session.phoneNumber,
    }, SetOptions(merge: true));
    return dispatches;
  }

  Future<void> _queueAlertForRetry({
    required AppSession session,
    required SosAlert alert,
    required List<EmergencyContact> contacts,
    required List<SosContactDispatch> dispatches,
    required String? customMessageNote,
    required String failureReason,
  }) async {
    final triggerLocation = alert.triggerLocation;
    await _localDatabase.insertQueuedAlert(
      ownerPhoneNumber: session.phoneNumber,
      sessionId:
          'sos_${FirebaseUserRepository.documentIdForPhoneNumber(session.phoneNumber)}',
      alertType: alert.mode.firestoreValue,
      triggerLatitude: triggerLocation?.latitude ?? 0,
      triggerLongitude: triggerLocation?.longitude ?? 0,
      payloadJson: jsonEncode({
        'schemaVersion': 1,
        'alertId': alert.id,
        'mode': alert.mode.firestoreValue,
        'triggeredAtLocal': alert.triggeredAt.toUtc().toIso8601String(),
        'phoneNumber': session.phoneNumber,
        'message': alert.message,
        if (triggerLocation != null)
          'triggerLocation': triggerLocation.toFirestore(),
        if (customMessageNote != null) 'customMessageNote': customMessageNote,
        'contacts': contacts.map((contact) => contact.toFirestore()).toList(),
        'dispatches': dispatches
            .map((dispatch) => dispatch.toFirestore())
            .toList(),
        'lastFailure': failureReason,
      }),
    );
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
    final successfulPhoneKeys = dispatches
        .where((dispatch) => dispatch.wasSent)
        .map((dispatch) => PhoneNumberFormatter.normalize(dispatch.phoneNumber))
        .map((phone) => phone.replaceAll(RegExp(r'[^0-9A-Za-z]+'), ''))
        .where((phone) => phone.isNotEmpty)
        .toSet();
    return contacts.where((contact) {
      final key = PhoneNumberFormatter.normalize(
        contact.phoneNumber,
      ).replaceAll(RegExp(r'[^0-9A-Za-z]+'), '');
      return key.isEmpty || !successfulPhoneKeys.contains(key);
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
    if (error is FirebaseException) {
      return error.message ?? error.code;
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
    required String message,
  }) async {
    final normalizedPhoneNumber = PhoneNumberFormatter.normalize(
      contact.phoneNumber,
    );

    if (!PhoneNumberFormatter.isValid(normalizedPhoneNumber)) {
      return SosContactDispatch(
        contactName: contact.name,
        phoneNumber: contact.phoneNumber,
        wasSent: false,
        errorMessage: 'Invalid phone number',
      );
    }

    Object? lastError;
    for (var attempt = 1; attempt <= _maxImmediateSendAttempts; attempt++) {
      try {
        await _greenApiClient
            .sendMessage(
              chatId: PhoneNumberFormatter.toWhatsAppChatId(
                normalizedPhoneNumber,
              ),
              message: message,
            )
            .timeout(_sendAttemptTimeout);

        return SosContactDispatch(
          contactName: contact.name,
          phoneNumber: normalizedPhoneNumber,
          wasSent: true,
        );
      } on GreenApiConfigException catch (error) {
        return _failedDispatch(contact, error.message);
      } on TimeoutException catch (error) {
        lastError = error;
      } on GreenApiException catch (error) {
        lastError = error;
      } catch (error) {
        lastError = error;
      }

      if (attempt < _maxImmediateSendAttempts) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }

    return _failedDispatch(
      contact,
      'Unable to send WhatsApp message after $_maxImmediateSendAttempts retries. ${_queueFailureMessage(lastError ?? Object())}',
    );
  }

  SosContactDispatch _failedDispatch(EmergencyContact contact, String message) {
    final normalizedPhoneNumber = PhoneNumberFormatter.normalize(
      contact.phoneNumber,
    );
    return SosContactDispatch(
      contactName: contact.name,
      phoneNumber: normalizedPhoneNumber.isEmpty
          ? contact.phoneNumber
          : normalizedPhoneNumber,
      wasSent: false,
      errorMessage: message,
    );
  }

  Future<void> _saveAlert({
    required AppSession session,
    required SosAlert alert,
  }) async {
    try {
      await _userDocumentFor(session)
          .set({
            'latest_sos_alert': alert.toFirestore(),
            'sos_alerts': FieldValue.arrayUnion([alert.toFirestore()]),
            'sosAlertsCount': FieldValue.increment(1),
            'sosAlertsUpdatedAt': FieldValue.serverTimestamp(),
            'sosAlertsUpdatedAtLocal': alert.triggeredAt.toIso8601String(),
            'phoneNumber': session.phoneNumber,
          }, SetOptions(merge: true))
          .timeout(_cloudWriteTimeout);
      await _sosAlerts
          .doc(alert.id)
          .set({
            ...alert.toFirestore(),
            'userId': FirebaseUserRepository.documentIdForPhoneNumber(
              session.phoneNumber,
            ),
            'phoneNumber': session.phoneNumber,
            'cloudLogPath': 'sosAlerts/${alert.id}',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(_cloudWriteTimeout);
    } on FirebaseException catch (error) {
      throw SosAlertRepositoryException(
        'Cloud sync failed (${error.code}). ${error.message ?? 'Please try again.'}',
      );
    } on TimeoutException {
      throw const SosAlertRepositoryException('Cloud sync timed out.');
    }
  }

  Future<void> _saveWhatsAppMessageLogs({
    required AppSession session,
    required String messageType,
    required String sourceId,
    required String mode,
    required String message,
    required List<SosContactDispatch> dispatches,
    required DateTime sentAt,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable || dispatches.isEmpty) {
      return;
    }

    final batch = _resolvedFirestore.batch();
    for (var index = 0; index < dispatches.length; index++) {
      final dispatch = dispatches[index];
      final document = _whatsAppMessageLogs.doc(
        '${sourceId}_${index}_${dispatch.phoneNumber.replaceAll(RegExp(r'[^0-9A-Za-z]+'), '_')}',
      );
      batch.set(document, {
        'messageLogId': document.id,
        'messageType': messageType,
        'sourceId': sourceId,
        'mode': mode,
        'userId': FirebaseUserRepository.documentIdForPhoneNumber(
          session.phoneNumber,
        ),
        'senderPhoneNumber': session.phoneNumber,
        'contactName': dispatch.contactName,
        'recipientPhoneNumber': dispatch.phoneNumber,
        'wasSent': dispatch.wasSent,
        if (dispatch.errorMessage != null)
          'errorMessage': dispatch.errorMessage,
        'message': message,
        'sentAt': FieldValue.serverTimestamp(),
        'sentAtLocal': sentAt.toUtc().toIso8601String(),
      }, SetOptions(merge: true));
    }
    await batch.commit().timeout(_cloudWriteTimeout);
  }

  DocumentReference<Map<String, dynamic>> _userDocumentFor(AppSession session) {
    return _users.doc(
      FirebaseUserRepository.documentIdForPhoneNumber(session.phoneNumber),
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

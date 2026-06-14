import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/firebase_user_repository.dart';
import '../../app/Model/app_session.dart';
import '../../authentication/Data/green_api_client.dart';
import '../../authentication/Data/green_api_config.dart';
import '../../authentication/Data/phone_number_formatter.dart';
import '../Model/sos_models.dart';

class SosAlertRepositoryException implements Exception {
  const SosAlertRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SosAlertRepository {
  SosAlertRepository({
    FirebaseFirestore? firestore,
    GreenApiClient? greenApiClient,
    FirebaseBootstrapResult firebaseBootstrapResult =
        const FirebaseBootstrapResult.available(),
  }) : _firestore = firestore,
       _greenApiClient =
           greenApiClient ?? GreenApiClient(config: const GreenApiConfig()),
       _firebaseBootstrapResult = firebaseBootstrapResult;

  final FirebaseFirestore? _firestore;
  final GreenApiClient _greenApiClient;
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
    _throwIfFirebaseUnavailable();

    final alertId = _alertIdFor(triggeredAt, mode);
    final message = SosAlertMessageComposer.compose(
      mode: mode,
      phoneNumber: session.phoneNumber,
      triggeredAt: triggeredAt,
      triggerLocation: triggerLocation,
      customNote: customMessageNote,
    );

    final dispatches = <SosContactDispatch>[];
    if (contacts.isNotEmpty) {
      for (final contact in contacts) {
        dispatches.add(
          await _sendToContact(contact: contact, message: message),
        );
      }
    }
    await _saveWhatsAppMessageLogs(
      session: session,
      messageType: 'sos_alert',
      sourceId: alertId,
      mode: mode.firestoreValue,
      message: message,
      dispatches: dispatches,
      sentAt: triggeredAt,
    );

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

    await _saveAlert(session: session, alert: alert);
    return SosAlertResult(alert: alert);
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

    try {
      await _greenApiClient.sendMessage(
        chatId: PhoneNumberFormatter.toWhatsAppChatId(normalizedPhoneNumber),
        message: message,
      );

      return SosContactDispatch(
        contactName: contact.name,
        phoneNumber: normalizedPhoneNumber,
        wasSent: true,
      );
    } on GreenApiConfigException catch (error) {
      return SosContactDispatch(
        contactName: contact.name,
        phoneNumber: normalizedPhoneNumber,
        wasSent: false,
        errorMessage: error.message,
      );
    } on GreenApiException catch (error) {
      return SosContactDispatch(
        contactName: contact.name,
        phoneNumber: normalizedPhoneNumber,
        wasSent: false,
        errorMessage: error.message,
      );
    } catch (_) {
      return SosContactDispatch(
        contactName: contact.name,
        phoneNumber: normalizedPhoneNumber,
        wasSent: false,
        errorMessage: 'Unable to send WhatsApp message',
      );
    }
  }

  Future<void> _saveAlert({
    required AppSession session,
    required SosAlert alert,
  }) async {
    try {
      await _userDocumentFor(session).set({
        'latest_sos_alert': alert.toFirestore(),
        'sos_alerts': FieldValue.arrayUnion([alert.toFirestore()]),
        'sosAlertsCount': FieldValue.increment(1),
        'sosAlertsUpdatedAt': FieldValue.serverTimestamp(),
        'sosAlertsUpdatedAtLocal': alert.triggeredAt.toIso8601String(),
        'phoneNumber': session.phoneNumber,
      }, SetOptions(merge: true));
      await _sosAlerts.doc(alert.id).set({
        ...alert.toFirestore(),
        'userId': FirebaseUserRepository.documentIdForPhoneNumber(
          session.phoneNumber,
        ),
        'phoneNumber': session.phoneNumber,
        'cloudLogPath': 'sosAlerts/${alert.id}',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (error) {
      throw SosAlertRepositoryException(
        'Firestore ${error.code}: ${error.message ?? 'No details provided.'}',
      );
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
    await batch.commit();
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

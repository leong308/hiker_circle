import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Data/local_session_database.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/authentication/Data/green_api_client.dart';
import 'package:hiker_circle/sos/Data/sos_alert_repository.dart';
import 'package:hiker_circle/sos/Model/sos_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'submits immediately and exposes an ACK timeout as pending retry',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'hiker_circle_sos_submission_test_',
      );
      final database = LocalSessionDatabase(
        databasePath: '${directory.path}/session.db',
      );
      final provider = _WaitingGreenApiClient();
      final repository = SosAlertRepository(
        greenApiClient: provider,
        localDatabase: database,
        sendAttemptTimeout: const Duration(milliseconds: 40),
        cloudWriteTimeout: const Duration(milliseconds: 40),
        firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
          'offline test',
        ),
      );
      final session = AppSession(
        phoneNumber: '+60111111111',
        signedInAt: DateTime.utc(2026, 8, 20),
      );

      try {
        final submission = await repository.submitAlert(
          session: session,
          mode: SosAlertMode.manual,
          triggeredAt: DateTime.utc(2026, 8, 20, 12),
          triggerLocation: null,
          contacts: const [
            EmergencyContact(
              name: 'Emergency contact',
              phoneNumber: '+60122222222',
              relationship: 'Family',
            ),
          ],
        );

        expect(submission.submittedResult.alert.status, SosAlertStatus.queued);
        expect(submission.submittedResult.alert.sentCount, 0);
        expect(submission.submittedResult.alert.dispatches, isEmpty);
        expect(submission.submittedResult.queuedAlertCount, 0);
        expect(
          await database.countQueuedAlerts(
            ownerPhoneNumber: session.phoneNumber,
          ),
          1,
          reason: 'the hidden in-flight row must already be durable',
        );

        final acknowledgement = await submission.acknowledgement;
        expect(acknowledgement.alert.status, SosAlertStatus.queued);
        expect(acknowledgement.queuedForRetry, isTrue);
        expect(acknowledgement.queuedAlertCount, 1);
      } finally {
        await database.close();
        directory.deleteSync(recursive: true);
      }
    },
  );
}

class _WaitingGreenApiClient extends GreenApiClient {
  final Completer<GreenApiSendResult> _completer = Completer();

  @override
  Future<GreenApiSendResult> sendMessage({
    required String chatId,
    required String dispatchId,
    required String mode,
    required DateTime triggeredAt,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String? customNote,
    String triggerSource = 'mobile_phone',
    bool isTest = false,
  }) {
    return _completer.future;
  }
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/sos/Data/emergency_contacts_repository.dart';
import 'package:hiker_circle/sos/Data/sos_alert_repository.dart';
import 'package:hiker_circle/sos/Model/sos_models.dart';
import 'package:hiker_circle/sos/ModelView/sos_view_model.dart';

void main() {
  final session = AppSession(
    phoneNumber: '+60123456789',
    signedInAt: DateTime.utc(2026, 6, 16),
  );

  test('does not notify after disposal when contacts finish loading', () async {
    final repository = _DelayedEmergencyContactsRepository();
    final viewModel = SosViewModel(
      session: session,
      emergencyContactsRepository: repository,
    );

    final loadFuture = viewModel.loadEmergencyContacts();
    viewModel.dispose();
    repository.complete(const []);

    await expectLater(loadFuture, completes);
  });

  test(
    'does not notify after disposal when alert logs finish loading',
    () async {
      final repository = _DelayedSosAlertRepository();
      final viewModel = SosViewModel(
        session: session,
        sosAlertRepository: repository,
      );

      final loadFuture = viewModel.loadCloudAlertLogs();
      viewModel.dispose();
      repository.complete(const []);

      await expectLater(loadFuture, completes);
    },
  );
}

class _DelayedEmergencyContactsRepository extends EmergencyContactsRepository {
  _DelayedEmergencyContactsRepository();

  final Completer<List<EmergencyContact>> _completer = Completer();

  void complete(List<EmergencyContact> contacts) {
    _completer.complete(contacts);
  }

  @override
  Future<List<EmergencyContact>> loadEmergencyContacts({
    required AppSession session,
  }) {
    return _completer.future;
  }
}

class _DelayedSosAlertRepository extends SosAlertRepository {
  _DelayedSosAlertRepository();

  final Completer<List<SosAlert>> _completer = Completer();

  void complete(List<SosAlert> alerts) {
    _completer.complete(alerts);
  }

  @override
  Future<List<SosAlert>> loadAlertLogs({
    required AppSession session,
    int limit = 30,
  }) {
    return _completer.future;
  }
}

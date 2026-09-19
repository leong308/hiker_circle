import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/local_session_database.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/sos/Data/emergency_contacts_repository.dart';
import 'package:hiker_circle/sos/Data/sos_alert_repository.dart';
import 'package:hiker_circle/sos/Model/sos_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late LocalSessionDatabase database;
  final session = AppSession(
    phoneNumber: '+60111111111',
    signedInAt: DateTime.utc(2026),
  );
  const contact = EmergencyContact(
    name: 'Family',
    phoneNumber: '+60122222222',
    relationship: 'Family',
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('safety_reconciliation_');
    database = LocalSessionDatabase(
      databasePath: '${directory.path}/session.db',
    );
  });
  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'pending delete-all survives reload and replays the empty contact list',
    () async {
      final repository = _Contacts(database)..remote = [contact];
      await database.saveEmergencyContacts(
        phoneNumber: session.phoneNumber,
        contacts: [contact],
      );
      repository.failSave = true;
      await expectLater(
        repository.saveEmergencyContacts(session: session, contacts: []),
        throwsA(isA<EmergencyContactsRepositoryException>()),
      );
      final restarted = _Contacts(database)
        ..remote = [contact]
        ..failSave = true;
      expect(await restarted.loadEmergencyContacts(session: session), isEmpty);
      expect(
        await database.loadLocalPreference(
          ownerPhoneNumber: session.phoneNumber,
          key: EmergencyContactsRepository.pendingPreferenceKey,
        ),
        isA<Map>(),
      );
      restarted.failSave = false;
      expect(await restarted.loadEmergencyContacts(session: session), isEmpty);
      expect(restarted.remote, isEmpty);
      expect(
        await database.loadLocalPreference(
          ownerPhoneNumber: session.phoneNumber,
          key: EmergencyContactsRepository.pendingPreferenceKey,
        ),
        isNull,
      );
    },
  );

  test('authoritative empty cloud list clears cached contacts', () async {
    await database.saveEmergencyContacts(
      phoneNumber: session.phoneNumber,
      contacts: [contact],
    );
    expect(
      await _Contacts(database).loadEmergencyContacts(session: session),
      isEmpty,
    );
    expect(
      await database.loadEmergencyContacts(phoneNumber: session.phoneNumber),
      isEmpty,
    );
  });

  test(
    'late cloud load cannot replace a contact edit and edits broadcast owner',
    () async {
      final repository = _Contacts(database)..loadGate = Completer();
      final load = repository.loadEmergencyContacts(session: session);
      await repository.fetchStarted.future;
      final changed = EmergencyContactsRepository.changes.firstWhere(
        (event) => event.phoneNumber == session.phoneNumber,
      );
      await repository.saveEmergencyContacts(
        session: session,
        contacts: [contact],
      );
      expect((await changed).contacts.single.phoneNumber, contact.phoneNumber);
      repository.loadGate!.complete([]);
      expect((await load).single.phoneNumber, contact.phoneNumber);
    },
  );

  test(
    'dirty SOS note survives failed cloud save and replays after restart',
    () async {
      final repository = _Notes(database)..failSave = true;
      await repository.saveCustomWhatsAppNote(
        session: session,
        mode: SosAlertMode.medical,
        note: 'New medication',
      );
      expect(
        (await repository.loadCustomWhatsAppNotes(
          session: session,
        ))[SosAlertMode.medical],
        'New medication',
      );
      final restarted = _Notes(database);
      expect(
        (await restarted.loadCustomWhatsAppNotes(
          session: session,
        ))[SosAlertMode.medical],
        'New medication',
      );
      expect(restarted.remote['medical'], 'New medication');
      expect(
        await database.loadDirtyLocalPreferences(
          ownerPhoneNumber: session.phoneNumber,
        ),
        isEmpty,
      );
    },
  );
}

class _Contacts extends EmergencyContactsRepository {
  _Contacts(LocalSessionDatabase db)
    : super(localDatabase: db, cloudTimeout: const Duration(milliseconds: 30));
  List<EmergencyContact> remote = [];
  bool failSave = false;
  Completer<List<EmergencyContact>>? loadGate;
  final fetchStarted = Completer<void>();
  @override
  Future<List<EmergencyContact>?> fetchCloudContacts(AppSession session) async {
    if (!fetchStarted.isCompleted) fetchStarted.complete();
    return loadGate?.future ?? remote;
  }

  @override
  Future<void> pushCloudContacts(
    AppSession session,
    List<EmergencyContact> contacts,
  ) async {
    if (failSave) throw StateError('offline');
    remote = List.of(contacts);
  }
}

class _Notes extends SosAlertRepository {
  _Notes(LocalSessionDatabase db)
    : super(
        localDatabase: db,
        cloudWriteTimeout: const Duration(milliseconds: 30),
      );
  bool failSave = false;
  Map<String, dynamic> remote = {'medical': 'Old medication'};
  @override
  Future<Map<String, dynamic>> fetchCloudCustomNotes(
    AppSession session,
  ) async => Map.of(remote);
  @override
  Future<void> pushCloudCustomNote(
    AppSession session,
    SosAlertMode mode,
    String note,
  ) async {
    if (failSave) throw StateError('offline');
    remote[mode.firestoreValue] = note;
  }
}

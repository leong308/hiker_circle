import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/local_session_database.dart';
import 'package:hiker_circle/sos/Model/nearby_sos_event.dart';
import 'package:hiker_circle/sos/Model/sos_models.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('nearby SOS classification', () {
    final receivedAt = DateTime.utc(2026, 8, 18, 12);
    const phoneLocation = SosTriggerLocation(
      latitude: 5.4141,
      longitude: 100.3288,
    );

    test('keeps a recent event within two kilometres active', () {
      final event = _event(
        receivedAt: receivedAt,
        location: const SosTriggerLocation(
          latitude: 5.4200,
          longitude: 100.3288,
        ),
      );

      expect(
        event.isActiveAt(
          now: receivedAt.add(const Duration(minutes: 59)),
          phoneLocation: phoneLocation,
        ),
        isTrue,
      );
    });

    test('archives an event farther than two kilometres', () {
      final event = _event(
        receivedAt: receivedAt,
        location: const SosTriggerLocation(
          latitude: 5.4500,
          longitude: 100.3288,
        ),
      );

      expect(
        event.isActiveAt(
          now: receivedAt.add(const Duration(minutes: 5)),
          phoneLocation: phoneLocation,
        ),
        isFalse,
      );
    });

    test('archives an event after one hour', () {
      final event = _event(receivedAt: receivedAt);

      expect(
        event.isActiveAt(
          now: receivedAt.add(const Duration(hours: 1, seconds: 1)),
          phoneLocation: phoneLocation,
        ),
        isFalse,
      );
    });

    test('keeps an approximate event active until the time limit', () {
      final event = _event(receivedAt: receivedAt);

      expect(
        event.isActiveAt(
          now: receivedAt.add(const Duration(minutes: 30)),
          phoneLocation: phoneLocation,
        ),
        isTrue,
      );
    });
  });

  group('nearby SOS persistence', () {
    late Directory temporaryDirectory;
    late LocalSessionDatabase database;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'hiker_circle_nearby_sos_test_',
      );
      database = LocalSessionDatabase(
        databasePath: path.join(temporaryDirectory.path, 'session.db'),
      );
    });

    tearDown(() async {
      await database.close();
      if (temporaryDirectory.existsSync()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('adds a later location relay to the original timestamp', () async {
      const owner = '+60111111111';
      final receivedAt = DateTime.utc(2026, 8, 18, 12);
      final eventKey = NearbySosEvent.eventKeyFor(
        deviceId: 'button-a',
        counter: 7,
        receivedAt: receivedAt,
      );
      await database.saveNearbySosEvent(
        NearbySosEvent(
          ownerPhoneNumber: owner,
          eventKey: eventKey,
          deviceId: 'button-a',
          counter: 7,
          rssi: -62,
          receivedAt: receivedAt,
          updatedAt: receivedAt,
          detectorLocation: const SosTriggerLocation(
            latitude: 5.415,
            longitude: 100.329,
            accuracyMeters: 18,
          ),
        ),
      );
      await database.saveNearbySosEvent(
        NearbySosEvent(
          ownerPhoneNumber: owner,
          eventKey: eventKey,
          deviceId: 'button-a',
          counter: 7,
          rssi: -59,
          receivedAt: receivedAt.add(const Duration(seconds: 8)),
          updatedAt: receivedAt.add(const Duration(seconds: 8)),
          location: const SosTriggerLocation(
            latitude: 5.4141,
            longitude: 100.3288,
            accuracyMeters: 12,
          ),
          detectorLocation: const SosTriggerLocation(
            latitude: 5.5,
            longitude: 100.4,
            accuracyMeters: 4,
          ),
        ),
      );

      final saved = (await database.loadNearbySosEvents(
        ownerPhoneNumber: owner,
      )).single;
      expect(saved.receivedAt, receivedAt);
      expect(saved.rssi, -59);
      expect(saved.location?.latitude, 5.4141);
      expect(saved.location?.accuracyMeters, 12);
      expect(saved.detectorLocation?.latitude, 5.415);
      expect(saved.detectorLocation?.accuracyMeters, 18);
    });

    test('isolates nearby events by signed-in account', () async {
      final receivedAt = DateTime.utc(2026, 8, 18, 12);
      for (final owner in ['+60111111111', '+60222222222']) {
        await database.saveNearbySosEvent(
          _event(receivedAt: receivedAt, ownerPhoneNumber: owner),
        );
      }

      final first = await database.loadNearbySosEvents(
        ownerPhoneNumber: '+60111111111',
      );
      final second = await database.loadNearbySosEvents(
        ownerPhoneNumber: '+60222222222',
      );
      expect(first.single.ownerPhoneNumber, '+60111111111');
      expect(second.single.ownerPhoneNumber, '+60222222222');
    });

    test('creates the nearby event table when upgrading version 20', () async {
      await database.close();
      final databasePath = path.join(temporaryDirectory.path, 'session.db');
      sqfliteFfiInit();
      final legacyDatabase = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 20,
          onCreate: (database, version) async {
            await database.execute(
              'CREATE TABLE legacy_marker (id INTEGER PRIMARY KEY)',
            );
          },
        ),
      );
      await legacyDatabase.close();
      database = LocalSessionDatabase(databasePath: databasePath);

      final receivedAt = DateTime.utc(2026, 8, 18, 12);
      await database.saveNearbySosEvent(_event(receivedAt: receivedAt));

      final saved = await database.loadNearbySosEvents(
        ownerPhoneNumber: '+60111111111',
      );
      expect(saved, hasLength(1));
      expect(saved.single.receivedAt, receivedAt);
    });

    test('adds detector coordinates when upgrading version 21', () async {
      await database.close();
      final databasePath = path.join(temporaryDirectory.path, 'session.db');
      sqfliteFfiInit();
      final legacyDatabase = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 21,
          onCreate: (database, version) async {
            await database.execute('''
              CREATE TABLE nearby_sos_events (
                owner_phone_number TEXT NOT NULL,
                event_key TEXT NOT NULL,
                device_id TEXT NOT NULL DEFAULT '',
                counter INTEGER,
                rssi INTEGER,
                received_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                latitude REAL,
                longitude REAL,
                accuracy_meters REAL,
                location_captured_at TEXT,
                PRIMARY KEY (owner_phone_number, event_key)
              )
            ''');
          },
        ),
      );
      await legacyDatabase.close();
      database = LocalSessionDatabase(databasePath: databasePath);

      final receivedAt = DateTime.utc(2026, 8, 18, 12);
      await database.saveNearbySosEvent(
        _event(
          receivedAt: receivedAt,
          detectorLocation: const SosTriggerLocation(
            latitude: 5.415,
            longitude: 100.329,
          ),
        ),
      );

      final saved = (await database.loadNearbySosEvents(
        ownerPhoneNumber: '+60111111111',
      )).single;
      expect(saved.detectorLocation?.latitude, 5.415);
      expect(saved.detectorLocation?.longitude, 100.329);
    });
  });
}

NearbySosEvent _event({
  required DateTime receivedAt,
  String ownerPhoneNumber = '+60111111111',
  SosTriggerLocation? location,
  SosTriggerLocation? detectorLocation,
}) {
  return NearbySosEvent(
    ownerPhoneNumber: ownerPhoneNumber,
    eventKey: NearbySosEvent.eventKeyFor(
      deviceId: 'button-a',
      counter: 7,
      receivedAt: receivedAt,
    ),
    deviceId: 'button-a',
    counter: 7,
    receivedAt: receivedAt,
    updatedAt: receivedAt,
    location: location,
    detectorLocation: detectorLocation,
  );
}

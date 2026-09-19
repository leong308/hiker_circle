import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/local_session_database.dart';
import 'package:hiker_circle/me/Data/expired_hikes_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late LocalSessionDatabase database;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('expired_hikes_');
    database = LocalSessionDatabase(databasePath: '${directory.path}/test.db');
  });
  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'expired plans retain details and use distinct cached cursor pages',
    () async {
      final repository = _ExpiredRepository(database);
      final first = await repository.loadPage(ownerPhoneNumber: '+60111111111');
      expect(first.hikes.single.trailName, 'Past scheduled ridge');
      expect(
        first.hikes.single.expectedReturnTime.toUtc(),
        DateTime.utc(2026, 7, 1, 12),
      );
      expect(first.hikes.single.creatorName, 'Organizer');
      expect(first.hikes.single.participantPhones, ['+60111111111']);
      expect(first.isFromCache, isFalse);
      final second = await repository.loadPage(
        ownerPhoneNumber: '+60111111111',
        cursor: first.nextCursor,
      );
      expect(second.hikes.single.id, 'older');
      expect(repository.requests.last['cursor'], first.nextCursor!.toMap());
      repository.offline = true;
      final cachedFirst = await repository.loadPage(
        ownerPhoneNumber: '+60111111111',
      );
      final cachedSecond = await repository.loadPage(
        ownerPhoneNumber: '+60111111111',
        cursor: first.nextCursor,
      );
      expect(cachedFirst.isFromCache, isTrue);
      expect(cachedFirst.hikes.single.id, 'recent');
      expect(cachedSecond.hikes.single.id, 'older');
      await expectLater(
        repository.loadPage(ownerPhoneNumber: '+60222222222'),
        throwsStateError,
      );
    },
  );

  test(
    'bad expired rows do not hide valid records or invent departure times',
    () {
      final page = ExpiredHikesPage.fromMap({
        'hikes': [
          null,
          'bad',
          {'hikeId': 'missing-time'},
          {'hikeId': 'bad-time', 'departureTimeLocal': 'invalid'},
          _record('good'),
        ],
        'nextCursor': {'departureTimeLocal': 'invalid', 'hikeId': 'good'},
      });
      expect(page.hikes.map((hike) => hike.id), ['good']);
      expect(page.nextCursor, isNull);
    },
  );

  test(
    'changed account response cannot populate another owner cache',
    () async {
      final repository = _ExpiredRepository(database);
      await expectLater(
        repository.loadPage(ownerPhoneNumber: '+60222222222'),
        throwsFormatException,
      );
      repository.offline = true;
      await expectLater(
        repository.loadPage(ownerPhoneNumber: '+60222222222'),
        throwsStateError,
      );
    },
  );
}

Map<String, dynamic> _record(String id) => {
  'hikeId': id,
  'trailName': 'Past scheduled ridge',
  'departureTimeLocal': '2026-07-01T08:00:00.000Z',
  'expectedReturnTimeLocal': '2026-07-01T12:00:00.000Z',
  'creatorName': 'Organizer',
  'creatorPhone': '+60111111111',
  'participantPhones': ['+60111111111'],
  'participantCount': 1,
  'hikeType': 'solo',
  'startPointName': 'Trailhead',
  'destinationName': 'Ridge',
  'distanceKm': 8.0,
  'durationMinutes': 240,
};

class _ExpiredRepository extends ExpiredHikesRepository {
  _ExpiredRepository(LocalSessionDatabase database)
    : super(localDatabase: database);
  bool offline = false;
  final requests = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> fetchCloudPage(
    Map<String, dynamic> request,
  ) async {
    requests.add(request);
    if (offline) throw StateError('offline');
    return {
      'ownerPhoneNumber': '+60111111111',
      'hikes': [_record(request['cursor'] == null ? 'recent' : 'older')],
      'nextCursor': request['cursor'] == null
          ? {
              'departureTimeLocal': '2026-07-01T08:00:00.000Z',
              'hikeId': 'recent',
            }
          : null,
    };
  }
}

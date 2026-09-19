import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Data/hiker_circle_firebase_repository.dart';
import 'package:hiker_circle/app/Data/local_session_database.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
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
  final startedAt = DateTime.utc(2026, 9, 18, 9);
  final hike = ActiveHikeSession(
    sessionId: 'session_${startedAt.millisecondsSinceEpoch}',
    draft: HikeSessionDraft.fromPersistence({
      'trail': {'trailId': 'trail-one', 'name': 'Test trail'},
    }),
    startedAt: startedAt,
    batteryLevel: 90,
    queuedUpdates: 0,
    manualPins: 0,
    checkIns: 0,
  );
  const channel = MethodChannel('hiker_circle/active_hike_live_status');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('location_ack_');
    database = LocalSessionDatabase(
      databasePath: '${directory.path}/session.db',
    );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'stationary timestamp samples persist separately, replay preserves first data, and owner queries isolate before limit',
    () async {
      for (final seconds in [0, 5]) {
        await database.insertLocationPoint(
          ownerPhoneNumber: session.phoneNumber,
          sessionId: hike.sessionId,
          latitude: 3,
          longitude: 101,
          pointType: 'tracking',
          recordedAt: startedAt.add(Duration(seconds: seconds)),
          fixCapturedAt: startedAt,
        );
      }
      await database.insertLocationPoint(
        ownerPhoneNumber: session.phoneNumber,
        sessionId: hike.sessionId,
        latitude: 9,
        longitude: 9,
        pointType: 'tracking',
        recordedAt: startedAt,
      );
      await database.insertLocationPoint(
        ownerPhoneNumber: '+60222222222',
        sessionId: hike.sessionId,
        latitude: 4,
        longitude: 102,
        pointType: 'tracking',
        recordedAt: startedAt,
      );
      final rows = await database.loadUnsentLocationPoints(
        sessionId: hike.sessionId,
        ownerPhoneNumber: session.phoneNumber,
      );
      expect(rows, hasLength(2));
      expect(rows.map((p) => p.latitude), everyElement(3));
      expect(rows.map((p) => p.fixCapturedAt), everyElement(startedAt));
      final other = await database.loadUnsentLocationPoints(
        sessionId: hike.sessionId,
        ownerPhoneNumber: '+60222222222',
        limit: 1,
      );
      expect(other.single.latitude, 4);
      await database.markLocationPointsSynced([rows.first.id]);
      expect(
        await database.countUnsentLocationPoints(
          hike.sessionId,
          ownerPhoneNumber: session.phoneNumber,
        ),
        1,
      );
    },
  );

  test(
    'only exact canonical acknowledgements remove requested timestamp identities',
    () {
      final first = startedAt.millisecondsSinceEpoch;
      Map<String, dynamic> ack() => {
        'sessionId': 'hike_one',
        'committedCount': 1,
        'committedRecordedAtMillis': [first],
        'committedPointIds': ['hike_one_$first'],
      };
      Set<int> parse(Map<String, dynamic> value) =>
          acknowledgedLocationSampleTimes(
            value,
            sessionId: 'hike_one',
            requestedTimes: {first, first + 5000},
          );
      expect(parse(ack()), {first});
      for (final invalid in [
        {...ack(), 'sessionId': 'foreign'},
        {...ack(), 'committedCount': 2},
        {
          ...ack(),
          'committedRecordedAtMillis': [first + 1],
        },
        {
          ...ack(),
          'committedRecordedAtMillis': [first + .5],
        },
        {
          ...ack(),
          'committedPointIds': ['wrong'],
        },
        {
          ...ack(),
          'committedCount': 2,
          'committedRecordedAtMillis': [first, first],
          'committedPointIds': ['hike_one_$first', 'hike_one_$first'],
        },
      ]) {
        expect(parse(invalid), isEmpty);
      }
    },
  );

  test(
    'durable end returns while cloud is pending and interrupted restart cannot resume tracking or discard acknowledged route',
    () async {
      final repository = _WaitingCompletionRepository(database);
      await database.saveActiveHikeSession(
        phoneNumber: session.phoneNumber,
        activeHike: hike,
      );
      await database.insertLocationPoint(
        ownerPhoneNumber: session.phoneNumber,
        sessionId: hike.sessionId,
        latitude: 3,
        longitude: 101,
        pointType: 'tracking',
        recordedAt: startedAt,
        isSynced: true,
      );
      final result = await repository
          .endHikeSession(session: session, activeHike: hike)
          .timeout(const Duration(seconds: 1));
      expect(result.status, 'pending');
      expect(repository.cloud.isCompleted, isFalse);
      expect(
        await database.loadPendingHikeEnds(
          ownerPhoneNumber: session.phoneNumber,
        ),
        hasLength(1),
      );
      expect(
        await database.loadActiveHikeSession(phoneNumber: session.phoneNumber),
        isNull,
      );
      expect(
        await database.loadLocationPoints(
          sessionId: hike.sessionId,
          ownerPhoneNumber: session.phoneNumber,
        ),
        hasLength(1),
      );
      repository.cloud.complete(0);
    },
  );

  test(
    'canonical remap keeps pending stop intent and route available for subsequent completion retry',
    () async {
      await database.saveActiveHikeSession(
        phoneNumber: session.phoneNumber,
        activeHike: hike,
      );
      await database.queuePendingHikeEnd(
        ownerPhoneNumber: session.phoneNumber,
        activeHike: hike,
        endedAt: startedAt.add(const Duration(hours: 1)),
      );
      await database.insertLocationPoint(
        ownerPhoneNumber: session.phoneNumber,
        sessionId: hike.sessionId,
        latitude: 3,
        longitude: 101,
        pointType: 'tracking',
        recordedAt: startedAt,
        isSynced: true,
      );
      final canonical = await database.migrateActiveHikeSessionId(
        ownerPhoneNumber: session.phoneNumber,
        activeHike: hike,
        newSessionId: 'hike_canonical',
      );
      final repository = HikerCircleFirebaseRepository(
        localDatabase: database,
        firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
          'test',
        ),
      );
      final merged = await repository.mergeStoredRoute(
        session: session,
        activeHike: canonical,
      );
      expect(merged.routePoints, hasLength(1));
      expect(
        await database.loadActiveHikeSession(phoneNumber: session.phoneNumber),
        isNull,
      );
      expect(
        await database.loadLocationPoints(
          sessionId: 'hike_canonical',
          ownerPhoneNumber: session.phoneNumber,
        ),
        hasLength(1),
      );
      expect(
        (await database.loadPendingHikeEnds(
          ownerPhoneNumber: session.phoneNumber,
        )).single.sessionId,
        hike.sessionId,
      );
    },
  );

  test(
    'an old stop acknowledgement cannot clear a newer durable stop intent',
    () async {
      await database.saveLocalPreference(
        ownerPhoneNumber: session.phoneNumber,
        key: 'pending_stop',
        value: {'generation': 2},
      );
      expect(
        await database.clearLocalPreferenceIfValue(
          ownerPhoneNumber: session.phoneNumber,
          key: 'pending_stop',
          expectedValue: {'generation': 1},
        ),
        isFalse,
      );
      expect(
        await database.loadLocalPreference(
          ownerPhoneNumber: session.phoneNumber,
          key: 'pending_stop',
        ),
        {'generation': 2},
      );
      expect(
        await database.clearLocalPreferenceIfValue(
          ownerPhoneNumber: session.phoneNumber,
          key: 'pending_stop',
          expectedValue: {'generation': 2},
        ),
        isTrue,
      );
    },
  );

  test(
    'account change while native read is pending cannot transfer or acknowledge another account samples',
    () async {
      String? uid = session.phoneNumber;
      var acknowledgements = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getPendingNativeLocationSamples') {
              uid = '+60222222222';
              return [
                {
                  'sampleId': '${hike.sessionId}:123',
                  'sampledAtMillis': 123,
                  'latitude': 3,
                  'longitude': 101,
                },
              ];
            }
            if (call.method == 'acknowledgeNativeLocationSamples') {
              acknowledgements++;
            }
            return null;
          });
      final repository = HikerCircleFirebaseRepository(
        localDatabase: database,
        authenticatedUid: () => uid,
      );
      await repository.drainNativeLocationSamples(
        session: session,
        sessionId: hike.sessionId,
      );
      expect(
        await database.loadLocationPoints(
          sessionId: hike.sessionId,
          ownerPhoneNumber: session.phoneNumber,
        ),
        isEmpty,
      );
      expect(acknowledgements, 0);
    },
  );
}

class _WaitingCompletionRepository extends HikerCircleFirebaseRepository {
  _WaitingCompletionRepository(LocalSessionDatabase database)
    : super(
        localDatabase: database,
        firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
          'test',
        ),
      );
  final cloud = Completer<int>();
  @override
  Future<int> flushPendingHikeEnds({
    required AppSession session,
    int limit = 20,
  }) => cloud.future;
}

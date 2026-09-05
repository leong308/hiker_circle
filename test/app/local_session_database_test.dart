import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/local_session_database.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory temporaryDirectory;
  late LocalSessionDatabase database;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'hiker_circle_local_session_test_',
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

  test(
    'user-only sign out preserves active hike and unsent safety queue',
    () async {
      final signedInAt = DateTime.utc(2026, 8, 4);
      const phoneNumber = '+60111111111';
      final activeHike = _activeHike();
      await database.saveSession(
        AppSession(phoneNumber: phoneNumber, signedInAt: signedInAt),
      );
      await database.saveActiveHikeSession(
        phoneNumber: phoneNumber,
        activeHike: activeHike,
      );
      await database.insertLocationPoint(
        ownerPhoneNumber: phoneNumber,
        sessionId: activeHike.sessionId,
        latitude: 3.1,
        longitude: 101.6,
        pointType: 'tracking',
      );
      await database.insertQueuedAlert(
        ownerPhoneNumber: phoneNumber,
        sessionId: activeHike.sessionId,
        alertType: 'manual_sos',
        triggerLatitude: 3.1,
        triggerLongitude: 101.6,
        payloadJson: '{}',
      );

      await database.clearUserSessionOnly();

      expect(await database.loadSession(), isNull);
      final restored = await database.loadActiveHikeSession(
        phoneNumber: phoneNumber,
      );
      expect(restored?.sessionId, activeHike.sessionId);
      expect(restored?.queuedUpdates, 1);
      expect(await database.countUnsentLocationPoints(activeHike.sessionId), 1);
    },
  );

  test('queued SOS alerts stay isolated to their owning account', () async {
    const firstOwner = '+60111111111';
    const secondOwner = '+60222222222';
    for (final owner in [firstOwner, secondOwner]) {
      await database.insertQueuedAlert(
        ownerPhoneNumber: owner,
        sessionId: 'sos-$owner',
        alertType: 'manual_sos',
        triggerLatitude: 3.1,
        triggerLongitude: 101.6,
        payloadJson: '{}',
      );
    }

    final firstAlerts = await database.loadQueuedAlerts(
      ownerPhoneNumber: firstOwner,
    );
    final secondAlerts = await database.loadQueuedAlerts(
      ownerPhoneNumber: secondOwner,
    );

    expect(firstAlerts.single.ownerPhoneNumber, firstOwner);
    expect(secondAlerts.single.ownerPhoneNumber, secondOwner);
    expect(await database.countQueuedAlerts(ownerPhoneNumber: firstOwner), 1);
    expect(await database.countQueuedAlerts(ownerPhoneNumber: secondOwner), 1);
  });

  test('SOS dispatch progress survives a database reopen', () async {
    const owner = '+60111111111';
    final rowId = await database.insertQueuedAlert(
      ownerPhoneNumber: owner,
      sessionId: 'sos-durable',
      alertType: 'manual_sos',
      triggerLatitude: 3.1,
      triggerLongitude: 101.6,
      payloadJson: jsonEncode({
        'contacts': ['first', 'second'],
        'dispatches': const [],
      }),
    );
    await database.updateQueuedAlertPayload(
      id: rowId,
      payloadJson: jsonEncode({
        'contacts': ['second'],
        'dispatches': ['first-sent'],
      }),
    );

    await database.close();
    database = LocalSessionDatabase(
      databasePath: path.join(temporaryDirectory.path, 'session.db'),
    );
    final queued = (await database.loadQueuedAlerts(
      ownerPhoneNumber: owner,
    )).single;
    final payload = jsonDecode(queued.payloadJson) as Map<String, dynamic>;

    expect(payload['contacts'], ['second']);
    expect(payload['dispatches'], ['first-sent']);
  });

  test('location queue can be loaded, acknowledged, and pruned', () async {
    const sessionId = 'queue-session';
    await database.insertLocationPoint(
      sessionId: sessionId,
      latitude: 3.1,
      longitude: 101.6,
      pointType: 'session_start',
      recordedAt: DateTime.utc(2026, 8, 4, 1),
    );
    await database.insertLocationPoint(
      sessionId: sessionId,
      latitude: 3.2,
      longitude: 101.7,
      pointType: 'tracking',
      recordedAt: DateTime.utc(2026, 8, 4, 2),
    );

    final queued = await database.loadUnsentLocationPoints(
      sessionId: sessionId,
    );
    expect(queued.map((point) => point.pointType), [
      'session_start',
      'tracking',
    ]);
    expect(queued.every((point) => point.hasValidCoordinate), isTrue);

    await database.markLocationPointsSynced(queued.map((point) => point.id));
    expect(await database.countUnsentLocationPoints(sessionId), 0);
    expect(await database.deleteSyncedLocationPoints(sessionId: sessionId), 2);
  });

  test(
    'cloud recovery remaps active state and queued telemetry atomically',
    () async {
      const phoneNumber = '+60111111111';
      final activeHike = _activeHike().copyWith(
        sourceUpcomingHikeId: 'upcoming-123',
      );
      const canonicalSessionId = 'hike_canonical_123';
      await database.saveActiveHikeSession(
        phoneNumber: phoneNumber,
        activeHike: activeHike,
      );
      await database.insertLocationPoint(
        ownerPhoneNumber: phoneNumber,
        sessionId: activeHike.sessionId,
        latitude: 3.1,
        longitude: 101.6,
        pointType: 'tracking',
      );

      await database.insertQueuedAlert(
        ownerPhoneNumber: phoneNumber,
        sessionId: activeHike.sessionId,
        alertType: 'manual_sos',
        triggerLatitude: 3.1,
        triggerLongitude: 101.6,
        payloadJson: '{}',
      );

      await database.migrateActiveHikeSessionId(
        ownerPhoneNumber: phoneNumber,
        activeHike: activeHike,
        newSessionId: canonicalSessionId,
      );

      final restored = await database.loadActiveHikeSession(
        phoneNumber: phoneNumber,
      );
      expect(restored?.sessionId, canonicalSessionId);
      expect(restored?.sourceUpcomingHikeId, 'upcoming-123');
      expect(await database.countUnsentLocationPoints(activeHike.sessionId), 0);
      expect(await database.countUnsentLocationPoints(canonicalSessionId), 1);
      expect(
        (await database.loadQueuedAlerts(
          ownerPhoneNumber: phoneNumber,
        )).single.sessionId,
        canonicalSessionId,
      );

      await database.discardHikeTrackingTelemetry(
        sessionId: canonicalSessionId,
      );
      expect(await database.countUnsentLocationPoints(canonicalSessionId), 0);
      expect(
        await database.countQueuedAlerts(ownerPhoneNumber: phoneNumber),
        1,
      );
    },
  );

  test('invalid GPS points are rejected before persistence', () async {
    expect(
      () => database.insertLocationPoint(
        sessionId: 'invalid-session',
        latitude: 120,
        longitude: 101.6,
        pointType: 'tracking',
      ),
      throwsArgumentError,
    );
  });

  test('pending hike end survives locally until explicitly deleted', () async {
    const phoneNumber = '+60111111111';
    final activeHike = _activeHike();
    final endedAt = DateTime.utc(2026, 8, 4, 4);
    final summary = HikeSummaryReport.fromActiveHike(
      activeHike: activeHike,
      endedAt: endedAt,
    );

    await database.queuePendingHikeEnd(
      ownerPhoneNumber: phoneNumber,
      activeHike: activeHike,
      summary: summary,
      endedAt: endedAt,
    );
    var queued = await database.loadPendingHikeEnds(
      ownerPhoneNumber: phoneNumber,
    );

    expect(queued, hasLength(1));
    expect(queued.single.sessionId, activeHike.sessionId);
    expect(queued.single.activeHike?.sessionId, activeHike.sessionId);
    expect(queued.single.summaryPayload?['sessionId'], activeHike.sessionId);
    expect(queued.single.endedAt, endedAt);

    await database.markPendingHikeEndRetry(
      ownerPhoneNumber: phoneNumber,
      sessionId: activeHike.sessionId,
      lastError: 'offline',
    );
    queued = await database.loadPendingHikeEnds(ownerPhoneNumber: phoneNumber);
    expect(queued.single.retryCount, 1);
    expect(queued.single.lastError, 'offline');

    await database.deletePendingHikeEnd(
      ownerPhoneNumber: phoneNumber,
      sessionId: activeHike.sessionId,
    );
    expect(
      await database.loadPendingHikeEnds(ownerPhoneNumber: phoneNumber),
      isEmpty,
    );
  });

  test('planned hike and checklist survive a database reopen', () async {
    const phoneNumber = '+60111111111';
    final draft = HikeSessionDraft.fromTrail(_activeHike().trail).copyWith(
      departureTime: DateTime.utc(2026, 8, 6, 1),
      expectedReturnTime: DateTime.utc(2026, 8, 6, 5),
      shareLiveLocation: true,
    );
    final upcoming = _upcomingHike(id: 'upcoming-1', draft: draft);
    await database.saveUpcomingHikesForPlanning(
      ownerPhoneNumber: phoneNumber,
      upcomingHikes: [upcoming],
    );
    await database.savePlannedHikeChecklist(
      ownerPhoneNumber: phoneNumber,
      upcomingHikeId: upcoming.id,
      completedItems: const {'Charged phone', 'not a real checklist item'},
    );

    final databasePath = path.join(temporaryDirectory.path, 'session.db');
    await database.close();
    database = LocalSessionDatabase(databasePath: databasePath);
    final restored = await database.loadPlannedHikeStates(
      ownerPhoneNumber: phoneNumber,
    );

    expect(restored, hasLength(1));
    expect(restored.single.upcomingHike.id, upcoming.id);
    expect(restored.single.upcomingHike.draft, isNotNull);
    final restoredDeparture = restored.single.upcomingHike.draft!.departureTime;
    expect(restoredDeparture.isUtc, isFalse);
    expect(restoredDeparture.toUtc(), draft.departureTime.toUtc());
    expect(restored.single.completedChecklistItems, {'Charged phone'});
    expect(restored.single.isConsumed, isFalse);

    await database.markPlannedHikeConsumed(
      ownerPhoneNumber: phoneNumber,
      upcomingHikeId: upcoming.id,
    );
    final consumed = await database.loadPlannedHikeStates(
      ownerPhoneNumber: phoneNumber,
    );
    expect(consumed.single.isConsumed, isTrue);
  });

  test(
    'confirmed cloud hike replaces its local pending copy without losing readiness',
    () async {
      const phoneNumber = '+60111111111';
      final draft = HikeSessionDraft.fromTrail(_activeHike().trail).copyWith(
        departureTime: DateTime.utc(2026, 8, 6, 1),
        expectedReturnTime: DateTime.utc(2026, 8, 6, 5),
      );
      final pending = _upcomingHike(id: 'local_pending_123', draft: draft);
      await database.saveUpcomingHikesForPlanning(
        ownerPhoneNumber: phoneNumber,
        upcomingHikes: [pending],
      );
      await database.savePlannedHikeChecklist(
        ownerPhoneNumber: phoneNumber,
        upcomingHikeId: pending.id,
        completedItems: const {'Power bank'},
      );

      final confirmed = _upcomingHike(id: 'cloud-upcoming-1', draft: null);
      await database.saveUpcomingHikesForPlanning(
        ownerPhoneNumber: phoneNumber,
        upcomingHikes: [confirmed],
      );
      final states = await database.loadPlannedHikeStates(
        ownerPhoneNumber: phoneNumber,
      );

      expect(states, hasLength(1));
      expect(states.single.upcomingHike.id, confirmed.id);
      expect(states.single.upcomingHike.draft, isNotNull);
      expect(states.single.completedChecklistItems, {'Power bank'});

      // A late scheduling callback must not recreate a pending duplicate after
      // the Firestore listener has already stored the confirmed document.
      await database.saveUpcomingHikesForPlanning(
        ownerPhoneNumber: phoneNumber,
        upcomingHikes: [pending],
      );
      final afterLatePendingWrite = await database.loadPlannedHikeStates(
        ownerPhoneNumber: phoneNumber,
      );
      expect(afterLatePendingWrite, hasLength(1));
      expect(afterLatePendingWrite.single.upcomingHike.id, confirmed.id);
    },
  );

  test(
    'local pending draft replaces an older cached confirmed draft',
    () async {
      const phoneNumber = '+60111111111';
      final baseDraft = HikeSessionDraft.fromTrail(_activeHike().trail)
          .copyWith(
            departureTime: DateTime.utc(2026, 8, 6, 1),
            expectedReturnTime: DateTime.utc(2026, 8, 6, 5),
            shareLiveLocation: false,
          );
      final privatePendingDraft = baseDraft.copyWith(
        shareLiveLocation: true,
        fallDetectionEnabled: true,
        emergencyContactNames: const ['Private contact'],
      );
      final confirmed = _upcomingHike(
        id: 'cloud-upcoming-older',
        draft: baseDraft,
      );
      final pending = _upcomingHike(
        id: 'local_pending_newer',
        draft: privatePendingDraft,
      );

      await database.saveUpcomingHikesForPlanning(
        ownerPhoneNumber: phoneNumber,
        upcomingHikes: [confirmed],
      );
      await database.saveUpcomingHikesForPlanning(
        ownerPhoneNumber: phoneNumber,
        upcomingHikes: [pending],
      );

      final states = await database.loadPlannedHikeStates(
        ownerPhoneNumber: phoneNumber,
      );
      expect(states, hasLength(1));
      expect(states.single.upcomingHike.id, confirmed.id);
      expect(states.single.upcomingHike.draft?.shareLiveLocation, isTrue);
      expect(states.single.upcomingHike.draft?.fallDetectionEnabled, isTrue);
      expect(states.single.upcomingHike.draft?.emergencyContactNames, [
        'Private contact',
      ]);
    },
  );

  test(
    'notification history supports read, star, delete, and 500 cap',
    () async {
      const phone = '+60111111111';
      for (var index = 0; index < 505; index++) {
        await database.saveDeviceNotification(
          ownerPhoneNumber: phone,
          messageId: 'message-$index',
          title: 'Update $index',
          body: 'Body',
          receivedAt: DateTime.utc(2026, 8, 1).add(Duration(minutes: index)),
        );
      }

      var records = await database.loadDeviceNotifications(
        ownerPhoneNumber: phone,
      );
      expect(records, hasLength(500));
      final keep = records.last;
      await database.setDeviceNotificationStarred(
        ownerPhoneNumber: phone,
        id: keep.id,
        isStarred: true,
      );
      await database.markAllDeviceNotificationsOpened(ownerPhoneNumber: phone);

      records = await database.loadDeviceNotifications(ownerPhoneNumber: phone);
      expect(records.first.id, keep.id);
      expect(records.every((record) => record.isOpened), isTrue);
      expect(records.first.isStarred, isTrue);

      await database.deleteDeviceNotification(
        ownerPhoneNumber: phone,
        id: keep.id,
      );
      records = await database.loadDeviceNotifications(ownerPhoneNumber: phone);
      expect(records, hasLength(499));
      expect(records.any((record) => record.id == keep.id), isFalse);
    },
  );

  test('achievement cache is account scoped and survives a reopen', () async {
    const owner = '+60111111111';
    await database.saveAchievementProgressCache(
      ownerPhoneNumber: owner,
      contentHash: 'hash-v1',
      rows: const [
        {
          'achievementId': 'state_scout',
          'title': 'State Scout',
          'progressCount': 1,
          'targetCount': 3,
        },
      ],
    );
    await database.close();

    database = LocalSessionDatabase(
      databasePath: path.join(temporaryDirectory.path, 'session.db'),
    );
    final cached = await database.loadAchievementProgressCache(
      ownerPhoneNumber: owner,
    );

    expect(cached?.contentHash, 'hash-v1');
    expect(cached?.rows.single['achievementId'], 'state_scout');
    expect(
      await database.loadAchievementProgressCache(
        ownerPhoneNumber: '+60222222222',
      ),
      isNull,
    );
  });
}

UpcomingHike _upcomingHike({
  required String id,
  required HikeSessionDraft? draft,
}) {
  final sourceDraft =
      draft ??
      HikeSessionDraft.fromTrail(_activeHike().trail).copyWith(
        departureTime: DateTime.utc(2026, 8, 6, 1),
        expectedReturnTime: DateTime.utc(2026, 8, 6, 5),
      );
  return UpcomingHike(
    id: id,
    sessionId: id,
    trailId: sourceDraft.trail.trailId,
    trailName: sourceDraft.trail.name,
    latitude: sourceDraft.trail.latitude,
    longitude: sourceDraft.trail.longitude,
    area: sourceDraft.trail.area,
    state: sourceDraft.trail.state,
    distanceKm: sourceDraft.trail.distanceKm,
    durationMinutes: sourceDraft.trail.estimatedDurationMinutes,
    difficulty: sourceDraft.trail.difficulty,
    startPointName: sourceDraft.startPointName,
    destinationName: sourceDraft.destinationName,
    departureTime: sourceDraft.departureTime,
    expectedReturnTime: sourceDraft.expectedReturnTime,
    hikeType: sourceDraft.hikeType.name,
    participantCount: 1,
    creatorPhone: '+60111111111',
    creatorName: 'Test Hiker',
    createdAt: DateTime.utc(2026, 8, 4),
    participantPhones: const ['+60111111111'],
    draft: draft,
  );
}

ActiveHikeSession _activeHike() {
  final trail = Trail(
    trailId: 'local-session-trail',
    name: 'Local Session Trail',
    area: 'Test',
    state: 'Test',
    latitude: 3.1,
    longitude: 101.6,
    distanceKm: 1,
    difficulty: 'Easy',
    estimatedDurationMinutes: 30,
    elevationGainMeters: 20,
    ratingAverage: 4,
    offlineMapAvailable: false,
    offlineMapDownloaded: false,
    isVerifiedTrail: true,
    routeFilePath: '',
    coverColorValue: 0xFF34A853,
    checkpoints: const [
      TrailCheckpoint(name: 'Start', latitude: 3.1, longitude: 101.6, order: 1),
      TrailCheckpoint(name: 'End', latitude: 3.11, longitude: 101.61, order: 2),
    ],
    weather: TrailWeather(
      summary: 'Clear',
      temperatureRange: '25 C',
      rainProbability: 0,
      cachedAt: DateTime.utc(2026, 8, 4),
    ),
    hazards: const [],
  );
  return ActiveHikeSession.fromDraft(HikeSessionDraft.fromTrail(trail));
}

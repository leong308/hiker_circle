import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

import '../../home/Model/hike_session_models.dart';
import '../../sos/Model/nearby_sos_event.dart';
import '../../sos/Model/sos_models.dart';
import '../Model/app_session.dart';

class LocalSessionDatabase {
  LocalSessionDatabase({String? databasePath})
    : _databasePathOverride = databasePath;

  Database? _database;
  final String? _databasePathOverride;
  static bool _isDesktopFactoryConfigured = false;

  Future<AppSession?> loadSession() async {
    final database = await _openDatabase();
    final rows = await database.query(
      'users',
      orderBy: 'signed_in_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _sessionFromRow(rows.first);
  }

  Future<void> saveSession(AppSession session) async {
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      await transaction.delete('users');
      await transaction.insert(
        'users',
        _sessionToRow(session),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> clearSession() async {
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      await transaction.delete('users');
      await transaction.delete('active_hike_session');
      await transaction.delete('planned_hike_state');
    });
  }

  Future<void> clearUserSessionOnly() async {
    final database = await _openDatabase();
    await database.delete('users');
  }

  Future<void> saveActiveHikeSession({
    required String phoneNumber,
    required ActiveHikeSession activeHike,
  }) async {
    final database = await _openDatabase();
    await database.insert('active_hike_session', {
      'owner_phone_number': phoneNumber,
      'session_id': activeHike.sessionId,
      'payload_json': jsonEncode(activeHike.toPersistence()),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Rebinds a locally generated hike ID to the canonical ID returned by the
  /// cloud recovery/completion callable. Pending hike-end records deliberately
  /// keep their original idempotency key so an interrupted retry can be replayed
  /// with the same request.
  Future<ActiveHikeSession> migrateActiveHikeSessionId({
    required String ownerPhoneNumber,
    required ActiveHikeSession activeHike,
    required String newSessionId,
  }) async {
    final owner = ownerPhoneNumber.trim();
    final oldSessionId = activeHike.sessionId.trim();
    final canonicalSessionId = newSessionId.trim();
    if (owner.isEmpty) {
      throw ArgumentError.value(
        ownerPhoneNumber,
        'ownerPhoneNumber',
        'must not be empty',
      );
    }
    if (oldSessionId.isEmpty || canonicalSessionId.isEmpty) {
      throw ArgumentError('Hike session IDs must not be empty.');
    }
    final migratedHike = activeHike.copyWith(sessionId: canonicalSessionId);
    if (oldSessionId == canonicalSessionId) {
      await saveActiveHikeSession(phoneNumber: owner, activeHike: migratedHike);
      return migratedHike;
    }

    final database = await _openDatabase();
    await database.transaction((transaction) async {
      final activeRows = await transaction.query(
        'active_hike_session',
        columns: ['session_id', 'payload_json'],
        where: 'owner_phone_number = ?',
        whereArgs: [owner],
        limit: 1,
      );
      if (activeRows.isNotEmpty &&
          activeRows.first['session_id'] == oldSessionId) {
        var snapshotToSave = migratedHike;
        try {
          final decoded = jsonDecode(
            activeRows.first['payload_json'] as String,
          );
          if (decoded is Map) {
            final persisted = ActiveHikeSession.fromPersistence(
              Map<String, dynamic>.from(decoded),
            );
            if (persisted.sessionId == oldSessionId) {
              snapshotToSave = persisted.copyWith(
                sessionId: canonicalSessionId,
              );
            }
          }
        } catch (_) {
          // The supplied in-memory snapshot is the safe fallback when an older
          // local payload is malformed.
        }
        await transaction.update(
          'active_hike_session',
          {
            'session_id': canonicalSessionId,
            'payload_json': jsonEncode(snapshotToSave.toPersistence()),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'owner_phone_number = ? AND session_id = ?',
          whereArgs: [owner, oldSessionId],
        );
      }
      await _migrateHikeTelemetrySessionId(
        transaction,
        ownerPhoneNumber: owner,
        oldSessionId: oldSessionId,
        newSessionId: canonicalSessionId,
      );
    });
    return migratedHike;
  }

  Future<void> migrateHikeTelemetrySessionId({
    required String ownerPhoneNumber,
    required String oldSessionId,
    required String newSessionId,
  }) async {
    final owner = ownerPhoneNumber.trim();
    final oldId = oldSessionId.trim();
    final newId = newSessionId.trim();
    if (owner.isEmpty || oldId.isEmpty || newId.isEmpty || oldId == newId) {
      return;
    }
    final database = await _openDatabase();
    await database.transaction((transaction) {
      return _migrateHikeTelemetrySessionId(
        transaction,
        ownerPhoneNumber: owner,
        oldSessionId: oldId,
        newSessionId: newId,
      );
    });
  }

  Future<void> _migrateHikeTelemetrySessionId(
    DatabaseExecutor database, {
    required String ownerPhoneNumber,
    required String oldSessionId,
    required String newSessionId,
  }) async {
    await database.update(
      'local_location_points',
      {'session_id': newSessionId},
      where:
          'session_id = ? AND (owner_phone_number = ? OR owner_phone_number = ?)',
      whereArgs: [oldSessionId, ownerPhoneNumber, ''],
    );
    await database.update(
      'network_observations',
      {'session_id': newSessionId},
      where: 'session_id = ?',
      whereArgs: [oldSessionId],
    );
    await database.update(
      'queued_alerts',
      {'session_id': newSessionId},
      where:
          'session_id = ? AND (owner_phone_number = ? OR owner_phone_number = ?)',
      whereArgs: [oldSessionId, ownerPhoneNumber, ''],
    );
  }

  Future<ActiveHikeSession?> loadActiveHikeSession({
    required String phoneNumber,
  }) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'active_hike_session',
      where: 'owner_phone_number = ?',
      whereArgs: [phoneNumber],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    try {
      final payload = jsonDecode(rows.first['payload_json'] as String);
      if (payload is! Map) {
        throw const FormatException('Active hike payload is not an object.');
      }
      final activeHike = ActiveHikeSession.fromPersistence(
        Map<String, dynamic>.from(payload),
      );
      if (activeHike.sessionId.isEmpty) {
        throw const FormatException('Active hike session ID is missing.');
      }
      final queuedUpdates = Sqflite.firstIntValue(
        await database.rawQuery(
          '''
          SELECT COUNT(*)
          FROM local_location_points
          WHERE session_id = ?
            AND is_synced = 0
            AND latitude BETWEEN -90 AND 90
            AND longitude BETWEEN -180 AND 180
          ''',
          [activeHike.sessionId],
        ),
      );
      return activeHike.copyWith(queuedUpdates: queuedUpdates ?? 0);
    } catch (error) {
      debugPrint('Unable to restore active hike snapshot: $error');
      await clearActiveHikeSession(phoneNumber: phoneNumber);
      return null;
    }
  }

  Future<void> clearActiveHikeSession({required String phoneNumber}) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'active_hike_session',
      columns: ['session_id'],
      where: 'owner_phone_number = ?',
      whereArgs: [phoneNumber],
    );
    final sessionIds = rows
        .map((row) => row['session_id'])
        .whereType<String>()
        .where((sessionId) => sessionId.isNotEmpty)
        .toSet();
    await database.transaction((transaction) async {
      await transaction.delete(
        'active_hike_session',
        where: 'owner_phone_number = ?',
        whereArgs: [phoneNumber],
      );
      for (final sessionId in sessionIds) {
        await _deleteCompletedHikeTelemetry(
          transaction,
          sessionId: sessionId,
          preserveUnsent: true,
        );
      }
    });
  }

  Future<void> saveUpcomingHikesForPlanning({
    required String ownerPhoneNumber,
    required Iterable<UpcomingHike> upcomingHikes,
    bool pruneMissing = false,
  }) async {
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty) {
      throw ArgumentError.value(
        ownerPhoneNumber,
        'ownerPhoneNumber',
        'must not be empty',
      );
    }
    final hikes = <String, UpcomingHike>{
      for (final hike in upcomingHikes)
        if (hike.id.trim().isNotEmpty) hike.id.trim(): hike,
    };
    final database = await _openDatabase();
    final now = DateTime.now().toUtc().toIso8601String();
    await database.transaction((transaction) async {
      for (final entry in hikes.entries) {
        final hike = entry.value;
        final payload = hike.toPersistence();
        if (hike.draft == null) {
          final existing = await transaction.query(
            'planned_hike_state',
            columns: ['upcoming_payload_json'],
            where: 'owner_phone_number = ? AND upcoming_hike_id = ?',
            whereArgs: [owner, entry.key],
            limit: 1,
          );
          if (existing.isNotEmpty) {
            final saved = _decodeJsonMap(
              existing.first['upcoming_payload_json'] as String?,
            );
            final savedDraft = saved['draft'];
            if (savedDraft is Map) {
              payload['draft'] = Map<String, dynamic>.from(savedDraft);
            }
          }
        }
        final initialChecklist = GearChecklistCatalog.sanitize(
          hike.draft?.completedChecklistItems ?? const <String>{},
        ).toList()..sort();
        await transaction.insert('planned_hike_state', {
          'owner_phone_number': owner,
          'upcoming_hike_id': entry.key,
          'upcoming_payload_json': jsonEncode(payload),
          'completed_checklist_json': jsonEncode(initialChecklist),
          'is_consumed': 0,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await transaction.update(
          'planned_hike_state',
          {'upcoming_payload_json': jsonEncode(payload), 'updated_at': now},
          where: 'owner_phone_number = ? AND upcoming_hike_id = ?',
          whereArgs: [owner, entry.key],
        );
      }
      final confirmedBySchedule = <String, UpcomingHike>{
        for (final hike in hikes.values)
          if (!hike.isLocalPendingSync) _plannedHikeScheduleKey(hike): hike,
      };
      final savedConfirmedRows = await transaction.query(
        'planned_hike_state',
        where: 'owner_phone_number = ? AND upcoming_hike_id NOT LIKE ?',
        whereArgs: [owner, 'local_pending_%'],
      );
      for (final row in savedConfirmedRows) {
        try {
          final state = LocalPlannedHikeState.fromRow(row);
          confirmedBySchedule[_plannedHikeScheduleKey(state.upcomingHike)] =
              state.upcomingHike;
        } catch (_) {
          continue;
        }
      }
      if (confirmedBySchedule.isNotEmpty) {
        final pendingRows = await transaction.query(
          'planned_hike_state',
          where: 'owner_phone_number = ? AND upcoming_hike_id LIKE ?',
          whereArgs: [owner, 'local_pending_%'],
        );
        for (final pendingRow in pendingRows) {
          LocalPlannedHikeState pendingState;
          try {
            pendingState = LocalPlannedHikeState.fromRow(pendingRow);
          } catch (_) {
            continue;
          }
          final confirmed =
              confirmedBySchedule[_plannedHikeScheduleKey(
                pendingState.upcomingHike,
              )];
          if (confirmed == null) continue;
          final targetRows = await transaction.query(
            'planned_hike_state',
            where: 'owner_phone_number = ? AND upcoming_hike_id = ?',
            whereArgs: [owner, confirmed.id],
            limit: 1,
          );
          if (targetRows.isNotEmpty) {
            final confirmedPayload = _decodeJsonMap(
              targetRows.first['upcoming_payload_json'] as String?,
            );
            final pendingPayload = _decodeJsonMap(
              pendingRow['upcoming_payload_json'] as String?,
            );
            if (pendingPayload['draft'] is Map) {
              confirmedPayload['draft'] = Map<String, dynamic>.from(
                pendingPayload['draft'] as Map,
              );
            }
            final existingChecklist = _decodeJsonStringList(
              targetRows.first['completed_checklist_json'] as String?,
            );
            final transferredChecklist = existingChecklist.isEmpty
                ? pendingState.completedChecklistItems.toList()
                : existingChecklist;
            transferredChecklist.sort();
            await transaction.update(
              'planned_hike_state',
              {
                'upcoming_payload_json': jsonEncode(confirmedPayload),
                'completed_checklist_json': jsonEncode(transferredChecklist),
                'updated_at': now,
              },
              where: 'owner_phone_number = ? AND upcoming_hike_id = ?',
              whereArgs: [owner, confirmed.id],
            );
          }
          await transaction.delete(
            'planned_hike_state',
            where: 'owner_phone_number = ? AND upcoming_hike_id = ?',
            whereArgs: [owner, pendingState.upcomingHike.id],
          );
        }
      }
      if (!pruneMissing) return;
      if (hikes.isEmpty) {
        await transaction.delete(
          'planned_hike_state',
          where: 'owner_phone_number = ?',
          whereArgs: [owner],
        );
        return;
      }
      final placeholders = List.filled(hikes.length, '?').join(', ');
      await transaction.delete(
        'planned_hike_state',
        where:
            'owner_phone_number = ? AND upcoming_hike_id NOT IN ($placeholders)',
        whereArgs: [owner, ...hikes.keys],
      );
    });
  }

  Future<List<LocalPlannedHikeState>> loadPlannedHikeStates({
    required String ownerPhoneNumber,
  }) async {
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty) return const [];
    final database = await _openDatabase();
    final rows = await database.query(
      'planned_hike_state',
      where: 'owner_phone_number = ?',
      whereArgs: [owner],
      orderBy: 'updated_at DESC',
      limit: 100,
    );
    final states = <LocalPlannedHikeState>[];
    for (final row in rows) {
      try {
        states.add(LocalPlannedHikeState.fromRow(row));
      } catch (error) {
        debugPrint('Ignoring an invalid planned hike snapshot: $error');
      }
    }
    return states;
  }

  Future<void> savePlannedHikeChecklist({
    required String ownerPhoneNumber,
    required String upcomingHikeId,
    required Iterable<String> completedItems,
  }) async {
    final owner = ownerPhoneNumber.trim();
    final hikeId = upcomingHikeId.trim();
    if (owner.isEmpty || hikeId.isEmpty) return;
    final items = GearChecklistCatalog.sanitize(completedItems).toList()
      ..sort();
    final database = await _openDatabase();
    await database.update(
      'planned_hike_state',
      {
        'completed_checklist_json': jsonEncode(items),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'owner_phone_number = ? AND upcoming_hike_id = ?',
      whereArgs: [owner, hikeId],
    );
  }

  Future<void> markPlannedHikeConsumed({
    required String ownerPhoneNumber,
    required String upcomingHikeId,
  }) async {
    final owner = ownerPhoneNumber.trim();
    final hikeId = upcomingHikeId.trim();
    if (owner.isEmpty || hikeId.isEmpty) return;
    final database = await _openDatabase();
    await database.update(
      'planned_hike_state',
      {
        'is_consumed': 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'owner_phone_number = ? AND upcoming_hike_id = ?',
      whereArgs: [owner, hikeId],
    );
  }

  Future<void> queuePendingHikeEnd({
    required String ownerPhoneNumber,
    required ActiveHikeSession activeHike,
    HikeSummaryReport? summary,
    DateTime? endedAt,
  }) async {
    final owner = ownerPhoneNumber.trim();
    final sessionId = activeHike.sessionId.trim();
    if (owner.isEmpty) {
      throw ArgumentError.value(
        ownerPhoneNumber,
        'ownerPhoneNumber',
        'must not be empty',
      );
    }
    if (sessionId.isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId', 'must not be empty');
    }
    final database = await _openDatabase();
    final now = DateTime.now().toUtc().toIso8601String();
    await database.insert('pending_hike_ends', {
      'owner_phone_number': owner,
      'session_id': sessionId,
      'active_hike_payload_json': jsonEncode(activeHike.toPersistence()),
      if (summary != null)
        'summary_payload_json': jsonEncode(summary.toFirestore()),
      if (endedAt != null) 'ended_at': endedAt.toUtc().toIso8601String(),
      'created_at': now,
      'updated_at': now,
      'retry_count': 0,
      'last_error': '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<LocalPendingHikeEnd>> loadPendingHikeEnds({
    required String ownerPhoneNumber,
    int limit = 20,
  }) async {
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty || limit <= 0) return const [];
    final database = await _openDatabase();
    final rows = await database.query(
      'pending_hike_ends',
      where: 'owner_phone_number = ?',
      whereArgs: [owner],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(LocalPendingHikeEnd.fromRow).toList();
  }

  Future<void> deletePendingHikeEnd({
    required String ownerPhoneNumber,
    required String sessionId,
  }) async {
    final database = await _openDatabase();
    await database.delete(
      'pending_hike_ends',
      where: 'owner_phone_number = ? AND session_id = ?',
      whereArgs: [ownerPhoneNumber.trim(), sessionId.trim()],
    );
  }

  Future<void> markPendingHikeEndRetry({
    required String ownerPhoneNumber,
    required String sessionId,
    String lastError = '',
  }) async {
    final database = await _openDatabase();
    await database.rawUpdate(
      '''
      UPDATE pending_hike_ends
      SET retry_count = retry_count + 1,
          last_error = ?,
          updated_at = ?
      WHERE owner_phone_number = ? AND session_id = ?
      ''',
      [
        lastError,
        DateTime.now().toUtc().toIso8601String(),
        ownerPhoneNumber.trim(),
        sessionId.trim(),
      ],
    );
  }

  Future<String> loadOrCreateAppInstanceId() async {
    final database = await _openDatabase();
    final rows = await database.query('app_device', limit: 1);
    if (rows.isNotEmpty) {
      final existingId = rows.first['app_instance_id'] as String?;
      if (existingId != null && existingId.isNotEmpty) {
        return existingId;
      }
    }

    final appInstanceId = _newAppInstanceId();
    await database.insert('app_device', {
      'id': 1,
      'app_instance_id': appInstanceId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return appInstanceId;
  }

  Future<List<EmergencyContact>> loadEmergencyContacts({
    required String phoneNumber,
  }) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'emergency_contacts',
      where: 'owner_phone_number = ?',
      whereArgs: [phoneNumber],
      orderBy: 'position ASC, name ASC',
    );
    return rows.map(_emergencyContactFromRow).toList();
  }

  Future<void> saveEmergencyContacts({
    required String phoneNumber,
    required List<EmergencyContact> contacts,
  }) async {
    final database = await _openDatabase();
    final now = DateTime.now().toUtc().toIso8601String();
    await database.transaction((transaction) async {
      await transaction.delete(
        'emergency_contacts',
        where: 'owner_phone_number = ?',
        whereArgs: [phoneNumber],
      );
      for (var index = 0; index < contacts.length; index++) {
        final contact = contacts[index];
        await transaction.insert('emergency_contacts', {
          'owner_phone_number': phoneNumber,
          'contact_phone_number': contact.phoneNumber,
          'name': contact.name,
          'relationship': contact.relationship,
          'position': index,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<CacheUsageSummary> loadCacheUsageSummary() async {
    final database = await _openDatabase();
    final downloadedMapCount =
        Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM downloaded_maps'),
        ) ??
        0;
    final downloadedMapBytes =
        Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COALESCE(SUM(file_size), 0) FROM downloaded_maps',
          ),
        ) ??
        0;
    final networkObservationCount =
        Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM network_observations'),
        ) ??
        0;

    return CacheUsageSummary(
      downloadedMapCount: downloadedMapCount,
      downloadedMapBytes: downloadedMapBytes,
      networkObservationCount: networkObservationCount,
    );
  }

  Future<void> clearCacheData() async {
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      await transaction.delete('downloaded_maps');
      await transaction.delete('network_observations');
    });
  }

  Future<void> saveDeviceNotification({
    required String ownerPhoneNumber,
    String messageId = '',
    required String title,
    required String body,
    String type = '',
    String deepLink = '',
    Map<String, dynamic> data = const {},
    DateTime? receivedAt,
    DateTime? openedAt,
    String source = 'fcm',
  }) async {
    final database = await _openDatabase();
    final now = DateTime.now().toUtc();
    final effectiveMessageId = messageId.trim();
    final received = (receivedAt ?? now).toUtc().toIso8601String();
    final existingRows = effectiveMessageId.isEmpty
        ? const <Map<String, Object?>>[]
        : await database.query(
            'device_notifications',
            columns: ['id'],
            where: 'owner_phone_number = ? AND message_id = ?',
            whereArgs: [ownerPhoneNumber, effectiveMessageId],
            limit: 1,
          );
    final row = {
      'owner_phone_number': ownerPhoneNumber,
      'message_id': effectiveMessageId,
      'title': title.trim(),
      'body': body.trim(),
      'type': type.trim(),
      'deep_link': deepLink.trim(),
      'data_json': jsonEncode(data),
      'received_at': received,
      if (openedAt != null) 'opened_at': openedAt.toUtc().toIso8601String(),
      'source': source.trim().isEmpty ? 'fcm' : source.trim(),
    };

    if (existingRows.isEmpty) {
      await database.insert('device_notifications', row);
    } else {
      await database.update(
        'device_notifications',
        row,
        where: 'id = ?',
        whereArgs: [existingRows.first['id']],
      );
    }

    await database.delete(
      'device_notifications',
      where: '''
        owner_phone_number = ? AND id NOT IN (
          SELECT id FROM device_notifications
          WHERE owner_phone_number = ?
          ORDER BY received_at DESC
          LIMIT 200
        )
      ''',
      whereArgs: [ownerPhoneNumber, ownerPhoneNumber],
    );
  }

  Future<List<DeviceNotificationRecord>> loadDeviceNotifications({
    required String ownerPhoneNumber,
    int limit = 100,
  }) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'device_notifications',
      where: 'owner_phone_number = ?',
      whereArgs: [ownerPhoneNumber],
      orderBy: 'received_at DESC',
      limit: limit,
    );
    return rows.map(DeviceNotificationRecord.fromRow).toList();
  }

  Future<void> markDeviceNotificationOpened({
    required String ownerPhoneNumber,
    required int id,
  }) async {
    final database = await _openDatabase();
    await database.update(
      'device_notifications',
      {'opened_at': DateTime.now().toUtc().toIso8601String()},
      where: 'owner_phone_number = ? AND id = ?',
      whereArgs: [ownerPhoneNumber, id],
    );
  }

  Future<void> clearDeviceNotifications({
    required String ownerPhoneNumber,
  }) async {
    final database = await _openDatabase();
    await database.delete(
      'device_notifications',
      where: 'owner_phone_number = ?',
      whereArgs: [ownerPhoneNumber],
    );
  }

  Future<void> saveNearbySosEvent(NearbySosEvent event) async {
    final owner = event.ownerPhoneNumber.trim();
    final eventKey = event.eventKey.trim();
    if (owner.isEmpty || eventKey.isEmpty) return;
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      final existingRows = await transaction.query(
        'nearby_sos_events',
        where: 'owner_phone_number = ? AND event_key = ?',
        whereArgs: [owner, eventKey],
        limit: 1,
      );
      final existing = existingRows.isEmpty ? null : existingRows.first;
      final existingReceivedAt = DateTime.tryParse(
        existing?['received_at'] as String? ?? '',
      );
      final receivedAt =
          existingReceivedAt != null &&
              existingReceivedAt.isBefore(event.receivedAt)
          ? existingReceivedAt
          : event.receivedAt;
      final location = event.hasReportedLocation ? event.location : null;
      final detectorLocation = event.detectorLocation?.hasValidPosition == true
          ? event.detectorLocation
          : null;
      final row = <String, Object?>{
        'owner_phone_number': owner,
        'event_key': eventKey,
        'device_id': event.deviceId.trim(),
        'counter': event.counter ?? existing?['counter'],
        'rssi': event.rssi ?? existing?['rssi'],
        'received_at': receivedAt.toUtc().toIso8601String(),
        'updated_at': event.updatedAt.toUtc().toIso8601String(),
        'latitude': location?.latitude ?? existing?['latitude'],
        'longitude': location?.longitude ?? existing?['longitude'],
        'accuracy_meters':
            location?.accuracyMeters ?? existing?['accuracy_meters'],
        'location_captured_at':
            location?.capturedAt?.toUtc().toIso8601String() ??
            existing?['location_captured_at'],
        'detector_latitude':
            existing?['detector_latitude'] ?? detectorLocation?.latitude,
        'detector_longitude':
            existing?['detector_longitude'] ?? detectorLocation?.longitude,
        'detector_accuracy_meters':
            existing?['detector_accuracy_meters'] ??
            detectorLocation?.accuracyMeters,
        'detector_captured_at':
            existing?['detector_captured_at'] ??
            detectorLocation?.capturedAt?.toUtc().toIso8601String(),
      };
      if (existing == null) {
        await transaction.insert('nearby_sos_events', row);
      } else {
        await transaction.update(
          'nearby_sos_events',
          row,
          where: 'owner_phone_number = ? AND event_key = ?',
          whereArgs: [owner, eventKey],
        );
      }

      await transaction.delete(
        'nearby_sos_events',
        where: '''
          owner_phone_number = ? AND event_key NOT IN (
            SELECT event_key FROM nearby_sos_events
            WHERE owner_phone_number = ?
            ORDER BY received_at DESC
            LIMIT 200
          )
        ''',
        whereArgs: [owner, owner],
      );
    });
  }

  Future<List<NearbySosEvent>> loadNearbySosEvents({
    required String ownerPhoneNumber,
    int limit = 200,
  }) async {
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty || limit <= 0) return const [];
    final database = await _openDatabase();
    final rows = await database.query(
      'nearby_sos_events',
      where: 'owner_phone_number = ?',
      whereArgs: [owner],
      orderBy: 'received_at DESC',
      limit: limit,
    );
    final events = <NearbySosEvent>[];
    for (final row in rows) {
      try {
        final latitude = row['latitude'];
        final longitude = row['longitude'];
        final hasLocation =
            latitude is num &&
            longitude is num &&
            latitude.isFinite &&
            longitude.isFinite;
        final detectorLatitude = row['detector_latitude'];
        final detectorLongitude = row['detector_longitude'];
        final hasDetectorLocation =
            detectorLatitude is num &&
            detectorLongitude is num &&
            detectorLatitude.isFinite &&
            detectorLongitude.isFinite;
        events.add(
          NearbySosEvent(
            ownerPhoneNumber: owner,
            eventKey: row['event_key'] as String? ?? '',
            deviceId: row['device_id'] as String? ?? '',
            counter: row['counter'] is num
                ? (row['counter'] as num).toInt()
                : null,
            rssi: row['rssi'] is num ? (row['rssi'] as num).toInt() : null,
            receivedAt: DateTime.parse(row['received_at'] as String).toUtc(),
            updatedAt:
                DateTime.tryParse(
                  row['updated_at'] as String? ?? '',
                )?.toUtc() ??
                DateTime.parse(row['received_at'] as String).toUtc(),
            location: hasLocation
                ? SosTriggerLocation(
                    latitude: latitude.toDouble(),
                    longitude: longitude.toDouble(),
                    accuracyMeters: row['accuracy_meters'] is num
                        ? (row['accuracy_meters'] as num).toDouble()
                        : null,
                    capturedAt: DateTime.tryParse(
                      row['location_captured_at'] as String? ?? '',
                    )?.toUtc(),
                  )
                : null,
            detectorLocation: hasDetectorLocation
                ? SosTriggerLocation(
                    latitude: detectorLatitude.toDouble(),
                    longitude: detectorLongitude.toDouble(),
                    accuracyMeters: row['detector_accuracy_meters'] is num
                        ? (row['detector_accuracy_meters'] as num).toDouble()
                        : null,
                    capturedAt: DateTime.tryParse(
                      row['detector_captured_at'] as String? ?? '',
                    )?.toUtc(),
                  )
                : null,
          ),
        );
      } catch (error) {
        debugPrint('Ignoring an invalid nearby SOS event: $error');
      }
    }
    return events;
  }

  Future<Database> _openDatabase() async {
    final existingDatabase = _database;
    if (existingDatabase != null) {
      return existingDatabase;
    }

    _configureDatabaseFactory();
    final databaseDirectory = await getDatabasesPath();
    final databasePath =
        _databasePathOverride ??
        path.join(databaseDirectory, 'hiker_circle.db');
    debugPrint('HikerCircle SQLite database path: $databasePath');

    _database = await openDatabase(
      databasePath,
      version: 22,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE users (
            phone_number TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            signed_in_at TEXT NOT NULL,
            app_instance_id TEXT NOT NULL DEFAULT '',
            is_admin INTEGER NOT NULL DEFAULT 0,
            username TEXT NOT NULL DEFAULT '',
            requires_onboarding INTEGER NOT NULL DEFAULT 0,
            onboarding_profile_complete INTEGER NOT NULL DEFAULT 0,
            photo_url TEXT,
            photo_bytes BLOB
          )
        ''');
        await _createSafetyTables(database);
        await _createDeviceBindingTables(database);
        await _createEmergencyContactsTable(database);
        await _createRouteCacheTable(database);
        await _createPendingMessagesTable(database);
        await _createActiveHikeSessionTable(database);
        await _createChatReadReceiptsTable(database);
        await _createDeviceNotificationsTable(database);
        await _createNearbySosEventsTable(database);
        await _createPendingHikeEndsTable(database);
        await _createPlannedHikeStateTable(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await _createSafetyTables(database);
        }
        if (oldVersion < 4) {
          await _addColumnIfMissing(
            database,
            tableName: 'users',
            columnName: 'app_instance_id',
            definition: "TEXT NOT NULL DEFAULT ''",
          );
          await _addColumnIfMissing(
            database,
            tableName: 'users',
            columnName: 'is_admin',
            definition: 'INTEGER NOT NULL DEFAULT 0',
          );
          await _createDeviceBindingTables(database);
          await _createEmergencyContactsTable(database);
        }
        if (oldVersion < 5) {
          await _addColumnIfMissing(
            database,
            tableName: 'users',
            columnName: 'username',
            definition: "TEXT NOT NULL DEFAULT ''",
          );
          await _addColumnIfMissing(
            database,
            tableName: 'users',
            columnName: 'requires_onboarding',
            definition: 'INTEGER NOT NULL DEFAULT 0',
          );
          await _addColumnIfMissing(
            database,
            tableName: 'users',
            columnName: 'onboarding_profile_complete',
            definition: 'INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 6) {
          await _createRouteCacheTable(database);
        }
        if (oldVersion < 7) {
          await _createPendingMessagesTable(database);
        }
        if (oldVersion < 8) {
          await _addColumnIfMissing(
            database,
            tableName: 'pending_messages',
            columnName: 'firestore_doc_id',
            definition: "TEXT DEFAULT ''",
          );
        }
        if (oldVersion < 9) {
          await _createActiveHikeSessionTable(database);
        }
        if (oldVersion < 10) {
          await _addColumnIfMissing(
            database,
            tableName: 'pending_messages',
            columnName: 'attachment_json',
            definition: "TEXT DEFAULT ''",
          );
        }
        if (oldVersion < 11) {
          await _createChatReadReceiptsTable(database);
        }
        if (oldVersion < 12) {
          await _addColumnIfMissing(
            database,
            tableName: 'users',
            columnName: 'photo_url',
            definition: 'TEXT',
          );
        }
        if (oldVersion < 13) {
          await _addColumnIfMissing(
            database,
            tableName: 'pending_messages',
            columnName: 'attachment_json',
            definition: "TEXT DEFAULT ''",
          );
        }
        if (oldVersion < 14) {
          await _addColumnIfMissing(
            database,
            tableName: 'users',
            columnName: 'photo_bytes',
            definition: 'BLOB',
          );
        }
        if (oldVersion < 15) {
          await _createDeviceNotificationsTable(database);
        }
        if (oldVersion < 16) {
          await _addColumnIfMissing(
            database,
            tableName: 'queued_alerts',
            columnName: 'owner_phone_number',
            definition: "TEXT NOT NULL DEFAULT ''",
          );
          await _addColumnIfMissing(
            database,
            tableName: 'queued_alerts',
            columnName: 'last_error',
            definition: "TEXT NOT NULL DEFAULT ''",
          );
          await _addColumnIfMissing(
            database,
            tableName: 'queued_alerts',
            columnName: 'sent_at',
            definition: 'TEXT',
          );
        }
        if (oldVersion < 17) {
          await _addColumnIfMissing(
            database,
            tableName: 'local_location_points',
            columnName: 'owner_phone_number',
            definition: "TEXT NOT NULL DEFAULT ''",
          );
          await _createSafetyIndexes(database);
        }
        if (oldVersion < 18) {
          await _createPendingHikeEndsTable(database);
        }
        if (oldVersion < 19) {
          await _createPlannedHikeStateTable(database);
        }
        if (oldVersion < 20) {
          await database.update(
            'queued_alerts',
            {
              'send_status': 'quarantined',
              'last_error':
                  'Legacy SOS queue has no account owner and cannot be sent safely.',
            },
            where: "TRIM(owner_phone_number) = '' AND send_status IN (?, ?)",
            whereArgs: ['queued', 'retry'],
          );
        }
        if (oldVersion < 21) {
          await _createNearbySosEventsTable(database);
        }
        if (oldVersion < 22) {
          await _addColumnIfMissing(
            database,
            tableName: 'nearby_sos_events',
            columnName: 'detector_latitude',
            definition: 'REAL',
          );
          await _addColumnIfMissing(
            database,
            tableName: 'nearby_sos_events',
            columnName: 'detector_longitude',
            definition: 'REAL',
          );
          await _addColumnIfMissing(
            database,
            tableName: 'nearby_sos_events',
            columnName: 'detector_accuracy_meters',
            definition: 'REAL',
          );
          await _addColumnIfMissing(
            database,
            tableName: 'nearby_sos_events',
            columnName: 'detector_captured_at',
            definition: 'TEXT',
          );
        }
      },
    );

    return _database!;
  }

  @visibleForTesting
  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }

  Future<int> insertLocationPoint({
    String ownerPhoneNumber = '',
    required String sessionId,
    required double latitude,
    required double longitude,
    double? altitude,
    double? accuracy,
    int? batteryLevel,
    required String pointType,
    bool isSynced = false,
    DateTime? recordedAt,
  }) async {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId', 'must not be empty');
    }
    if (!_isValidCoordinate(latitude, longitude)) {
      throw ArgumentError('Location coordinates are outside valid GPS bounds.');
    }
    final database = await _openDatabase();
    return database.insert('local_location_points', {
      'owner_phone_number': ownerPhoneNumber.trim(),
      'session_id': normalizedSessionId,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude?.isFinite == true ? altitude : null,
      'accuracy': accuracy?.isFinite == true && accuracy! >= 0
          ? accuracy
          : null,
      'battery_level': batteryLevel?.clamp(0, 100),
      'point_type': pointType.trim().isEmpty ? 'automatic' : pointType.trim(),
      'recorded_at': (recordedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
    });
  }

  Future<int> insertQueuedAlert({
    required String ownerPhoneNumber,
    required String sessionId,
    required String alertType,
    required double triggerLatitude,
    required double triggerLongitude,
    required String payloadJson,
  }) async {
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty) {
      throw ArgumentError.value(
        ownerPhoneNumber,
        'ownerPhoneNumber',
        'must not be empty',
      );
    }
    final database = await _openDatabase();
    final now = DateTime.now().toUtc().toIso8601String();
    return database.insert('queued_alerts', {
      'owner_phone_number': owner,
      'session_id': sessionId,
      'alert_type': alertType,
      'trigger_latitude': triggerLatitude,
      'trigger_longitude': triggerLongitude,
      'trigger_time': now,
      'payload_json': payloadJson,
      'send_status': 'queued',
      'retry_count': 0,
      'created_at': now,
      'last_error': '',
    });
  }

  Future<List<LocalQueuedAlert>> loadQueuedAlerts({
    required String ownerPhoneNumber,
    int limit = 20,
  }) async {
    final database = await _openDatabase();
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty) {
      return const [];
    }
    final rows = await database.query(
      'queued_alerts',
      where: 'owner_phone_number = ? AND send_status IN (?, ?)',
      whereArgs: [owner, 'queued', 'retry'],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(LocalQueuedAlert.fromRow).toList();
  }

  Future<int> countQueuedAlerts({required String ownerPhoneNumber}) async {
    final database = await _openDatabase();
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty) {
      return 0;
    }
    final result = await database.rawQuery(
      '''
        SELECT COUNT(*) AS total
        FROM queued_alerts
        WHERE owner_phone_number = ?
          AND send_status IN (?, ?)
      ''',
      [owner, 'queued', 'retry'],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> markQueuedAlertSent(int id) async {
    final database = await _openDatabase();
    await database.update(
      'queued_alerts',
      {
        'send_status': 'sent',
        'sent_at': DateTime.now().toUtc().toIso8601String(),
        'last_error': '',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateQueuedAlertPayload({
    required int id,
    required String payloadJson,
    String sendStatus = 'queued',
    String lastError = '',
  }) async {
    final database = await _openDatabase();
    await database.update(
      'queued_alerts',
      {
        'send_status': sendStatus,
        'payload_json': payloadJson,
        'last_error': lastError,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateQueuedAlertRetry({
    required int id,
    required String payloadJson,
    String lastError = '',
  }) async {
    final database = await _openDatabase();
    await database.rawUpdate(
      '''
      UPDATE queued_alerts
      SET send_status = ?,
          payload_json = ?,
          retry_count = retry_count + 1,
          last_error = ?
      WHERE id = ?
      ''',
      ['retry', payloadJson, lastError, id],
    );
  }

  Future<int> insertDownloadedMap({
    required String trailId,
    required String trailName,
    required String localFilePath,
    int? fileSize,
  }) async {
    final database = await _openDatabase();
    return database.insert('downloaded_maps', {
      'trail_id': trailId,
      'trail_name': trailName,
      'local_file_path': localFilePath,
      'file_size': fileSize,
      'downloaded_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> insertNetworkObservation({
    required String sessionId,
    required double latitude,
    required double longitude,
    double? accuracy,
    required bool networkAvailable,
    required bool apiRequestSuccess,
    String? networkType,
    bool isSynced = false,
  }) async {
    final database = await _openDatabase();
    return database.insert('network_observations', {
      'session_id': sessionId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'network_available': networkAvailable ? 1 : 0,
      'api_request_success': apiRequestSuccess ? 1 : 0,
      'network_type': networkType,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
    });
  }

  Future<int> countUnsentLocationPoints(String sessionId) async {
    final database = await _openDatabase();
    final result = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM local_location_points
      WHERE session_id = ?
        AND is_synced = 0
        AND latitude BETWEEN -90 AND 90
        AND longitude BETWEEN -180 AND 180
      ''',
      [sessionId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<LocalLocationPoint>> loadUnsentLocationPoints({
    required String sessionId,
    int limit = 200,
  }) async {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty || limit <= 0) {
      return const [];
    }
    final database = await _openDatabase();
    final rows = await database.query(
      'local_location_points',
      where: '''
        session_id = ?
        AND is_synced = 0
        AND latitude BETWEEN -90 AND 90
        AND longitude BETWEEN -180 AND 180
      ''',
      whereArgs: [normalizedSessionId],
      orderBy: 'recorded_at ASC, id ASC',
      limit: limit,
    );
    return rows
        .map(LocalLocationPoint.fromRow)
        .where((point) => point.hasValidCoordinate)
        .toList();
  }

  Future<void> markLocationPointsSynced(Iterable<int> pointIds) async {
    final ids = pointIds.where((id) => id > 0).toSet();
    if (ids.isEmpty) {
      return;
    }
    final database = await _openDatabase();
    final batch = database.batch();
    for (final id in ids) {
      batch.update(
        'local_location_points',
        {'is_synced': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> deleteSyncedLocationPoints({
    String? sessionId,
    DateTime? recordedBefore,
  }) async {
    final clauses = <String>['is_synced = 1'];
    final arguments = <Object?>[];
    final normalizedSessionId = sessionId?.trim() ?? '';
    if (normalizedSessionId.isNotEmpty) {
      clauses.add('session_id = ?');
      arguments.add(normalizedSessionId);
    }
    if (recordedBefore != null) {
      clauses.add('recorded_at < ?');
      arguments.add(recordedBefore.toUtc().toIso8601String());
    }
    final database = await _openDatabase();
    return database.delete(
      'local_location_points',
      where: clauses.join(' AND '),
      whereArgs: arguments,
    );
  }

  Future<void> clearCompletedHikeTelemetry({
    required String sessionId,
    bool preserveUnsent = true,
  }) async {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      return;
    }
    final database = await _openDatabase();
    await database.transaction((transaction) {
      return _deleteCompletedHikeTelemetry(
        transaction,
        sessionId: normalizedSessionId,
        preserveUnsent: preserveUnsent,
      );
    });
  }

  /// Deletes location/network tracking rows after the canonical route capture
  /// is saved, while deliberately preserving every queued SOS alert.
  Future<void> discardHikeTrackingTelemetry({required String sessionId}) async {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) return;
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      await transaction.delete(
        'local_location_points',
        where: 'session_id = ?',
        whereArgs: [normalizedSessionId],
      );
      await transaction.delete(
        'network_observations',
        where: 'session_id = ?',
        whereArgs: [normalizedSessionId],
      );
    });
  }

  Future<void> _deleteCompletedHikeTelemetry(
    DatabaseExecutor database, {
    required String sessionId,
    required bool preserveUnsent,
  }) async {
    await database.delete(
      'local_location_points',
      where: preserveUnsent
          ? 'session_id = ? AND is_synced = 1'
          : 'session_id = ?',
      whereArgs: [sessionId],
    );
    await database.delete(
      'network_observations',
      where: preserveUnsent
          ? 'session_id = ? AND is_synced = 1'
          : 'session_id = ?',
      whereArgs: [sessionId],
    );
    await database.delete(
      'queued_alerts',
      where: preserveUnsent
          ? "session_id = ? AND send_status = 'sent'"
          : 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> _createSafetyTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS local_location_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        owner_phone_number TEXT NOT NULL DEFAULT '',
        session_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        accuracy REAL,
        battery_level INTEGER,
        point_type TEXT NOT NULL DEFAULT 'automatic',
        recorded_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS queued_alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        owner_phone_number TEXT NOT NULL DEFAULT '',
        session_id TEXT NOT NULL,
        alert_type TEXT NOT NULL,
        trigger_latitude REAL,
        trigger_longitude REAL,
        trigger_time TEXT NOT NULL,
        latest_latitude REAL,
        latest_longitude REAL,
        latest_time TEXT,
        battery_level INTEGER,
        payload_json TEXT NOT NULL,
        send_status TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        last_error TEXT NOT NULL DEFAULT '',
        sent_at TEXT
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS downloaded_maps (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trail_id TEXT NOT NULL UNIQUE,
        trail_name TEXT NOT NULL,
        local_file_path TEXT NOT NULL,
        file_size INTEGER,
        downloaded_at TEXT NOT NULL,
        last_weather_cached_at TEXT,
        weather_expiry_time TEXT
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS network_observations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy REAL,
        network_available INTEGER NOT NULL,
        api_request_success INTEGER NOT NULL,
        network_type TEXT,
        recorded_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await _createSafetyIndexes(database);
  }

  Future<void> _createSafetyIndexes(Database database) async {
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_location_points_session_sync_time
      ON local_location_points(session_id, is_synced, recorded_at)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_queued_alerts_session_status
      ON queued_alerts(session_id, send_status, created_at)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_network_observations_session_sync
      ON network_observations(session_id, is_synced, recorded_at)
    ''');
  }

  Future<void> _createDeviceBindingTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS app_device (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        app_instance_id TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createEmergencyContactsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS emergency_contacts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        owner_phone_number TEXT NOT NULL,
        contact_phone_number TEXT NOT NULL,
        name TEXT NOT NULL,
        relationship TEXT NOT NULL,
        position INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        UNIQUE(owner_phone_number, contact_phone_number)
      )
    ''');
  }

  Future<void> _createPendingMessagesTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS pending_messages (
        local_id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL,
        sender_phone TEXT NOT NULL,
        sender_name TEXT NOT NULL DEFAULT '',
        text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        send_status TEXT NOT NULL DEFAULT 'pending',
        retry_count INTEGER NOT NULL DEFAULT 0,
        firestore_doc_id TEXT DEFAULT '',
        attachment_json TEXT DEFAULT ''
      )
    ''');
  }

  Future<void> _createActiveHikeSessionTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS active_hike_session (
        owner_phone_number TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createPendingHikeEndsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS pending_hike_ends (
        owner_phone_number TEXT NOT NULL,
        session_id TEXT NOT NULL,
        active_hike_payload_json TEXT NOT NULL,
        summary_payload_json TEXT,
        ended_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (owner_phone_number, session_id)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_pending_hike_ends_owner_created
      ON pending_hike_ends(owner_phone_number, created_at)
    ''');
  }

  Future<void> _createPlannedHikeStateTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS planned_hike_state (
        owner_phone_number TEXT NOT NULL,
        upcoming_hike_id TEXT NOT NULL,
        upcoming_payload_json TEXT NOT NULL,
        completed_checklist_json TEXT NOT NULL DEFAULT '[]',
        is_consumed INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (owner_phone_number, upcoming_hike_id)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_planned_hike_state_owner_updated
      ON planned_hike_state(owner_phone_number, updated_at DESC)
    ''');
  }

  Future<void> _createChatReadReceiptsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS chat_read_receipts (
        chat_id TEXT PRIMARY KEY,
        last_read_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _createDeviceNotificationsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS device_notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        owner_phone_number TEXT NOT NULL,
        message_id TEXT,
        title TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT '',
        deep_link TEXT NOT NULL DEFAULT '',
        data_json TEXT NOT NULL DEFAULT '{}',
        received_at TEXT NOT NULL,
        opened_at TEXT,
        source TEXT NOT NULL DEFAULT 'fcm'
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_device_notifications_owner_received
      ON device_notifications(owner_phone_number, received_at DESC)
    ''');
  }

  Future<void> _createNearbySosEventsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS nearby_sos_events (
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
        detector_latitude REAL,
        detector_longitude REAL,
        detector_accuracy_meters REAL,
        detector_captured_at TEXT,
        PRIMARY KEY (owner_phone_number, event_key)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_nearby_sos_events_owner_received
      ON nearby_sos_events(owner_phone_number, received_at DESC)
    ''');
  }

  Future<void> saveChatReadReceipt(
    String chatId,
    DateTime lastReadAt, {
    bool synced = false,
  }) async {
    final database = await _openDatabase();
    await database.insert('chat_read_receipts', {
      'chat_id': chatId,
      'last_read_at': lastReadAt.toUtc().toIso8601String(),
      'is_synced': synced ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<DateTime?> loadChatReadReceipt(String chatId) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'chat_read_receipts',
      columns: ['last_read_at', 'is_synced'],
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['last_read_at'] as String? ?? '');
  }

  Future<Map<String, DateTime>> loadAllChatReadReceipts() async {
    final database = await _openDatabase();
    final rows = await database.query('chat_read_receipts');
    final result = <String, DateTime>{};
    for (final row in rows) {
      final ts = DateTime.tryParse(row['last_read_at'] as String? ?? '');
      if (ts != null) {
        result[row['chat_id'] as String] = ts;
      }
    }
    return result;
  }

  Future<List<String>> loadUnsyncedReadReceiptChatIds() async {
    final database = await _openDatabase();
    final rows = await database.query(
      'chat_read_receipts',
      columns: ['chat_id'],
      where: 'is_synced = 0',
    );
    return rows.map((r) => r['chat_id'] as String).toList();
  }

  Future<void> markChatReadReceiptSynced(String chatId) async {
    final database = await _openDatabase();
    await database.update(
      'chat_read_receipts',
      {'is_synced': 1},
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );
  }

  Future<void> insertPendingMessage({
    required String localId,
    required String chatId,
    required String senderPhone,
    required String senderName,
    required String text,
    String firestoreDocId = '',
    String sendStatus = 'pending',
  }) async {
    final database = await _openDatabase();
    await database.insert('pending_messages', {
      'local_id': localId,
      'chat_id': chatId,
      'sender_phone': senderPhone,
      'sender_name': senderName,
      'text': text,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'send_status': sendStatus,
      'retry_count': 0,
      'firestore_doc_id': firestoreDocId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertChatMessages(List<Map<String, dynamic>> rows) async {
    final database = await _openDatabase();
    final batch = database.batch();
    for (final row in rows) {
      batch.insert(
        'pending_messages',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> updatePendingFirestoreDocId({
    required String localId,
    required String firestoreDocId,
  }) async {
    final database = await _openDatabase();
    await database.update(
      'pending_messages',
      {'firestore_doc_id': firestoreDocId},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<List<Map<String, dynamic>>> loadPendingMessages() async {
    final database = await _openDatabase();
    return database.query(
      'pending_messages',
      where: 'send_status IN (?, ?)',
      whereArgs: ['pending', 'unsent'],
      orderBy: 'created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> loadAllLocalMessagesForChat(
    String chatId,
  ) async {
    final database = await _openDatabase();
    return database.query(
      'pending_messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> updateLocalMessageStatus(
    String localId,
    String status, {
    String? firestoreDocId,
  }) async {
    final database = await _openDatabase();
    final values = <String, dynamic>{'send_status': status};
    if (firestoreDocId != null) {
      values['firestore_doc_id'] = firestoreDocId;
    }
    await database.update(
      'pending_messages',
      values,
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<List<Map<String, dynamic>>> loadPendingMessagesForChat(
    String chatId,
  ) async {
    final database = await _openDatabase();
    return database.query(
      'pending_messages',
      where: 'chat_id = ? AND send_status = ?',
      whereArgs: [chatId, 'pending'],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> markPendingMessageSent(String localId) async {
    final database = await _openDatabase();
    await database.update(
      'pending_messages',
      {'send_status': 'sent'},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> incrementPendingMessageRetry(String localId) async {
    final database = await _openDatabase();
    await database.rawUpdate(
      'UPDATE pending_messages SET retry_count = retry_count + 1 WHERE local_id = ?',
      [localId],
    );
  }

  Future<void> deletePendingMessage(String localId) async {
    final database = await _openDatabase();
    await database.delete(
      'pending_messages',
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<int> countPendingMessages() async {
    final database = await _openDatabase();
    final result = await database.rawQuery(
      'SELECT COUNT(*) AS total FROM pending_messages WHERE send_status = ?',
      ['pending'],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> deleteChatData(String chatId) async {
    final database = await _openDatabase();
    await database.delete(
      'chat_read_receipts',
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );
    await database.delete(
      'pending_messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );
  }

  Future<void> _createRouteCacheTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS route_cache (
        trail_id TEXT NOT NULL,
        checkpoints_hash TEXT NOT NULL,
        encoded_polyline TEXT NOT NULL,
        distance_meters INTEGER NOT NULL,
        duration_seconds INTEGER NOT NULL,
        elevation_gain_meters REAL,
        source_label TEXT NOT NULL,
        cached_at TEXT NOT NULL,
        PRIMARY KEY (trail_id, checkpoints_hash)
      )
    ''');
  }

  Future<void> saveRouteCache({
    required String trailId,
    required String checkpointsHash,
    required String encodedPolyline,
    required int distanceMeters,
    required int durationSeconds,
    double? elevationGainMeters,
    required String sourceLabel,
  }) async {
    final database = await _openDatabase();
    await database.insert('route_cache', {
      'trail_id': trailId,
      'checkpoints_hash': checkpointsHash,
      'encoded_polyline': encodedPolyline,
      'distance_meters': distanceMeters,
      'duration_seconds': durationSeconds,
      'elevation_gain_meters': elevationGainMeters,
      'source_label': sourceLabel,
      'cached_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> loadRouteCache({
    required String trailId,
    required String checkpointsHash,
  }) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'route_cache',
      where: 'trail_id = ? AND checkpoints_hash = ?',
      whereArgs: [trailId, checkpointsHash],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<void> deleteRouteCacheForTrail(String trailId) async {
    final database = await _openDatabase();
    await database.delete(
      'route_cache',
      where: 'trail_id = ?',
      whereArgs: [trailId],
    );
  }

  Future<void> clearAllRouteCache() async {
    final database = await _openDatabase();
    await database.delete('route_cache');
  }

  Future<Map<String, List<Map<String, dynamic>>>> dumpAllTables() async {
    final database = await _openDatabase();
    final tableRows = await database.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name NOT LIKE 'sqlite_%'
        AND name NOT LIKE 'android_%'
      ORDER BY name
    ''');
    final tableNames = tableRows
        .map((row) => row['name'])
        .whereType<String>()
        .toList();
    final result = <String, List<Map<String, dynamic>>>{};
    for (final table in tableNames) {
      result[table] = await database.query(table);
    }
    return result;
  }

  Future<void> _addColumnIfMissing(
    Database database, {
    required String tableName,
    required String columnName,
    required String definition,
  }) async {
    final columns = await database.rawQuery('PRAGMA table_info($tableName)');
    final exists = columns.any((column) => column['name'] == columnName);
    if (exists) {
      return;
    }
    await database.execute(
      'ALTER TABLE $tableName ADD COLUMN $columnName $definition',
    );
  }

  void _configureDatabaseFactory() {
    if (kIsWeb || _isDesktopFactoryConfigured) {
      return;
    }

    // An explicit path is used by host-side tests and diagnostics. Flutter
    // tests default to an Android target even while running on Windows, so
    // target-platform detection alone cannot select the FFI database factory.
    if (_databasePathOverride != null) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _isDesktopFactoryConfigured = true;
      return;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        _isDesktopFactoryConfigured = true;
        break;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.iOS:
        break;
    }
  }

  Map<String, Object?> _sessionToRow(AppSession session) {
    return {
      'phone_number': session.phoneNumber,
      'created_at': session.createdAt.toUtc().toIso8601String(),
      'signed_in_at': session.signedInAt.toUtc().toIso8601String(),
      'app_instance_id': session.appInstanceId,
      'is_admin': session.isAdmin ? 1 : 0,
      'username': session.username,
      'requires_onboarding': session.requiresOnboarding ? 1 : 0,
      'onboarding_profile_complete': session.isOnboardingProfileComplete
          ? 1
          : 0,
      'photo_url': session.photoURL,
      'photo_bytes': session.photoBytes,
    };
  }

  AppSession _sessionFromRow(Map<String, Object?> row) {
    final signedInAt =
        DateTime.tryParse(row['signed_in_at'] as String? ?? '') ??
        DateTime.now().toUtc();
    final createdAt =
        DateTime.tryParse(row['created_at'] as String? ?? '') ?? signedInAt;

    return AppSession(
      phoneNumber: row['phone_number'] as String,
      signedInAt: signedInAt,
      createdAt: createdAt,
      appInstanceId: row['app_instance_id'] as String? ?? '',
      isAdmin: row['is_admin'] == 1,
      username: row['username'] as String? ?? '',
      requiresOnboarding: row['requires_onboarding'] == 1,
      isOnboardingProfileComplete: row['onboarding_profile_complete'] == 1,
      photoURL: row['photo_url'] as String?,
      photoBytes: row['photo_bytes'] is Uint8List
          ? row['photo_bytes'] as Uint8List
          : null,
    );
  }

  EmergencyContact _emergencyContactFromRow(Map<String, Object?> row) {
    return EmergencyContact(
      name: row['name'] as String? ?? '',
      phoneNumber: row['contact_phone_number'] as String? ?? '',
      relationship: row['relationship'] as String? ?? '',
    );
  }

  String _newAppInstanceId() {
    final random = math.Random.secure();
    final parts = List.generate(
      4,
      (_) => random.nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0'),
    );
    return 'hc_${DateTime.now().microsecondsSinceEpoch}_${parts.join()}';
  }
}

class LocalPlannedHikeState {
  const LocalPlannedHikeState({
    required this.ownerPhoneNumber,
    required this.upcomingHike,
    required this.completedChecklistItems,
    required this.isConsumed,
    required this.updatedAt,
  });

  factory LocalPlannedHikeState.fromRow(Map<String, Object?> row) {
    final hikeId = row['upcoming_hike_id'] as String? ?? '';
    final payload = _decodeJsonMap(row['upcoming_payload_json'] as String?);
    if (hikeId.trim().isEmpty || payload.isEmpty) {
      throw const FormatException('Planned hike snapshot is incomplete.');
    }
    final rawChecklist = row['completed_checklist_json'] as String? ?? '[]';
    Iterable<String> checklist = const <String>[];
    try {
      final decoded = jsonDecode(rawChecklist);
      if (decoded is Iterable) {
        checklist = decoded.whereType<String>();
      }
    } catch (_) {
      checklist = const <String>[];
    }
    return LocalPlannedHikeState(
      ownerPhoneNumber: row['owner_phone_number'] as String? ?? '',
      upcomingHike: UpcomingHike.fromFirestore(hikeId, payload),
      completedChecklistItems: GearChecklistCatalog.sanitize(checklist),
      isConsumed: row['is_consumed'] == 1,
      updatedAt:
          DateTime.tryParse(row['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String ownerPhoneNumber;
  final UpcomingHike upcomingHike;
  final Set<String> completedChecklistItems;
  final bool isConsumed;
  final DateTime updatedAt;
}

class LocalPendingHikeEnd {
  const LocalPendingHikeEnd({
    required this.ownerPhoneNumber,
    required this.sessionId,
    required this.activeHikePayload,
    required this.summaryPayload,
    required this.endedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.retryCount,
    required this.lastError,
  });

  factory LocalPendingHikeEnd.fromRow(Map<String, Object?> row) {
    return LocalPendingHikeEnd(
      ownerPhoneNumber: row['owner_phone_number'] as String? ?? '',
      sessionId: row['session_id'] as String? ?? '',
      activeHikePayload: _decodeJsonMap(
        row['active_hike_payload_json'] as String?,
      ),
      summaryPayload: _decodeNullableJsonMap(
        row['summary_payload_json'] as String?,
      ),
      endedAt: DateTime.tryParse(row['ended_at'] as String? ?? ''),
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt:
          DateTime.tryParse(row['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      retryCount:
          row['retry_count'] is num && (row['retry_count'] as num).isFinite
          ? (row['retry_count'] as num).toInt()
          : 0,
      lastError: row['last_error'] as String? ?? '',
    );
  }

  final String ownerPhoneNumber;
  final String sessionId;
  final Map<String, dynamic> activeHikePayload;
  final Map<String, dynamic>? summaryPayload;
  final DateTime? endedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int retryCount;
  final String lastError;

  ActiveHikeSession? get activeHike {
    if (activeHikePayload.isEmpty) return null;
    try {
      return ActiveHikeSession.fromPersistence(activeHikePayload);
    } catch (_) {
      return null;
    }
  }
}

class CacheUsageSummary {
  const CacheUsageSummary({
    required this.downloadedMapCount,
    required this.downloadedMapBytes,
    required this.networkObservationCount,
  });

  final int downloadedMapCount;
  final int downloadedMapBytes;
  final int networkObservationCount;

  String get label {
    final sizeLabel = downloadedMapBytes <= 0
        ? '0 MB'
        : '${(downloadedMapBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '$sizeLabel offline maps, $downloadedMapCount route packs, $networkObservationCount connection records';
  }
}

class LocalLocationPoint {
  const LocalLocationPoint({
    required this.id,
    required this.ownerPhoneNumber,
    required this.sessionId,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.accuracy,
    required this.batteryLevel,
    required this.pointType,
    required this.recordedAt,
    required this.isSynced,
  });

  factory LocalLocationPoint.fromRow(Map<String, Object?> row) {
    final latitude = row['latitude'];
    final longitude = row['longitude'];
    final altitude = row['altitude'];
    final accuracy = row['accuracy'];
    final batteryLevel = row['battery_level'];
    return LocalLocationPoint(
      id: row['id'] is int ? row['id'] as int : 0,
      ownerPhoneNumber: row['owner_phone_number'] as String? ?? '',
      sessionId: row['session_id'] as String? ?? '',
      latitude: latitude is num ? latitude.toDouble() : double.nan,
      longitude: longitude is num ? longitude.toDouble() : double.nan,
      altitude: altitude is num && altitude.isFinite
          ? altitude.toDouble()
          : null,
      accuracy: accuracy is num && accuracy.isFinite && accuracy >= 0
          ? accuracy.toDouble()
          : null,
      batteryLevel: batteryLevel is num && batteryLevel.isFinite
          ? batteryLevel.toInt().clamp(0, 100)
          : null,
      pointType: row['point_type'] as String? ?? 'automatic',
      recordedAt:
          DateTime.tryParse(row['recorded_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      isSynced: row['is_synced'] == 1,
    );
  }

  final int id;
  final String ownerPhoneNumber;
  final String sessionId;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final int? batteryLevel;
  final String pointType;
  final DateTime recordedAt;
  final bool isSynced;

  bool get hasValidCoordinate => _isValidCoordinate(latitude, longitude);
}

class DeviceNotificationRecord {
  const DeviceNotificationRecord({
    required this.id,
    required this.messageId,
    required this.title,
    required this.body,
    required this.type,
    required this.deepLink,
    required this.data,
    required this.receivedAt,
    required this.openedAt,
    required this.source,
  });

  factory DeviceNotificationRecord.fromRow(Map<String, Object?> row) {
    final rawData = row['data_json'] as String? ?? '{}';
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(rawData);
      data = decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      data = {};
    }
    return DeviceNotificationRecord(
      id: row['id'] is int ? row['id'] as int : 0,
      messageId: row['message_id'] as String? ?? '',
      title: row['title'] as String? ?? '',
      body: row['body'] as String? ?? '',
      type: row['type'] as String? ?? '',
      deepLink: row['deep_link'] as String? ?? '',
      data: data,
      receivedAt:
          DateTime.tryParse(row['received_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      openedAt: DateTime.tryParse(row['opened_at'] as String? ?? ''),
      source: row['source'] as String? ?? 'fcm',
    );
  }

  final int id;
  final String messageId;
  final String title;
  final String body;
  final String type;
  final String deepLink;
  final Map<String, dynamic> data;
  final DateTime receivedAt;
  final DateTime? openedAt;
  final String source;

  bool get isOpened => openedAt != null;
}

class LocalQueuedAlert {
  const LocalQueuedAlert({
    required this.id,
    required this.ownerPhoneNumber,
    required this.sessionId,
    required this.alertType,
    required this.triggerLatitude,
    required this.triggerLongitude,
    required this.triggerTime,
    required this.payloadJson,
    required this.sendStatus,
    required this.retryCount,
    required this.createdAt,
    required this.lastError,
  });

  factory LocalQueuedAlert.fromRow(Map<String, Object?> row) {
    return LocalQueuedAlert(
      id: row['id'] is int ? row['id'] as int : 0,
      ownerPhoneNumber: row['owner_phone_number'] as String? ?? '',
      sessionId: row['session_id'] as String? ?? '',
      alertType: row['alert_type'] as String? ?? '',
      triggerLatitude: row['trigger_latitude'] is num
          ? (row['trigger_latitude'] as num).toDouble()
          : 0,
      triggerLongitude: row['trigger_longitude'] is num
          ? (row['trigger_longitude'] as num).toDouble()
          : 0,
      triggerTime:
          DateTime.tryParse(row['trigger_time'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      payloadJson: row['payload_json'] as String? ?? '{}',
      sendStatus: row['send_status'] as String? ?? 'queued',
      retryCount: row['retry_count'] is int ? row['retry_count'] as int : 0,
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastError: row['last_error'] as String? ?? '',
    );
  }

  final int id;
  final String ownerPhoneNumber;
  final String sessionId;
  final String alertType;
  final double triggerLatitude;
  final double triggerLongitude;
  final DateTime triggerTime;
  final String payloadJson;
  final String sendStatus;
  final int retryCount;
  final DateTime createdAt;
  final String lastError;
}

bool _isValidCoordinate(double latitude, double longitude) {
  return latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

Map<String, dynamic> _decodeJsonMap(String? value) {
  if (value == null || value.isEmpty) return const {};
  try {
    final decoded = jsonDecode(value);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
  } catch (_) {
    return const {};
  }
}

Map<String, dynamic>? _decodeNullableJsonMap(String? value) {
  if (value == null || value.isEmpty) return null;
  final decoded = _decodeJsonMap(value);
  return decoded.isEmpty ? null : decoded;
}

List<String> _decodeJsonStringList(String? value) {
  if (value == null || value.isEmpty) return const [];
  try {
    final decoded = jsonDecode(value);
    return decoded is Iterable
        ? decoded.whereType<String>().toList()
        : const [];
  } catch (_) {
    return const [];
  }
}

String _plannedHikeScheduleKey(UpcomingHike hike) {
  final phone = hike.creatorPhone.replaceAll(RegExp(r'[^0-9]'), '');
  return jsonEncode([
    hike.trailId.trim().toLowerCase(),
    hike.departureTime.toUtc().toIso8601String(),
    hike.expectedReturnTime.toUtc().toIso8601String(),
    hike.hikeType.trim().toLowerCase(),
    hike.startPointName.trim(),
    hike.destinationName.trim(),
    phone,
  ]);
}

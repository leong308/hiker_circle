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

@immutable
class LocalAchievementProgressCache {
  const LocalAchievementProgressCache({
    required this.contentHash,
    required this.rows,
    required this.cachedAt,
  });

  final String contentHash;
  final List<Map<String, dynamic>> rows;
  final DateTime cachedAt;
}

@immutable
class LocalCachedEntity {
  const LocalCachedEntity({
    required this.ownerPhoneNumber,
    required this.entityType,
    required this.entityId,
    required this.parentId,
    required this.payload,
    required this.cachedAt,
    this.sourceUpdatedAt,
    this.expiresAt,
  });

  factory LocalCachedEntity.fromRow(Map<String, Object?> row) {
    final decoded = jsonDecode(row['payload_json'] as String? ?? '{}');
    if (decoded is! Map) {
      throw const FormatException('Cached entity payload is not an object.');
    }
    return LocalCachedEntity(
      ownerPhoneNumber: row['owner_phone_number'] as String? ?? '',
      entityType: row['entity_type'] as String? ?? '',
      entityId: row['entity_id'] as String? ?? '',
      parentId: row['parent_id'] as String? ?? '',
      payload: Map<String, dynamic>.from(decoded),
      cachedAt:
          DateTime.tryParse(row['cached_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      sourceUpdatedAt: DateTime.tryParse(
        row['source_updated_at'] as String? ?? '',
      ),
      expiresAt: DateTime.tryParse(row['expires_at'] as String? ?? ''),
    );
  }

  final String ownerPhoneNumber;
  final String entityType;
  final String entityId;
  final String parentId;
  final Map<String, dynamic> payload;
  final DateTime cachedAt;
  final DateTime? sourceUpdatedAt;
  final DateTime? expiresAt;
}

@immutable
class LocalSyncOperation {
  const LocalSyncOperation({
    required this.operationId,
    required this.ownerPhoneNumber,
    required this.operationType,
    required this.entityType,
    required this.entityId,
    required this.idempotencyKey,
    required this.payload,
    required this.status,
    required this.attemptCount,
    required this.createdAt,
    required this.updatedAt,
    this.localFilePath = '',
    this.nextAttemptAt,
    this.lastError = '',
  });

  factory LocalSyncOperation.fromRow(Map<String, Object?> row) {
    final decoded = jsonDecode(row['payload_json'] as String? ?? '{}');
    return LocalSyncOperation(
      operationId: row['operation_id'] as String? ?? '',
      ownerPhoneNumber: row['owner_phone_number'] as String? ?? '',
      operationType: row['operation_type'] as String? ?? '',
      entityType: row['entity_type'] as String? ?? '',
      entityId: row['entity_id'] as String? ?? '',
      idempotencyKey: row['idempotency_key'] as String? ?? '',
      payload: decoded is Map ? Map<String, dynamic>.from(decoded) : const {},
      localFilePath: row['local_file_path'] as String? ?? '',
      status: row['status'] as String? ?? 'pending',
      attemptCount: row['attempt_count'] as int? ?? 0,
      nextAttemptAt: DateTime.tryParse(row['next_attempt_at'] as String? ?? ''),
      lastError: row['last_error'] as String? ?? '',
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt:
          DateTime.tryParse(row['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String operationId;
  final String ownerPhoneNumber;
  final String operationType;
  final String entityType;
  final String entityId;
  final String idempotencyKey;
  final Map<String, dynamic> payload;
  final String localFilePath;
  final String status;
  final int attemptCount;
  final DateTime? nextAttemptAt;
  final String lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
}

@immutable
class LocalOfflineMapRegion {
  const LocalOfflineMapRegion({
    required this.trailId,
    required this.regionId,
    required this.styleUri,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.status,
    required this.completedResourceCount,
    required this.requiredResourceCount,
    required this.completedBytes,
    required this.updatedAt,
    this.downloadedAt,
    this.lastError = '',
  });

  factory LocalOfflineMapRegion.fromRow(Map<String, Object?> row) {
    final bounds = jsonDecode(row['bounds_json'] as String? ?? '{}');
    return LocalOfflineMapRegion(
      trailId: row['trail_id'] as String? ?? '',
      regionId: row['region_id'] as String? ?? '',
      styleUri: row['style_uri'] as String? ?? '',
      bounds: bounds is Map ? Map<String, dynamic>.from(bounds) : const {},
      minZoom: (row['min_zoom'] as num?)?.toInt() ?? 0,
      maxZoom: (row['max_zoom'] as num?)?.toInt() ?? 0,
      status: row['status'] as String? ?? 'pending',
      completedResourceCount:
          (row['completed_resource_count'] as num?)?.toInt() ?? 0,
      requiredResourceCount:
          (row['required_resource_count'] as num?)?.toInt() ?? 0,
      completedBytes: (row['completed_bytes'] as num?)?.toInt() ?? 0,
      downloadedAt: DateTime.tryParse(row['downloaded_at'] as String? ?? ''),
      updatedAt:
          DateTime.tryParse(row['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastError: row['last_error'] as String? ?? '',
    );
  }

  final String trailId;
  final String regionId;
  final String styleUri;
  final Map<String, dynamic> bounds;
  final int minZoom;
  final int maxZoom;
  final String status;
  final int completedResourceCount;
  final int requiredResourceCount;
  final int completedBytes;
  final DateTime? downloadedAt;
  final DateTime updatedAt;
  final String lastError;

  bool get isComplete =>
      status == 'complete' &&
      requiredResourceCount > 0 &&
      completedResourceCount >= requiredResourceCount;
}

@immutable
class LocalStaticHazard {
  const LocalStaticHazard({
    required this.hazardId,
    required this.hazardType,
    required this.title,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.severity,
    required this.confidence,
    required this.sourceName,
    required this.sourceUrl,
    required this.sourceFeatureId,
    required this.safetyGuidance,
    required this.downloadedAt,
    this.sourceUpdatedAt,
    this.expiresAt,
  });

  factory LocalStaticHazard.fromRow(Map<String, Object?> row) {
    return LocalStaticHazard(
      hazardId: row['hazard_id'] as String? ?? '',
      hazardType: row['hazard_type'] as String? ?? '',
      title: row['title'] as String? ?? '',
      description: row['description'] as String? ?? '',
      latitude: (row['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (row['longitude'] as num?)?.toDouble() ?? 0,
      severity: row['severity'] as String? ?? 'info',
      confidence: row['confidence'] as String? ?? 'mapped',
      sourceName: row['source_name'] as String? ?? '',
      sourceUrl: row['source_url'] as String? ?? '',
      sourceFeatureId: row['source_feature_id'] as String? ?? '',
      safetyGuidance: row['safety_guidance'] as String? ?? '',
      sourceUpdatedAt: DateTime.tryParse(
        row['source_updated_at'] as String? ?? '',
      ),
      downloadedAt:
          DateTime.tryParse(row['downloaded_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      expiresAt: DateTime.tryParse(row['expires_at'] as String? ?? ''),
    );
  }

  final String hazardId;
  final String hazardType;
  final String title;
  final String description;
  final double latitude;
  final double longitude;
  final String severity;
  final String confidence;
  final String sourceName;
  final String sourceUrl;
  final String sourceFeatureId;
  final String safetyGuidance;
  final DateTime? sourceUpdatedAt;
  final DateTime downloadedAt;
  final DateTime? expiresAt;
}

@immutable
class LocalTrailHazardMatch {
  const LocalTrailHazardMatch({
    required this.trailId,
    required this.hazard,
    required this.relationship,
    required this.distanceMeters,
    required this.routeProgress,
    required this.computedAt,
  });

  final String trailId;
  final LocalStaticHazard hazard;
  final String relationship;
  final double distanceMeters;
  final double routeProgress;
  final DateTime computedAt;
}

@immutable
class LocalHazardDatasetSummary {
  const LocalHazardDatasetSummary({
    required this.hazardCount,
    required this.trailCount,
    this.downloadedAt,
  });

  final int hazardCount;
  final int trailCount;
  final DateTime? downloadedAt;

  bool get isDownloaded => downloadedAt != null;
}

class LocalSessionDatabase {
  LocalSessionDatabase({String? databasePath})
    : _databasePathOverride = databasePath;

  // Refresh older scans after lowering the steep-caution threshold to 12.5°.
  // Existing offline hazards remain available until the refresh succeeds.
  static const _staticHazardScanPreferencePrefix = 'static_hazard_scan:v4:';

  Database? _database;
  Future<Database>? _openingDatabase;
  final String? _databasePathOverride;
  static bool _isDesktopFactoryConfigured = false;
  static Future<Database>? _sharedDefaultDatabaseOpening;
  static final Set<String> _loggedDatabasePaths = <String>{};

  Future<void> createButtonDebugSession(
    String id,
    String owner,
    DateTime start,
  ) async {
    final db = await _openDatabase();
    await db.insert('button_debug_sessions', {
      'id': id,
      'owner_phone_number': owner,
      'started_at': start.toUtc().toIso8601String(),
      'status': 'recording',
    });
  }

  Future<void> appendButtonDebugEntry(
    String owner,
    Map<String, Object?> entry,
  ) async {
    final db = await _openDatabase();
    await db.transaction((txn) async {
      final session = await txn.query(
        'button_debug_sessions',
        where: 'id = ? AND owner_phone_number = ? AND status = ?',
        whereArgs: [entry['session_id'], owner, 'recording'],
      );
      if (session.isEmpty) throw StateError('Debug session is not recording.');
      await txn.insert('button_debug_entries', entry);
    });
  }

  Future<List<Map<String, Object?>>> loadButtonDebugSessions(
    String owner,
  ) async {
    final db = await _openDatabase();
    return db.query(
      'button_debug_sessions',
      columns: [
        'id',
        'owner_phone_number',
        'started_at',
        'ended_at',
        'status',
        'end_reason',
        'file_path',
      ],
      where: 'owner_phone_number = ?',
      whereArgs: [owner],
      orderBy: 'started_at DESC',
    );
  }

  Future<String?> loadButtonDebugLog(String owner, String id) async {
    final db = await _openDatabase();
    final rows = await db.query(
      'button_debug_sessions',
      columns: ['log_text'],
      where: 'owner_phone_number = ? AND id = ?',
      whereArgs: [owner, id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['log_text'] as String?;
  }

  Future<List<Map<String, Object?>>> loadButtonDebugEntries(
    String owner,
    String id,
  ) async {
    final db = await _openDatabase();
    return db.rawQuery(
      '''
      SELECT e.* FROM button_debug_entries e
      JOIN button_debug_sessions s ON s.id = e.session_id
      WHERE s.owner_phone_number = ? AND s.id = ? ORDER BY e.sequence
    ''',
      [owner, id],
    );
  }

  Future<void> concludeButtonDebugSession({
    required String owner,
    required String id,
    required DateTime endedAt,
    required String reason,
    required String logText,
    String? filePath,
  }) async {
    final db = await _openDatabase();
    await db.update(
      'button_debug_sessions',
      {
        'ended_at': endedAt.toUtc().toIso8601String(),
        'status': 'concluded',
        'end_reason': reason,
        'log_text': logText,
        'file_path': filePath,
      },
      where: 'id = ? AND owner_phone_number = ?',
      whereArgs: [id, owner],
    );
  }

  Future<void> _createButtonDebugTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS button_debug_sessions (
        id TEXT PRIMARY KEY, owner_phone_number TEXT NOT NULL,
        started_at TEXT NOT NULL, ended_at TEXT,
        status TEXT NOT NULL, end_reason TEXT, log_text TEXT, file_path TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS button_debug_entries (
        session_id TEXT NOT NULL REFERENCES button_debug_sessions(id),
        sequence INTEGER NOT NULL, timestamp TEXT NOT NULL,
        direction TEXT NOT NULL, operation TEXT NOT NULL,
        device_id TEXT NOT NULL, characteristic TEXT NOT NULL,
        status TEXT NOT NULL, payload BLOB NOT NULL,
        interpretation TEXT NOT NULL, PRIMARY KEY (session_id, sequence)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS button_debug_owner_time '
      'ON button_debug_sessions(owner_phone_number, started_at)',
    );
  }

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

  Future<void> clearUserSessionOnly() async {
    final database = await _openDatabase();
    await database.delete('users');
  }

  Future<LocalAchievementProgressCache?> loadAchievementProgressCache({
    required String ownerPhoneNumber,
  }) async {
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty) return null;
    final database = await _openDatabase();
    final rows = await database.query(
      'achievement_progress_cache',
      where: 'owner_phone_number = ?',
      whereArgs: [owner],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final decoded = jsonDecode(rows.first['payload_json'] as String);
      if (decoded is! List) return null;
      final achievements = decoded
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
      if (achievements.isEmpty) return null;
      return LocalAchievementProgressCache(
        contentHash: rows.first['content_hash'] as String? ?? '',
        rows: achievements,
        cachedAt:
            DateTime.tryParse(rows.first['cached_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    } catch (_) {
      await database.delete(
        'achievement_progress_cache',
        where: 'owner_phone_number = ?',
        whereArgs: [owner],
      );
      return null;
    }
  }

  Future<void> saveAchievementProgressCache({
    required String ownerPhoneNumber,
    required String contentHash,
    required List<Map<String, dynamic>> rows,
  }) async {
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty || rows.isEmpty) return;
    final database = await _openDatabase();
    await database.insert('achievement_progress_cache', {
      'owner_phone_number': owner,
      'content_hash': contentHash.trim(),
      'payload_json': jsonEncode(rows),
      'cached_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    await database.rawDelete(
      '''DELETE FROM local_location_points WHERE session_id = ? AND owner_phone_number = ? AND sample_key IS NOT NULL AND sample_key IN (SELECT sample_key FROM local_location_points WHERE session_id = ? AND owner_phone_number = ?)''',
      [oldSessionId, ownerPhoneNumber, newSessionId, ownerPhoneNumber],
    );
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
      final pendingEnds = await database.query(
        'pending_hike_ends',
        where: 'owner_phone_number = ?',
        whereArgs: [phoneNumber],
      );
      final stopWasSaved = pendingEnds.any((row) {
        if (row['session_id'] == activeHike.sessionId) return true;
        final pending = LocalPendingHikeEnd.fromRow(row).activeHike;
        // An interrupted cloud retry may already have remapped the active
        // snapshot while the pending request keeps its original identity.
        return pending != null &&
            pending.trail.trailId == activeHike.trail.trailId &&
            pending.startedAt.millisecondsSinceEpoch ==
                activeHike.startedAt.millisecondsSinceEpoch;
      });
      if (stopWasSaved) {
        await clearActiveHikeSession(phoneNumber: phoneNumber);
        return null;
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
      final pendingEnds = await transaction.query(
        'pending_hike_ends',
        columns: ['session_id'],
        where: 'owner_phone_number = ?',
        whereArgs: [phoneNumber],
        limit: 1,
      );
      // Pending requests retain their original idempotency ID even when their
      // samples have moved to a canonical cloud ID. Keep route evidence until
      // the owner's pending completions are fully acknowledged.
      if (pendingEnds.isNotEmpty) return;
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

  Future<void> saveCachedEntity(LocalCachedEntity entity) async {
    final database = await _openDatabase();
    await database.insert('cached_entities', {
      'owner_phone_number': entity.ownerPhoneNumber.trim(),
      'entity_type': entity.entityType.trim(),
      'entity_id': entity.entityId.trim(),
      'parent_id': entity.parentId.trim(),
      'payload_json': jsonEncode(entity.payload),
      'source_updated_at': entity.sourceUpdatedAt?.toUtc().toIso8601String(),
      'cached_at': entity.cachedAt.toUtc().toIso8601String(),
      'expires_at': entity.expiresAt?.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveCachedEntities(List<LocalCachedEntity> entities) async {
    if (entities.isEmpty) return;
    final database = await _openDatabase();
    final batch = database.batch();
    for (final entity in entities) {
      batch.insert('cached_entities', {
        'owner_phone_number': entity.ownerPhoneNumber.trim(),
        'entity_type': entity.entityType.trim(),
        'entity_id': entity.entityId.trim(),
        'parent_id': entity.parentId.trim(),
        'payload_json': jsonEncode(entity.payload),
        'source_updated_at': entity.sourceUpdatedAt?.toUtc().toIso8601String(),
        'cached_at': entity.cachedAt.toUtc().toIso8601String(),
        'expires_at': entity.expiresAt?.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<LocalCachedEntity>> loadCachedEntities({
    required String ownerPhoneNumber,
    required String entityType,
    String? parentId,
    bool includeExpired = false,
  }) async {
    final database = await _openDatabase();
    final clauses = <String>['owner_phone_number = ?', 'entity_type = ?'];
    final arguments = <Object?>[ownerPhoneNumber.trim(), entityType.trim()];
    if (parentId != null) {
      clauses.add('parent_id = ?');
      arguments.add(parentId.trim());
    }
    if (!includeExpired) {
      clauses.add('(expires_at IS NULL OR expires_at > ?)');
      arguments.add(DateTime.now().toUtc().toIso8601String());
    }
    final rows = await database.query(
      'cached_entities',
      where: clauses.join(' AND '),
      whereArgs: arguments,
      orderBy: 'source_updated_at DESC, cached_at DESC',
    );
    return rows.map(LocalCachedEntity.fromRow).toList();
  }

  Future<LocalCachedEntity?> loadCachedEntity({
    required String ownerPhoneNumber,
    required String entityType,
    required String entityId,
    bool includeExpired = false,
  }) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'cached_entities',
      where:
          'owner_phone_number = ? AND entity_type = ? AND entity_id = ?${includeExpired ? '' : ' AND (expires_at IS NULL OR expires_at > ?)'}',
      whereArgs: [
        ownerPhoneNumber.trim(),
        entityType.trim(),
        entityId.trim(),
        if (!includeExpired) DateTime.now().toUtc().toIso8601String(),
      ],
      limit: 1,
    );
    return rows.isEmpty ? null : LocalCachedEntity.fromRow(rows.first);
  }

  Future<void> replaceCachedEntitySet({
    required String ownerPhoneNumber,
    required String entityType,
    String parentId = '',
    required List<LocalCachedEntity> entities,
  }) async {
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      await transaction.delete(
        'cached_entities',
        where: 'owner_phone_number = ? AND entity_type = ? AND parent_id = ?',
        whereArgs: [
          ownerPhoneNumber.trim(),
          entityType.trim(),
          parentId.trim(),
        ],
      );
      for (final entity in entities) {
        await transaction.insert('cached_entities', {
          'owner_phone_number': entity.ownerPhoneNumber.trim(),
          'entity_type': entity.entityType.trim(),
          'entity_id': entity.entityId.trim(),
          'parent_id': entity.parentId.trim(),
          'payload_json': jsonEncode(entity.payload),
          'source_updated_at': entity.sourceUpdatedAt
              ?.toUtc()
              .toIso8601String(),
          'cached_at': entity.cachedAt.toUtc().toIso8601String(),
          'expires_at': entity.expiresAt?.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> enqueueSyncOperation(LocalSyncOperation operation) async {
    final database = await _openDatabase();
    await database.insert('sync_outbox', {
      'operation_id': operation.operationId,
      'owner_phone_number': operation.ownerPhoneNumber.trim(),
      'operation_type': operation.operationType,
      'entity_type': operation.entityType,
      'entity_id': operation.entityId,
      'idempotency_key': operation.idempotencyKey,
      'payload_json': jsonEncode(operation.payload),
      'local_file_path': operation.localFilePath,
      'status': operation.status,
      'attempt_count': operation.attemptCount,
      'next_attempt_at': operation.nextAttemptAt?.toUtc().toIso8601String(),
      'last_error': operation.lastError,
      'created_at': operation.createdAt.toUtc().toIso8601String(),
      'updated_at': operation.updatedAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<LocalSyncOperation>> loadDueSyncOperations({
    required String ownerPhoneNumber,
    int limit = 50,
  }) async {
    final database = await _openDatabase();
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await database.query(
      'sync_outbox',
      where:
          "owner_phone_number = ? AND status IN ('pending', 'retry') AND (next_attempt_at IS NULL OR next_attempt_at <= ?)",
      whereArgs: [ownerPhoneNumber.trim(), now],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(LocalSyncOperation.fromRow).toList();
  }

  Future<void> markSyncOperationRetry(
    String operationId, {
    required String lastError,
    DateTime? nextAttemptAt,
  }) async {
    final database = await _openDatabase();
    await database.rawUpdate(
      '''
      UPDATE sync_outbox
      SET status = 'retry', attempt_count = attempt_count + 1,
          next_attempt_at = ?, last_error = ?, updated_at = ?
      WHERE operation_id = ?
    ''',
      [
        nextAttemptAt?.toUtc().toIso8601String(),
        lastError,
        DateTime.now().toUtc().toIso8601String(),
        operationId,
      ],
    );
  }

  Future<void> deleteSyncOperation(String operationId) async {
    final database = await _openDatabase();
    await database.delete(
      'sync_outbox',
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
  }

  Future<void> saveLocalPreference({
    required String ownerPhoneNumber,
    required String key,
    required Object? value,
    bool isDirty = false,
  }) async {
    final database = await _openDatabase();
    await database.insert('local_preferences', {
      'owner_phone_number': ownerPhoneNumber.trim(),
      'preference_key': key.trim(),
      'value_json': jsonEncode(value),
      'is_dirty': isDirty ? 1 : 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Object?> loadLocalPreference({
    required String ownerPhoneNumber,
    required String key,
  }) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'local_preferences',
      columns: ['value_json'],
      where: 'owner_phone_number = ? AND preference_key = ?',
      whereArgs: [ownerPhoneNumber.trim(), key.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['value_json'] as String? ?? 'null');
  }

  Future<bool> clearLocalPreferenceIfValue({
    required String ownerPhoneNumber,
    required String key,
    required Object? expectedValue,
  }) async {
    final database = await _openDatabase();
    final deleted = await database.delete(
      'local_preferences',
      where: 'owner_phone_number = ? AND preference_key = ? AND value_json = ?',
      whereArgs: [
        ownerPhoneNumber.trim(),
        key.trim(),
        jsonEncode(expectedValue),
      ],
    );
    return deleted > 0;
  }

  Future<bool> saveLocalPreferenceIfClean({
    required String ownerPhoneNumber,
    required String key,
    required Object? value,
  }) async {
    final database = await _openDatabase();
    return database.transaction((transaction) async {
      final rows = await transaction.query(
        'local_preferences',
        columns: ['is_dirty'],
        where: 'owner_phone_number = ? AND preference_key = ?',
        whereArgs: [ownerPhoneNumber.trim(), key.trim()],
      );
      if (rows.isNotEmpty && rows.first['is_dirty'] == 1) return false;
      await transaction.insert('local_preferences', {
        'owner_phone_number': ownerPhoneNumber.trim(),
        'preference_key': key.trim(),
        'value_json': jsonEncode(value),
        'is_dirty': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }

  Future<Map<String, Object?>> loadDirtyLocalPreferences({
    required String ownerPhoneNumber,
  }) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'local_preferences',
      columns: ['preference_key', 'value_json'],
      where: 'owner_phone_number = ? AND is_dirty = 1',
      whereArgs: [ownerPhoneNumber.trim()],
    );
    final result = <String, Object?>{};
    for (final row in rows) {
      try {
        result[row['preference_key'] as String] = jsonDecode(
          row['value_json'] as String,
        );
      } on FormatException {
        continue;
      }
    }
    return result;
  }

  Future<void> markLocalPreferenceSynced({
    required String ownerPhoneNumber,
    required String key,
    required Object? expectedValue,
  }) async {
    final database = await _openDatabase();
    await database.update(
      'local_preferences',
      {'is_dirty': 0},
      where: 'owner_phone_number = ? AND preference_key = ? AND value_json = ?',
      whereArgs: [
        ownerPhoneNumber.trim(),
        key.trim(),
        jsonEncode(expectedValue),
      ],
    );
  }

  Future<void> upsertOfflineMapRegion(LocalOfflineMapRegion region) async {
    final database = await _openDatabase();
    await database.insert('offline_map_regions', {
      'trail_id': region.trailId,
      'region_id': region.regionId,
      'style_uri': region.styleUri,
      'bounds_json': jsonEncode(region.bounds),
      'min_zoom': region.minZoom,
      'max_zoom': region.maxZoom,
      'status': region.status,
      'completed_resource_count': region.completedResourceCount,
      'required_resource_count': region.requiredResourceCount,
      'completed_bytes': region.completedBytes,
      'downloaded_at': region.downloadedAt?.toUtc().toIso8601String(),
      'updated_at': region.updatedAt.toUtc().toIso8601String(),
      'last_error': region.lastError,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<LocalOfflineMapRegion>> loadOfflineMapRegions() async {
    final database = await _openDatabase();
    final rows = await database.query(
      'offline_map_regions',
      orderBy: 'updated_at DESC',
    );
    return rows.map(LocalOfflineMapRegion.fromRow).toList();
  }

  Future<LocalOfflineMapRegion?> loadOfflineMapRegion(String trailId) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'offline_map_regions',
      where: 'trail_id = ?',
      whereArgs: [trailId],
      limit: 1,
    );
    return rows.isEmpty ? null : LocalOfflineMapRegion.fromRow(rows.first);
  }

  Future<void> deleteOfflineMapRegion(String trailId) async {
    final database = await _openDatabase();
    await database.delete(
      'offline_map_regions',
      where: 'trail_id = ?',
      whereArgs: [trailId],
    );
  }

  Future<void> replaceStaticHazardDataset({
    required List<LocalStaticHazard> hazards,
    required List<LocalTrailHazardMatch> matches,
    required int scannedTrailCount,
    Iterable<String> scannedTrailIds = const [],
  }) async {
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      await transaction.delete('trail_hazard_matches');
      await transaction.delete('hazard_feature_rtree');
      await transaction.delete('hazard_features');
      await transaction.delete(
        'local_preferences',
        where: 'owner_phone_number = ? AND preference_key LIKE ?',
        whereArgs: ['', '$_staticHazardScanPreferencePrefix%'],
      );

      final localIds = <String, int>{};
      for (final hazard in hazards) {
        final localId = await transaction.insert('hazard_features', {
          'hazard_id': hazard.hazardId,
          'hazard_type': hazard.hazardType,
          'title': hazard.title,
          'description': hazard.description,
          'latitude': hazard.latitude,
          'longitude': hazard.longitude,
          'severity': hazard.severity,
          'confidence': hazard.confidence,
          'source_name': hazard.sourceName,
          'source_url': hazard.sourceUrl,
          'source_feature_id': hazard.sourceFeatureId,
          'safety_guidance': hazard.safetyGuidance,
          'source_updated_at': hazard.sourceUpdatedAt
              ?.toUtc()
              .toIso8601String(),
          'downloaded_at': hazard.downloadedAt.toUtc().toIso8601String(),
          'expires_at': hazard.expiresAt?.toUtc().toIso8601String(),
        });
        localIds[hazard.hazardId] = localId;
        await transaction.insert('hazard_feature_rtree', {
          'local_id': localId,
          'min_longitude': hazard.longitude,
          'max_longitude': hazard.longitude,
          'min_latitude': hazard.latitude,
          'max_latitude': hazard.latitude,
        });
      }

      for (final match in matches) {
        if (!localIds.containsKey(match.hazard.hazardId)) continue;
        await transaction.insert('trail_hazard_matches', {
          'trail_id': match.trailId,
          'hazard_id': match.hazard.hazardId,
          'relationship': match.relationship,
          'distance_meters': match.distanceMeters,
          'route_progress': match.routeProgress,
          'computed_at': match.computedAt.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      final downloadedAt = hazards.isEmpty
          ? DateTime.now().toUtc()
          : hazards
                .map((hazard) => hazard.downloadedAt.toUtc())
                .reduce((a, b) => a.isAfter(b) ? a : b);
      await transaction.insert('local_preferences', {
        'owner_phone_number': '',
        'preference_key': 'static_hazard_dataset_metadata',
        'value_json': jsonEncode({
          'hazardCount': hazards.length,
          'trailCount': scannedTrailCount,
          'downloadedAt': downloadedAt.toIso8601String(),
        }),
        'is_dirty': 0,
        'updated_at': downloadedAt.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final hazardCountByTrail = <String, int>{};
      for (final match in matches) {
        hazardCountByTrail.update(
          match.trailId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      for (final trailId in scannedTrailIds.map((id) => id.trim())) {
        if (trailId.isEmpty) continue;
        await transaction.insert('local_preferences', {
          'owner_phone_number': '',
          'preference_key': '$_staticHazardScanPreferencePrefix$trailId',
          'value_json': jsonEncode({
            'trailId': trailId,
            'hazardCount': hazardCountByTrail[trailId] ?? 0,
            'scannedAt': downloadedAt.toIso8601String(),
          }),
          'is_dirty': 0,
          'updated_at': downloadedAt.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<DateTime?> loadStaticHazardScanTime(String trailId) async {
    final normalizedTrailId = trailId.trim();
    if (normalizedTrailId.isEmpty) return null;
    final database = await _openDatabase();
    final rows = await database.query(
      'local_preferences',
      columns: ['value_json', 'updated_at'],
      where: 'owner_phone_number = ? AND preference_key = ?',
      whereArgs: ['', '$_staticHazardScanPreferencePrefix$normalizedTrailId'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final decoded = jsonDecode(rows.single['value_json'] as String? ?? '{}');
      if (decoded is Map) {
        final scannedAt = DateTime.tryParse(
          decoded['scannedAt']?.toString() ?? '',
        );
        if (scannedAt != null) return scannedAt;
      }
    } catch (_) {}
    return DateTime.tryParse(rows.single['updated_at'] as String? ?? '');
  }

  /// Replaces only one trail's mapped hazards while preserving every other
  /// trail's offline dataset. A scan preference is written even for zero
  /// results so opening an empty trail does not repeatedly hit Mapbox.
  Future<void> replaceStaticHazardsForTrail({
    required String trailId,
    required List<LocalStaticHazard> hazards,
    required List<LocalTrailHazardMatch> matches,
    required DateTime scannedAt,
  }) async {
    final normalizedTrailId = trailId.trim();
    if (normalizedTrailId.isEmpty) {
      throw ArgumentError.value(trailId, 'trailId', 'must not be empty');
    }
    final database = await _openDatabase();
    final scannedAtUtc = scannedAt.toUtc();
    await database.transaction((transaction) async {
      final previousHazards = await transaction.rawQuery(
        '''
        SELECT hazards.hazard_id, hazards.local_id
        FROM trail_hazard_matches AS matches
        JOIN hazard_features AS hazards
          ON hazards.hazard_id = matches.hazard_id
        WHERE matches.trail_id = ?
        ''',
        [normalizedTrailId],
      );
      await transaction.delete(
        'trail_hazard_matches',
        where: 'trail_id = ?',
        whereArgs: [normalizedTrailId],
      );
      for (final row in previousHazards) {
        final hazardId = row['hazard_id'] as String? ?? '';
        final referenceCount = Sqflite.firstIntValue(
          await transaction.rawQuery(
            'SELECT COUNT(*) FROM trail_hazard_matches WHERE hazard_id = ?',
            [hazardId],
          ),
        );
        if ((referenceCount ?? 0) != 0) continue;
        await transaction.delete(
          'hazard_feature_rtree',
          where: 'local_id = ?',
          whereArgs: [row['local_id']],
        );
        await transaction.delete(
          'hazard_features',
          where: 'hazard_id = ?',
          whereArgs: [hazardId],
        );
      }

      final localIds = <String, int>{};
      for (final hazard in hazards) {
        final localId = await transaction.insert('hazard_features', {
          'hazard_id': hazard.hazardId,
          'hazard_type': hazard.hazardType,
          'title': hazard.title,
          'description': hazard.description,
          'latitude': hazard.latitude,
          'longitude': hazard.longitude,
          'severity': hazard.severity,
          'confidence': hazard.confidence,
          'source_name': hazard.sourceName,
          'source_url': hazard.sourceUrl,
          'source_feature_id': hazard.sourceFeatureId,
          'safety_guidance': hazard.safetyGuidance,
          'source_updated_at': hazard.sourceUpdatedAt
              ?.toUtc()
              .toIso8601String(),
          'downloaded_at': hazard.downloadedAt.toUtc().toIso8601String(),
          'expires_at': hazard.expiresAt?.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        localIds[hazard.hazardId] = localId;
        await transaction.insert('hazard_feature_rtree', {
          'local_id': localId,
          'min_longitude': hazard.longitude,
          'max_longitude': hazard.longitude,
          'min_latitude': hazard.latitude,
          'max_latitude': hazard.latitude,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final match in matches) {
        if (match.trailId.trim() != normalizedTrailId ||
            !localIds.containsKey(match.hazard.hazardId)) {
          continue;
        }
        await transaction.insert('trail_hazard_matches', {
          'trail_id': normalizedTrailId,
          'hazard_id': match.hazard.hazardId,
          'relationship': match.relationship,
          'distance_meters': match.distanceMeters,
          'route_progress': match.routeProgress,
          'computed_at': match.computedAt.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await transaction.insert('local_preferences', {
        'owner_phone_number': '',
        'preference_key':
            '$_staticHazardScanPreferencePrefix$normalizedTrailId',
        'value_json': jsonEncode({
          'trailId': normalizedTrailId,
          'hazardCount': matches.length,
          'scannedAt': scannedAtUtc.toIso8601String(),
        }),
        'is_dirty': 0,
        'updated_at': scannedAtUtc.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<LocalTrailHazardMatch>> loadStaticHazardsForTrail(
    String trailId,
  ) async {
    final database = await _openDatabase();
    final rows = await database.rawQuery(
      '''
      SELECT hazards.*, matches.trail_id, matches.relationship,
             matches.distance_meters, matches.route_progress,
             matches.computed_at
      FROM trail_hazard_matches AS matches
      JOIN hazard_features AS hazards
        ON hazards.hazard_id = matches.hazard_id
      WHERE matches.trail_id = ?
      ORDER BY matches.route_progress, matches.distance_meters
      ''',
      [trailId.trim()],
    );
    return rows
        .map(
          (row) => LocalTrailHazardMatch(
            trailId: row['trail_id'] as String? ?? '',
            hazard: LocalStaticHazard.fromRow(row),
            relationship: row['relationship'] as String? ?? 'nearby',
            distanceMeters: (row['distance_meters'] as num?)?.toDouble() ?? 0,
            routeProgress: (row['route_progress'] as num?)?.toDouble() ?? 0,
            computedAt:
                DateTime.tryParse(row['computed_at'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
        )
        .toList(growable: false);
  }

  Future<LocalHazardDatasetSummary> loadStaticHazardDatasetSummary() async {
    final database = await _openDatabase();
    final rows = await database.rawQuery('''
      SELECT COUNT(*) AS hazard_count,
             COUNT(DISTINCT matches.trail_id) AS trail_count,
             MAX(hazards.downloaded_at) AS downloaded_at
      FROM hazard_features AS hazards
      LEFT JOIN trail_hazard_matches AS matches
        ON matches.hazard_id = hazards.hazard_id
    ''');
    final row = rows.single;
    final scanRows = await database.rawQuery(
      '''
      SELECT COUNT(*) AS trail_count, MAX(updated_at) AS scanned_at
      FROM local_preferences
      WHERE owner_phone_number = ? AND preference_key LIKE ?
      ''',
      ['', '$_staticHazardScanPreferencePrefix%'],
    );
    final scanRow = scanRows.single;
    final metadataRows = await database.query(
      'local_preferences',
      columns: ['value_json'],
      where: 'owner_phone_number = ? AND preference_key = ?',
      whereArgs: ['', 'static_hazard_dataset_metadata'],
      limit: 1,
    );
    Map<String, dynamic> metadata = const {};
    if (metadataRows.isNotEmpty) {
      final decoded = jsonDecode(
        metadataRows.single['value_json'] as String? ?? '{}',
      );
      if (decoded is Map) metadata = Map<String, dynamic>.from(decoded);
    }
    final storedHazardCount = (row['hazard_count'] as num?)?.toInt() ?? 0;
    final storedTrailCount = (row['trail_count'] as num?)?.toInt() ?? 0;
    final scannedTrailCount = (scanRow['trail_count'] as num?)?.toInt() ?? 0;
    return LocalHazardDatasetSummary(
      hazardCount: math.max(
        storedHazardCount,
        (metadata['hazardCount'] as num?)?.toInt() ?? 0,
      ),
      trailCount: math.max(
        math.max(storedTrailCount, scannedTrailCount),
        (metadata['trailCount'] as num?)?.toInt() ?? 0,
      ),
      downloadedAt:
          DateTime.tryParse(row['downloaded_at'] as String? ?? '') ??
          DateTime.tryParse(scanRow['scanned_at'] as String? ?? '') ??
          DateTime.tryParse(metadata['downloadedAt']?.toString() ?? ''),
    );
  }

  Future<void> clearStaticHazardDataset() async {
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      await transaction.delete('trail_hazard_matches');
      await transaction.delete('hazard_feature_rtree');
      await transaction.delete('hazard_features');
      await transaction.delete(
        'local_preferences',
        where:
            'owner_phone_number = ? AND (preference_key = ? OR preference_key LIKE ?)',
        whereArgs: [
          '',
          'static_hazard_dataset_metadata',
          '$_staticHazardScanPreferencePrefix%',
        ],
      );
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
          ORDER BY is_starred DESC, received_at DESC
          LIMIT 500
        )
      ''',
      whereArgs: [ownerPhoneNumber, ownerPhoneNumber],
    );
  }

  Future<List<DeviceNotificationRecord>> loadDeviceNotifications({
    required String ownerPhoneNumber,
    int limit = 500,
  }) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'device_notifications',
      where: 'owner_phone_number = ?',
      whereArgs: [ownerPhoneNumber],
      orderBy: 'is_starred DESC, received_at DESC',
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

  Future<void> markAllDeviceNotificationsOpened({
    required String ownerPhoneNumber,
  }) async {
    final database = await _openDatabase();
    await database.update(
      'device_notifications',
      {'opened_at': DateTime.now().toUtc().toIso8601String()},
      where: 'owner_phone_number = ? AND opened_at IS NULL',
      whereArgs: [ownerPhoneNumber],
    );
  }

  Future<void> setDeviceNotificationStarred({
    required String ownerPhoneNumber,
    required int id,
    required bool isStarred,
  }) async {
    final database = await _openDatabase();
    await database.update(
      'device_notifications',
      {'is_starred': isStarred ? 1 : 0},
      where: 'owner_phone_number = ? AND id = ?',
      whereArgs: [ownerPhoneNumber, id],
    );
  }

  Future<void> deleteDeviceNotification({
    required String ownerPhoneNumber,
    required int id,
  }) async {
    final database = await _openDatabase();
    await database.delete(
      'device_notifications',
      where: 'owner_phone_number = ? AND id = ?',
      whereArgs: [ownerPhoneNumber, id],
    );
  }

  Future<void> clearDeviceNotifications({
    required String ownerPhoneNumber,
    bool includeStarred = true,
  }) async {
    final database = await _openDatabase();
    await database.delete(
      'device_notifications',
      where: includeStarred
          ? 'owner_phone_number = ?'
          : 'owner_phone_number = ? AND is_starred = 0',
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
    final existingOpening = _openingDatabase;
    if (existingOpening != null) {
      return existingOpening;
    }

    _configureDatabaseFactory();
    final databaseDirectory = await getDatabasesPath();
    final databasePath =
        _databasePathOverride ??
        path.join(databaseDirectory, 'hiker_circle.db');
    if (_databasePathOverride == null) {
      final sharedOpening = _sharedDefaultDatabaseOpening;
      if (sharedOpening != null) {
        _openingDatabase = sharedOpening;
        try {
          final database = await sharedOpening;
          _database = database;
          return database;
        } finally {
          _openingDatabase = null;
        }
      }
    }
    if (_loggedDatabasePaths.add(databasePath)) {
      debugPrint('HikerCircle SQLite database path: $databasePath');
    }

    final opening = openDatabase(
      databasePath,
      version: 28,
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
        await database.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS location_sample_identity ON local_location_points(owner_phone_number, session_id, sample_key)',
        );
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
        await _createAchievementProgressCacheTable(database);
        await _createOfflineFirstTables(database);
        await _createStaticHazardTables(database);
        await _createButtonDebugTables(database);
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
        if (oldVersion < 23) {
          // Some legacy and partially restored databases can report a recent
          // version while omitting this optional local-only table. Recreate it
          // before applying the v23 column migration so startup remains safe.
          await _createDeviceNotificationsTable(database);
          await _addColumnIfMissing(
            database,
            tableName: 'device_notifications',
            columnName: 'is_starred',
            definition: 'INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 24) {
          await _createAchievementProgressCacheTable(database);
        }
        if (oldVersion < 25) {
          // Some recovery/fixture databases contain only the tables relevant
          // to their original version. Recreate optional tables before the
          // column and primary-key migration so partial databases still open.
          await _createPendingMessagesTable(database);
          await _addColumnIfMissing(
            database,
            tableName: 'pending_messages',
            columnName: 'owner_phone_number',
            definition: "TEXT NOT NULL DEFAULT ''",
          );
          await _addColumnIfMissing(
            database,
            tableName: 'pending_messages',
            columnName: 'updated_at',
            definition: 'TEXT',
          );
          await _addColumnIfMissing(
            database,
            tableName: 'pending_messages',
            columnName: 'last_error',
            definition: "TEXT NOT NULL DEFAULT ''",
          );
          await database.rawUpdate('''
            UPDATE pending_messages
            SET owner_phone_number = sender_phone
            WHERE TRIM(owner_phone_number) = ''
          ''');
          final readReceiptTable = await database.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'chat_read_receipts'",
          );
          final usersTable = await database.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'users'",
          );
          if (readReceiptTable.isEmpty) {
            await _createChatReadReceiptsTable(database);
          } else {
            await database.execute(
              'ALTER TABLE chat_read_receipts RENAME TO chat_read_receipts_v24',
            );
            await _createChatReadReceiptsTable(database);
            final receiptOwnerExpression = usersTable.isEmpty
                ? "''"
                : "COALESCE((SELECT phone_number FROM users ORDER BY signed_in_at DESC LIMIT 1), '')";
            await database.execute('''
              INSERT OR REPLACE INTO chat_read_receipts (
                owner_phone_number, chat_id, last_read_at, is_synced
              )
              SELECT $receiptOwnerExpression,
                     chat_id,
                     last_read_at,
                     is_synced
              FROM chat_read_receipts_v24
            ''');
            await database.execute('DROP TABLE chat_read_receipts_v24');
          }
          await _createOfflineFirstTables(database);
        }
        if (oldVersion < 26) {
          await _createStaticHazardTables(database);
        }
        if (oldVersion < 27) {
          await _createButtonDebugTables(database);
        }
        if (oldVersion < 28) {
          await _createSafetyTables(database);
          await _addColumnIfMissing(
            database,
            tableName: 'local_location_points',
            columnName: 'sample_key',
            definition: 'TEXT',
          );
          await _addColumnIfMissing(
            database,
            tableName: 'local_location_points',
            columnName: 'fix_captured_at',
            definition: 'TEXT',
          );
          await database.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS location_sample_identity ON local_location_points(owner_phone_number, session_id, sample_key)',
          );
        }
      },
    );
    _openingDatabase = opening;
    if (_databasePathOverride == null) {
      _sharedDefaultDatabaseOpening = opening;
    }
    try {
      final database = await opening;
      _database = database;
      return database;
    } catch (_) {
      if (identical(_sharedDefaultDatabaseOpening, opening)) {
        _sharedDefaultDatabaseOpening = null;
      }
      rethrow;
    } finally {
      _openingDatabase = null;
    }
  }

  @visibleForTesting
  Future<void> close() async {
    final database = _database;
    _database = null;
    _openingDatabase = null;
    if (_databasePathOverride == null) {
      _sharedDefaultDatabaseOpening = null;
    }
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
    DateTime? fixCapturedAt,
  }) async {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId', 'must not be empty');
    }
    if (!_isValidCoordinate(latitude, longitude)) {
      throw ArgumentError('Location coordinates are outside valid GPS bounds.');
    }
    final database = await _openDatabase();
    final sampledAt = DateTime.fromMillisecondsSinceEpoch(
      (recordedAt ?? DateTime.now()).millisecondsSinceEpoch,
      isUtc: true,
    );
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
      'recorded_at': sampledAt.toIso8601String(),
      'sample_key': sampledAt.millisecondsSinceEpoch.toString(),
      'fix_captured_at': fixCapturedAt?.toUtc().toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
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

  Future<int> countUnsentLocationPoints(
    String sessionId, {
    String? ownerPhoneNumber,
  }) async {
    final database = await _openDatabase();
    final result = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM local_location_points
      WHERE session_id = ?
        ${ownerPhoneNumber != null ? 'AND owner_phone_number = ?' : ''}
        AND is_synced = 0
        AND latitude BETWEEN -90 AND 90
        AND longitude BETWEEN -180 AND 180
      ''',
      [sessionId, if (ownerPhoneNumber != null) ownerPhoneNumber],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<LocalLocationPoint>> loadUnsentLocationPoints({
    required String sessionId,
    String? ownerPhoneNumber,
    int limit = 200,
  }) async {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty || limit <= 0) {
      return const [];
    }
    final database = await _openDatabase();
    final rows = await database.query(
      'local_location_points',
      where:
          '''
        session_id = ?
        ${ownerPhoneNumber != null ? 'AND owner_phone_number = ?' : ''}
        AND is_synced = 0
        AND latitude BETWEEN -90 AND 90
        AND longitude BETWEEN -180 AND 180
      ''',
      whereArgs: [
        normalizedSessionId,
        if (ownerPhoneNumber != null) ownerPhoneNumber,
      ],
      orderBy: 'recorded_at ASC, id ASC',
      limit: limit,
    );
    return rows
        .map(LocalLocationPoint.fromRow)
        .where((point) => point.hasValidCoordinate)
        .toList();
  }

  Future<List<LocalLocationPoint>> loadLocationPoints({
    required String sessionId,
    required String ownerPhoneNumber,
  }) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'local_location_points',
      where: 'session_id = ? AND owner_phone_number = ?',
      whereArgs: [sessionId, ownerPhoneNumber],
      orderBy: 'recorded_at ASC, id ASC',
    );
    return rows
        .map(LocalLocationPoint.fromRow)
        .where((p) => p.hasValidCoordinate)
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
        sample_key TEXT,
        fix_captured_at TEXT,
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
        attachment_json TEXT DEFAULT '',
        owner_phone_number TEXT NOT NULL DEFAULT '',
        updated_at TEXT,
        last_error TEXT NOT NULL DEFAULT ''
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

  Future<void> _createAchievementProgressCacheTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS achievement_progress_cache (
        owner_phone_number TEXT PRIMARY KEY,
        content_hash TEXT NOT NULL DEFAULT '',
        payload_json TEXT NOT NULL,
        cached_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createOfflineFirstTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS cached_entities (
        owner_phone_number TEXT NOT NULL DEFAULT '',
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        parent_id TEXT NOT NULL DEFAULT '',
        payload_json TEXT NOT NULL,
        source_updated_at TEXT,
        cached_at TEXT NOT NULL,
        expires_at TEXT,
        PRIMARY KEY (owner_phone_number, entity_type, entity_id)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_cached_entities_owner_type_parent
      ON cached_entities(owner_phone_number, entity_type, parent_id, source_updated_at DESC)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_outbox (
        operation_id TEXT PRIMARY KEY,
        owner_phone_number TEXT NOT NULL,
        operation_type TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        idempotency_key TEXT NOT NULL UNIQUE,
        payload_json TEXT NOT NULL,
        local_file_path TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'pending',
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at TEXT,
        last_error TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_outbox_owner_status_next
      ON sync_outbox(owner_phone_number, status, next_attempt_at, created_at)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS local_preferences (
        owner_phone_number TEXT NOT NULL,
        preference_key TEXT NOT NULL,
        value_json TEXT NOT NULL,
        is_dirty INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (owner_phone_number, preference_key)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_local_preferences_owner_dirty
      ON local_preferences(owner_phone_number, is_dirty, updated_at)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS offline_map_regions (
        trail_id TEXT PRIMARY KEY,
        region_id TEXT NOT NULL UNIQUE,
        style_uri TEXT NOT NULL,
        bounds_json TEXT NOT NULL,
        min_zoom INTEGER NOT NULL,
        max_zoom INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        completed_resource_count INTEGER NOT NULL DEFAULT 0,
        required_resource_count INTEGER NOT NULL DEFAULT 0,
        completed_bytes INTEGER NOT NULL DEFAULT 0,
        downloaded_at TEXT,
        updated_at TEXT NOT NULL,
        last_error TEXT NOT NULL DEFAULT ''
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_offline_map_regions_status_updated
      ON offline_map_regions(status, updated_at DESC)
    ''');
    await _createPendingMessagesTable(database);
    await _createChatReadReceiptsTable(database);
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_pending_messages_owner_status_created
      ON pending_messages(owner_phone_number, send_status, created_at)
    ''');
  }

  Future<void> _createStaticHazardTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS hazard_features (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        hazard_id TEXT NOT NULL UNIQUE,
        hazard_type TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        severity TEXT NOT NULL,
        confidence TEXT NOT NULL,
        source_name TEXT NOT NULL,
        source_url TEXT NOT NULL DEFAULT '',
        source_feature_id TEXT NOT NULL DEFAULT '',
        safety_guidance TEXT NOT NULL,
        source_updated_at TEXT,
        downloaded_at TEXT NOT NULL,
        expires_at TEXT
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_hazard_features_type_downloaded
      ON hazard_features(hazard_type, downloaded_at DESC)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS trail_hazard_matches (
        trail_id TEXT NOT NULL,
        hazard_id TEXT NOT NULL,
        relationship TEXT NOT NULL,
        distance_meters REAL NOT NULL,
        route_progress REAL NOT NULL,
        computed_at TEXT NOT NULL,
        PRIMARY KEY (trail_id, hazard_id),
        FOREIGN KEY (hazard_id) REFERENCES hazard_features(hazard_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_trail_hazard_matches_route
      ON trail_hazard_matches(trail_id, route_progress, distance_meters)
    ''');
    // Android's system SQLite is not guaranteed to be compiled with the
    // optional RTREE module. Keep the existing table name/data contract but
    // use a portable table: current hazard reads are trail-id based, while
    // these bounds remain available for a future indexed bounding-box query.
    await database.execute('''
      CREATE TABLE IF NOT EXISTS hazard_feature_rtree (
        local_id INTEGER PRIMARY KEY,
        min_longitude REAL NOT NULL,
        max_longitude REAL NOT NULL,
        min_latitude REAL NOT NULL,
        max_latitude REAL NOT NULL,
        FOREIGN KEY (local_id) REFERENCES hazard_features(local_id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_hazard_feature_bounds_longitude
      ON hazard_feature_rtree(min_longitude, max_longitude)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_hazard_feature_bounds_latitude
      ON hazard_feature_rtree(min_latitude, max_latitude)
    ''');
  }

  Future<void> _createChatReadReceiptsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS chat_read_receipts (
        chat_id TEXT NOT NULL,
        owner_phone_number TEXT NOT NULL DEFAULT '',
        last_read_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (owner_phone_number, chat_id)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_chat_read_receipts_owner_sync
      ON chat_read_receipts(owner_phone_number, is_synced, last_read_at)
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
        source TEXT NOT NULL DEFAULT 'fcm',
        is_starred INTEGER NOT NULL DEFAULT 0
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
    String ownerPhoneNumber = '',
    bool synced = false,
  }) async {
    final database = await _openDatabase();
    await database.insert('chat_read_receipts', {
      'chat_id': chatId,
      'owner_phone_number': ownerPhoneNumber.trim(),
      'last_read_at': lastReadAt.toUtc().toIso8601String(),
      'is_synced': synced ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<DateTime?> loadChatReadReceipt(
    String chatId, {
    String ownerPhoneNumber = '',
  }) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'chat_read_receipts',
      columns: ['last_read_at', 'is_synced'],
      where: 'owner_phone_number = ? AND chat_id = ?',
      whereArgs: [ownerPhoneNumber.trim(), chatId],
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['last_read_at'] as String? ?? '');
  }

  Future<Map<String, DateTime>> loadAllChatReadReceipts({
    String ownerPhoneNumber = '',
  }) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'chat_read_receipts',
      where: 'owner_phone_number = ?',
      whereArgs: [ownerPhoneNumber.trim()],
    );
    final result = <String, DateTime>{};
    for (final row in rows) {
      final ts = DateTime.tryParse(row['last_read_at'] as String? ?? '');
      if (ts != null) {
        result[row['chat_id'] as String] = ts;
      }
    }
    return result;
  }

  Future<List<String>> loadUnsyncedReadReceiptChatIds({
    String ownerPhoneNumber = '',
  }) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'chat_read_receipts',
      columns: ['chat_id'],
      where: 'owner_phone_number = ? AND is_synced = 0',
      whereArgs: [ownerPhoneNumber.trim()],
    );
    return rows.map((r) => r['chat_id'] as String).toList();
  }

  Future<void> markChatReadReceiptSynced(
    String chatId, {
    String ownerPhoneNumber = '',
  }) async {
    final database = await _openDatabase();
    await database.update(
      'chat_read_receipts',
      {'is_synced': 1},
      where: 'owner_phone_number = ? AND chat_id = ?',
      whereArgs: [ownerPhoneNumber.trim(), chatId],
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
    String? ownerPhoneNumber,
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
      'owner_phone_number': (ownerPhoneNumber ?? senderPhone).trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'last_error': '',
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

  Future<List<Map<String, dynamic>>> loadPendingMessages({
    String? ownerPhoneNumber,
  }) async {
    final database = await _openDatabase();
    final owner = ownerPhoneNumber?.trim();
    return database.query(
      'pending_messages',
      where: owner == null || owner.isEmpty
          ? 'send_status IN (?, ?, ?)'
          : 'owner_phone_number = ? AND send_status IN (?, ?, ?)',
      whereArgs: owner == null || owner.isEmpty
          ? ['pending', 'unsent', 'failed']
          : [owner, 'pending', 'unsent', 'failed'],
      orderBy: 'created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> loadAllLocalMessagesForChat(
    String chatId, {
    String? ownerPhoneNumber,
  }) async {
    final database = await _openDatabase();
    final owner = ownerPhoneNumber?.trim();
    return database.query(
      'pending_messages',
      where: owner == null || owner.isEmpty
          ? 'chat_id = ?'
          : 'owner_phone_number = ? AND chat_id = ?',
      whereArgs: owner == null || owner.isEmpty ? [chatId] : [owner, chatId],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> updateLocalMessageStatus(
    String localId,
    String status, {
    String? firestoreDocId,
    String lastError = '',
  }) async {
    final database = await _openDatabase();
    final values = <String, dynamic>{
      'send_status': status,
      'last_error': lastError,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
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
    String chatId, {
    String? ownerPhoneNumber,
  }) async {
    final database = await _openDatabase();
    final owner = ownerPhoneNumber?.trim();
    return database.query(
      'pending_messages',
      where: owner == null || owner.isEmpty
          ? 'chat_id = ? AND send_status IN (?, ?, ?)'
          : 'owner_phone_number = ? AND chat_id = ? AND send_status IN (?, ?, ?)',
      whereArgs: owner == null || owner.isEmpty
          ? [chatId, 'pending', 'unsent', 'failed']
          : [owner, chatId, 'pending', 'unsent', 'failed'],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> incrementPendingMessageRetry(String localId) async {
    final database = await _openDatabase();
    await database.rawUpdate(
      '''UPDATE pending_messages
         SET retry_count = retry_count + 1, send_status = 'failed',
             updated_at = ?
         WHERE local_id = ?''',
      [DateTime.now().toUtc().toIso8601String(), localId],
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
    this.fixCapturedAt,
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
      fixCapturedAt: DateTime.tryParse(row['fix_captured_at'] as String? ?? ''),
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
  final DateTime? fixCapturedAt;
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
    required this.isStarred,
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
      isStarred: (row['is_starred'] as int? ?? 0) == 1,
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
  final bool isStarred;

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

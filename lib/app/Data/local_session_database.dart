// LocalSessionDatabase owns encrypted mobile SQLite, incremental schema upgrades and operational
// offline hike, SOS, chat and cache records.
import '../../core/services/content_hash.dart';
import '../../circle/Model/community_post_limits.dart';
import '../../achievements/Model/achievement_progress.dart';
import '../../achievements/Model/achievement_catalog.dart';
import '../../achievements/Model/achievement_notification.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

import '../../home/Model/hike_session_models.dart';
import '../../feedback/Model/feedback_saved_draft.dart';
import '../../trail/Model/local_caution_report.dart';
import '../../sos/Model/nearby_sos_event.dart';
import '../../sos/Model/sos_models.dart';
import '../Model/app_session.dart';
import 'secure_local_database.dart';

part 'local_community_database.dart';
part 'local_planning_database.dart';
part 'local_achievement_database.dart';
part 'local_caution_database.dart';

/// Represents local achievement progress cache.
@immutable
class LocalAchievementProgressCache {
  /// Creates local achievement progress cache.
  const LocalAchievementProgressCache({
    required this.contentHash,
    required this.rows,
    required this.cachedAt,
  });

  final String contentHash;
  final List<Map<String, dynamic>> rows;
  final DateTime cachedAt;
}

/// Represents local cached entity.
@immutable
class LocalCachedEntity {
  /// Creates local cached entity.
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

  /// Creates local cached entity using from row.
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

/// Represents local sync operation.
@immutable
class LocalSyncOperation {
  /// Creates local sync operation.
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

  /// Creates local sync operation using from row.
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

/// Represents local static hazard.
@immutable
class LocalStaticHazard {
  /// Creates local static hazard.
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

  /// Creates local static hazard using from row.
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

/// Represents local trail hazard match.
@immutable
class LocalTrailHazardMatch {
  /// Creates local trail hazard match.
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

/// Represents local hazard dataset summary.
@immutable
class LocalHazardDatasetSummary {
  /// Creates local hazard dataset summary.
  const LocalHazardDatasetSummary({
    required this.hazardCount,
    required this.trailCount,
    this.downloadedAt,
  });

  final int hazardCount;
  final int trailCount;
  final DateTime? downloadedAt;

  /// Returns is downloaded.
  bool get isDownloaded => downloadedAt != null;
}

/// Represents local session database.
class LocalSessionDatabase {
  /// Creates local session database.
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
  static final _deviceNotificationChanges =
      StreamController<String>.broadcast();

  /// Returns device notification changes.
  static Stream<String> get deviceNotificationChanges =>
      _deviceNotificationChanges.stream;

  FeedbackSavedDraft _feedbackDraftFromRow(Map<String, Object?> row) =>
      FeedbackSavedDraft(
        id: row['draft_id'] as String,
        uid: row['owner'] as String,
        category: row['category'] as String,
        message: row['message'] as String,
        screenshot: row['screenshot'] as Uint8List?,
        submissionAttempted: row['submission_attempted'] == 1,
        revision: row['revision'] as int,
      );

  String _feedbackScreenshotHash(Uint8List? bytes) =>
      bytes == null ? '' : crypto.sha256.convert(bytes).toString();

  Future<FeedbackSavedDraft?> loadFeedbackDraft(String owner) async {
    final database = await _openDatabase();
    // Query local: owner's feedback draft
    final rows = await database.query(
      'feedback_drafts',
      where: 'owner = ? AND status = ?',
      whereArgs: [owner, 'active'],
      limit: 1,
    );
    return rows.isEmpty ? null : _feedbackDraftFromRow(rows.single);
  }

  /// Open is atomic across multiple forms and never replaces an existing draft.
  Future<FeedbackSavedDraft> openFeedbackDraft(
    FeedbackSavedDraft initial,
  ) async {
    final database = await _openDatabase();
    return database.transaction((transaction) async {
      // Query local: open feedback draft
      final rows = await transaction.query(
        'feedback_drafts',
        where: 'owner = ?',
        whereArgs: [initial.uid],
        limit: 1,
      );
      if (rows.isNotEmpty && rows.single['status'] == 'active') {
        return _feedbackDraftFromRow(rows.single);
      }
      final revision = rows.isEmpty ? 0 : (rows.single['revision'] as int) + 1;
      final saved = {
        'owner': initial.uid,
        'draft_id': initial.id,
        'status': 'active',
        'revision': revision,
        'category': initial.category,
        'message': initial.message,
        'screenshot': initial.screenshot,
        'screenshot_hash': _feedbackScreenshotHash(initial.screenshot),
        'submission_attempted': initial.submissionAttempted ? 1 : 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      // Update local: create feedback draft
      await transaction.insert(
        'feedback_drafts',
        saved,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return _feedbackDraftFromRow(saved);
    });
  }

  /// CAS saves keep stale debounce callbacks from resurrecting a sent form.
  Future<FeedbackSavedDraft?> saveFeedbackDraft(
    FeedbackSavedDraft draft,
  ) async {
    final database = await _openDatabase();
    final screenshotHash = _feedbackScreenshotHash(draft.screenshot);
    return database.transaction((transaction) async {
      // Query local: draft and revision
      final rows = await transaction.query(
        'feedback_drafts',
        columns: [
          'draft_id',
          'revision',
          'status',
          'category',
          'message',
          'screenshot_hash',
          'submission_attempted',
        ],
        where: 'owner = ?',
        whereArgs: [draft.uid],
        limit: 1,
      );
      if (rows.isEmpty ||
          rows.single['status'] != 'active' ||
          rows.single['draft_id'] != draft.id ||
          rows.single['revision'] != draft.revision) {
        return null;
      }
      // Once a request may have reached the server, this identity belongs to
      // its frozen payload. A late autosave cannot edit or unfreeze that report.
      if (rows.single['submission_attempted'] == 1 &&
          (!draft.submissionAttempted ||
              rows.single['category'] != draft.category ||
              rows.single['message'] != draft.message ||
              rows.single['screenshot_hash'] != screenshotHash)) {
        return null;
      }
      final changedImage = rows.single['screenshot_hash'] != screenshotHash;
      final revision = draft.revision + 1;
      // Update local: save draft and revision
      await transaction.update(
        'feedback_drafts',
        {
          'category': draft.category,
          'message': draft.message,
          'submission_attempted': draft.submissionAttempted ? 1 : 0,
          'revision': revision,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          if (changedImage) 'screenshot': draft.screenshot,
          if (changedImage) 'screenshot_hash': screenshotHash,
        },
        where: 'owner = ? AND draft_id = ? AND revision = ? AND status = ?',
        whereArgs: [draft.uid, draft.id, draft.revision, 'active'],
      );
      return FeedbackSavedDraft(
        id: draft.id,
        uid: draft.uid,
        category: draft.category,
        message: draft.message,
        screenshot: draft.screenshot,
        submissionAttempted: draft.submissionAttempted,
        revision: revision,
      );
    });
  }

  Future<bool> discardFeedbackDraft(FeedbackSavedDraft expected) async {
    final database = await _openDatabase();
    // Update local: discard feedback draft
    return await database.update(
          'feedback_drafts',
          _clearedFeedbackDraftValues(expected.revision + 1),
          where: 'owner = ? AND draft_id = ? AND revision = ? AND status = ?',
          whereArgs: [expected.uid, expected.id, expected.revision, 'active'],
        ) ==
        1;
  }

  Future<bool> acknowledgeFeedbackDraft({
    required String owner,
    required String id,
    required String category,
    required String message,
    Uint8List? screenshot,
  }) async {
    final database = await _openDatabase();
    return database.transaction((transaction) async {
      // Query local: submitted draft revision
      final rows = await transaction.query(
        'feedback_drafts',
        columns: ['revision'],
        where:
            'owner = ? AND draft_id = ? AND status = ? AND submission_attempted = 1 AND category = ? AND message = ? AND screenshot_hash = ?',
        whereArgs: [
          owner,
          id,
          'active',
          category,
          message,
          _feedbackScreenshotHash(screenshot),
        ],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      // Update local: acknowledge draft submission
      await transaction.update(
        'feedback_drafts',
        _clearedFeedbackDraftValues((rows.single['revision'] as int) + 1),
        where: 'owner = ? AND draft_id = ? AND status = ?',
        whereArgs: [owner, id, 'active'],
      );
      return true;
    });
  }

  Map<String, Object?> _clearedFeedbackDraftValues(int revision) => {
    'status': 'cleared',
    'revision': revision,
    'category': '',
    'message': '',
    'screenshot': null,
    'screenshot_hash': '',
    'submission_attempted': 0,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  /// Creates button debug session.
  Future<void> createButtonDebugSession(
    String id,
    String owner,
    DateTime start,
  ) async {
    final db = await _openDatabase();
    // Update local: create SOS button debug session
    await db.insert('button_debug_sessions', {
      'id': id,
      'owner_phone_number': owner,
      'started_at': start.toUtc().toIso8601String(),
      'status': 'recording',
    });
  }

  /// Computes append button debug entry.
  Future<void> appendButtonDebugEntry(
    String owner,
    Map<String, Object?> entry,
  ) async {
    final db = await _openDatabase();
    await db.transaction((txn) async {
      // Query local: button debug session
      final session = await txn.query(
        'button_debug_sessions',
        where: 'id = ? AND owner_phone_number = ? AND status = ?',
        whereArgs: [entry['session_id'], owner, 'recording'],
      );
      if (session.isEmpty) throw StateError('Debug session is not recording.');
      // Update local: append button debug event
      await txn.insert('button_debug_entries', entry);
    });
  }

  /// Loads button debug sessions.
  Future<List<Map<String, Object?>>> loadButtonDebugSessions(
    String owner,
  ) async {
    final db = await _openDatabase();
    // Query local: owner's button debug sessions
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

  /// Loads button debug log.
  Future<String?> loadButtonDebugLog(String owner, String id) async {
    final db = await _openDatabase();
    // Query local: button debug session by ID
    final rows = await db.query(
      'button_debug_sessions',
      columns: ['log_text'],
      where: 'owner_phone_number = ? AND id = ?',
      whereArgs: [owner, id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['log_text'] as String?;
  }

  /// Loads button debug entries.
  Future<List<Map<String, Object?>>> loadButtonDebugEntries(
    String owner,
    String id,
  ) async {
    final db = await _openDatabase();
    // Query local: debug log by session
    return db.rawQuery(
      '''
      SELECT e.* FROM button_debug_entries e
      JOIN button_debug_sessions s ON s.id = e.session_id
      WHERE s.owner_phone_number = ? AND s.id = ? ORDER BY e.sequence
    ''',
      [owner, id],
    );
  }

  /// Computes conclude button debug session.
  Future<void> concludeButtonDebugSession({
    required String owner,
    required String id,
    required DateTime endedAt,
    required String reason,
    required String logText,
    String? filePath,
  }) async {
    final db = await _openDatabase();
    // Update local: close button debug session
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

  /// Creates button debug tables.
  Future<void> _createButtonDebugTables(DatabaseExecutor db) async {
    // Update local: create button debug tables
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

  // loadSession restores only the account/profile row; pending hikes and safety queues are
  // independent.
  /// Loads session.
  Future<AppSession?> loadSession() async {
    final database = await _openDatabase();
    // Query local: saved user session
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

  // saveSession updates the signed-in profile without replacing unrelated operational tables.
  /// Saves session.
  Future<void> saveSession(AppSession session) async {
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      // Update local: replace saved user session
      await transaction.delete('users');
      await transaction.insert(
        'users',
        _sessionToRow(session),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Applies cloud-owned roles without replacing a newer local profile snapshot.
  Future<void> updateSessionRoles({
    required String ownerPhoneNumber,
    required bool isAdmin,
    required bool isSuperAdmin,
  }) async {
    final database = await _openDatabase();
    // Update local: update saved session roles
    await database.update(
      'users',
      {
        'is_admin': isAdmin || isSuperAdmin ? 1 : 0,
        'is_super_admin': isSuperAdmin ? 1 : 0,
      },
      where: 'phone_number = ?',
      whereArgs: [ownerPhoneNumber],
    );
  }

  // clearUserSessionOnly removes visible account state while preserving owner-scoped offline work.
  /// Clears user session only.
  Future<void> clearUserSessionOnly() async {
    final database = await _openDatabase();
    // Update local: clear saved session
    await database.delete('users');
  }

  /// Loads achievement progress cache.
  Future<LocalAchievementProgressCache?> loadAchievementProgressCache({
    required String ownerPhoneNumber,
  }) async {
    await AchievementCatalog.load();
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty) return null;
    final database = await _openDatabase();
    // Query local: cached achievement progress
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
          .where(
            (row) =>
                AchievementCatalog.visible(row) || row['isUnlocked'] == true,
          )
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
      // Update local: remove invalid achievement cache
      await database.delete(
        'achievement_progress_cache',
        where: 'owner_phone_number = ?',
        whereArgs: [owner],
      );
      return null;
    }
  }

  /// Saves achievement progress cache.
  Future<void> saveAchievementProgressCache({
    required String ownerPhoneNumber,
    required String contentHash,
    required List<Map<String, dynamic>> rows,
  }) async {
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty || rows.isEmpty) return;
    final database = await _openDatabase();
    // Update local: cache achievement progress
    await database.insert('achievement_progress_cache', {
      'owner_phone_number': owner,
      'content_hash': contentHash.trim(),
      'payload_json': jsonEncode(rows),
      'cached_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // saveActiveHikeSession persists the local hike snapshot before later cloud recovery or app
  // restart.
  /// Saves active hike session.
  Future<void> saveActiveHikeSession({
    required String phoneNumber,
    required ActiveHikeSession activeHike,
  }) async {
    final database = await _openDatabase();
    // Update local: save active hike
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
      // Query local: provisional hike session
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
        // Update local: replace provisional hike ID
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

  /// Computes migrate hike telemetry session id.
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

  /// Computes migrate hike telemetry session id.
  Future<void> _migrateHikeTelemetrySessionId(
    DatabaseExecutor database, {
    required String ownerPhoneNumber,
    required String oldSessionId,
    required String newSessionId,
  }) async {
    // Update local: move footprints and alerts
    await database.rawDelete(
      '''DELETE FROM footprints WHERE session_id = ? AND owner_phone_number = ? AND sample_key IS NOT NULL AND sample_key IN (SELECT sample_key FROM footprints WHERE session_id = ? AND owner_phone_number = ?)''',
      [oldSessionId, ownerPhoneNumber, newSessionId, ownerPhoneNumber],
    );
    await database.update(
      'footprints',
      {'session_id': newSessionId},
      where:
          'session_id = ? AND (owner_phone_number = ? OR owner_phone_number = ?)',
      whereArgs: [oldSessionId, ownerPhoneNumber, ''],
    );
    await database.update(
      'queued_alerts',
      {'session_id': newSessionId},
      where:
          'session_id = ? AND (owner_phone_number = ? OR owner_phone_number = ?)',
      whereArgs: [oldSessionId, ownerPhoneNumber, ''],
    );
  }

  /// Loads active hike session.
  Future<ActiveHikeSession?> loadActiveHikeSession({
    required String phoneNumber,
  }) async {
    final database = await _openDatabase();
    // Query local: owner's active hike
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
      // Query local: queued completion and GPS samples
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
          FROM footprints
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

  /// Clears active hike session.
  Future<void> clearActiveHikeSession({required String phoneNumber}) async {
    final database = await _openDatabase();
    // Query local: active hike to clear
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
      // Update local: remove saved active hike
      await transaction.delete(
        'active_hike_session',
        where: 'owner_phone_number = ?',
        whereArgs: [phoneNumber],
      );
      // Query local: pending hike completions
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

  /// Saves upcoming hikes for planning.
  Future<void> saveUpcomingHikesForPlanning({
    required String ownerPhoneNumber,
    required Iterable<UpcomingHike> upcomingHikes,
    bool pruneMissing = false,
    bool localEdit = false,
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
        // Query local: matching saved hike plan
        final existing = await transaction.query(
          'planned_hike_state',
          where: 'owner_phone_number = ? AND upcoming_hike_id = ?',
          whereArgs: [owner, entry.key],
          limit: 1,
        );
        if (!localEdit && existing.isNotEmpty) {
          final saved = _decodeJsonMap(
            existing.first['upcoming_payload_json'] as String?,
          );
          final savedDraft = saved['draft'];
          if (saved['isDeleted'] == true &&
              saved['deletedReason'] == 'user_cancelled') {
            payload.addAll({
              'isDeleted': true,
              'deletedReason': 'user_cancelled',
              'status': 'cancelled',
              'expired': true,
              'historyCategory': 'expired',
              'deletedAtLocal': saved['deletedAtLocal'],
            });
          }
          // A different cloud hash does not make it newer than preparation
          // edited on this phone. Cloud membership/timing can still refresh.
          if (savedDraft is Map &&
              stableContentHash(savedDraft) !=
                  stableContentHash(payload['draft'])) {
            payload['draft'] = Map<String, dynamic>.from(savedDraft);
          }
        }
        final initialChecklist = GearChecklistCatalog.sanitize(
          hike.draft?.completedChecklistItems ?? const <String>{},
        ).toList()..sort();
        // Update local: save hike plan
        await transaction.insert('planned_hike_state', {
          'owner_phone_number': owner,
          'upcoming_hike_id': entry.key,
          'upcoming_payload_json': jsonEncode(payload),
          'completed_checklist_json': jsonEncode(initialChecklist),
          'is_consumed': hike.teamLaunchConsumed ? 1 : 0,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await transaction.update(
          'planned_hike_state',
          {
            'upcoming_payload_json': jsonEncode(payload),
            if (hike.teamLaunchConsumed) 'is_consumed': 1,
            if (!localEdit) 'has_cloud_snapshot': 1,
            if (localEdit)
              'completed_checklist_json': jsonEncode(initialChecklist),
            'preparation_hash': _preparationHash(
              payload,
              localEdit || existing.isEmpty
                  ? initialChecklist
                  : _decodeJsonStringList(
                      existing.first['completed_checklist_json'] as String?,
                    ),
            ),
            'updated_at': now,
          },
          where: 'owner_phone_number = ? AND upcoming_hike_id = ?',
          whereArgs: [owner, entry.key],
        );
      }
      final confirmedBySchedule = <String, UpcomingHike>{
        for (final hike in hikes.values)
          if (!hike.isLocalPendingSync && !hike.isCancelledForHistory)
            _plannedHikeScheduleKey(hike): hike,
      };
      // Query local: pending and confirmed hike plans
      final savedConfirmedRows = await transaction.query(
        'planned_hike_state',
        where: 'owner_phone_number = ? AND upcoming_hike_id NOT LIKE ?',
        whereArgs: [owner, 'local_pending_%'],
      );
      for (final row in savedConfirmedRows) {
        try {
          final state = LocalPlannedHikeState.fromRow(row);
          if (state.upcomingHike.isCancelledForHistory) continue;
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
            if (pendingState.upcomingHike.isCancelledForHistory) continue;
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
            final transferredChecklist = pendingState.completedChecklistItems
                .toList();
            transferredChecklist.sort();
            // Update local: move plan to confirmed hike
            await transaction.update(
              'planned_hike_state',
              {
                'upcoming_payload_json': jsonEncode(confirmedPayload),
                'completed_checklist_json': jsonEncode(transferredChecklist),
                'preparation_hash': _preparationHash(
                  confirmedPayload,
                  transferredChecklist,
                ),
                'creation_key': pendingRow['creation_key'] ?? '',
                'join_policy': pendingRow['join_policy'] ?? 'approval',
                'reminder_preference_json':
                    pendingRow['reminder_preference_json'] ??
                    targetRows.first['reminder_preference_json'],
                'reminder_sync_pending':
                    pendingRow['reminder_sync_pending'] ?? 0,
                'is_consumed':
                    pendingState.isConsumed ||
                        targetRows.first['is_consumed'] == 1
                    ? 1
                    : 0,
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
          await transaction.update(
            'local_preferences',
            {'preference_key': 'hike_preparation_sharing:${confirmed.id}'},
            where: 'owner_phone_number = ? AND preference_key = ?',
            whereArgs: [
              owner,
              'hike_preparation_sharing:${pendingState.upcomingHike.id}',
            ],
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      if (!pruneMissing) return;
      // Query local: obsolete hike plans
      final savedRows = await transaction.query(
        'planned_hike_state',
        columns: ['upcoming_hike_id', 'upcoming_payload_json', 'is_consumed'],
        where: 'owner_phone_number = ?',
        whereArgs: [owner],
      );
      final preserved = savedRows
          .where(
            (row) =>
                row['is_consumed'] == 1 ||
                _decodeJsonMap(
                      row['upcoming_payload_json'] as String?,
                    )['deletedReason'] ==
                    'user_cancelled',
          )
          .map((row) => row['upcoming_hike_id'] as String)
          .toList();
      final preserveClause = preserved.isEmpty
          ? ''
          : ' AND upcoming_hike_id NOT IN (${List.filled(preserved.length, '?').join(',')})';
      if (hikes.isEmpty) {
        // Update local: remove obsolete plans
        await transaction.delete(
          'planned_hike_state',
          where:
              'owner_phone_number = ? AND schedule_sync_pending = 0 AND has_cloud_snapshot = 1 AND upcoming_hike_id NOT LIKE ?$preserveClause',
          whereArgs: [owner, 'local_pending_%', ...preserved],
        );
        return;
      }
      final placeholders = List.filled(hikes.length, '?').join(', ');
      await transaction.delete(
        'planned_hike_state',
        where:
            'owner_phone_number = ? AND schedule_sync_pending = 0 AND has_cloud_snapshot = 1 AND upcoming_hike_id NOT LIKE ? AND upcoming_hike_id NOT IN ($placeholders)$preserveClause',
        whereArgs: [owner, 'local_pending_%', ...hikes.keys, ...preserved],
      );
    });
  }

  /// Loads planned hike states.
  Future<List<LocalPlannedHikeState>> loadPlannedHikeStates({
    required String ownerPhoneNumber,
  }) async {
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty) return const [];
    final database = await _openDatabase();
    // Query local: owner's hike plans
    final rows = await database.query(
      'planned_hike_state',
      where: 'owner_phone_number = ?',
      whereArgs: [owner],
      orderBy: 'updated_at DESC',
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

  /// Saves planned hike checklist.
  Future<void> savePlannedHikeChecklist({
    required String ownerPhoneNumber,
    required String upcomingHikeId,
    required Iterable<String> completedItems,
  }) async {
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty || upcomingHikeId.trim().isEmpty) return;
    final items = GearChecklistCatalog.sanitize(completedItems).toList()
      ..sort();
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      final hikeId = await _resolvePlannedHikeId(
        transaction,
        owner,
        upcomingHikeId.trim(),
      );
      // Query local: hike plan checklist
      final rows = await transaction.query(
        'planned_hike_state',
        where: 'owner_phone_number = ? AND upcoming_hike_id = ?',
        whereArgs: [owner, hikeId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      // Update local: save hike checklist
      await transaction.update(
        'planned_hike_state',
        {
          'completed_checklist_json': jsonEncode(items),
          'preparation_hash': _preparationHash(
            _decodeJsonMap(rows.first['upcoming_payload_json'] as String?),
            items,
          ),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'owner_phone_number = ? AND upcoming_hike_id = ?',
        whereArgs: [owner, hikeId],
      );
    });
  }

  /// Restores visibility only when a cloud lifecycle decision rejects local cancellation.
  Future<void> setPlannedHikeConsumed(
    String owner,
    String hikeId,
    bool consumed,
  ) async {
    final db = await _openDatabase();
    // Update local: change plan consumption status
    await db.update(
      'planned_hike_state',
      {'is_consumed': consumed ? 1 : 0},
      where: 'owner_phone_number = ? AND upcoming_hike_id = ?',
      whereArgs: [owner, hikeId],
    );
  }

  /// Marks planned hike consumed.
  Future<void> markPlannedHikeConsumed({
    required String ownerPhoneNumber,
    required String upcomingHikeId,
  }) async {
    final owner = ownerPhoneNumber.trim();
    final hikeId = upcomingHikeId.trim();
    if (owner.isEmpty || hikeId.isEmpty) return;
    final database = await _openDatabase();
    // Update local: mark hike plan consumed
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

  // queuePendingHikeEnd retains the original end time and route/summary snapshot for a safe cloud
  // retry.
  /// Computes queue pending hike end.
  Future<void> queuePendingHikeEnd({
    required String ownerPhoneNumber,
    required ActiveHikeSession activeHike,
    HikeSummaryReport? summary,
    DateTime? endedAt,
    Map<String, dynamic>? trailRating,
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
    await database.transaction((transaction) async {
      // Query local: existing queued completion
      final rows = await transaction.query(
        'pending_hike_ends',
        where: 'owner_phone_number = ? AND session_id = ?',
        whereArgs: [owner, sessionId],
        limit: 1,
      );
      final previous = rows.isEmpty ? null : rows.single;
      final previousSummary = _decodeNullableJsonMap(
        previous?['summary_payload_json'] as String?,
      );
      final rating =
          trailRating ?? previousSummary?[LocalPendingHikeEnd.trailRatingKey];
      final savedSummary = summary?.toFirestore() ?? previousSummary;
      // Update local: queue hike completion
      await transaction.insert('pending_hike_ends', {
        'owner_phone_number': owner,
        'session_id': sessionId,
        'active_hike_payload_json': jsonEncode(activeHike.toPersistence()),
        if (savedSummary != null || rating != null)
          'summary_payload_json': jsonEncode({
            ...?savedSummary,
            if (rating != null) LocalPendingHikeEnd.trailRatingKey: rating,
          }),
        if (endedAt != null || previous?['ended_at'] != null)
          'ended_at':
              previous?['ended_at'] ?? endedAt!.toUtc().toIso8601String(),
        'created_at': previous?['created_at'] ?? now,
        'updated_at': now,
        'retry_count': 0,
        'last_error': '',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Loads pending hike ends.
  Future<List<LocalPendingHikeEnd>> loadPendingHikeEnds({
    required String ownerPhoneNumber,
    int limit = 20,
    bool newestFirst = false,
  }) async {
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty || limit <= 0) return const [];
    final database = await _openDatabase();
    // Query local: pending hike completions
    final rows = await database.query(
      'pending_hike_ends',
      where: 'owner_phone_number = ?',
      whereArgs: [owner],
      orderBy: newestFirst
          ? 'COALESCE(ended_at, created_at) DESC'
          : 'created_at ASC',
      limit: limit,
    );
    return rows.map(LocalPendingHikeEnd.fromRow).toList();
  }

  /// Deletes pending hike end.
  Future<bool> deletePendingHikeEnd({
    required String ownerPhoneNumber,
    required String sessionId,
    Map<String, dynamic>? expectedSummaryPayload,
    String? completedCloudId,
  }) async {
    final database = await _openDatabase();
    return database.transaction((transaction) async {
      // Query local: queued completion by ID
      final rows = await transaction.query(
        'pending_hike_ends',
        where: 'owner_phone_number = ? AND session_id = ?',
        whereArgs: [ownerPhoneNumber.trim(), sessionId.trim()],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final summary = _decodeNullableJsonMap(
        rows.single['summary_payload_json'] as String?,
      );
      if (expectedSummaryPayload == null) {
        // Sharing/completion acknowledgement alone cannot discard a queued rating.
        if (summary?[LocalPendingHikeEnd.trailRatingKey] != null) return false;
      } else if (stableContentHash(summary) !=
          stableContentHash(expectedSummaryPayload)) {
        // A rating saved while an older completion was uploading stays queued.
        return false;
      }
      if (completedCloudId != null && completedCloudId.isNotEmpty) {
        final preview = LocalPendingHikeEnd.fromRow(
          rows.single,
        ).historyPreview(ownerPhoneNumber, cloudId: completedCloudId);
        if (preview != null) {
          // Update local: acknowledge queued hike completion
          await transaction.insert('cached_entities', {
            'owner_phone_number': ownerPhoneNumber.trim(),
            'entity_type': acknowledgedHikeHistoryType,
            'entity_id': completedCloudId,
            'parent_id': '',
            'payload_json': jsonEncode(preview),
            'cached_at': DateTime.now().toUtc().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      return await transaction.delete(
            'pending_hike_ends',
            where: 'owner_phone_number = ? AND session_id = ?',
            whereArgs: [ownerPhoneNumber.trim(), sessionId.trim()],
          ) >
          0;
    });
  }

  // Keep accepted completions visible until the server's history list covers them.
  static const acknowledgedHikeHistoryType = 'acknowledged_hike_history';

  Future<void> retireAcknowledgedHikes(String owner, List<String> ids) async {
    if (ids.isEmpty) return;
    final database = await _openDatabase();
    final batch = database.batch();
    for (final id in ids) {
      // Update local: clear retired completion acknowledgements
      batch.delete(
        'cached_entities',
        where: 'owner_phone_number = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: [owner, acknowledgedHikeHistoryType, id],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Marks pending hike end retry.
  Future<void> markPendingHikeEndRetry({
    required String ownerPhoneNumber,
    required String sessionId,
    String lastError = '',
  }) async {
    final database = await _openDatabase();
    // Update local: count completion retry
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

  /// Loads or create app instance id.
  Future<String> loadOrCreateAppInstanceId() async {
    final database = await _openDatabase();
    // Query local: installation device ID
    final rows = await database.query('app_device', limit: 1);
    if (rows.isNotEmpty) {
      final existingId = rows.first['app_instance_id'] as String?;
      if (existingId != null && existingId.isNotEmpty) {
        return existingId;
      }
    }

    final appInstanceId = _newAppInstanceId();
    // Update local: save installation ID
    await database.insert('app_device', {
      'id': 1,
      'app_instance_id': appInstanceId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return appInstanceId;
  }

  /// Loads emergency contacts.
  Future<List<EmergencyContact>> loadEmergencyContacts({
    required String phoneNumber,
  }) async {
    final database = await _openDatabase();
    // Query local: ordered emergency contacts
    final rows = await database.query(
      'emergency_contacts',
      where: 'owner_phone_number = ?',
      whereArgs: [phoneNumber],
      orderBy: 'position ASC, name ASC',
    );
    return rows.map(_emergencyContactFromRow).toList();
  }

  /// Saves emergency contacts.
  Future<void> saveEmergencyContacts({
    required String phoneNumber,
    required List<EmergencyContact> contacts,
  }) async {
    final database = await _openDatabase();
    final now = DateTime.now().toUtc().toIso8601String();
    await database.transaction((transaction) async {
      // Update local: replace emergency contacts
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

  // saveCachedEntity avoids rewriting identical JSON while retaining its scope, revision time and
  // expiry.
  /// Saves cached entity.
  Future<void> saveCachedEntity(LocalCachedEntity entity) async {
    final database = await _openDatabase();
    // Query local: existing cached entity
    final existing = await database.query(
      'cached_entities',
      columns: ['payload_json', 'source_updated_at', 'expires_at'],
      where: 'owner_phone_number=? AND entity_type=? AND entity_id=?',
      whereArgs: [
        entity.ownerPhoneNumber.trim(),
        entity.entityType.trim(),
        entity.entityId.trim(),
      ],
      limit: 1,
    );
    if (existing.isNotEmpty &&
        stableContentHash(
              jsonDecode(existing.single['payload_json'] as String),
            ) ==
            stableContentHash(entity.payload) &&
        existing.single['source_updated_at'] ==
            entity.sourceUpdatedAt?.toUtc().toIso8601String() &&
        existing.single['expires_at'] ==
            entity.expiresAt?.toUtc().toIso8601String()) {
      return;
    }
    // Update local: save cached entity
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

  /// Saves cached entities.
  Future<void> saveCachedEntities(List<LocalCachedEntity> entities) async {
    if (entities.isEmpty) return;
    final database = await _openDatabase();
    final batch = database.batch();
    for (final entity in entities) {
      // Update local: cache entity batch
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

  /// Loads cached entities.
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
    // Query local: cached entities by owner and type
    final rows = await database.query(
      'cached_entities',
      where: clauses.join(' AND '),
      whereArgs: arguments,
      orderBy: 'source_updated_at DESC, cached_at DESC',
    );
    return rows.map(LocalCachedEntity.fromRow).toList();
  }

  /// Loads cached entity.
  Future<LocalCachedEntity?> loadCachedEntity({
    required String ownerPhoneNumber,
    required String entityType,
    required String entityId,
    bool includeExpired = false,
  }) async {
    final database = await _openDatabase();
    // Query local: cached entity by ID
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

  /// Bounds the registered reconnect working set while retaining offline data.
  /// Pending user operations and downloaded historical rows are never removed.
  Future<void> registerConditionalReadDescriptor(
    LocalCachedEntity descriptor, {
    int maximumPerOwner = 64,
    int maximumWorkUnits = 12288,
  }) async {
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      // Update local: register cached resource
      await transaction.insert('cached_entities', {
        'owner_phone_number': descriptor.ownerPhoneNumber.trim(),
        'entity_type': 'conditional_read_descriptor',
        'entity_id': descriptor.entityId,
        'parent_id': '',
        'payload_json': jsonEncode(descriptor.payload),
        'cached_at': descriptor.cachedAt.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      // Query local: cache entries for eviction
      final rows = await transaction.query(
        'cached_entities',
        where: 'owner_phone_number = ? AND entity_type = ?',
        whereArgs: [
          descriptor.ownerPhoneNumber.trim(),
          'conditional_read_descriptor',
        ],
        orderBy: 'cached_at DESC, entity_id ASC',
      );
      for (final row in rows.skip(maximumPerOwner.clamp(1, 64))) {
        final old = LocalCachedEntity.fromRow(row);
        // Update local: prune old cache entries
        await transaction.delete(
          'cached_entities',
          where: 'owner_phone_number = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [
            old.ownerPhoneNumber,
            'conditional_read_descriptor',
            old.entityId,
          ],
        );
      }
      // A detailed history projection is more expensive than a preference
      // record. Keep the registered working set within the server's work budget.
      // Only registration metadata is evicted here: downloaded data remains
      // available offline and can register again when it is next opened.
      final retained = rows
          .take(maximumPerOwner.clamp(1, 64))
          .map(LocalCachedEntity.fromRow)
          .toList();
      int cost(LocalCachedEntity item) =>
          (item.payload['workUnits'] as num?)?.toInt().clamp(1, 16384) ?? 4;
      var total = retained.fold(0, (sum, item) => sum + cost(item));
      for (final old in retained.reversed) {
        if (total <= maximumWorkUnits) break;
        await transaction.delete(
          'cached_entities',
          where: 'owner_phone_number = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [
            old.ownerPhoneNumber,
            'conditional_read_descriptor',
            old.entityId,
          ],
        );
        total -= cost(old);
      }
    });
  }

  /// Removes legacy private reads mistakenly stored in the shared public scope.
  /// Public profiles, trail/weather caches and pending operations are preserved.
  Future<void> purgeUnownedConditionalReadCaches({
    required Set<String> privateCallables,
  }) async {
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      // Update local: remove unowned private data
      await transaction.delete(
        'cached_entities',
        where: "owner_phone_number = '' AND entity_type IN (?, ?, ?, ?)",
        whereArgs: [
          'hike_history_list',
          'hike_history_list:validation',
          'hike_history_detail',
          'hike_history_detail:validation',
        ],
      );
      // Query local: orphaned private cache entries
      final descriptors = await transaction.query(
        'cached_entities',
        where: "owner_phone_number = '' AND entity_type = ?",
        whereArgs: ['conditional_read_descriptor'],
      );
      for (final row in descriptors) {
        final descriptor = LocalCachedEntity.fromRow(row);
        if (!privateCallables.contains(descriptor.payload['callable'])) {
          continue;
        }
        final type = descriptor.payload['type'];
        final id = descriptor.payload['id'];
        if (type is String && id is String) {
          // Update local: remove orphaned cache entries
          await transaction.delete(
            'cached_entities',
            where:
                "owner_phone_number = '' AND entity_id = ? AND entity_type IN (?, ?)",
            whereArgs: [id, type, '$type:validation'],
          );
        }
        await transaction.delete(
          'cached_entities',
          where:
              "owner_phone_number = '' AND entity_type = ? AND entity_id = ?",
          whereArgs: ['conditional_read_descriptor', descriptor.entityId],
        );
      }
    });
  }

  /// Applies a response only while its account and requested local baseline match.
  Future<bool> saveConditionalCacheResponse({
    required LocalCachedEntity entity,
    required LocalCachedEntity validation,
    required String? expectedPayloadHash,
    required DateTime? expectedCachedAt,
    String? expectedValidationHash,
    String? descriptorId,
    String expectedSessionOwner = '',
    bool payloadChanged = true,
    bool deletePayload = false,
  }) async {
    final database = await _openDatabase();
    return database.transaction((transaction) async {
      if (expectedSessionOwner.isNotEmpty) {
        // Query local: cache owner and validation state
        final users = await transaction.query(
          'users',
          columns: ['phone_number'],
          orderBy: 'signed_in_at DESC',
          limit: 1,
        );
        if (users.isEmpty ||
            users.single['phone_number'] != expectedSessionOwner) {
          return false;
        }
      }
      final rows = await transaction.query(
        'cached_entities',
        where: 'owner_phone_number = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: [
          entity.ownerPhoneNumber,
          entity.entityType,
          entity.entityId,
        ],
        limit: 1,
      );
      final current = rows.isEmpty
          ? null
          : LocalCachedEntity.fromRow(rows.single);
      if ((current == null) != (expectedPayloadHash == null) ||
          (current != null &&
              (stableContentHash(current.payload) != expectedPayloadHash ||
                  current.cachedAt != expectedCachedAt))) {
        return false;
      }
      final validationRows = await transaction.query(
        'cached_entities',
        where: 'owner_phone_number = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: [
          entity.ownerPhoneNumber,
          validation.entityType,
          entity.entityId,
        ],
        limit: 1,
      );
      final currentValidation = validationRows.isEmpty
          ? null
          : LocalCachedEntity.fromRow(validationRows.single);
      if ((currentValidation == null) != (expectedValidationHash == null) ||
          (currentValidation != null &&
              stableContentHash(currentValidation.payload) !=
                  expectedValidationHash)) {
        return false;
      }
      if (descriptorId != null) {
        final descriptors = await transaction.query(
          'cached_entities',
          columns: ['entity_id'],
          where: 'owner_phone_number = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [
            entity.ownerPhoneNumber,
            'conditional_read_descriptor',
            descriptorId,
          ],
          limit: 1,
        );
        if (descriptors.isEmpty) return false;
      }
      if (deletePayload) {
        // Update local: save resource and validation state
        await transaction.delete(
          'cached_entities',
          where: 'owner_phone_number = ? AND entity_type = ? AND entity_id = ?',
          whereArgs: [
            entity.ownerPhoneNumber,
            entity.entityType,
            entity.entityId,
          ],
        );
      }
      for (final item in [
        if (payloadChanged && !deletePayload) entity,
        validation,
      ]) {
        await transaction.insert('cached_entities', {
          'owner_phone_number': item.ownerPhoneNumber,
          'entity_type': item.entityType,
          'entity_id': item.entityId,
          'parent_id': item.parentId,
          'payload_json': jsonEncode(item.payload),
          'source_updated_at': item.sourceUpdatedAt?.toUtc().toIso8601String(),
          'cached_at': item.cachedAt.toUtc().toIso8601String(),
          'expires_at': item.expiresAt?.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      return true;
    });
  }

  /// Invalidates a downloaded read model without touching its retryable intent.
  Future<void> deleteConditionalCacheResource({
    required String owner,
    required String type,
    required String id,
    String? invalidationToken,
  }) async {
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      // Update local: invalidate cached resource
      await transaction.delete(
        'cached_entities',
        where:
            'owner_phone_number = ? AND entity_id = ? AND entity_type IN (?, ?)',
        whereArgs: [owner, id, type, '$type:validation'],
      );
      // This tombstone also protects a request that began before the first
      // cached payload existed. A late response cannot repopulate that cache.
      await transaction.insert('cached_entities', {
        'owner_phone_number': owner,
        'entity_type': '$type:validation',
        'entity_id': id,
        'parent_id': '',
        'payload_json': jsonEncode({
          'invalidated': true,
          'invalidationToken':
              invalidationToken ??
              DateTime.now().microsecondsSinceEpoch.toString(),
        }),
        'cached_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  // replaceCachedEntitySet replaces one scoped cache result atomically without disturbing other
  // entity types.
  /// Computes replace cached entity set.
  Future<void> replaceCachedEntitySet({
    required String ownerPhoneNumber,
    required String entityType,
    String parentId = '',
    required List<LocalCachedEntity> entities,
  }) async {
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      // Update local: replace owner's cached entities
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

  // enqueueSyncOperation retains owner scope and a stable idempotency key for retryable offline
  // work.
  /// Computes enqueue sync operation.
  Future<void> enqueueSyncOperation(LocalSyncOperation operation) async {
    final database = await _openDatabase();
    // Update local: queue sync operation
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

  /// Loads due sync operations.
  Future<List<LocalSyncOperation>> loadDueSyncOperations({
    required String ownerPhoneNumber,
    int limit = 50,
  }) async {
    final database = await _openDatabase();
    final now = DateTime.now().toUtc().toIso8601String();
    // Query local: sync operations ready to retry
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

  /// Marks sync operation retry.
  Future<void> markSyncOperationRetry(
    String operationId, {
    required String lastError,
    DateTime? nextAttemptAt,
  }) async {
    final database = await _openDatabase();
    // Update local: schedule sync retry
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

  /// Deletes sync operation.
  Future<void> deleteSyncOperation(String operationId) async {
    final database = await _openDatabase();
    // Update local: remove acknowledged sync operation
    await database.delete(
      'sync_outbox',
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
  }

  /// Saves local preference.
  Future<void> saveLocalPreference({
    required String ownerPhoneNumber,
    required String key,
    required Object? value,
    bool isDirty = false,
  }) async {
    final database = await _openDatabase();
    // Update local: save device preference
    await database.insert('local_preferences', {
      'owner_phone_number': ownerPhoneNumber.trim(),
      'preference_key': key.trim(),
      'value_json': jsonEncode(value),
      'is_dirty': isDirty ? 1 : 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Imports a default only when no device choice exists, including across background isolates.
  Future<void> seedLocalPreference(
    String owner,
    String key,
    Object? value,
  ) async {
    final db = await _openDatabase();
    // Update local: initialize missing preference
    await db.insert('local_preferences', {
      'owner_phone_number': owner,
      'preference_key': key,
      'value_json': jsonEncode(value),
      'is_dirty': 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Stores a dirty value and its durable logical sequence in the same transaction.
  Future<void> saveVersionedDirtyPreference(
    String owner,
    String key,
    Object? value,
  ) async {
    final db = await _openDatabase();
    await db.transaction((tx) async {
      final versionKey = 'sync_sequence:$key';
      // Query local: current preference revision
      final rows = await tx.query(
        'local_preferences',
        where: 'owner_phone_number = ? AND preference_key = ?',
        whereArgs: [owner, versionKey],
      );
      final sequence = rows.isEmpty
          ? 0
          : (jsonDecode(rows.single['value_json'] as String) as num).toInt();
      for (final entry in {key: value, versionKey: sequence + 1}.entries) {
        // Update local: queue preference revision
        await tx.insert('local_preferences', {
          'owner_phone_number': owner,
          'preference_key': entry.key,
          'value_json': jsonEncode(entry.value),
          'is_dirty': entry.key == key ? 1 : 0,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// Reads a consistent value/version pair and migrates a legacy dirty note on first replay.
  Future<({Object? value, int sequence})> loadVersionedPreference(
    String owner,
    String key,
  ) async {
    final db = await _openDatabase();
    return db.transaction((tx) async {
      // Query local: versioned preference
      final rows = await tx.query(
        'local_preferences',
        where: 'owner_phone_number = ? AND preference_key IN (?, ?)',
        whereArgs: [owner, key, 'sync_sequence:$key'],
      );
      final values = {for (final row in rows) row['preference_key']: row};
      final value = values[key] == null
          ? null
          : jsonDecode(values[key]!['value_json'] as String);
      var sequence = values['sync_sequence:$key'] == null
          ? 0
          : (jsonDecode(values['sync_sequence:$key']!['value_json'] as String)
                    as num)
                .toInt();
      if (sequence == 0 && values[key]?['is_dirty'] == 1) {
        sequence = 1;
        // Update local: initialize preference revision
        await tx.insert('local_preferences', {
          'owner_phone_number': owner,
          'preference_key': 'sync_sequence:$key',
          'value_json': '1',
          'is_dirty': 0,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      return (value: value, sequence: sequence);
    });
  }

  /// Loads local preference.
  Future<Object?> loadLocalPreference({
    required String ownerPhoneNumber,
    required String key,
  }) async {
    final database = await _openDatabase();
    // Query local: preference by owner and key
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

  /// Clears local preference if value.
  Future<bool> clearLocalPreferenceIfValue({
    required String ownerPhoneNumber,
    required String key,
    required Object? expectedValue,
  }) async {
    final database = await _openDatabase();
    // Update local: clear matching preference
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

  // saveLocalPreferenceIfClean accepts cloud values only when no unsynced local edit would be
  // overwritten.
  /// Saves local preference if clean.
  Future<bool> saveLocalPreferenceIfClean({
    required String ownerPhoneNumber,
    required String key,
    required Object? value,
  }) async {
    final database = await _openDatabase();
    return database.transaction((transaction) async {
      // Query local: unsent preference edits
      final rows = await transaction.query(
        'local_preferences',
        columns: ['is_dirty'],
        where: 'owner_phone_number = ? AND preference_key = ?',
        whereArgs: [ownerPhoneNumber.trim(), key.trim()],
      );
      if (rows.isNotEmpty && rows.first['is_dirty'] == 1) return false;
      // Update local: save downloaded preference
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

  /// Loads dirty local preferences.
  Future<Map<String, Map<String, dynamic>>> loadPendingArrivalResponses({
    required String owner,
  }) async {
    final database = await _openDatabase();
    // Query local: pending hike arrival responses
    final rows = await database.query(
      'local_preferences',
      columns: ['preference_key', 'value_json'],
      where: 'owner_phone_number = ? AND preference_key GLOB ?',
      whereArgs: [owner, 'pending_arrival_response:*'],
    );
    return {
      for (final row in rows)
        row['preference_key'] as String: Map<String, dynamic>.from(
          jsonDecode(row['value_json'] as String) as Map,
        ),
    };
  }

  /// Loads dirty local preferences.
  Future<Map<String, Object?>> loadDirtyLocalPreferences({
    required String ownerPhoneNumber,
  }) async {
    final database = await _openDatabase();
    // Query local: pending preference edits
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

  // markLocalPreferenceSynced acknowledges the uploaded value only if the local value still
  // matches.
  /// Marks local preference synced.
  Future<void> markLocalPreferenceSynced({
    required String ownerPhoneNumber,
    required String key,
    required Object? expectedValue,
    int? expectedSequence,
  }) async {
    final database = await _openDatabase();
    // Update local: acknowledge preference revision
    await database.update(
      'local_preferences',
      {'is_dirty': 0},
      where:
          'owner_phone_number = ? AND preference_key = ? AND value_json = ?'
          '${expectedSequence == null ? '' : ' AND EXISTS (SELECT 1 FROM local_preferences AS revision WHERE revision.owner_phone_number = ? AND revision.preference_key = ? AND revision.value_json = ?)'}',
      whereArgs: [
        ownerPhoneNumber.trim(),
        key.trim(),
        jsonEncode(expectedValue),
        if (expectedSequence != null) ...[
          ownerPhoneNumber.trim(),
          'sync_sequence:${key.trim()}',
          jsonEncode(expectedSequence),
        ],
      ],
    );
  }

  /// Computes replace static hazard dataset.
  Future<void> replaceStaticHazardDataset({
    required List<LocalStaticHazard> hazards,
    required List<LocalTrailHazardMatch> matches,
    required int scannedTrailCount,
    Iterable<String> scannedTrailIds = const [],
  }) async {
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      // Update local: replace static hazards and matches
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
        // Update local: save hazard scan metadata
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

  /// Loads static hazard scan time.
  Future<DateTime?> loadStaticHazardScanTime(String trailId) async {
    final normalizedTrailId = trailId.trim();
    if (normalizedTrailId.isEmpty) return null;
    final database = await _openDatabase();
    // Query local: last hazard scan time
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
      // Query local: previous hazard matches by trail
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
      // Update local: clear trail hazard matches
      await transaction.delete(
        'trail_hazard_matches',
        where: 'trail_id = ?',
        whereArgs: [normalizedTrailId],
      );
      for (final row in previousHazards) {
        final hazardId = row['hazard_id'] as String? ?? '';
        // Query local: shared hazard reference count
        final referenceCount = Sqflite.firstIntValue(
          await transaction.rawQuery(
            'SELECT COUNT(*) FROM trail_hazard_matches WHERE hazard_id = ?',
            [hazardId],
          ),
        );
        if ((referenceCount ?? 0) != 0) continue;
        // Update local: remove unreferenced hazards
        await transaction.delete(
          'hazard_feature_rtree',
          where: 'owner_phone_number = ? AND chat_id = ? AND local_id = ?',
          whereArgs: [
            row['owner_phone_number'],
            row['chat_id'],
            row['local_id'],
          ],
        );
        await transaction.delete(
          'hazard_features',
          where: 'hazard_id = ?',
          whereArgs: [hazardId],
        );
      }

      final localIds = <String, int>{};
      for (final hazard in hazards) {
        // Update local: save refreshed hazards and matches
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

  /// Loads static hazards for trail.
  Future<List<LocalTrailHazardMatch>> loadStaticHazardsForTrail(
    String trailId,
  ) async {
    final database = await _openDatabase();
    // Query local: saved hazard matches by trail
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

  /// Loads static hazard dataset summary.
  Future<LocalHazardDatasetSummary> loadStaticHazardDatasetSummary() async {
    final database = await _openDatabase();
    // Query local: hazard counts and scan metadata
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

  /// Clears static hazard dataset.
  Future<void> clearStaticHazardDataset() async {
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      // Update local: clear static hazard data
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

  /// Saves device notification.
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
    await database.transaction(
      (transaction) => _saveDeviceNotification(
        transaction,
        ownerPhoneNumber: ownerPhoneNumber,
        messageId: messageId,
        title: title,
        body: body,
        type: type,
        deepLink: deepLink,
        data: data,
        receivedAt: receivedAt,
        openedAt: openedAt,
        source: source,
      ),
    );
    _deviceNotificationChanges.add(ownerPhoneNumber);
  }

  /// Saves device notification.
  Future<void> _saveDeviceNotification(
    DatabaseExecutor database, {
    required String ownerPhoneNumber,
    required String messageId,
    required String title,
    required String body,
    required String type,
    required String deepLink,
    required Map<String, dynamic> data,
    DateTime? receivedAt,
    DateTime? openedAt,
    required String source,
  }) async {
    final now = DateTime.now().toUtc();
    final effectiveMessageId = messageId.trim();
    // Query local: existing device notification
    final existingRows = effectiveMessageId.isEmpty
        ? const <Map<String, Object?>>[]
        : await database.query(
            'device_notifications',
            columns: ['id', 'received_at'],
            where: 'owner_phone_number = ? AND message_id = ?',
            whereArgs: [ownerPhoneNumber, effectiveMessageId],
            limit: 1,
          );
    final received =
        receivedAt?.toUtc().toIso8601String() ??
        (existingRows.isEmpty
            ? now.toIso8601String()
            : existingRows.first['received_at']);
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
      // Update local: save notification and prune old entries
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

  /// Loads device notifications.
  Future<List<DeviceNotificationRecord>> loadDeviceNotifications({
    required String ownerPhoneNumber,
    int limit = 500,
    DateTime? asOf,
  }) async {
    final database = await _openDatabase();
    // Query local: hiker's device notifications
    final rows = await database.query(
      'device_notifications',
      where: 'owner_phone_number = ? AND received_at <= ?',
      whereArgs: [
        ownerPhoneNumber,
        (asOf ?? DateTime.now()).toUtc().toIso8601String(),
      ],
      orderBy: 'is_starred DESC, received_at DESC',
      limit: limit,
    );
    return rows.map(DeviceNotificationRecord.fromRow).toList();
  }

  /// Computes next device notification at.
  Future<DateTime?> nextDeviceNotificationAt(
    String ownerPhoneNumber, {
    DateTime? asOf,
  }) async {
    final database = await _openDatabase();
    // Query local: next notification timestamp
    final rows = await database.query(
      'device_notifications',
      columns: ['received_at'],
      where: 'owner_phone_number = ? AND received_at > ?',
      whereArgs: [
        ownerPhoneNumber,
        (asOf ?? DateTime.now()).toUtc().toIso8601String(),
      ],
      orderBy: 'received_at ASC',
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : DateTime.tryParse(rows.first['received_at'] as String);
  }

  /// Deletes scheduled device notification.
  Future<void> deleteScheduledDeviceNotification({
    required String ownerPhoneNumber,
    required String messageId,
  }) async {
    final database = await _openDatabase();
    // Update local: remove scheduled notification
    await database.delete(
      'device_notifications',
      where: 'owner_phone_number = ? AND message_id = ? AND received_at > ?',
      whereArgs: [
        ownerPhoneNumber,
        messageId,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    _deviceNotificationChanges.add(ownerPhoneNumber);
  }

  /// Marks device notification message opened.
  Future<void> markDeviceNotificationMessageOpened({
    required String ownerPhoneNumber,
    required String messageId,
  }) async {
    final database = await _openDatabase();
    // Update local: mark notification message opened
    await database.update(
      'device_notifications',
      {'opened_at': DateTime.now().toUtc().toIso8601String()},
      where: 'owner_phone_number = ? AND message_id = ?',
      whereArgs: [ownerPhoneNumber, messageId],
    );
    _deviceNotificationChanges.add(ownerPhoneNumber);
  }

  /// Marks device notification opened.
  Future<void> markDeviceNotificationOpened({
    required String ownerPhoneNumber,
    required int id,
  }) async {
    final database = await _openDatabase();
    // Update local: mark device notification opened
    await database.update(
      'device_notifications',
      {'opened_at': DateTime.now().toUtc().toIso8601String()},
      where: 'owner_phone_number = ? AND id = ?',
      whereArgs: [ownerPhoneNumber, id],
    );
    _deviceNotificationChanges.add(ownerPhoneNumber);
  }

  /// Marks all device notifications opened.
  Future<void> markAllDeviceNotificationsOpened({
    required String ownerPhoneNumber,
  }) async {
    final database = await _openDatabase();
    // Update local: mark all notifications opened
    await database.update(
      'device_notifications',
      {'opened_at': DateTime.now().toUtc().toIso8601String()},
      where:
          'owner_phone_number = ? AND opened_at IS NULL AND received_at <= ?',
      whereArgs: [ownerPhoneNumber, DateTime.now().toUtc().toIso8601String()],
    );
    _deviceNotificationChanges.add(ownerPhoneNumber);
  }

  /// Marks device notification unread.
  Future<void> markDeviceNotificationUnread({
    required String ownerPhoneNumber,
    required int id,
  }) async {
    final database = await _openDatabase();
    // Update local: mark notification unread
    await database.update(
      'device_notifications',
      {'opened_at': null},
      where: 'owner_phone_number = ? AND id = ?',
      whereArgs: [ownerPhoneNumber, id],
    );
    _deviceNotificationChanges.add(ownerPhoneNumber);
  }

  /// Sets device notification starred.
  Future<void> setDeviceNotificationStarred({
    required String ownerPhoneNumber,
    required int id,
    required bool isStarred,
  }) async {
    final database = await _openDatabase();
    // Update local: change notification star
    await database.update(
      'device_notifications',
      {'is_starred': isStarred ? 1 : 0},
      where: 'owner_phone_number = ? AND id = ?',
      whereArgs: [ownerPhoneNumber, id],
    );
    _deviceNotificationChanges.add(ownerPhoneNumber);
  }

  /// Deletes device notification.
  Future<void> deleteDeviceNotification({
    required String ownerPhoneNumber,
    required int id,
  }) async {
    final database = await _openDatabase();
    // Update local: delete device notification
    await database.delete(
      'device_notifications',
      where: 'owner_phone_number = ? AND id = ?',
      whereArgs: [ownerPhoneNumber, id],
    );
    _deviceNotificationChanges.add(ownerPhoneNumber);
  }

  /// Clears device notifications.
  Future<void> clearDeviceNotifications({
    required String ownerPhoneNumber,
    bool includeStarred = true,
  }) async {
    final database = await _openDatabase();
    // Update local: clear owner's notifications
    await database.delete(
      'device_notifications',
      where: includeStarred
          ? 'owner_phone_number = ? AND received_at <= ?'
          : 'owner_phone_number = ? AND is_starred = 0 AND received_at <= ?',
      whereArgs: [ownerPhoneNumber, DateTime.now().toUtc().toIso8601String()],
    );
    _deviceNotificationChanges.add(ownerPhoneNumber);
  }

  /// Saves nearby sos event.
  Future<void> saveNearbySosEvent(NearbySosEvent event) async {
    if (event.isDiagnosticTest) return;
    final owner = event.ownerPhoneNumber.trim();
    final eventKey = event.eventKey.trim();
    if (owner.isEmpty || eventKey.isEmpty) return;
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      // Query local: previous nearby SOS event
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
        // Update local: save nearby SOS event
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

  /// Loads nearby sos events.
  Future<List<NearbySosEvent>> loadNearbySosEvents({
    required String ownerPhoneNumber,
    int limit = 200,
  }) async {
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty || limit <= 0) return const [];
    final database = await _openDatabase();
    // Query local: saved nearby SOS events
    final rows = await database.query(
      'nearby_sos_events',
      where:
          "owner_phone_number = ? AND substr(lower(trim(device_id)), 1, 5) <> 'help_'",
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

  // _openDatabase shares one protected connection and applies incremental schema upgrades without
  // resetting queues.
  /// Opens database.
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

    final opening = SecureLocalDatabase.open(
      databasePath,
      version: 40,
      onCreate: (database, version) async {
        // Update local: create session database schema
        await database.execute('''
          CREATE TABLE users (
            phone_number TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            signed_in_at TEXT NOT NULL,
            app_instance_id TEXT NOT NULL DEFAULT '',
            is_admin INTEGER NOT NULL DEFAULT 0,
            is_super_admin INTEGER NOT NULL DEFAULT 0,
            username TEXT NOT NULL DEFAULT '',
            requires_onboarding INTEGER NOT NULL DEFAULT 0,
            onboarding_profile_complete INTEGER NOT NULL DEFAULT 0,
            requires_privacy_consent INTEGER NOT NULL DEFAULT 0,
            photo_url TEXT,
            photo_bytes BLOB
          )
        ''');
        await _createSafetyTables(database);
        await database.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS footprint_sample_identity ON footprints(owner_phone_number, session_id, sample_key)',
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
        await _createUpcomingHikeRemindersTable(database);
        await _createAchievementProgressCacheTable(database);
        await _createAchievementEventTables(database);
        await _createOfflineFirstTables(database);
        await _createStaticHazardTables(database);
        await _createButtonDebugTables(database);
        await _createCommunityTables(database);
        await _createFeedbackDraftTable(database);
        await _createCautionOutboxTables(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 40) {
          // Update local: add privacy consent fields
          await database.execute(
            'ALTER TABLE users ADD COLUMN requires_privacy_consent INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 39) {
          await _createCautionOutboxTables(database);
        }
        if (oldVersion < 36) {
          await _createFeedbackDraftTable(database);
        }
        // One-time rename keeps pending samples, IDs and owner isolation intact.
        if (oldVersion < 29) {
          // Query local: legacy tracking schema
          final oldTable = await database.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'local_location_points'",
          );
          if (oldTable.isNotEmpty) {
            // Update local: migrate tracking tables and indexes
            await database.execute(
              'ALTER TABLE local_location_points RENAME TO footprints',
            );
          }
          await database.execute(
            'DROP INDEX IF EXISTS location_sample_identity',
          );
          await database.execute(
            'DROP INDEX IF EXISTS idx_location_points_session_sync_time',
          );
        }

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
            tableName: 'footprints',
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
          // Update local: migrate queued alerts
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
          // Update local: assign owners to queued messages
          await database.rawUpdate('''
            UPDATE pending_messages
            SET owner_phone_number = sender_phone
            WHERE TRIM(owner_phone_number) = ''
          ''');
          // Query local: legacy read receipt tables
          final readReceiptTable = await database.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'chat_read_receipts'",
          );
          final usersTable = await database.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'users'",
          );
          if (readReceiptTable.isEmpty) {
            await _createChatReadReceiptsTable(database);
          } else {
            // Update local: migrate chat read receipts
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
            tableName: 'footprints',
            columnName: 'sample_key',
            definition: 'TEXT',
          );
          await _addColumnIfMissing(
            database,
            tableName: 'footprints',
            columnName: 'fix_captured_at',
            definition: 'TEXT',
          );
          // Update local: rebuild GPS sample index
          await database.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS footprint_sample_identity ON footprints(owner_phone_number, session_id, sample_key)',
          );
        }
        if (oldVersion < 29) {
          await _createSafetyTables(database);
          await database.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS footprint_sample_identity ON footprints(owner_phone_number, session_id, sample_key)',
          );
        }
        if (oldVersion < 30) {
          await _createCommunityTables(database);
          await _migrateCommunityCache(database);
        }
        if (oldVersion < 31) {
          // These dormant map/network caches have no readers or replay path.
          // Preserve operational users, footprints, drafts and every sync queue.
          // Update local: drop retired map tables
          await database.execute('DROP TABLE IF EXISTS downloaded_maps');
          await database.execute('DROP TABLE IF EXISTS offline_map_regions');
          await database.execute('DROP TABLE IF EXISTS network_observations');
        }
        if (oldVersion < 33) {
          await _createAchievementProgressCacheTable(database);
          await _createAchievementEventTables(database);
        }
        if (oldVersion < 32) {
          for (final column in const {
            'preparation_hash': "TEXT NOT NULL DEFAULT ''",
            'schedule_sync_pending': 'INTEGER NOT NULL DEFAULT 0',
            'creation_key': "TEXT NOT NULL DEFAULT ''",
            'join_policy': "TEXT NOT NULL DEFAULT 'approval'",
            'reminder_preference_json': 'TEXT',
            'reminder_sync_pending': 'INTEGER NOT NULL DEFAULT 0',
            'has_cloud_snapshot': 'INTEGER NOT NULL DEFAULT 1',
          }.entries) {
            await _addColumnIfMissing(
              database,
              tableName: 'planned_hike_state',
              columnName: column.key,
              definition: column.value,
            );
          }
          await _createUpcomingHikeRemindersTable(database);
          // Query local: existing plans for migration
          for (final row in await database.query('planned_hike_state')) {
            // Update local: migrate planning state
            await database.update(
              'planned_hike_state',
              {
                'preparation_hash': _preparationHash(
                  _decodeJsonMap(row['upcoming_payload_json'] as String?),
                  _decodeJsonStringList(
                    row['completed_checklist_json'] as String?,
                  ),
                ),
              },
              where: 'owner_phone_number = ? AND upcoming_hike_id = ?',
              whereArgs: [row['owner_phone_number'], row['upcoming_hike_id']],
            );
          }
        }
        if (oldVersion < 35) {
          await _addColumnIfMissing(
            database,
            tableName: 'pending_messages',
            columnName: 'shared_post_json',
            definition: "TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 34) {
          // Remove only the retired assistant's conversation and clear markers.
          await _createOfflineFirstTables(database);
          // Update local: remove obsolete preferences
          await database.delete(
            'local_preferences',
            where: 'preference_key IN (?, ?)',
            whereArgs: [
              'assistant_conversation_v1',
              'assistant_conversation_cleared_v1',
            ],
          );
        }
        if (oldVersion < 38) {
          // Update local: add superadmin session role
          await database.execute(
            'ALTER TABLE users ADD COLUMN is_super_admin INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 37) {
          // Update local: migrate pending chat messages
          await database.execute(
            'ALTER TABLE pending_messages RENAME TO pending_messages_v36',
          );
          await _createPendingMessagesTable(database);
          // Query local: legacy pending message columns
          final columns = (await database.rawQuery(
            'PRAGMA table_info(pending_messages_v36)',
          )).map((row) => row['name'] as String).join(', ');
          await database.execute(
            'INSERT INTO pending_messages ($columns) SELECT $columns FROM pending_messages_v36',
          );
          await database.execute('DROP TABLE pending_messages_v36');
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

  /// Closes.
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

  // insertFootprint saves a timestamp-identified sample locally before upload; replay preserves
  // the first stored sample.
  /// Computes insert footprint.
  Future<int> insertFootprint({
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
    // Update local: insert GPS footprint
    return database.insert('footprints', {
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

  // insertQueuedAlert makes an SOS dispatch retry durable before cloud or messaging work begins.
  /// Computes insert queued alert.
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
    // Update local: queue hike safety alert
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

  /// Loads queued alerts.
  Future<List<LocalQueuedAlert>> loadQueuedAlerts({
    required String ownerPhoneNumber,
    int? limit = 20,
  }) async {
    final database = await _openDatabase();
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty) {
      return const [];
    }
    // Query local: queued hike safety alerts
    final rows = await database.query(
      'queued_alerts',
      where: 'owner_phone_number = ? AND send_status IN (?, ?)',
      whereArgs: [owner, 'queued', 'retry'],
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
    return rows.map(LocalQueuedAlert.fromRow).toList();
  }

  /// Computes count queued alerts.
  Future<int> countQueuedAlerts({required String ownerPhoneNumber}) async {
    final database = await _openDatabase();
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty) {
      return 0;
    }
    // Query local: queued alert count by status
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

  /// Marks queued alert sent.
  Future<void> markQueuedAlertSent(int id) async {
    final database = await _openDatabase();
    // Update local: mark queued alert sent
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

  /// Updates queued alert payload.
  Future<void> updateQueuedAlertPayload({
    required int id,
    required String payloadJson,
    String sendStatus = 'queued',
    String lastError = '',
  }) async {
    final database = await _openDatabase();
    // Update local: replace queued alert payload
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

  /// Updates queued alert retry.
  Future<void> updateQueuedAlertRetry({
    required int id,
    required String payloadJson,
    String lastError = '',
  }) async {
    final database = await _openDatabase();
    // Update local: record alert retry
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

  /// Computes count unsent footprints.
  Future<int> countUnsentFootprints(
    String sessionId, {
    String? ownerPhoneNumber,
  }) async {
    final database = await _openDatabase();
    // Query local: unsent GPS footprint count
    final result = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM footprints
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

  /// Loads unsent footprints.
  Future<List<LocalFootprint>> loadUnsentFootprints({
    required String sessionId,
    String? ownerPhoneNumber,
    int limit = 200,
  }) async {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty || limit <= 0) {
      return const [];
    }
    final database = await _openDatabase();
    // Query local: pending GPS footprints by time
    final rows = await database.query(
      'footprints',
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
        .map(LocalFootprint.fromRow)
        .where((point) => point.hasValidCoordinate)
        .toList();
  }

  /// Loads footprints.
  Future<List<LocalFootprint>> loadFootprints({
    required String sessionId,
    required String ownerPhoneNumber,
  }) async {
    final database = await _openDatabase();
    // Query local: recorded GPS footprints by hike
    final rows = await database.query(
      'footprints',
      where: 'session_id = ? AND owner_phone_number = ?',
      whereArgs: [sessionId, ownerPhoneNumber],
      orderBy: 'recorded_at ASC, id ASC',
    );
    return rows
        .map(LocalFootprint.fromRow)
        .where((p) => p.hasValidCoordinate)
        .toList();
  }

  // markFootprintsSynced accepts only the sample IDs that its caller has confirmed in the server
  // acknowledgement.
  /// Marks footprints synced.
  Future<void> markFootprintsSynced(Iterable<int> pointIds) async {
    final ids = pointIds.where((id) => id > 0).toSet();
    if (ids.isEmpty) {
      return;
    }
    final database = await _openDatabase();
    final batch = database.batch();
    for (final id in ids) {
      // Update local: acknowledge uploaded GPS footprints
      batch.update(
        'footprints',
        {'is_synced': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Deletes synced footprints.
  Future<int> deleteSyncedFootprints({
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
    // Update local: remove synced GPS footprints
    return database.delete(
      'footprints',
      where: clauses.join(' AND '),
      whereArgs: arguments,
    );
  }

  /// Deletes recorded tracking rows after the canonical route capture
  /// is saved, while deliberately preserving every queued SOS alert.
  Future<void> discardHikeTrackingTelemetry({required String sessionId}) async {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) return;
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      // Update local: discard hike tracking points
      await transaction.delete(
        'footprints',
        where: 'session_id = ?',
        whereArgs: [normalizedSessionId],
      );
    });
  }

  /// Deletes completed hike telemetry.
  Future<void> _deleteCompletedHikeTelemetry(
    DatabaseExecutor database, {
    required String sessionId,
    required bool preserveUnsent,
  }) async {
    // Update local: clear completed hike tracking data
    await database.delete(
      'footprints',
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

  /// Creates safety tables.
  Future<void> _createSafetyTables(Database database) async {
    // Update local: create footprint and alert tables
    await database.execute('''
      CREATE TABLE IF NOT EXISTS footprints (
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

    await _createSafetyIndexes(database);
  }

  /// Creates safety indexes.
  Future<void> _createSafetyIndexes(Database database) async {
    // Update local: index pending footprints and alerts
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_footprints_session_sync_time
      ON footprints(session_id, is_synced, recorded_at)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_queued_alerts_session_status
      ON queued_alerts(session_id, send_status, created_at)
    ''');
  }

  /// Creates device binding tables.
  Future<void> _createDeviceBindingTables(Database database) async {
    // Update local: create device binding table
    await database.execute('''
      CREATE TABLE IF NOT EXISTS app_device (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        app_instance_id TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  /// Preserve report payloads and attachment bytes atomically until confirmed.
  Future<void> _createCautionOutboxTables(Database database) async {
    // Update local: create caution outbox and media tables
    await database.execute('''CREATE TABLE IF NOT EXISTS caution_report_outbox (
      owner TEXT NOT NULL, report_id TEXT NOT NULL, payload TEXT NOT NULL,
      content_hash TEXT NOT NULL, created_at TEXT NOT NULL,
      status TEXT NOT NULL CHECK (status IN ('pending','sent','failed')),
      media_count INTEGER NOT NULL DEFAULT 0, attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT NOT NULL DEFAULT '', last_attempt_at TEXT,
      next_retry_at TEXT, sent_at TEXT, PRIMARY KEY(owner, report_id)
    )''');
    await database.execute('''CREATE TABLE IF NOT EXISTS caution_report_media (
      owner TEXT NOT NULL, report_id TEXT NOT NULL, media_key TEXT NOT NULL,
      name TEXT NOT NULL, content_type TEXT NOT NULL, bytes BLOB NOT NULL,
      PRIMARY KEY(owner, report_id, media_key)
    )''');
    await database.execute(
      '''CREATE INDEX IF NOT EXISTS idx_caution_outbox_pending
      ON caution_report_outbox(owner, status, created_at)''',
    );
  }

  /// Keeps unsent feedback independent of downloaded caches and upload queues.
  Future<void> _createFeedbackDraftTable(Database database) async {
    // Update local: create feedback draft table
    await database.execute('''
      CREATE TABLE IF NOT EXISTS feedback_drafts (
        owner TEXT PRIMARY KEY,
        draft_id TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('active', 'cleared')),
        revision INTEGER NOT NULL DEFAULT 0,
        category TEXT NOT NULL,
        message TEXT NOT NULL,
        screenshot BLOB,
        screenshot_hash TEXT NOT NULL DEFAULT '',
        submission_attempted INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  /// Creates emergency contacts table.
  Future<void> _createEmergencyContactsTable(Database database) async {
    // Update local: create emergency contacts table
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

  /// Creates pending messages table.
  Future<void> _createPendingMessagesTable(Database database) async {
    // Update local: create pending chat messages table
    await database.execute('''
      CREATE TABLE IF NOT EXISTS pending_messages (
        local_id TEXT NOT NULL,
        chat_id TEXT NOT NULL,
        sender_phone TEXT NOT NULL,
        sender_name TEXT NOT NULL DEFAULT '',
        text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        send_status TEXT NOT NULL DEFAULT 'pending',
        retry_count INTEGER NOT NULL DEFAULT 0,
        firestore_doc_id TEXT DEFAULT '',
        attachment_json TEXT DEFAULT '',
        shared_post_json TEXT NOT NULL DEFAULT '',
        owner_phone_number TEXT NOT NULL DEFAULT '',
        updated_at TEXT,
        last_error TEXT NOT NULL DEFAULT '',
        attachment_bytes BLOB,
        attachment_upload_json TEXT NOT NULL DEFAULT '',
        message_json TEXT NOT NULL DEFAULT '',
        awaiting_cloud_snapshot INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (owner_phone_number, chat_id, local_id)
      )
    ''');
  }

  /// Creates active hike session table.
  Future<void> _createActiveHikeSessionTable(Database database) async {
    // Update local: create active hike table
    await database.execute('''
      CREATE TABLE IF NOT EXISTS active_hike_session (
        owner_phone_number TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  /// Creates pending hike ends table.
  Future<void> _createPendingHikeEndsTable(Database database) async {
    // Update local: create pending hike completions table
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

  /// Creates planned hike state table.
  Future<void> _createPlannedHikeStateTable(Database database) async {
    // Update local: create hike planning table
    await database.execute('''
      CREATE TABLE IF NOT EXISTS planned_hike_state (
        owner_phone_number TEXT NOT NULL,
        upcoming_hike_id TEXT NOT NULL,
        upcoming_payload_json TEXT NOT NULL,
        completed_checklist_json TEXT NOT NULL DEFAULT '[]',
        preparation_hash TEXT NOT NULL DEFAULT '',
        schedule_sync_pending INTEGER NOT NULL DEFAULT 0,
        creation_key TEXT NOT NULL DEFAULT '',
        join_policy TEXT NOT NULL DEFAULT 'approval',
        reminder_preference_json TEXT,
        reminder_sync_pending INTEGER NOT NULL DEFAULT 0,
        has_cloud_snapshot INTEGER NOT NULL DEFAULT 0,
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

  /// Creates achievement progress cache table.
  Future<void> _createAchievementProgressCacheTable(Database database) async {
    // Update local: create achievement progress cache
    await database.execute('''
      CREATE TABLE IF NOT EXISTS achievement_progress_cache (
        owner_phone_number TEXT PRIMARY KEY,
        content_hash TEXT NOT NULL DEFAULT '',
        payload_json TEXT NOT NULL,
        cached_at TEXT NOT NULL
      )
    ''');
  }

  /// Creates offline first tables.
  Future<void> _createOfflineFirstTables(Database database) async {
    // Update local: create entity cache table
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
    // Update local: create sync outbox table
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
    // Update local: create preferences table and indexes
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
    await _createPendingMessagesTable(database);
    await _createChatReadReceiptsTable(database);
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_pending_messages_owner_status_created
      ON pending_messages(owner_phone_number, send_status, created_at)
    ''');
  }

  /// Creates static hazard tables.
  Future<void> _createStaticHazardTables(Database database) async {
    // Update local: create hazard features table
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
    // Update local: create trail hazard matches table
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
    // Update local: create hazard bounds table
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

  /// Creates chat read receipts table.
  Future<void> _createChatReadReceiptsTable(Database database) async {
    // Update local: create chat read receipts table
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

  /// Creates device notifications table.
  Future<void> _createDeviceNotificationsTable(Database database) async {
    // Update local: create device notifications table
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

  /// Creates nearby sos events table.
  Future<void> _createNearbySosEventsTable(Database database) async {
    // Update local: create nearby SOS events table
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

  /// Saves chat read receipt.
  Future<void> saveChatReadReceipt(
    String chatId,
    DateTime lastReadAt, {
    String ownerPhoneNumber = '',
    bool synced = false,
  }) async {
    final database = await _openDatabase();
    await database.transaction((tx) async {
      // Query local: saved chat read position
      final rows = await tx.query(
        'chat_read_receipts',
        where: 'owner_phone_number = ? AND chat_id = ?',
        whereArgs: [ownerPhoneNumber.trim(), chatId],
      );
      if (rows.isNotEmpty) {
        final old = DateTime.tryParse(rows.single['last_read_at'] as String);
        if (old != null && old.isAfter(lastReadAt)) return;
      }
      // Update local: save newer chat read receipt
      await tx.insert('chat_read_receipts', {
        'chat_id': chatId,
        'owner_phone_number': ownerPhoneNumber.trim(),
        'last_read_at': lastReadAt.toUtc().toIso8601String(),
        'is_synced': synced ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Loads chat read receipt.
  Future<DateTime?> loadChatReadReceipt(
    String chatId, {
    String ownerPhoneNumber = '',
  }) async {
    final database = await _openDatabase();
    // Query local: chat read receipt by owner
    final rows = await database.query(
      'chat_read_receipts',
      columns: ['last_read_at', 'is_synced'],
      where: 'owner_phone_number = ? AND chat_id = ?',
      whereArgs: [ownerPhoneNumber.trim(), chatId],
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['last_read_at'] as String? ?? '');
  }

  /// Loads all chat read receipts.
  Future<Map<String, DateTime>> loadAllChatReadReceipts({
    String ownerPhoneNumber = '',
  }) async {
    final database = await _openDatabase();
    // Query local: owner's chat read receipts
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

  /// Loads unsynced read receipt chat ids.
  Future<List<String>> loadUnsyncedReadReceiptChatIds({
    String ownerPhoneNumber = '',
  }) async {
    final database = await _openDatabase();
    // Query local: unsynced chat read receipts
    final rows = await database.query(
      'chat_read_receipts',
      columns: ['chat_id'],
      where: 'owner_phone_number = ? AND is_synced = 0',
      whereArgs: [ownerPhoneNumber.trim()],
    );
    return rows.map((r) => r['chat_id'] as String).toList();
  }

  /// Marks chat read receipt synced.
  Future<void> markChatReadReceiptSynced(
    String chatId, {
    String ownerPhoneNumber = '',
    required DateTime expectedLastReadAt,
  }) async {
    final database = await _openDatabase();
    // Update local: acknowledge chat read receipt
    await database.update(
      'chat_read_receipts',
      {'is_synced': 1},
      where: 'owner_phone_number = ? AND chat_id = ? AND last_read_at = ?',
      whereArgs: [
        ownerPhoneNumber.trim(),
        chatId,
        expectedLastReadAt.toUtc().toIso8601String(),
      ],
    );
  }

  // insertPendingMessage retains a local message identity so reconnect retries can reuse the same
  // cloud document.
  /// Computes insert pending message.
  Future<void> insertPendingMessage({
    required String localId,
    required String chatId,
    required String senderPhone,
    required String senderName,
    required String text,
    String firestoreDocId = '',
    String sendStatus = 'pending',
    String? ownerPhoneNumber,
    Map<String, dynamic>? sharedPost,
    DateTime? sentAt,
    Map<String, dynamic>? attachment,
    Uint8List? attachmentBytes,
    Map<String, dynamic>? attachmentUpload,
  }) async {
    final database = await _openDatabase();
    // Update local: queue outgoing chat message
    await database.insert('pending_messages', {
      'local_id': localId,
      'chat_id': chatId,
      'sender_phone': senderPhone,
      'sender_name': senderName,
      'text': text,
      'shared_post_json': sharedPost == null ? '' : jsonEncode(sharedPost),
      'created_at': (sentAt ?? DateTime.now()).toUtc().toIso8601String(),
      'attachment_json': attachment == null ? '' : jsonEncode(attachment),
      'attachment_bytes': attachmentBytes,
      'attachment_upload_json': attachmentUpload == null
          ? ''
          : jsonEncode(attachmentUpload),
      'send_status': sendStatus,
      'retry_count': 0,
      'firestore_doc_id': firestoreDocId,
      'owner_phone_number': (ownerPhoneNumber ?? senderPhone).trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'last_error': '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Caches cloud messages without acknowledging or replacing the local outbox.
  Future<void> upsertChatMessages(List<Map<String, dynamic>> rows) async {
    final database = await _openDatabase();
    await database.transaction((tx) async {
      for (final row in rows) {
        // Query local: stored chat message state
        final existing = await tx.query(
          'pending_messages',
          columns: ['send_status', 'awaiting_cloud_snapshot'],
          where: 'local_id = ?',
          whereArgs: [row['local_id']],
          limit: 1,
        );
        if (existing.isNotEmpty && existing.single['send_status'] != 'sent') {
          continue;
        }
        // Update local: save chat message
        await tx.insert('pending_messages', {
          ...row,
          if (existing.isNotEmpty)
            'awaiting_cloud_snapshot':
                existing.single['awaiting_cloud_snapshot'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// Clears the local acknowledgement overlay only after the cloud lists that message.
  Future<void> confirmDownloadedChatMessages(
    String owner,
    String chatId,
    Iterable<String> ids,
  ) async {
    final db = await _openDatabase();
    await db.transaction((tx) async {
      for (final id in ids) {
        // Update local: confirm downloaded messages
        await tx.update(
          'pending_messages',
          {'awaiting_cloud_snapshot': 0},
          where:
              'owner_phone_number = ? AND chat_id = ? AND local_id = ? AND send_status = ?',
          whereArgs: [owner, chatId, id, 'sent'],
        );
      }
    });
  }

  /// Saves an uploaded file reference while retaining its bytes until message acknowledgement.
  Future<void> saveUploadedChatAttachment(
    String owner,
    String chatId,
    String id,
    Map<String, dynamic> attachment,
  ) async {
    final db = await _openDatabase();
    // Update local: save uploaded attachment details
    await db.update(
      'pending_messages',
      {'attachment_json': jsonEncode(attachment)},
      where: 'owner_phone_number = ? AND chat_id = ? AND local_id = ?',
      whereArgs: [owner, chatId, id],
    );
  }

  /// Loads pending messages.
  Future<List<Map<String, dynamic>>> loadPendingMessages({
    String? ownerPhoneNumber,
  }) async {
    final database = await _openDatabase();
    final owner = ownerPhoneNumber?.trim();
    // Query local: outgoing messages awaiting upload
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

  /// Loads all local messages for chat.
  Future<List<Map<String, dynamic>>> loadAllLocalMessagesForChat(
    String chatId, {
    String? ownerPhoneNumber,
  }) async {
    final database = await _openDatabase();
    final owner = ownerPhoneNumber?.trim();
    // Query local: saved conversation messages
    return database.query(
      'pending_messages',
      where: owner == null || owner.isEmpty
          ? 'chat_id = ?'
          : 'owner_phone_number = ? AND chat_id = ?',
      whereArgs: owner == null || owner.isEmpty ? [chatId] : [owner, chatId],
      orderBy: 'created_at ASC',
    );
  }

  /// Updates local message status.
  Future<void> updateLocalMessageStatus(
    String localId,
    String status, {
    String? firestoreDocId,
    String lastError = '',
    required String ownerPhoneNumber,
    String? chatId,
    Map<String, dynamic>? attachment,
    DateTime? sentAt,
  }) async {
    final database = await _openDatabase();
    final values = <String, dynamic>{
      'send_status': status,
      if (sentAt != null) 'created_at': sentAt.toUtc().toIso8601String(),
      if (status == 'sent') 'awaiting_cloud_snapshot': 1,
      if (status == 'sent') 'attachment_bytes': null,
      if (status == 'sent') 'attachment_upload_json': '',
      if (attachment != null) 'attachment_json': jsonEncode(attachment),
      'last_error': lastError,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (firestoreDocId != null) {
      values['firestore_doc_id'] = firestoreDocId;
    }
    // Update local: update message send status
    await database.update(
      'pending_messages',
      values,
      where:
          'owner_phone_number = ? AND local_id = ?${chatId == null ? '' : ' AND chat_id = ?'}',
      whereArgs: [ownerPhoneNumber, localId, if (chatId != null) chatId],
    );
  }

  /// Loads pending messages for chat.
  Future<List<Map<String, dynamic>>> loadPendingMessagesForChat(
    String chatId, {
    String? ownerPhoneNumber,
  }) async {
    final database = await _openDatabase();
    final owner = ownerPhoneNumber?.trim();
    // Query local: pending messages by chat
    return database.query(
      'pending_messages',
      where: owner == null || owner.isEmpty
          ? 'chat_id = ? AND (send_status IN (?, ?, ?) OR awaiting_cloud_snapshot = 1)'
          : 'owner_phone_number = ? AND chat_id = ? AND (send_status IN (?, ?, ?) OR awaiting_cloud_snapshot = 1)',
      whereArgs: owner == null || owner.isEmpty
          ? [chatId, 'pending', 'unsent', 'failed']
          : [owner, chatId, 'pending', 'unsent', 'failed'],
      orderBy: 'created_at ASC',
    );
  }

  /// Computes increment pending message retry.
  Future<void> incrementPendingMessageRetry(
    String localId, {
    required String ownerPhoneNumber,
    String? chatId,
  }) async {
    final database = await _openDatabase();
    // Update local: count failed message retry
    await database.rawUpdate(
      '''UPDATE pending_messages
         SET retry_count = retry_count + 1, send_status = 'failed',
             updated_at = ?
         WHERE owner_phone_number = ? AND local_id = ?${chatId == null ? '' : ' AND chat_id = ?'}''',
      [
        DateTime.now().toUtc().toIso8601String(),
        ownerPhoneNumber,
        localId,
        if (chatId != null) chatId,
      ],
    );
  }

  /// Creates route cache table.
  Future<void> _createRouteCacheTable(Database database) async {
    // Update local: create route cache
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

  // saveRouteCache keeps the provider route under its trail/checkpoint identity for offline reuse.
  /// Saves route cache.
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
    // Update local: cache route, distance and duration
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

  /// Loads route cache.
  Future<Map<String, dynamic>?> loadRouteCache({
    required String trailId,
    required String checkpointsHash,
  }) async {
    final database = await _openDatabase();
    // Query local: route by trail and checkpoint hash
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

  // dumpAllTables exposes application tables for diagnostics, excluding SQLite and Android engine
  // metadata.
  /// Computes dump all tables.
  Future<Map<String, List<Map<String, dynamic>>>> dumpAllTables() async {
    final database = await _openDatabase();
    // Query local: SQLite tables and diagnostic rows
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

  /// Adds column if missing.
  Future<void> _addColumnIfMissing(
    Database database, {
    required String tableName,
    required String columnName,
    required String definition,
  }) async {
    // Query local: columns before schema migration
    final columns = await database.rawQuery('PRAGMA table_info($tableName)');
    final exists = columns.any((column) => column['name'] == columnName);
    if (exists) {
      return;
    }
    // Update local: add missing migration column
    await database.execute(
      'ALTER TABLE $tableName ADD COLUMN $columnName $definition',
    );
  }

  /// Computes configure database factory.
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

  /// Computes session to row.
  Map<String, Object?> _sessionToRow(AppSession session) {
    return {
      'phone_number': session.phoneNumber,
      'created_at': session.createdAt.toUtc().toIso8601String(),
      'signed_in_at': session.signedInAt.toUtc().toIso8601String(),
      'app_instance_id': session.appInstanceId,
      'is_admin': session.isAdmin ? 1 : 0,
      'is_super_admin': session.isSuperAdmin ? 1 : 0,
      'username': session.username,
      'requires_onboarding': session.requiresOnboarding ? 1 : 0,
      'onboarding_profile_complete': session.isOnboardingProfileComplete
          ? 1
          : 0,
      'photo_url': session.photoURL,
      'photo_bytes': session.photoBytes,
    };
  }

  /// Computes session from row.
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
      isSuperAdmin: row['is_super_admin'] == 1,
      username: row['username'] as String? ?? '',
      requiresOnboarding: row['requires_onboarding'] == 1,
      isOnboardingProfileComplete: row['onboarding_profile_complete'] == 1,
      photoURL: row['photo_url'] as String?,
      photoBytes: row['photo_bytes'] is Uint8List
          ? row['photo_bytes'] as Uint8List
          : null,
    );
  }

  /// Computes emergency contact from row.
  EmergencyContact _emergencyContactFromRow(Map<String, Object?> row) {
    return EmergencyContact(
      name: row['name'] as String? ?? '',
      phoneNumber: row['contact_phone_number'] as String? ?? '',
      relationship: row['relationship'] as String? ?? '',
    );
  }

  /// Computes new app instance id.
  String _newAppInstanceId() {
    final random = math.Random.secure();
    final parts = List.generate(
      4,
      (_) => random.nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0'),
    );
    return 'hc_${DateTime.now().microsecondsSinceEpoch}_${parts.join()}';
  }
}

/// Represents local planned hike state.
class LocalPlannedHikeState {
  /// Creates local planned hike state.
  const LocalPlannedHikeState({
    required this.ownerPhoneNumber,
    required this.upcomingHike,
    required this.completedChecklistItems,
    required this.isConsumed,
    required this.updatedAt,
    this.preparationHash = '',
    this.scheduleSyncPending = false,
    this.creationKey = '',
    this.joinPolicy = 'approval',
    this.reminderPreference,
    this.reminderSyncPending = false,
  });

  /// Creates local planned hike state using from row.
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
      preparationHash: row['preparation_hash'] as String? ?? '',
      scheduleSyncPending: row['schedule_sync_pending'] == 1,
      creationKey: row['creation_key'] as String? ?? '',
      joinPolicy: row['join_policy'] as String? ?? 'approval',
      reminderPreference: row['reminder_preference_json'] == null
          ? null
          : HikeReminderPreference.fromFirestore(
              _decodeJsonMap(row['reminder_preference_json'] as String?),
            ),
      reminderSyncPending: row['reminder_sync_pending'] == 1,
      completedChecklistItems: GearChecklistCatalog.sanitize(checklist),
      isConsumed: row['is_consumed'] == 1,
      updatedAt:
          DateTime.tryParse(row['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String ownerPhoneNumber;
  final UpcomingHike upcomingHike;
  final String preparationHash;
  final bool scheduleSyncPending;
  final String creationKey;
  final String joinPolicy;
  final HikeReminderPreference? reminderPreference;
  final bool reminderSyncPending;
  final Set<String> completedChecklistItems;
  final bool isConsumed;
  final DateTime updatedAt;
}

/// Represents local pending hike end.
class LocalPendingHikeEnd {
  static const trailRatingKey = '_pendingTrailRating';

  /// Creates local pending hike end.
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

  /// Creates local pending hike end using from row.
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

  Map<String, dynamic>? historyPreview(String owner, {String? cloudId}) {
    final hike = activeHike;
    if (hike == null) return null;
    final finish = endedAt ?? createdAt;
    final summary = summaryPayload?.containsKey('durationSeconds') == true
        ? summaryPayload!
        : HikeSummaryReport.fromActiveHike(
            activeHike: hike,
            endedAt: finish,
          ).toFirestore();
    return {
      'sessionId':
          cloudId ??
          canonicalCompletedHikeSessionId(
            owner: owner,
            sessionId: sessionId,
            sourceUpcomingHikeId: hike.sourceUpcomingHikeId,
            teamSessionId: hike.teamHikeSessionId,
          ),
      'startedAtLocal': hike.startedAt.toUtc().toIso8601String(),
      'endedAtLocal': finish.toUtc().toIso8601String(),
      'trailId': hike.trail.trailId,
      'trailName': hike.trail.name,
      'location': hike.trail.locationLabel,
      'difficulty': hike.trail.difficulty,
      'hikeType': hike.draft.hikeType.name,
      'teamHikeSessionId': hike.teamHikeSessionId,
      'teamMemberCount': 1 + hike.draft.teamBuddies.length,
      'coverImageUrl': hike.trail.coverImageUrl,
      for (final key in [
        'durationSeconds',
        'distanceKm',
        'checkIns',
        'manualPins',
        'routePointCount',
        'batteryStartPercent',
        'batteryEndPercent',
      ])
        key: summary[key],
    };
  }

  Map<String, dynamic>? get trailRating {
    final value = summaryPayload?[trailRatingKey];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  /// Returns active hike.
  ActiveHikeSession? get activeHike {
    if (activeHikePayload.isEmpty) return null;
    try {
      return ActiveHikeSession.fromPersistence(activeHikePayload);
    } catch (_) {
      return null;
    }
  }
}

/// Represents local footprint.
class LocalFootprint {
  /// Creates local footprint.
  const LocalFootprint({
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

  /// Creates local footprint using from row.
  factory LocalFootprint.fromRow(Map<String, Object?> row) {
    final latitude = row['latitude'];
    final longitude = row['longitude'];
    final altitude = row['altitude'];
    final accuracy = row['accuracy'];
    final batteryLevel = row['battery_level'];
    return LocalFootprint(
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

  /// Returns has valid coordinate.
  bool get hasValidCoordinate => _isValidCoordinate(latitude, longitude);
}

/// Represents device notification record.
class DeviceNotificationRecord {
  /// Creates device notification record.
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

  /// Creates device notification record using from row.
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

  /// Returns is opened.
  bool get isOpened => openedAt != null;
}

/// Represents local queued alert.
class LocalQueuedAlert {
  /// Creates local queued alert.
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

  /// Creates local queued alert using from row.
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

/// Checks whether valid coordinate.
bool _isValidCoordinate(double latitude, double longitude) {
  return latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

/// Computes decode json map.
Map<String, dynamic> _decodeJsonMap(String? value) {
  if (value == null || value.isEmpty) return const {};
  try {
    final decoded = jsonDecode(value);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
  } catch (_) {
    return const {};
  }
}

/// Computes decode nullable json map.
Map<String, dynamic>? _decodeNullableJsonMap(String? value) {
  if (value == null || value.isEmpty) return null;
  final decoded = _decodeJsonMap(value);
  return decoded.isEmpty ? null : decoded;
}

/// Computes decode json string list.
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

/// Computes planned hike schedule key.
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

part of 'local_session_database.dart';

/// Computes preparation hash.
String _preparationHash(
  Map<String, dynamic> payload,
  Iterable<String> checklist,
) {
  final items = checklist.toList()..sort();
  return stableContentHash({'draft': payload['draft'], 'checklist': items});
}

/// Resolves planned hike id.
Future<String> _resolvePlannedHikeId(
  DatabaseExecutor database,
  String owner,
  String id,
) async {
  final rows = await database.query(
    'planned_hike_state',
    columns: ['upcoming_hike_id'],
    where:
        'owner_phone_number = ? AND (upcoming_hike_id = ? OR creation_key = ?)',
    whereArgs: [
      owner,
      id,
      id.startsWith('local_pending_')
          ? id.substring('local_pending_'.length)
          : 'unmatched',
    ],
    limit: 1,
  );
  return rows.isEmpty ? id : rows.first['upcoming_hike_id'] as String;
}

/// Provides helpers for `LocalSessionDatabase`.
extension LocalPlanningDatabase on LocalSessionDatabase {
  /// Loads preparation safety preference.
  Future<Object?> loadPreparationSafetyPreference({
    required String ownerPhoneNumber,
    required String hikeId,
  }) async {
    final database = await _openDatabase();
    return database.transaction((transaction) async {
      final id = await _resolvePlannedHikeId(
        transaction,
        ownerPhoneNumber.trim(),
        hikeId,
      );
      final rows = await transaction.query(
        'local_preferences',
        columns: ['value_json'],
        where: 'owner_phone_number = ? AND preference_key = ?',
        whereArgs: [ownerPhoneNumber.trim(), 'hike_safety_settings:$id'],
        limit: 1,
      );
      return rows.isEmpty
          ? null
          : jsonDecode(rows.first['value_json'] as String);
    });
  }

  /// Saves preparation safety preference.
  Future<void> savePreparationSafetyPreference({
    required String ownerPhoneNumber,
    required String hikeId,
    required Object value,
  }) async {
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      final id = await _resolvePlannedHikeId(
        transaction,
        ownerPhoneNumber.trim(),
        hikeId,
      );
      await transaction.insert('local_preferences', {
        'owner_phone_number': ownerPhoneNumber.trim(),
        'preference_key': 'hike_safety_settings:$id',
        'value_json': jsonEncode(value),
        'is_dirty': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Resolves planned hike id.
  Future<String> resolvePlannedHikeId({
    required String ownerPhoneNumber,
    required String hikeId,
  }) async => _resolvePlannedHikeId(
    await _openDatabase(),
    ownerPhoneNumber.trim(),
    hikeId,
  );

  /// Loads preparation sharing preference.
  Future<Object?> loadPreparationSharingPreference({
    required String ownerPhoneNumber,
    required String hikeId,
  }) async {
    final database = await _openDatabase();
    return database.transaction((transaction) async {
      final id = await _resolvePlannedHikeId(
        transaction,
        ownerPhoneNumber.trim(),
        hikeId,
      );
      final rows = await transaction.query(
        'local_preferences',
        columns: ['value_json'],
        where: 'owner_phone_number = ? AND preference_key = ?',
        whereArgs: [ownerPhoneNumber.trim(), 'hike_preparation_sharing:$id'],
        limit: 1,
      );
      return rows.isEmpty
          ? null
          : jsonDecode(rows.first['value_json'] as String);
    });
  }

  /// Saves preparation sharing preference.
  Future<void> savePreparationSharingPreference({
    required String ownerPhoneNumber,
    required String hikeId,
    required Object value,
  }) async {
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      final id = await _resolvePlannedHikeId(
        transaction,
        ownerPhoneNumber.trim(),
        hikeId,
      );
      await transaction.insert('local_preferences', {
        'owner_phone_number': ownerPhoneNumber.trim(),
        'preference_key': 'hike_preparation_sharing:$id',
        'value_json': jsonEncode(value),
        'is_dirty': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Computes queue scheduled hike.
  Future<String> queueScheduledHike({
    required String ownerPhoneNumber,
    required UpcomingHike hike,
    required String creationKey,
    required String joinPolicy,
    required HikeReminderPreference reminderPreference,
  }) async {
    final database = await _openDatabase();
    return database.transaction((transaction) async {
      final existing = await transaction.query(
        'planned_hike_state',
        where: 'owner_phone_number = ? AND creation_key = ?',
        whereArgs: [ownerPhoneNumber.trim(), creationKey],
        limit: 1,
      );
      final id = existing.isEmpty
          ? hike.id
          : existing.first['upcoming_hike_id'] as String;
      final payload = {
        ...hike.toPersistence(),
        'sessionId': id,
        'joinPolicy': joinPolicy,
      };
      final items = GearChecklistCatalog.sanitize(
        hike.draft?.completedChecklistItems ?? {},
      ).toList()..sort();
      await transaction.insert('planned_hike_state', {
        'owner_phone_number': ownerPhoneNumber.trim(),
        'upcoming_hike_id': id,
        'upcoming_payload_json': jsonEncode(payload),
        'completed_checklist_json': jsonEncode(items),
        'preparation_hash': _preparationHash(payload, items),
        'schedule_sync_pending': id.startsWith('local_pending_') ? 1 : 0,
        'creation_key': creationKey,
        'join_policy': joinPolicy == 'open' ? 'open' : 'approval',
        'reminder_preference_json': jsonEncode(
          reminderPreference.normalized().toFirestore(),
        ),
        'reminder_sync_pending': 1,
        'has_cloud_snapshot': existing.isEmpty
            ? 0
            : existing.first['has_cloud_snapshot'] ?? 0,
        'is_consumed': existing.isEmpty ? 0 : existing.first['is_consumed'],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return id;
    });
  }

  /// Computes confirm scheduled hike.
  Future<void> confirmScheduledHike({
    required String ownerPhoneNumber,
    required String creationKey,
    required String cloudHikeId,
  }) async {
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'planned_hike_state',
        where: 'owner_phone_number = ? AND creation_key = ?',
        whereArgs: [ownerPhoneNumber.trim(), creationKey],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final row = Map<String, Object?>.from(rows.first);
      final oldId = row['upcoming_hike_id'] as String;
      final payload = _decodeJsonMap(row['upcoming_payload_json'] as String?);
      payload['sessionId'] = cloudHikeId;
      row['upcoming_hike_id'] = cloudHikeId;
      row['upcoming_payload_json'] = jsonEncode(payload);
      row['schedule_sync_pending'] = 0;
      await transaction.insert(
        'planned_hike_state',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (oldId != cloudHikeId) {
        await transaction.delete(
          'planned_hike_state',
          where: 'owner_phone_number = ? AND upcoming_hike_id = ?',
          whereArgs: [ownerPhoneNumber.trim(), oldId],
        );
        for (final prefix in [
          'hike_preparation_sharing',
          'hike_safety_settings',
        ]) {
          await transaction.update(
            'local_preferences',
            {'preference_key': '$prefix:$cloudHikeId'},
            where: 'owner_phone_number = ? AND preference_key = ?',
            whereArgs: [ownerPhoneNumber.trim(), '$prefix:$oldId'],
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  /// Saves planned reminder preference.
  Future<void> savePlannedReminderPreference({
    required String ownerPhoneNumber,
    required String hikeId,
    required HikeReminderPreference preference,
    bool pendingSync = true,
  }) async {
    final database = await _openDatabase();
    await database.update(
      'planned_hike_state',
      {
        'reminder_preference_json': jsonEncode(
          preference.normalized().toFirestore(),
        ),
        'reminder_sync_pending': pendingSync ? 1 : 0,
      },
      where: 'owner_phone_number = ? AND upcoming_hike_id = ?',
      whereArgs: [ownerPhoneNumber.trim(), hikeId],
    );
  }

  /// Acknowledges the sent choices, including pending records in the old format.
  Future<void> acknowledgePlannedReminderPreference({
    required String ownerPhoneNumber,
    required String hikeId,
    required HikeReminderPreference preference,
  }) async {
    final database = await _openDatabase();
    final expected = jsonEncode(preference.normalized().toFirestore());
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'planned_hike_state',
        columns: ['reminder_preference_json'],
        where: 'owner_phone_number = ? AND upcoming_hike_id = ?',
        whereArgs: [ownerPhoneNumber.trim(), hikeId],
      );
      if (rows.isEmpty) return;
      final raw = rows.single['reminder_preference_json'];
      if (raw is! String || raw.isEmpty) return;
      final current = HikeReminderPreference.fromFirestore(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      // A late receipt must never clear a newer local preference edit.
      if (jsonEncode(current.toFirestore()) != expected) return;
      await transaction.update(
        'planned_hike_state',
        {'reminder_sync_pending': 0, 'reminder_preference_json': expected},
        where: 'owner_phone_number = ? AND upcoming_hike_id = ?',
        whereArgs: [ownerPhoneNumber.trim(), hikeId],
      );
    });
  }

  /// Creates upcoming hike reminders table.
  Future<void> _createUpcomingHikeRemindersTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS upcoming_hike_reminders (
        owner_phone_number TEXT NOT NULL,
        reminder_key TEXT NOT NULL,
        hike_id TEXT NOT NULL,
        notification_id INTEGER NOT NULL UNIQUE,
        departure_at TEXT NOT NULL,
        remind_at TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        PRIMARY KEY (owner_phone_number, reminder_key)
      )
    ''');
  }

  /// Loads hike reminders.
  Future<List<LocalHikeReminder>> loadHikeReminders() async {
    final database = await _openDatabase();
    return (await database.query(
      'upcoming_hike_reminders',
    )).map(LocalHikeReminder.fromRow).toList();
  }

  /// Saves hike reminder.
  Future<LocalHikeReminder> saveHikeReminder({
    required String ownerPhoneNumber,
    required String reminderKey,
    required String hikeId,
    required DateTime departureAt,
    required DateTime remindAt,
    required String contentHash,
  }) async {
    final database = await _openDatabase();
    return database.transaction((transaction) async {
      final rows = await transaction.query(
        'upcoming_hike_reminders',
        where: 'owner_phone_number = ? AND reminder_key = ?',
        whereArgs: [ownerPhoneNumber, reminderKey],
        limit: 1,
      );
      final saved = rows.isEmpty ? null : LocalHikeReminder.fromRow(rows.first);
      var id =
          saved?.notificationId ??
          (0x40000000 +
              int.parse(
                stableContentHash(
                  '$ownerPhoneNumber:$reminderKey',
                ).substring(0, 7),
                radix: 16,
              ));
      if (saved == null) {
        while ((await transaction.query(
          'upcoming_hike_reminders',
          columns: ['notification_id'],
          where: 'notification_id = ?',
          whereArgs: [id],
          limit: 1,
        )).isNotEmpty) {
          id = id == 0x4fffffff ? 0x40000000 : id + 1;
        }
      }
      final row = <String, Object?>{
        'owner_phone_number': ownerPhoneNumber,
        'reminder_key': reminderKey,
        'hike_id': hikeId,
        'notification_id': id,
        'departure_at': departureAt.toUtc().toIso8601String(),
        'remind_at': (saved?.remindAt ?? remindAt).toUtc().toIso8601String(),
        'content_hash': contentHash,
        'status': saved?.status ?? 'pending',
      };
      await transaction.insert(
        'upcoming_hike_reminders',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return LocalHikeReminder.fromRow(row);
    });
  }

  /// Sets hike reminder status.
  Future<void> setHikeReminderStatus(int notificationId, String status) async {
    final database = await _openDatabase();
    await database.update(
      'upcoming_hike_reminders',
      {'status': status},
      where: 'notification_id = ?',
      whereArgs: [notificationId],
    );
  }
}

/// Represents local hike reminder.
class LocalHikeReminder {
  /// Creates local hike reminder using from row.
  LocalHikeReminder.fromRow(Map<String, Object?> row)
    : ownerPhoneNumber = row['owner_phone_number'] as String,
      reminderKey = row['reminder_key'] as String,
      hikeId = row['hike_id'] as String,
      notificationId = row['notification_id'] as int,
      departureAt = DateTime.parse(row['departure_at'] as String),
      remindAt = DateTime.parse(row['remind_at'] as String),
      contentHash = row['content_hash'] as String,
      status = row['status'] as String;

  final String ownerPhoneNumber;
  final String reminderKey;
  final String hikeId;
  final int notificationId;
  final DateTime departureAt;
  final DateTime remindAt;
  final String contentHash;
  final String status;
}

part of 'local_session_database.dart';

/// Computes achievement int.
int _achievementInt(Object? value) =>
    value is num && value.isFinite ? value.toInt() : 0;

/// Computes achievement rows.
List<Map<String, dynamic>> _achievementRows(Object? json) {
  try {
    final decoded = jsonDecode(json as String? ?? '[]');
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where(
          (row) =>
              row['achievementId'] is String &&
              (row['achievementId'] as String).isNotEmpty &&
              (AchievementCatalog.visible(row) || row['isUnlocked'] == true),
        )
        .toList();
  } catch (_) {
    return [];
  }
}

/// Provides helpers for `LocalSessionDatabase`.
extension LocalAchievementEvents on LocalSessionDatabase {
  /// Creates achievement event tables.
  Future<void> _createAchievementEventTables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS achievement_event_receipts (
      owner_phone_number TEXT NOT NULL, event_key TEXT NOT NULL,
      metric_key TEXT NOT NULL, recorded_at TEXT NOT NULL,
      PRIMARY KEY(owner_phone_number, event_key))''');
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS achievement_notification_outbox (
      owner_phone_number TEXT NOT NULL, achievement_id TEXT NOT NULL,
      payload_json TEXT NOT NULL, created_at TEXT NOT NULL, delivered_at TEXT,
      PRIMARY KEY(owner_phone_number, achievement_id))''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS achievement_sync_state (
      owner_phone_number TEXT PRIMARY KEY, has_server_baseline INTEGER NOT NULL DEFAULT 0)''',
    );
  }

  /// Commit event receipts, visible progress and notification intents atomically.
  Future<List<Map<String, dynamic>>> updateLocalAchievementProgress({
    required String ownerPhoneNumber,
    required List<Map<String, dynamic>> seedRows,
    List<AchievementMetricEvent> events = const [],
    List<Map<String, dynamic>>? serverRows,
    bool freshServerSnapshot = false,
  }) async {
    await AchievementCatalog.load();
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty) return const [];
    final db = await _openDatabase();
    final result = await db.transaction((tx) async {
      final cached = await tx.query(
        'achievement_progress_cache',
        where: 'owner_phone_number = ?',
        whereArgs: [owner],
        limit: 1,
      );
      var rows = cached.isEmpty
          ? seedRows.map((row) => Map<String, dynamic>.from(row)).toList()
          : _achievementRows(cached.single['payload_json']);
      final state = await tx.query(
        'achievement_sync_state',
        where: 'owner_phone_number = ?',
        whereArgs: [owner],
        limit: 1,
      );
      final hasBaseline =
          state.isNotEmpty && state.single['has_server_baseline'] == 1;
      if (!hasBaseline) {
        final knownIds = rows.map((row) => row['achievementId']).toSet();
        rows.addAll(
          seedRows
              .where((row) => knownIds.add(row['achievementId']))
              .map((row) => Map<String, dynamic>.from(row)),
        );
      }
      final now = DateTime.now().toUtc().toIso8601String();

      /// Records unlock.
      Future<void> recordUnlock(
        Map<String, dynamic> row, {
        required bool announce,
      }) async {
        final existing = await tx.query(
          'achievement_notification_outbox',
          columns: ['achievement_id'],
          where: 'owner_phone_number = ? AND achievement_id = ?',
          whereArgs: [owner, row['achievementId']],
          limit: 1,
        );
        if (existing.isNotEmpty) return;
        await tx.insert(
          'achievement_notification_outbox',
          {
            'owner_phone_number': owner,
            'achievement_id': row['achievementId'],
            'payload_json': jsonEncode({...row, '_deviceHistorySaved': true}),
            'created_at': now,
            'delivered_at': announce ? null : now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (announce) {
          final notification = AchievementNotification(owner: owner, row: row);
          await _saveDeviceNotification(
            tx,
            ownerPhoneNumber: owner,
            messageId: notification.messageId,
            title: notification.title,
            body: notification.body,
            type: 'local_achievement_unlocked',
            deepLink: notification.deepLink,
            data: notification.data,
            receivedAt:
                DateTime.tryParse(row['awardedAtLocal']?.toString() ?? '') ??
                DateTime.now(),
            source: 'local_achievement',
          );
        }
      }

      if (serverRows != null) {
        final oldById = {for (final row in rows) row['achievementId']: row};
        final next = <Map<String, dynamic>>[];
        for (final remote in serverRows.where(
          (row) => AchievementCatalog.visible(row) || row['isUnlocked'] == true,
        )) {
          final row = Map<String, dynamic>.from(remote);
          final old = oldById.remove(row['achievementId']);
          final target = _achievementInt(
            row['targetCount'],
          ).clamp(1, 1000000000);
          final serverProgress = row['isUnlocked'] == true
              ? target
              : _achievementInt(row['progressCount']).clamp(0, target);
          final localProgress = old?['metricKey'] != row['metricKey']
              ? 0
              : _achievementInt(old?['localProgressCount']).clamp(0, target);
          final progress = math.max(serverProgress, localProgress);
          final unlocked = row['isUnlocked'] == true || progress >= target;
          row['progressCount'] = progress;
          row['isUnlocked'] = unlocked;
          if (localProgress > serverProgress) {
            row['localProgressCount'] = localProgress;
          }
          if (unlocked) {
            row['pointsAwarded'] = _achievementInt(row['pointsAwarded']) > 0
                ? row['pointsAwarded']
                : row['rewardPoints'];
            row['awardedAtLocal'] ??= old?['awardedAtLocal'] ?? now;
          }
          if (unlocked && old?['isUnlocked'] != true) {
            await recordUnlock(row, announce: hasBaseline);
          }
          next.add(row);
        }
        // Keep unsynchronized local progress if a remote catalog refresh omits it.
        next.addAll(
          oldById.values.where(
            (row) => _achievementInt(row['localProgressCount']) > 0,
          ),
        );
        rows = next;
        if (freshServerSnapshot) {
          await tx.insert('achievement_sync_state', {
            'owner_phone_number': owner,
            'has_server_baseline': 1,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      for (final event in events) {
        final metric = AchievementCatalog.metric(event.metricKey);
        if (event.eventKey.isEmpty ||
            metric == null ||
            event.increment < 1 ||
            event.increment > (metric['maxIncrement'] as num).toInt()) {
          continue;
        }
        final seen = await tx.query(
          'achievement_event_receipts',
          where: 'owner_phone_number = ? AND event_key = ?',
          whereArgs: [owner, event.eventKey],
          limit: 1,
        );
        if (seen.isNotEmpty) continue;
        await tx.insert('achievement_event_receipts', {
          'owner_phone_number': owner,
          'event_key': event.eventKey,
          'metric_key': event.metricKey,
          'recorded_at': now,
        });
        for (final row in rows) {
          if (row['isActive'] == false ||
              row['metricKey'] != event.metricKey ||
              row['isUnlocked'] == true) {
            continue;
          }
          final target = row['rewardType'] == 'one_time'
              ? 1
              : _achievementInt(row['targetCount']).clamp(1, 1000000000);
          final progress =
              (_achievementInt(row['progressCount']) + event.increment).clamp(
                0,
                target,
              );
          row['progressCount'] = progress;
          row['localProgressCount'] = progress;
          row['isUnlocked'] = progress >= target;
          if (row['isUnlocked'] == true) {
            row['pointsAwarded'] = _achievementInt(row['rewardPoints']);
            row['awardedAtLocal'] = now;
            await recordUnlock(row, announce: true);
          }
        }
      }
      await tx.insert('achievement_progress_cache', {
        'owner_phone_number': owner,
        'content_hash': achievementProgressContentHash(rows),
        'payload_json': jsonEncode(rows),
        'cached_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return rows;
    });
    LocalSessionDatabase._deviceNotificationChanges.add(owner);
    return result;
  }

  /// Computes pending achievement notifications.
  Future<List<Map<String, dynamic>>> pendingAchievementNotifications(
    String owner,
  ) async {
    await AchievementCatalog.load();
    final db = await _openDatabase();
    final rows = await db.query(
      'achievement_notification_outbox',
      where: 'owner_phone_number = ? AND delivered_at IS NULL',
      whereArgs: [owner.trim()],
      orderBy: 'created_at ASC',
    );
    final cache = await db.query(
      'achievement_progress_cache',
      where: 'owner_phone_number = ?',
      whereArgs: [owner.trim()],
      limit: 1,
    );
    final current = {
      for (final row in _achievementRows(
        cache.isEmpty ? null : cache.single['payload_json'],
      ))
        row['achievementId']: row,
    };
    return rows
        .map(
          (row) => Map<String, dynamic>.from(
            jsonDecode(row['payload_json'] as String) as Map,
          ),
        )
        .where(
          (row) =>
              AchievementCatalog.visible(row) &&
              (current[row['achievementId']] ?? row)['isActive'] != false,
        )
        .toList();
  }

  /// Older outbox entries may predate atomic history writes. Import each once,
  /// so a banner retry cannot restore a history item the hiker deleted.
  Future<void> recordPendingAchievementNotificationHistory(String owner) async {
    final db = await _openDatabase();
    final changed = await db.transaction((tx) async {
      var changed = false;
      final pending = await tx.query(
        'achievement_notification_outbox',
        where: 'owner_phone_number = ? AND delivered_at IS NULL',
        whereArgs: [owner],
      );
      for (final saved in pending) {
        final row = Map<String, dynamic>.from(
          jsonDecode(saved['payload_json'] as String) as Map,
        );
        if (row['_deviceHistorySaved'] == true) continue;
        final notification = AchievementNotification(owner: owner, row: row);
        await _saveDeviceNotification(
          tx,
          ownerPhoneNumber: owner,
          messageId: notification.messageId,
          title: notification.title,
          body: notification.body,
          type: 'local_achievement_unlocked',
          deepLink: notification.deepLink,
          data: notification.data,
          receivedAt: DateTime.tryParse(saved['created_at'] as String),
          source: 'local_achievement',
        );
        row['_deviceHistorySaved'] = true;
        await tx.update(
          'achievement_notification_outbox',
          {'payload_json': jsonEncode(row)},
          where: 'owner_phone_number = ? AND achievement_id = ?',
          whereArgs: [owner, notification.achievementId],
        );
        changed = true;
      }
      return changed;
    });
    if (changed) LocalSessionDatabase._deviceNotificationChanges.add(owner);
  }

  /// Marks achievement notification delivered.
  Future<void> markAchievementNotificationDelivered(
    String owner,
    String achievementId,
  ) async {
    final db = await _openDatabase();
    await db.update(
      'achievement_notification_outbox',
      {'delivered_at': DateTime.now().toUtc().toIso8601String()},
      where: 'owner_phone_number = ? AND achievement_id = ?',
      whereArgs: [owner.trim(), achievementId],
    );
  }

  /// Loads achievement notification.
  Future<Map<String, dynamic>?> loadAchievementNotification(
    String owner,
    String achievementId,
  ) async {
    final db = await _openDatabase();
    final rows = await db.query(
      'achievement_notification_outbox',
      where: 'owner_phone_number = ? AND achievement_id = ?',
      whereArgs: [owner.trim(), achievementId],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : Map<String, dynamic>.from(
            jsonDecode(rows.single['payload_json'] as String) as Map,
          );
  }
}

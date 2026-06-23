import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

import '../../home/Model/hike_session_models.dart';
import '../../sos/Model/sos_models.dart';
import '../Model/app_session.dart';

class LocalSessionDatabase {
  Database? _database;
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
    });
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
      return activeHike;
    } catch (error) {
      debugPrint('Unable to restore active hike snapshot: $error');
      await clearActiveHikeSession(phoneNumber: phoneNumber);
      return null;
    }
  }

  Future<void> clearActiveHikeSession({required String phoneNumber}) async {
    final database = await _openDatabase();
    await database.delete(
      'active_hike_session',
      where: 'owner_phone_number = ?',
      whereArgs: [phoneNumber],
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

  Future<Database> _openDatabase() async {
    final existingDatabase = _database;
    if (existingDatabase != null) {
      return existingDatabase;
    }

    _configureDatabaseFactory();
    final databaseDirectory = await getDatabasesPath();
    final databasePath = path.join(databaseDirectory, 'hiker_circle.db');
    debugPrint('HikerCircle SQLite database path: $databasePath');

    _database = await openDatabase(
      databasePath,
      version: 13,
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
            photo_url TEXT
          )
        ''');
        await _createSafetyTables(database);
        await _createDeviceBindingTables(database);
        await _createEmergencyContactsTable(database);
        await _createRouteCacheTable(database);
        await _createPendingMessagesTable(database);
        await _createActiveHikeSessionTable(database);
        await _createChatReadReceiptsTable(database);
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
      },
    );

    return _database!;
  }

  Future<int> insertLocationPoint({
    required String sessionId,
    required double latitude,
    required double longitude,
    double? altitude,
    double? accuracy,
    int? batteryLevel,
    required String pointType,
    bool isSynced = false,
  }) async {
    final database = await _openDatabase();
    return database.insert('local_location_points', {
      'session_id': sessionId,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'accuracy': accuracy,
      'battery_level': batteryLevel,
      'point_type': pointType,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
    });
  }

  Future<int> insertQueuedAlert({
    required String sessionId,
    required String alertType,
    required double triggerLatitude,
    required double triggerLongitude,
    required String payloadJson,
  }) async {
    final database = await _openDatabase();
    final now = DateTime.now().toUtc().toIso8601String();
    return database.insert('queued_alerts', {
      'session_id': sessionId,
      'alert_type': alertType,
      'trigger_latitude': triggerLatitude,
      'trigger_longitude': triggerLongitude,
      'trigger_time': now,
      'payload_json': payloadJson,
      'send_status': 'queued',
      'retry_count': 0,
      'created_at': now,
    });
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
      'SELECT COUNT(*) AS total FROM local_location_points WHERE session_id = ? AND is_synced = 0',
      [sessionId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> _createSafetyTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS local_location_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
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
        created_at TEXT NOT NULL
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

  Future<void> _createChatReadReceiptsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS chat_read_receipts (
        chat_id TEXT PRIMARY KEY,
        last_read_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
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
    return '$sizeLabel map cache, $downloadedMapCount route packs, $networkObservationCount network samples';
  }
}

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

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
    await database.insert(
      'users',
      _sessionToRow(session),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearSession() async {
    final database = await _openDatabase();
    await database.delete('users');
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
      version: 3,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE users (
            phone_number TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            signed_in_at TEXT NOT NULL
          )
        ''');
        await _createSafetyTables(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await _createSafetyTables(database);
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
    );
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

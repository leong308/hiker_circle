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
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE users (
            phone_number TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            signed_in_at TEXT NOT NULL
          )
        ''');
      },
    );

    return _database!;
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

// SecureLocalDatabase opens SQLCipher on mobile and migrates plaintext with native locking and
// recoverable file replacement.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

/// Represents secure local database.
abstract final class SecureLocalDatabase {
  // Registered by the plugin on every foreground and headless Flutter engine.
  static const _channel = MethodChannel('hiker_circle/database_security');

  // SecureLocalDatabase.open validates the native key, then holds the migration lease while
  // opening the protected database.
  /// Opens.
  static Future<Database> open(
    String path, {
    int? version,
    OnDatabaseCreateFn? onCreate,
    OnDatabaseVersionChangeFn? onUpgrade,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return openDatabase(
        path,
        version: version,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
      );
    }
    final key = await _channel.invokeMethod<String>('databaseKey', {
      'name': 'flutter-main',
    });
    if (key == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
      throw StateError('The protected local database key is unavailable.');
    }
    final lease = await _channel.invokeMethod<String>('acquireDatabase', {
      'path': path,
    });
    if (lease == null || lease.isEmpty) {
      throw StateError('Database migration lock unavailable.');
    }
    try {
      await _migratePlaintext(path, key);
      // Read-only preflight prevents the plugin's writable corruption recovery
      // from deleting an existing database when the device key is unavailable.
      if (await File(path).exists()) {
        final check = await cipher.openDatabase(
          path,
          password: key,
          readOnly: true,
          singleInstance: false,
        );
        try {
          // Query local: encrypted SQLite schema
          await check.rawQuery('SELECT count(*) FROM sqlite_master');
        } finally {
          await check.close();
        }
      }
      return await cipher.openDatabase(
        path,
        password: key,
        version: version,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
      );
    } finally {
      await _channel.invokeMethod<void>('releaseDatabase', {
        'path': path,
        'lease': lease,
      });
    }
  }

  /// Computes plain.
  static Future<bool> _plain(File file) async {
    if (!await file.exists() || await file.length() < 16) return false;
    final handle = await file.open();
    try {
      return String.fromCharCodes(await handle.read(16)) ==
          'SQLite format 3\u0000';
    } finally {
      await handle.close();
    }
  }

  // _migratePlaintext exports into a verified encrypted replacement and keeps recoverable rename
  // state across crashes.
  /// Computes migrate plaintext.
  static Future<void> _migratePlaintext(String path, String key) async {
    final source = File(path);
    final backup = File('$path.migration-original');
    final target = File('$path.encrypted-pending');
    // Recover a crash between the two atomic renames without dropping records.
    if (!await source.exists() && await backup.exists()) {
      await backup.rename(path);
    }
    if (!await _plain(source)) {
      if (await source.exists() && await backup.exists()) {
        final check = await cipher.openDatabase(
          path,
          password: key,
          readOnly: true,
          singleInstance: false,
        );
        try {
          // Query local: recovered database integrity
          await check.rawQuery('SELECT count(*) FROM sqlite_master');
        } finally {
          await check.close();
        }
        await backup.delete();
      }
      return;
    }
    if (await target.exists()) await target.delete();
    final original = await cipher.openDatabase(
      path,
      password: '',
      singleInstance: false,
    );
    try {
      // Update local: export legacy SQLite data with encryption
      await original.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      final oldVersion = await original.getVersion();
      final quotedPath = target.path.replaceAll("'", "''");
      await original.execute(
        "ATTACH DATABASE '$quotedPath' AS encrypted KEY '$key'",
      );
      await original.rawQuery("SELECT sqlcipher_export('encrypted')");
      await original.execute('PRAGMA encrypted.user_version = $oldVersion');
      await original.execute('DETACH DATABASE encrypted');
    } finally {
      await original.close();
    }
    final check = await cipher.openDatabase(
      target.path,
      password: key,
      readOnly: true,
      singleInstance: false,
    );
    try {
      // Query local: encrypted replacement database integrity
      final integrity = await check.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty || integrity.first.values.first != 'ok') {
        throw StateError(
          'The encrypted database migration did not pass its integrity check.',
        );
      }
    } finally {
      await check.close();
    }
    await source.rename(backup.path);
    await target.rename(path);
    // Both databases were closed and WAL checkpointed before replacing the file.
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final sidecar = File('$path$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }
    await backup.delete();
  }
}

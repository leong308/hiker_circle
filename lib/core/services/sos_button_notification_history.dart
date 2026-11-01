import '../../app/Data/local_session_database.dart';
import 'hiker_ble_service.dart';

/// Copies native background notices into the same account-scoped tray as other local alerts.
abstract final class SosButtonNotificationHistory {
  static final _running = <String, Future<void>>{};
  static final _again = <String>{};

  /// Coalesces native callbacks while preserving notices that arrive during an earlier read.
  static Future<void> synchronize({
    required String owner,
    required HikerBleService ble,
    LocalSessionDatabase? database,
  }) {
    final pending = _running[owner];
    if (pending != null) {
      _again.add(owner);
      return pending;
    }
    final db = database ?? LocalSessionDatabase();
    final work = _copy(owner, ble, db);
    _running[owner] = work;
    return work.whenComplete(() {
      _running.remove(owner);
      if (_again.remove(owner)) {
        synchronize(owner: owner, ble: ble, database: db);
      }
    });
  }

  /// Rechecks account ownership and acknowledges only records successfully stored in SQLite.
  static Future<void> _copy(
    String owner,
    HikerBleService ble,
    LocalSessionDatabase db,
  ) async {
    try {
      if ((await db.loadSession())?.phoneNumber != owner) return;
      final rows = await ble.readSosButtonNotices(owner);
      final acknowledged = <String>[];
      for (final row in rows) {
        if ((await db.loadSession())?.phoneNumber != owner) return;
        final id = row['messageId'];
        final type = row['type'];
        final millis = row['receivedAtMillis'];
        if (id is! String ||
            millis is! num ||
            !{'sos_button_seen', 'sos_button_unseen'}.contains(type)) {
          continue;
        }
        await db.saveDeviceNotification(
          ownerPhoneNumber: owner,
          messageId: id,
          title: row['title'] as String,
          body: row['body'] as String,
          type: type as String,
          deepLink: row['deepLink'] as String,
          receivedAt: DateTime.fromMillisecondsSinceEpoch(
            millis.toInt(),
            isUtc: true,
          ),
          source: 'local',
        );
        acknowledged.add(id);
      }
      if (acknowledged.isNotEmpty) {
        await ble.acknowledgeSosButtonNotices(owner, acknowledged);
      }
    } catch (_) {
      /* Native history remains durable and is retried on the next callback or resume. */
    }
  }
}

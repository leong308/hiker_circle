import '../../app/Data/local_session_database.dart';

/// Each receiving device owns its chat mute choices, including background isolates.
class ChatMuteStore {
  /// Uses encrypted account-scoped storage in foreground and background isolates.
  ChatMuteStore(this.database);
  final LocalSessionDatabase database;
  static final _migrations = <String, Future<void>>{};

  /// Coalesces the one-time import without replacing an explicit device choice.
  Future<void> _migrate(String owner) async {
    final existing = _migrations[owner];
    if (existing != null) return existing;
    final work = _importDownloadedMutes(owner);
    _migrations[owner] = work;
    try {
      await work;
    } finally {
      if (identical(_migrations[owner], work)) _migrations.remove(owner);
    }
  }

  /// Missing downloaded settings can be imported later; explicit local unmutes always win.
  Future<void> _importDownloadedMutes(String owner) async {
    if (await database.loadLocalPreference(
          ownerPhoneNumber: owner,
          key: 'local_chat_mutes_migrated',
        ) ==
        true) {
      return;
    }
    final cached = await database.loadCachedEntity(
      ownerPhoneNumber: owner,
      entityType: 'mobile_preferences',
      entityId: 'current',
      includeExpired: true,
    );
    final preferences = cached?.payload['preferences'];
    if (preferences is! Map) return;
    final muted = preferences['groupChatMutedUntil'];
    if (muted is Map) {
      for (final entry in muted.entries) {
        final key = 'local_chat_mute:${entry.key}';
        if (await database.loadLocalPreference(
                  ownerPhoneNumber: owner,
                  key: key,
                ) ==
                null &&
            entry.value is String) {
          await database.seedLocalPreference(owner, key, entry.value);
        }
      }
    }
    await database.saveLocalPreference(
      ownerPhoneNumber: owner,
      key: 'local_chat_mutes_migrated',
      value: true,
    );
  }

  /// Reads only this account's local mute; cloud preference snapshots cannot replace it.
  Future<DateTime?> load(String owner, String chatId) async {
    await _migrate(owner);
    final value = await database.loadLocalPreference(
      ownerPhoneNumber: owner,
      key: 'local_chat_mute:$chatId',
    );
    final until = value is String ? DateTime.tryParse(value) : null;
    return until != null && until.isAfter(DateTime.now()) ? until : null;
  }

  /// Unmuting persists an explicit local deletion without waiting for connectivity.
  Future<void> save(String owner, String chatId, DateTime? until) async {
    await _migrate(owner);
    await database.saveLocalPreference(
      ownerPhoneNumber: owner,
      key: 'local_chat_mute:$chatId',
      value: until?.isAfter(DateTime.now()) == true
          ? until!.toUtc().toIso8601String()
          : false,
    );
  }

  /// Safety and team lifecycle notifications never pass through the chat mute filter.
  static Future<bool> suppress(
    Map<String, dynamic> data, {
    String? owner,
    LocalSessionDatabase? database,
  }) async {
    if (data['type'] != 'group_chat_message') return false;
    final db = database ?? LocalSessionDatabase();
    final account = owner ?? (await db.loadSession())?.phoneNumber;
    final chatId = data['chatId'];
    if (account == null || chatId is! String || chatId.isEmpty) return true;
    if (data['recipientPhone'] != null && data['recipientPhone'] != account) {
      return true;
    }
    return await ChatMuteStore(db).load(account, chatId) != null;
  }
}

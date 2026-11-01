import 'dart:async';

import '../../app/Data/conditional_cloud_cache.dart';

/// Downloaded chat display preferences; server authorization is kept separate.
class DownloadedChatPreferences {
  DownloadedChatPreferences.fromSnapshot(Map<String, dynamic> snapshot) {
    final raw = snapshot['preferences'];
    final preferences = raw is Map ? raw : const <String, dynamic>{};
    notificationsEnabled =
        preferences['groupChatNotificationsEnabled'] != false;
    final pins = preferences['pinnedChats'];
    pinnedChatIds = pins is Map
        ? pins.keys
              .where((key) => pins[key] == true || _date(pins[key]) != null)
              .map((key) => key.toString())
              .toSet()
        : <String>{};
    final muted = preferences['groupChatMutedUntil'];
    mutedUntilByChat = {
      if (muted is Map)
        for (final entry in muted.entries)
          if (_date(entry.value) case final DateTime until)
            entry.key.toString(): until,
    };
  }

  late final bool notificationsEnabled;
  late final Set<String> pinnedChatIds;
  late final Map<String, DateTime> mutedUntilByChat;

  DateTime? mutedUntilFor(String chatId, {DateTime? now}) {
    final until = mutedUntilByChat[chatId];
    return until != null && until.isAfter(now ?? DateTime.now()) ? until : null;
  }

  static DateTime? _date(Object? value) => switch (value) {
    DateTime date => date,
    String text => DateTime.tryParse(text),
    _ => null,
  };
}

/// Applies batched preference downloads without starting another network read.
class ChatPreferenceCacheObserver {
  ChatPreferenceCacheObserver({
    required this.owner,
    required this.readOwner,
    required this.readCached,
    required this.onChanged,
    required Stream<CacheResourceUpdate> changes,
  }) {
    _subscription = changes.listen((change) {
      if (change.owner == owner &&
          change.type == 'mobile_preferences' &&
          change.id == 'current') {
        unawaited(refresh(clearMissing: change.revoked));
      }
    });
  }

  final String owner;
  final String Function() readOwner;
  final Future<Map<String, dynamic>> Function() readCached;
  final void Function(DownloadedChatPreferences) onChanged;
  late final StreamSubscription<CacheResourceUpdate> _subscription;
  bool _disposed = false;
  bool _needsRefresh = false;
  bool _needsRevocationClear = false;
  int _writes = 0;
  int _generation = 0;

  /// Invalidate an older display read before optimistic local editing begins.
  void beginWrite() {
    _writes++;
    _generation++;
    _needsRefresh = true;
  }

  /// Reapply the latest acknowledged cache once all local writes finish.
  void endWrite() {
    if (_writes > 0) _writes--;
    if (_writes == 0 && _needsRefresh) unawaited(refresh());
  }

  Future<void> refresh({bool clearMissing = false}) async {
    if (_disposed || readOwner() != owner) return;
    if (clearMissing) _needsRevocationClear = true;
    if (_writes > 0) {
      _needsRefresh = true;
      return;
    }
    _needsRefresh = false;
    final generation = ++_generation;
    try {
      final snapshot = await readCached();
      if (_disposed ||
          readOwner() != owner ||
          generation != _generation ||
          _writes > 0) {
        return;
      }
      if (snapshot['preferences'] is! Map && !_needsRevocationClear) {
        // An acknowledged edit remains visible if its follow-up cloud read
        // failed after invalidation. A later download will replace it.
        return;
      }
      onChanged(DownloadedChatPreferences.fromSnapshot(snapshot));
      _needsRevocationClear = false;
    } catch (_) {
      // Keep the visible local choice if cache storage is temporarily unavailable.
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_subscription.cancel());
  }
}

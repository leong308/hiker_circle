import 'dart:async';

/// Notifies local screens and the active account's platform notification host.
abstract final class AchievementNotificationEvents {
  static final _changes = StreamController<String>.broadcast(sync: true);

  /// Returns changes.
  static Stream<String> get changes => _changes.stream;
  static final _hosts = <String, Future<void> Function()>{};

  /// Computes register.
  static void Function() register(
    String owner,
    Future<void> Function() deliver,
  ) {
    _hosts[owner] = deliver;
    return () {
      if (_hosts[owner] == deliver) _hosts.remove(owner);
    };
  }

  /// Computes changed.
  static Future<void> changed(String owner) async {
    _changes.add(owner);
    try {
      await _hosts[owner]?.call();
    } catch (_) {
      // The durable notification outbox retries on the next foreground session.
    }
  }
}

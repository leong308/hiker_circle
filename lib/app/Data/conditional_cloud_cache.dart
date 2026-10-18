// ConditionalCloudCache reuses local payloads and sends content/revision hashes for authenticated
// refreshes without rewriting unchanged data.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'local_session_database.dart';

/// Local-first non-real-time reads. Hash checks never poll the full collection.
class ConditionalCloudCache {
  ConditionalCloudCache(this.database, this.functions, {String? Function()? currentOwner})
    : currentOwner = currentOwner ?? (() => FirebaseAuth.instance.currentUser?.uid);
  final LocalSessionDatabase database;
  final FirebaseFunctions Function() functions;
  final String? Function() currentOwner;
  final _pending = <String, Future<Map<String, dynamic>>>{};
  final _checked = <String, DateTime>{};
  void _requireOwner(String owner) {
    if (owner.isNotEmpty && currentOwner() != owner) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'The signed-in account changed.',
      );
    }
  }

  // ConditionalCloudCache.read coalesces requests by owner/resource and rejects responses after an
  // account change.
  Future<Map<String, dynamic>> read({
    required String owner,
    required String type,
    required String id,
    required String callable,
    required Map<String, Object?> arguments,
    required Duration freshness,
    bool online = true,
    bool force = false,
  }) async {
    final key = '$owner/$type/$id';
    final existing = _pending[key];
    if (existing != null) return existing;
    final future = _read(
      owner,
      type,
      id,
      callable,
      arguments,
      freshness,
      online,
      force,
      key,
    );
    _pending[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  Future<Map<String, dynamic>> _read(
    String owner,
    String type,
    String id,
    String callable,
    Map<String, Object?> arguments,
    Duration freshness,
    bool online,
    bool force,
    String key,
  ) async {
    final cached = await database.loadCachedEntity(
      ownerPhoneNumber: owner,
      entityType: type,
      entityId: id,
      includeExpired: true,
    );
    final now = DateTime.now().toUtc();
    final validation = cached == null ? null : await database.loadCachedEntity(
      ownerPhoneNumber: owner, entityType: '$type:validation', entityId: id, includeExpired: true);
    final validMetadata = validation?.payload['contentHash'] == cached?.payload['contentHash'] ? validation : null;
    final revision = validMetadata?.payload['revisionHash'] ?? cached?.payload['revisionHash'];
    final fullCheckedAt = (validMetadata?.payload['fullCheckedAtMillis'] as num?)?.toInt()
      ?? cached?.cachedAt.millisecondsSinceEpoch ?? 0;
    final checked = _checked[key] ?? cached?.cachedAt;
    if (cached != null &&
        (!online ||
            (!force && checked != null && now.difference(checked) < freshness)))
      return cached.payload;
    if (!online) return const {};
    try {
      _requireOwner(owner);
      final response = await functions()
          .httpsCallable(callable)
          .call<Map<String, dynamic>>({
            ...arguments,
            if (owner.isNotEmpty) 'expectedOwner': owner,
            if (cached != null)
              'knownContentHash': cached.payload['contentHash'],
            if (cached != null) 'knownRevision': revision,
            'forcePayload':
                force ||
                (cached != null &&
                    now.millisecondsSinceEpoch - fullCheckedAt > const Duration(hours: 6).inMilliseconds),
          })
          .timeout(const Duration(seconds: 20));
      final data = Map<String, dynamic>.from(response.data);
      _requireOwner(owner);
      _checked[key] = now;
      if (data['notModified'] == true) {
        if (cached == null ||
            data['contentHash'] != cached.payload['contentHash'])
          throw const FormatException('Invalid cache validation');
        if (data['revisionHash'] != revision || data['payloadChecked'] == true) {
          await database.saveCachedEntity(LocalCachedEntity(ownerPhoneNumber: owner,
            entityType: '$type:validation', entityId: id, parentId: '', cachedAt: now,
            payload: {'revisionHash': data['revisionHash'], 'contentHash': data['contentHash'],
              'fullCheckedAtMillis': data['payloadChecked'] == true ? now.millisecondsSinceEpoch : fullCheckedAt}));
        }
        // Only small validation metadata changes; unchanged history rows stay intact.
        return cached.payload;
      }
      await database.saveCachedEntity(
        LocalCachedEntity(
          ownerPhoneNumber: owner,
          entityType: type,
          entityId: id,
          parentId: '',
          payload: data,
          cachedAt: now,
        ),
      );
      await database.saveCachedEntity(LocalCachedEntity(ownerPhoneNumber: owner,
        entityType: '$type:validation', entityId: id, parentId: '', cachedAt: now,
        payload: {'revisionHash': data['revisionHash'], 'contentHash': data['contentHash'],
          'fullCheckedAtMillis': now.millisecondsSinceEpoch}));
      return data;
    } on FirebaseFunctionsException catch (error) {
      if (const {'unauthenticated', 'permission-denied'}.contains(error.code))
        rethrow;
      if (cached != null) return cached.payload;
      rethrow;
    } catch (_) {
      if (cached != null) return cached.payload;
      rethrow;
    }
  }
}

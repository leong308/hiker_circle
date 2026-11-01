part of 'hiker_circle_firebase_repository.dart';

final _achievementMaintenance = <String, Future<void>>{};

/// Read-model refresh never writes over drafts, pending messages or safety queues.
extension MobileReadRepository on HikerCircleFirebaseRepository {
  Stream<CacheResourceUpdate> get cachedReadUpdates =>
      _conditionalCache.updates;

  bool isReadCacheReconciliationPaused(String owner) =>
      _conditionalCache.isRevalidationPausedFor(owner);

  Future<void> _invalidateReadModel(String owner, String resourceType) async {
    try {
      await _conditionalCache.invalidate(
        owner: owner,
        type: 'mobile_$resourceType',
        id: 'current',
      );
    } catch (_) {
      /* Confirmed writes are not undone by a cache storage failure. */
    }
  }

  Future<Map<String, dynamic>> readMobileSnapshot({
    required String owner,
    required String resourceType,
    Map<String, Object?> resourceArgs = const {},
    String id = 'current',
    bool force = false,
    bool cacheOnly = false,
  }) => _conditionalCache.read(
    owner: owner,
    type: 'mobile_$resourceType',
    id: id,
    callable: 'readMobileResource',
    arguments: {
      'resourceType': resourceType,
      if (resourceArgs.isNotEmpty) 'resourceArgs': resourceArgs,
    },
    freshness: const Duration(minutes: 2),
    online: _firebaseBootstrapResult.isAvailable,
    force: force,
    cacheOnly: cacheOnly,
  );

  /// Compare cloud snapshots first; release readers before replaying independent durable writes.
  Future<CacheReconciliationResult> reconcileCachedReadsAfter({
    required AppSession session,
    required Future<void> Function() synchronizePending,
    Future<void> Function()? recoverLive,
  }) async {
    final CacheReconciliationResult result;
    try {
      result = await _conditionalCache.withRevalidationPaused(
        owner: session.phoneNumber,
        action: () async {
          try {
            await _registerDownloadedCloudReads(session);
          } on FirebaseFunctionsException catch (error) {
            if (error.code == 'unauthenticated') rethrow;
          } catch (_) {
            // Cache registration must not prevent durable local uploads.
          }
          return _conditionalCache.reconcileRegistered(
            owner: session.phoneNumber,
          );
        },
      );
    } catch (error, stack) {
      // Live recovery can join an earlier read which was waiting for this hold.
      // Always release the hold first, including when hash validation failed.
      try {
        await synchronizePending();
        await recoverLive?.call();
      } catch (_) {
        // Preserve the original synchronization failure for its caller.
      }
      Error.throwWithStackTrace(error, stack);
    }
    await synchronizePending();
    await recoverLive?.call();
    return result;
  }

  Future<void> _refreshPreferenceSnapshot(AppSession session) async {
    try {
      await _conditionalCache.invalidate(
        owner: session.phoneNumber,
        type: 'mobile_preferences',
        id: 'current',
      );
      await readMobileSnapshot(
        owner: session.phoneNumber,
        resourceType: 'preferences',
        force: true,
      );
    } catch (_) {
      // The setting's acknowledged write remains valid if its display reload fails.
    }
  }

  /// Award backfill is a mutation and completes before the read-hash batch.
  Future<void> synchronizeHistoricalAchievementProgress({
    required AppSession session,
  }) {
    if (!_firebaseBootstrapResult.isAvailable) return Future.value();
    final owner = session.phoneNumber;
    final existing = _achievementMaintenance[owner];
    if (existing != null) return existing;
    final future = () async {
      await _resolvedFunctions
          .httpsCallable(
            'syncMyAchievementProgress',
            options: HttpsCallableOptions(
              timeout: const Duration(seconds: 125),
            ),
          )
          .call({'expectedOwner': owner})
          .timeout(const Duration(seconds: 125));
      await _conditionalCache.invalidate(
        owner: owner,
        type: 'mobile_achievement_progress',
        id: 'current',
      );
    }();
    _achievementMaintenance[owner] = future;
    unawaited(
      future.then<void>(
        (_) {
          if (identical(_achievementMaintenance[owner], future)) {
            _achievementMaintenance.remove(owner);
          }
        },
        onError: (Object _, StackTrace __) {
          if (identical(_achievementMaintenance[owner], future)) {
            _achievementMaintenance.remove(owner);
          }
        },
      ),
    );
    return future;
  }

  Future<Map<String, dynamic>> _readPreferences(AppSession session) async {
    final snapshot = await readMobileSnapshot(
      owner: session.phoneNumber,
      resourceType: 'preferences',
    );
    final preferences = snapshot['preferences'];
    return preferences is Map
        ? Map<String, dynamic>.from(preferences)
        : const {};
  }

  Future<Map<String, dynamic>> _readSocial(AppSession session) =>
      readMobileSnapshot(owner: session.phoneNumber, resourceType: 'social');

  List<Map<String, dynamic>> _snapshotRows(
    Map<String, dynamic> snapshot,
    String field,
  ) => snapshot[field] is List
      ? (snapshot[field] as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
      : const [];
}

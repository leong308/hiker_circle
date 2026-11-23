// Read-cache hashes detect changed content; pending writes retain their own
// durable identities, ordering and server acknowledgement rules.
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services/content_hash.dart';
import 'local_session_database.dart';

/// Chooses the read authority; durable local changes upload through their own queues.
enum CacheReadPolicy { localFirst, cloudFirst }

class CacheResourceUpdate {
  const CacheResourceUpdate({
    required this.owner,
    required this.type,
    required this.id,
    this.invalidated = false,
    this.revoked = false,
  });
  final String owner, type, id;
  final bool invalidated;

  /// Server access was denied or the resource no longer exists.
  final bool revoked;
}

class CacheReconciliationResult {
  const CacheReconciliationResult({
    this.requestedCount = 0,
    this.changedCount = 0,
    this.unchangedCount = 0,
    this.unavailableCount = 0,
    this.deferredCount = 0,
    this.skippedCount = 0,
  });
  final int requestedCount,
      changedCount,
      unchangedCount,
      unavailableCount,
      deferredCount,
      skippedCount;
  bool get isComplete =>
      unavailableCount == 0 && deferredCount == 0 && skippedCount == 0;
}

typedef ConditionalCacheRequest =
    Future<Map<String, dynamic>> Function(
      String callable,
      Map<String, Object?> arguments,
    );

/// Coordinates local-first and cloud-first reads in one owner-scoped hash batch.
class ConditionalCloudCache {
  ConditionalCloudCache(
    this.database,
    this.functions, {
    String? Function()? currentOwner,
    ConditionalCacheRequest? request,
    DateTime Function()? clock,
    this.revalidationWaitTimeout = const Duration(seconds: 8),
  }) : currentOwner = currentOwner ?? _firebaseOwner,
       _request = request,
       _clock = clock ?? DateTime.now;

  // Each account and the shared public scope retain at most 64 registered read
  // descriptors. Older downloaded payloads remain available for offline use.
  // All registered resources therefore fit one 128-item request.
  static const maximumRegisteredResourcesPerOwner = 64;
  static const maximumBatchResources = 128;
  static const maximumOwnerReadWorkUnits = 12288;
  static const maximumPublicReadWorkUnits = 4096;
  static const _descriptorType = 'conditional_read_descriptor';
  static const _ownerCallables = {
    'readMobileResource',
    'listMyHikeHistory',
    'loadMyHikeHistoryDetail',
    'listExpiredScheduledHikes',
    'loadAchievementLeaderboard',
  };
  static final _updates = StreamController<CacheResourceUpdate>.broadcast();
  static final _refreshes = <String, Future<Map<String, dynamic>>>{};
  static final _refreshEpochs = <String, int>{};
  static final _refreshVerifications = <String, bool>{};
  static final _batches = <String, Future<CacheReconciliationResult>>{};
  static final _checked = <String, DateTime>{};
  static final _epochs = <String, int>{};
  static final _validationVersions = <String, int>{};
  static final _pauses = <String, int>{};
  static final _pauseCompletions = <String, Completer<void>>{};
  static final _batchResourceKeys = <String, Set<String>>{};
  static final _batchAttemptVersions = <String, int>{};
  static final _successfulBatchAttempts = <String, int>{};
  static final _pauseOwnersZoneKey = Object();

  final Duration revalidationWaitTimeout;
  final LocalSessionDatabase database;
  final FirebaseFunctions Function() functions;
  final String? Function() currentOwner;
  final ConditionalCacheRequest? _request;
  final DateTime Function() _clock;
  Stream<CacheResourceUpdate> get updates => _updates.stream;

  /// Viewer-specific snapshots must never be stored in the shared public scope.
  static const viewerScopedCloudResources = {
    'community_posts',
    'community_post',
    'community_comments',
    'chat_messages',
  };

  /// Requires an account key for reads containing private or viewer-specific data.
  static bool _requiresOwner(String callable, Map<String, Object?> arguments) =>
      _ownerCallables.contains(callable) ||
      (callable == 'readCloudResource' &&
          viewerScopedCloudResources.contains(arguments['resourceType']));

  static String? _firebaseOwner() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    } // Local restoration can precede Firebase startup.
  }

  String? _authenticationOwner() {
    try {
      return currentOwner();
    } catch (_) {
      return null;
    }
  }

  FirebaseFunctionsException _accountChanged() => FirebaseFunctionsException(
    code: 'unauthenticated',
    message: 'The signed-in account changed.',
  );

  Future<void> _requireLocalOwner(String owner) async {
    if (owner.isEmpty) return;
    String? local;
    try {
      local = (await database.loadSession())?.phoneNumber.trim();
    } catch (_) {
      /* A cloud read can remain possible without SQLite. */
    }
    final authenticated = _authenticationOwner();
    if ((local != null && local != owner) ||
        (authenticated != null && authenticated != owner) ||
        (local != owner && authenticated != owner)) {
      throw _accountChanged();
    }
  }

  void _requireRemoteOwner(String owner) {
    if (owner.isNotEmpty && _authenticationOwner() != owner) {
      throw _accountChanged();
    }
  }

  String _key(String owner, String type, String id) =>
      stableContentHash([owner, type, id]);
  bool _paused(String owner) => owner.isEmpty
      ? _pauses.values.any((count) => count > 0)
      : (_pauses[owner] ?? 0) > 0;

  /// Automatic listeners wait for the shared pending-write/hash-batch sequence.
  bool isRevalidationPausedFor(String owner) =>
      _paused(owner) ||
      (owner.isEmpty ? _batches.isNotEmpty : _batches.containsKey(owner));

  Future<void> waitForRevalidation(String owner) => _waitForRevalidation(owner);

  bool _insidePendingWriteSequence(String owner) {
    final owners = Zone.current[_pauseOwnersZoneKey] as Set<String>?;
    return owner.isEmpty
        ? owners?.isNotEmpty == true
        : owners?.contains(owner) == true;
  }

  Future<void> _waitForRevalidation(String owner) async {
    while (isRevalidationPausedFor(owner)) {
      final waiting = <Future<void>>[
        for (final entry in _pauseCompletions.entries)
          if (owner.isEmpty || entry.key == owner) entry.value.future,
        for (final entry in _batches.entries)
          if (owner.isEmpty || entry.key == owner)
            entry.value.then<void>(
              (_) {},
              onError: (Object _, StackTrace __) {},
            ),
      ];
      if (waiting.isEmpty) return;
      await Future.wait(waiting);
    }
  }

  /// Holds automatic individual checks while pending writes and the batch run.
  Future<T> withRevalidationPaused<T>({
    required String owner,
    required Future<T> Function() action,
  }) async {
    if ((_pauses[owner] ?? 0) == 0) {
      _pauseCompletions[owner] = Completer<void>();
    }
    _pauses[owner] = (_pauses[owner] ?? 0) + 1;
    try {
      // A pending-write helper may itself load a read model. Returning its local
      // copy avoids making that helper wait for the batch which depends on it.
      // Readers opened by other UI work wait for the completed batch instead.
      final owners = <String>{
        ...?Zone.current[_pauseOwnersZoneKey] as Set<String>?,
        owner,
      };
      return await runZoned(action, zoneValues: {_pauseOwnersZoneKey: owners});
    } finally {
      final remaining = (_pauses[owner] ?? 1) - 1;
      if (remaining <= 0) {
        _pauses.remove(owner);
        _pauseCompletions.remove(owner)?.complete();
      } else {
        _pauses[owner] = remaining;
      }
    }
  }

  Future<Map<String, dynamic>> _call(
    String callable,
    Map<String, Object?> arguments, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_request != null) return _request(callable, arguments).timeout(timeout);
    final response = await functions()
        .httpsCallable(
          callable,
          options: HttpsCallableOptions(timeout: timeout),
        )
        .call<Map<String, dynamic>>(arguments)
        .timeout(timeout);
    return Map<String, dynamic>.from(response.data);
  }

  Future<LocalCachedEntity?> _cached(_ReadResource resource) async {
    try {
      return await database.loadCachedEntity(
        ownerPhoneNumber: resource.owner,
        entityType: resource.type,
        entityId: resource.id,
        includeExpired: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<LocalCachedEntity?> _validation(_ReadResource resource) async {
    try {
      return await database.loadCachedEntity(
        ownerPhoneNumber: resource.owner,
        entityType: '${resource.type}:validation',
        entityId: resource.id,
        includeExpired: true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Marks stale fallback only on the returned map, never in hashed stored data.
  Map<String, dynamic> _fallback(
    _ReadResource resource,
    Map<String, dynamic> payload,
  ) => resource.policy == CacheReadPolicy.cloudFirst && payload.isNotEmpty
      ? {...payload, 'cacheFallback': true}
      : payload;

  Future<void> _register(_ReadResource resource) async {
    final previous = await database.loadCachedEntity(
      ownerPhoneNumber: resource.owner,
      entityType: _descriptorType,
      entityId: resource.key,
      includeExpired: true,
    );
    if (previous != null &&
        (previous.payload['callable'] != resource.callable ||
            stableContentHash(
                  _ReadResource.fromDescriptor(
                    previous,
                  )?.reconciliationArguments,
                ) !=
                stableContentHash(resource.reconciliationArguments))) {
      await invalidate(
        owner: resource.owner,
        type: resource.type,
        id: resource.id,
      );
    }
    await database.registerConditionalReadDescriptor(
      LocalCachedEntity(
        ownerPhoneNumber: resource.owner,
        entityType: _descriptorType,
        entityId: resource.key,
        parentId: '',
        payload: resource.toMap(),
        cachedAt: _clock().toUtc(),
      ),
      maximumPerOwner: maximumRegisteredResourcesPerOwner,
      maximumWorkUnits: resource.owner.isEmpty
          ? maximumPublicReadWorkUnits
          : maximumOwnerReadWorkUnits,
    );
  }

  /// Returns cached data immediately by default and revalidates stale data safely.
  Future<Map<String, dynamic>> read({
    required String owner,
    required String type,
    required String id,
    required String callable,
    required Map<String, Object?> arguments,
    required Duration freshness,
    bool online = true,
    bool force = false,
    CacheReadPolicy policy = CacheReadPolicy.localFirst,
    bool cacheOnly = false,
    bool registerForReconciliation = true,
  }) async {
    if (owner.trim().isEmpty && _requiresOwner(callable, arguments)) {
      throw _accountChanged();
    }
    await _requireLocalOwner(owner);
    final resource = _ReadResource(
      key: _key(owner, type, id),
      owner: owner,
      type: type,
      id: id,
      callable: callable,
      arguments: arguments,
      policy: policy,
      registered: registerForReconciliation,
    );
    if (!cacheOnly && registerForReconciliation) {
      try {
        await _register(resource);
      } catch (_) {
        /* A storage failure must not prevent the service request. */
      }
    }
    final cached = await _cached(resource);
    await _requireLocalOwner(owner);
    if (cacheOnly || !online) {
      return _fallback(resource, cached?.payload ?? const {});
    }
    if (isRevalidationPausedFor(owner)) {
      if (_insidePendingWriteSequence(owner) ||
          (policy == CacheReadPolicy.localFirst && cached != null)) {
        return _fallback(resource, cached?.payload ?? const {});
      }
      final attemptVersion = _batchAttemptVersions[resource.key] ?? 0;
      final includedInActiveBatch = _batchResourceKeys.values.any(
        (keys) => keys.contains(resource.key),
      );
      try {
        await _waitForRevalidation(owner).timeout(revalidationWaitTimeout);
      } on TimeoutException {
        await _requireLocalOwner(owner);
        return _fallback(resource, cached?.payload ?? const {});
      }
      await _requireLocalOwner(owner);
      final reconciled = await _cached(resource);
      await _requireLocalOwner(owner);
      final checkedByBatch =
          includedInActiveBatch ||
          (_batchAttemptVersions[resource.key] ?? 0) > attemptVersion;
      if (checkedByBatch && !force) {
        // This resource was already checked by the one batch. An unavailable
        // result must not immediately fan out into another individual check.
        final payload = reconciled?.payload ?? const <String, dynamic>{};
        return _successfulBatchAttempts[resource.key] ==
                _batchAttemptVersions[resource.key]
            ? payload
            : _fallback(resource, payload);
      }
      if (!force &&
          policy == CacheReadPolicy.localFirst &&
          reconciled != null) {
        return reconciled.payload;
      }
      // A screen opened after the batch captured its descriptors. Download its
      // uncached resource normally, without issuing a second manifest request.
      return _refresh(resource, verifySource: force);
    }
    if (!force && cached != null) {
      final validation = await _validation(resource);
      final validatedMillis =
          validation?.payload['contentHash'] == cached.payload['contentHash']
          ? (validation?.payload['fullCheckedAtMillis'] as num?)?.toInt()
          : null;
      final checked =
          _checked[resource.key] ??
          (validatedMillis == null
              ? cached.cachedAt
              : DateTime.fromMillisecondsSinceEpoch(
                  validatedMillis,
                  isUtc: true,
                ));
      await _requireLocalOwner(owner);
      final needsRefresh =
          validation?.payload['refreshRequired'] == true ||
          _clock().toUtc().difference(checked) >= freshness;
      if (policy == CacheReadPolicy.cloudFirst) {
        // A completed shared hash check is a server check too. Reuse it rather
        // than issuing a second request from each cloud-first screen.
        if (validatedMillis != null && !needsRefresh) {
          return (_batchAttemptVersions[resource.key] ?? 0) >
                  (_successfulBatchAttempts[resource.key] ?? 0)
              ? _fallback(resource, cached.payload)
              : cached.payload;
        }
        return _refresh(resource);
      }
      if (needsRefresh && !isRevalidationPausedFor(owner)) {
        unawaited(_refresh(resource).catchError((_) => cached.payload));
      }
      return cached.payload;
    }
    return _refresh(resource, verifySource: force);
  }

  /// Manual refresh checks the source even when an automatic manifest check is already running.
  Future<Map<String, dynamic>> _refresh(
    _ReadResource resource, {
    bool verifySource = false,
  }) {
    final epoch = _epochs[resource.key] ?? 0;
    final pending = _refreshes[resource.key];
    if (pending != null && _refreshEpochs[resource.key] == epoch) {
      if (verifySource && _refreshVerifications[resource.key] != true) {
        return pending.then(
          (_) => _refresh(resource, verifySource: true),
          onError: (Object _, StackTrace _) =>
              _refresh(resource, verifySource: true),
        );
      }
      return pending;
    }
    final operation = _fetch(
      resource,
      epoch: epoch,
      verifySource: verifySource,
    );
    _refreshes[resource.key] = operation;
    _refreshEpochs[resource.key] = epoch;
    _refreshVerifications[resource.key] = verifySource;
    void clear() {
      if (identical(_refreshes[resource.key], operation)) {
        _refreshes.remove(resource.key);
        _refreshEpochs.remove(resource.key);
        _refreshVerifications.remove(resource.key);
      }
    }

    unawaited(
      operation.then<void>(
        (_) => clear(),
        onError: (Object _, StackTrace _) => clear(),
      ),
    );
    return operation;
  }

  Future<Map<String, dynamic>> _fetch(
    _ReadResource resource, {
    required int epoch,
    required bool verifySource,
  }) async {
    await _requireLocalOwner(resource.owner);
    final baseline = await _cached(resource);
    final validationBaseline = await _validation(resource);
    if ((_epochs[resource.key] ?? 0) != epoch) {
      throw const FormatException('The requested resource changed.');
    }
    try {
      _requireRemoteOwner(resource.owner);
      final data = await _call(resource.callable, {
        ...resource.arguments,
        if (resource.owner.isNotEmpty) 'expectedOwner': resource.owner,
        if (baseline != null)
          'knownContentHash': baseline.payload['contentHash'],
        if (baseline != null) 'knownRevision': baseline.payload['revisionHash'],
        // Automatic reads compare stored hashes; explicit refresh always checks source content.
        'forcePayload': verifySource,
      });
      _requireRemoteOwner(resource.owner);
      await _requireLocalOwner(resource.owner);
      bool applied;
      try {
        applied = await _apply(
          resource,
          baseline,
          data,
          validationBaseline: validationBaseline,
          epoch: epoch,
          expectedSessionOwner: resource.owner,
        );
      } on _CachePersistenceException {
        // A valid server result can still be displayed when disk persistence
        // is unavailable. It must not outlive its account or invalidation epoch.
        _requireRemoteOwner(resource.owner);
        await _requireLocalOwner(resource.owner);
        if ((_epochs[resource.key] ?? 0) != epoch) {
          throw const FormatException('The cache changed during the request.');
        }
        return data['notModified'] == true ? baseline!.payload : data;
      }
      _requireRemoteOwner(resource.owner);
      await _requireLocalOwner(resource.owner);
      if (applied) {
        return data['notModified'] == true ? baseline!.payload : data;
      }
      final current = await _cached(resource);
      _requireRemoteOwner(resource.owner);
      await _requireLocalOwner(resource.owner);
      if (current != null) return current.payload;
      if ((_epochs[resource.key] ?? 0) == epoch &&
          data['notModified'] != true) {
        return data;
      }
      throw const FormatException('The cache changed during the request.');
    } on FirebaseFunctionsException catch (error) {
      if (const {'permission-denied', 'not-found'}.contains(error.code)) {
        await _invalidateIfCurrent(
          resource,
          baseline,
          validationBaseline,
          epoch: epoch,
          expectedSessionOwner: resource.owner,
        );
        rethrow;
      }
      if (error.code == 'unauthenticated') {
        rethrow;
      }
      await _requireLocalOwner(resource.owner);
      final cached = await _cached(resource);
      await _requireLocalOwner(resource.owner);
      if (cached != null) return _fallback(resource, cached.payload);
      rethrow;
    } catch (_) {
      await _requireLocalOwner(resource.owner);
      final cached = await _cached(resource);
      await _requireLocalOwner(resource.owner);
      if (cached != null) return _fallback(resource, cached.payload);
      rethrow;
    }
  }

  Future<bool> _apply(
    _ReadResource resource,
    LocalCachedEntity? baseline,
    Map<String, dynamic> data, {
    required LocalCachedEntity? validationBaseline,
    required int epoch,
    required String expectedSessionOwner,
  }) async {
    if ((_epochs[resource.key] ?? 0) != epoch) return false;
    final hash = data['contentHash'];
    if (hash is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Missing cache content hash.');
    }
    final unchanged = data['notModified'] == true;
    if (unchanged &&
        (baseline == null || baseline.payload['contentHash'] != hash)) {
      throw const FormatException('Invalid cache validation.');
    }
    await _requireLocalOwner(expectedSessionOwner);
    if ((_epochs[resource.key] ?? 0) != epoch) return false;
    final now = _clock().toUtc();
    final bool applied;
    try {
      applied = await database.saveConditionalCacheResponse(
        entity: LocalCachedEntity(
          ownerPhoneNumber: resource.owner,
          entityType: resource.type,
          entityId: resource.id,
          parentId: '',
          payload: unchanged ? baseline!.payload : data,
          cachedAt: now,
        ),
        validation: LocalCachedEntity(
          ownerPhoneNumber: resource.owner,
          entityType: '${resource.type}:validation',
          entityId: resource.id,
          parentId: '',
          cachedAt: now,
          payload: {
            'contentHash': hash,
            'revisionHash': data['revisionHash'],
            'fullCheckedAtMillis': now.millisecondsSinceEpoch,
          },
        ),
        expectedPayloadHash: baseline == null
            ? null
            : stableContentHash(baseline.payload),
        expectedCachedAt: baseline?.cachedAt,
        expectedValidationHash: validationBaseline == null
            ? null
            : stableContentHash(validationBaseline.payload),
        descriptorId: resource.registered ? resource.key : null,
        expectedSessionOwner: expectedSessionOwner,
        payloadChanged: !unchanged,
      );
    } on FirebaseFunctionsException {
      rethrow;
    } on FormatException {
      rethrow;
    } catch (error) {
      throw _CachePersistenceException(error);
    }
    if (!applied || (_epochs[resource.key] ?? 0) != epoch) return false;
    _checked[resource.key] = now;
    _successfulBatchAttempts[resource.key] =
        _batchAttemptVersions[resource.key] ?? 0;
    _validationVersions[resource.key] =
        (_validationVersions[resource.key] ?? 0) + 1;
    if (!unchanged && baseline?.payload['contentHash'] != hash) {
      _updates.add(
        CacheResourceUpdate(
          owner: resource.owner,
          type: resource.type,
          id: resource.id,
        ),
      );
    }
    return true;
  }

  /// Deletes only the downloaded resource, retaining its registered read recipe.
  Future<void> invalidate({
    required String owner,
    required String type,
    required String id,
  }) async {
    final key = _key(owner, type, id);
    _epochs[key] = (_epochs[key] ?? 0) + 1;
    _checked.remove(key);
    await database.deleteConditionalCacheResource(
      owner: owner,
      type: type,
      id: id,
      invalidationToken: '$key:${_epochs[key]}',
    );
    _updates.add(
      CacheResourceUpdate(owner: owner, type: type, id: id, invalidated: true),
    );
  }

  /// Confirmed writes invalidate related downloaded queries, never pending changes.
  Future<void> invalidateTypes({
    required String owner,
    required Set<String> types,
  }) async {
    final descriptors = await database.loadCachedEntities(
      ownerPhoneNumber: owner,
      entityType: _descriptorType,
      includeExpired: true,
    );
    for (final descriptor in descriptors) {
      final resource = _ReadResource.fromDescriptor(descriptor);
      if (resource == null ||
          !types.contains(resource.type) ||
          resource.key != _key(owner, resource.type, resource.id)) {
        continue;
      }
      await invalidate(owner: owner, type: resource.type, id: resource.id);
    }
  }

  Future<void> _invalidateIfCurrent(
    _ReadResource resource,
    LocalCachedEntity? baseline,
    LocalCachedEntity? validationBaseline, {
    required int epoch,
    required String expectedSessionOwner,
  }) async {
    if ((_epochs[resource.key] ?? 0) != epoch) return;
    await _requireLocalOwner(expectedSessionOwner);
    final now = _clock().toUtc();
    final nextEpoch = epoch + 1;
    final invalidated = await database.saveConditionalCacheResponse(
      entity: LocalCachedEntity(
        ownerPhoneNumber: resource.owner,
        entityType: resource.type,
        entityId: resource.id,
        parentId: '',
        payload: baseline?.payload ?? const {},
        cachedAt: now,
      ),
      validation: LocalCachedEntity(
        ownerPhoneNumber: resource.owner,
        entityType: '${resource.type}:validation',
        entityId: resource.id,
        parentId: '',
        cachedAt: now,
        payload: {
          'invalidated': true,
          'revoked': true,
          'invalidationToken': '${resource.key}:$nextEpoch',
        },
      ),
      expectedPayloadHash: baseline == null
          ? null
          : stableContentHash(baseline.payload),
      expectedCachedAt: baseline?.cachedAt,
      expectedValidationHash: validationBaseline == null
          ? null
          : stableContentHash(validationBaseline.payload),
      expectedSessionOwner: expectedSessionOwner,
      descriptorId: resource.registered ? resource.key : null,
      payloadChanged: false,
      deletePayload: true,
    );
    if (!invalidated) return;
    _epochs[resource.key] = nextEpoch;
    _checked.remove(resource.key);
    if (baseline != null || validationBaseline?.payload['revoked'] != true) {
      _updates.add(
        CacheResourceUpdate(
          owner: resource.owner,
          type: resource.type,
          id: resource.id,
          invalidated: true,
          revoked: true,
        ),
      );
    }
  }

  Future<bool> _markDeferredRefresh(
    _ReadResource resource,
    LocalCachedEntity? baseline,
    LocalCachedEntity? validationBaseline, {
    required int epoch,
    required String owner,
  }) async {
    await _requireLocalOwner(owner);
    if ((_epochs[resource.key] ?? 0) != epoch) return false;
    final now = _clock().toUtc();
    final marked = await database.saveConditionalCacheResponse(
      entity: LocalCachedEntity(
        ownerPhoneNumber: resource.owner,
        entityType: resource.type,
        entityId: resource.id,
        parentId: '',
        payload: baseline?.payload ?? const {},
        cachedAt: now,
      ),
      validation: LocalCachedEntity(
        ownerPhoneNumber: resource.owner,
        entityType: '${resource.type}:validation',
        entityId: resource.id,
        parentId: '',
        cachedAt: now,
        payload: {
          'contentHash': baseline?.payload['contentHash'],
          'fullCheckedAtMillis': 0,
          'refreshRequired': true,
          'requestGeneration': epoch + 1,
        },
      ),
      expectedPayloadHash: baseline == null
          ? null
          : stableContentHash(baseline.payload),
      expectedCachedAt: baseline?.cachedAt,
      expectedValidationHash: validationBaseline == null
          ? null
          : stableContentHash(validationBaseline.payload),
      expectedSessionOwner: owner,
      descriptorId: resource.key,
      payloadChanged: false,
    );
    if (marked) {
      _epochs[resource.key] = epoch + 1;
      _checked.remove(resource.key);
    }
    return marked;
  }

  /// All registered cached resources fit a single bounded server hash request.
  Future<CacheReconciliationResult> reconcileRegistered({
    required String owner,
  }) {
    final existing = _batches[owner];
    if (existing != null) return existing;
    final operation = _reconcile(owner);
    _batches[owner] = operation;
    void clear() {
      if (identical(_batches[owner], operation)) {
        _batches.remove(owner);
        _batchResourceKeys.remove(owner);
      }
    }

    unawaited(
      operation.then<void>(
        (_) => clear(),
        onError: (Object _, StackTrace _) => clear(),
      ),
    );
    return operation;
  }

  Future<CacheReconciliationResult> _reconcile(String owner) async {
    await _requireLocalOwner(owner);
    _requireRemoteOwner(owner);
    try {
      await database.purgeUnownedConditionalReadCaches(
        privateCallables: _ownerCallables,
      );
    } catch (_) {
      // Invalid public-scope private descriptors are also rejected below.
    }
    final descriptors = <LocalCachedEntity>[
      ...await database.loadCachedEntities(
        ownerPhoneNumber: owner,
        entityType: _descriptorType,
        includeExpired: true,
      ),
      if (owner.isNotEmpty)
        ...await database.loadCachedEntities(
          ownerPhoneNumber: '',
          entityType: _descriptorType,
          includeExpired: true,
        ),
    ];
    final resources = <_ReadResource>[];
    final baselines = <String, LocalCachedEntity?>{};
    final validations = <String, LocalCachedEntity?>{};
    final epochs = <String, int>{};
    var skipped = 0;
    for (final descriptor in descriptors) {
      final resource = _ReadResource.fromDescriptor(descriptor);
      if (resource == null ||
          resource.key != _key(resource.owner, resource.type, resource.id) ||
          (resource.owner.isEmpty &&
              _requiresOwner(resource.callable, resource.arguments))) {
        skipped += 1;
        continue;
      }
      final cached = await _cached(resource);
      resources.add(resource);
      baselines[resource.key] = cached;
      validations[resource.key] = await _validation(resource);
      epochs[resource.key] = _epochs[resource.key] ?? 0;
    }
    if (resources.length > maximumBatchResources) {
      throw StateError(
        'The registered read cache exceeds its bounded batch size.',
      );
    }
    if (resources.isEmpty) {
      return CacheReconciliationResult(skippedCount: skipped);
    }
    resources.sort((a, b) => a.key.compareTo(b.key));
    _batchResourceKeys[owner] = {
      for (final resource in resources) resource.key,
    };
    for (final resource in resources) {
      _batchAttemptVersions[resource.key] =
          (_batchAttemptVersions[resource.key] ?? 0) + 1;
    }
    // Firebase compares server-maintained manifests before rebuilding any unchanged projection.
    final response = await _call('reconcileMobileReadCache', {
      'expectedOwner': owner,
      'manifestVersion': 1,
      'resources': [
        for (final resource in resources)
          {
            ...resource.toRequest(),
            'knownContentHash': baselines[resource.key]?.payload['contentHash'],
            'knownRevision': baselines[resource.key]?.payload['revisionHash'],
          },
      ],
    }, timeout: const Duration(seconds: 125));
    _requireRemoteOwner(owner);
    await _requireLocalOwner(owner);
    if (response['manifestVersion'] != null &&
        response['manifestVersion'] != 1) {
      throw const FormatException('Unsupported sync manifest version.');
    }
    final raw = response['resources'];
    if (raw is! List) {
      throw const FormatException('Invalid cache batch result.');
    }
    final results = <String, Map<String, dynamic>>{};
    for (final value in raw) {
      if (value is! Map || value['key'] is! String) continue;
      final entry = Map<String, dynamic>.from(value);
      final key = entry['key'] as String;
      if (results.containsKey(key)) {
        throw const FormatException('Duplicate cache batch result.');
      }
      results[key] = entry;
    }
    var changed = 0, unchanged = 0, unavailable = 0, deferred = 0;
    for (final resource in resources) {
      final result = results[resource.key];
      if (result == null || result['status'] == 'unavailable') {
        if (const {
          'permission-denied',
          'not-found',
        }.contains(result?['code'])) {
          try {
            await _invalidateIfCurrent(
              resource,
              baselines[resource.key],
              validations[resource.key],
              epoch: epochs[resource.key]!,
              expectedSessionOwner: owner,
            );
          } on FirebaseFunctionsException catch (error) {
            if (error.code == 'unauthenticated') rethrow;
          } catch (_) {
            // One failed local purge must not discard other batch results.
          }
        }
        unavailable += 1;
        continue;
      }
      Map<String, dynamic> data;
      if (result['status'] == 'unchanged') {
        data = {
          'notModified': true,
          'contentHash': result['contentHash'],
          'revisionHash': result['revisionHash'],
          'payloadChecked': true,
        };
      } else if (result['status'] == 'changed') {
        final payload = result['payload'];
        if (payload is! Map) {
          // The one manifest already compared this hash. Download only its
          // changed payload through the normal read endpoint; unchanged entries
          // never produce extra requests.
          try {
            final marked = await _markDeferredRefresh(
              resource,
              baselines[resource.key],
              validations[resource.key],
              epoch: epochs[resource.key]!,
              owner: owner,
            );
            if (!marked) {
              skipped += 1;
              continue;
            }
            final version = _validationVersions[resource.key] ?? 0;
            await _refresh(resource);
            if ((_validationVersions[resource.key] ?? 0) > version) {
              changed += 1;
            } else {
              deferred += 1;
            }
          } on FirebaseFunctionsException catch (error) {
            if (error.code == 'unauthenticated') rethrow;
            deferred += 1;
          } catch (_) {
            deferred += 1;
          }
          continue;
        }
        data = {
          ...Map<String, dynamic>.from(payload),
          'contentHash': result['contentHash'],
          'revisionHash': result['revisionHash'],
          'payloadChecked': true,
        };
      } else {
        unavailable += 1;
        continue;
      }
      try {
        final applied = await _apply(
          resource,
          baselines[resource.key],
          data,
          validationBaseline: validations[resource.key],
          epoch: epochs[resource.key]!,
          expectedSessionOwner: owner,
        );
        if (!applied) {
          skipped += 1;
        } else if (result['status'] == 'unchanged') {
          _successfulBatchAttempts[resource.key] =
              _batchAttemptVersions[resource.key]!;
          unchanged += 1;
        } else {
          _successfulBatchAttempts[resource.key] =
              _batchAttemptVersions[resource.key]!;
          changed += 1;
        }
      } on FirebaseFunctionsException catch (error) {
        if (error.code == 'unauthenticated') rethrow;
        unavailable += 1;
      } catch (_) {
        unavailable += 1;
      }
    }
    return CacheReconciliationResult(
      requestedCount: resources.length,
      changedCount: changed,
      unchangedCount: unchanged,
      unavailableCount: unavailable,
      deferredCount: deferred,
      skippedCount: skipped,
    );
  }
}

class _CachePersistenceException implements Exception {
  const _CachePersistenceException(this.cause);
  final Object cause;
}

class _ReadResource {
  const _ReadResource({
    required this.key,
    required this.owner,
    required this.type,
    required this.id,
    required this.callable,
    required this.arguments,
    required this.policy,
    this.registered = true,
  });
  static _ReadResource? fromDescriptor(LocalCachedEntity descriptor) {
    final data = descriptor.payload;
    if (data['key'] is! String ||
        data['type'] is! String ||
        data['id'] is! String ||
        data['callable'] is! String ||
        data['arguments'] is! Map) {
      return null;
    }
    return _ReadResource(
      key: data['key'] as String,
      owner: descriptor.ownerPhoneNumber,
      type: data['type'] as String,
      id: data['id'] as String,
      callable: data['callable'] as String,
      arguments: Map<String, Object?>.from(data['arguments'] as Map),
      policy: data['policy'] == CacheReadPolicy.cloudFirst.name
          ? CacheReadPolicy.cloudFirst
          : CacheReadPolicy.localFirst,
    );
  }

  final String key, owner, type, id, callable;
  final Map<String, Object?> arguments;
  final CacheReadPolicy policy;
  final bool registered;

  /// Manual weather age thresholds change refresh behavior, not snapshot identity.
  Map<String, Object?> get reconciliationArguments =>
      callable == 'fetchWeatherForTrail'
      ? ({...arguments}..remove('refreshIfOlderThanMinutes'))
      : arguments;
  Map<String, Object?> toRequest() => {
    'key': key,
    'type': type,
    'id': id,
    'callable': callable,
    'arguments': arguments,
  };
  // Matches the conservative projection weights in mobile_read_cache.js.
  int get workUnits {
    int limit(Object? value, int fallback) =>
        value is num ? value.toInt() : fallback;
    if (callable == 'loadMyHikeHistoryDetail') return 2500;
    if (callable == 'listMyHikeHistory') {
      return 2 * limit(arguments['limit'], 100) + 1;
    }
    if (callable == 'listExpiredScheduledHikes') return 2000;
    if (callable == 'loadAchievementLeaderboard') return 2500;
    if (callable == 'loadPublicHikerProfile') return 100;
    if (callable == 'getPublicProfiles') {
      final phones = arguments['phoneNumbers'];
      final users = arguments['userIds'];
      final count = phones is List && phones.isNotEmpty
          ? phones.length
          : users is List && users.isNotEmpty
          ? users.length
          : limit(arguments['limit'], 80);
      return 3 * count;
    }
    if (callable == 'readCloudResource') {
      final type = arguments['resourceType'];
      final args = arguments['resourceArgs'];
      final nested = args is Map ? args : const {};
      if (type == 'trail_catalog') return 1001;
      if (type == 'trail_hazards') return 2000;
      if (type == 'community_posts') return 3 * limit(nested['limit'], 20);
      if (type == 'community_comments') return limit(nested['limit'], 50) + 3;
      if (type == 'chat_messages') return 1002;
      return 4;
    }
    final resource = arguments['resourceType'];
    final args = arguments['resourceArgs'];
    final nested = args is Map ? args : const {};
    if (resource == 'achievement_progress') return 2000;
    if (resource == 'my_feedback') return limit(nested['limit'], 100);
    if (resource == 'my_upcoming_hikes' || resource == 'chat_list') {
      return limit(nested['limit'], 200);
    }
    return 4;
  }

  Map<String, Object?> toMap() => {
    ...toRequest(),
    'arguments': reconciliationArguments,
    'policy': policy.name,
    'workUnits': workUnits,
  };
}

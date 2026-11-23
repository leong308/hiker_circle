part of '../hike_history_page_feature.dart';

/// Owns the state and non-visual actions of HikeHistoryPage.
class _HikeHistoryPageStateViewModel extends ChangeNotifier {
  /// Creates hike history page state view model.
  _HikeHistoryPageStateViewModel({
    required this.readLoadHistory,
    required this.readRepository,
  });
  final HikeHistoryListLoader? Function() readLoadHistory;
  final HikerCircleFirebaseRepository Function() readRepository;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late Future<List<HikeHistorySummary>> stateHistoryFuture;
  StreamSubscription<CacheResourceUpdate>? _cacheChanges;

  void watchCachedHistory() {
    if (readLoadHistory() != null) return;
    _cacheChanges = readRepository().cachedReadUpdates.listen((change) async {
      if (!mounted || change.type != 'hike_history_list') return;
      try {
        final owner =
            (await readRepository().localDatabase.loadSession())?.phoneNumber;
        if (!mounted || change.owner != owner) return;
        _publish(
          () => stateHistoryFuture = readRepository().loadMyHikeHistory(
            cacheOnly: true,
          ),
        );
      } catch (_) {
        // A temporary local storage error must not fail the event stream.
      }
    });
  }

  /// Loads.
  Future<List<HikeHistorySummary>> commandLoad() =>
      readLoadHistory()?.call() ?? readRepository().loadMyHikeHistory();

  /// Refreshes.
  Future<void> commandRefresh() async {
    final future =
        readLoadHistory()?.call() ??
        readRepository().loadMyHikeHistory(force: true);
    _publish(() => stateHistoryFuture = future);
    await future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        // The FutureBuilder owns the error state; a button discards this callback future.
      },
    );
  }

  StreamSubscription<String>? _sharedHistory;
  StreamSubscription<String>? _completedSyncs;
  Timer? _sharedRefresh;

  /// Refreshes visible common history cards after another hiker's result is finalized.
  void watchSharedHistory(String phone) {
    _completedSyncs = HikerCircleFirebaseRepository.completedHikeSyncs
        .where((owner) => owner == phone)
        .listen((_) async {
          if (!mounted) return;
          _publish(
            () => stateHistoryFuture = readRepository().loadMyHikeHistory(
              cacheOnly: true,
            ),
          );
          await readRepository().waitForReadCacheReconciliation(phone);
          if (mounted) await commandRefresh();
        });
    _sharedHistory = readRepository().watchTeamHistoryChanges(phone).listen((
      _,
    ) {
      if (!NetworkReachabilityService.instance.latest.isOnline ||
          readRepository().isReadCacheReconciliationPaused(phone)) {
        return;
      }
      _sharedRefresh?.cancel();
      _sharedRefresh = Timer(const Duration(milliseconds: 250), () async {
        if (!mounted ||
            !NetworkReachabilityService.instance.latest.isOnline ||
            readRepository().isReadCacheReconciliationPaused(phone)) {
          return;
        }
        try {
          await commandRefresh();
        } catch (_) {
          /* Keep the existing cached history. */
        }
      });
    }, onError: (Object _) {});
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    _sharedRefresh?.cancel();
    _sharedHistory?.cancel();
    _completedSyncs?.cancel();
    _cacheChanges?.cancel();
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _ExpiredHikeHistoryList.
class _ExpiredHikeHistoryListStateViewModel extends ChangeNotifier {
  /// Creates expired hike history list state view model.
  _ExpiredHikeHistoryListStateViewModel({
    required this.readLoader,
    required this.readRefreshLoader,
    required this.readCacheLoader,
  });
  final ExpiredHikesPageLoader Function() readLoader;
  final ExpiredHikesPageLoader Function() readRefreshLoader;
  final ExpiredHikesPageLoader Function() readCacheLoader;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  List<UpcomingHike> stateHikes = [];

  ExpiredHikesCursor? stateCursor;

  bool stateIsLoading = true;

  bool stateIsFromCache = false;

  Object? stateError;

  int stateLoadGeneration = 0;

  bool stateFailedRefresh = false;
  StreamSubscription<CacheResourceUpdate>? _cacheChanges;
  final Map<String, ExpiredHikesCursor?> _loadedRequests = {};
  final Map<String, ExpiredHikesPage> _loadedPages = {};
  final Set<String> _revokedPages = {};
  String? _activeLoadKey;
  bool _cacheReloadPending = false;
  bool _isReloadingCache = false;

  String _pageKey(ExpiredHikesCursor? cursor) =>
      jsonEncode({'limit': 30, 'cursor': cursor?.toMap()});

  void watchCachedPages(HikerCircleFirebaseRepository repository) {
    _cacheChanges = repository.cachedReadUpdates.listen((change) async {
      if (!mounted || change.type != 'expired_hike_history_page') return;
      try {
        final owner =
            (await repository.localDatabase.loadSession())?.phoneNumber;
        if (!mounted || change.owner != owner) return;
        if (!_loadedPages.containsKey(change.id) &&
            _activeLoadKey != change.id) {
          return;
        }
        if (change.revoked) {
          _revokedPages.add(change.id);
        } else if (!change.invalidated) {
          _revokedPages.remove(change.id);
        }
        _cacheReloadPending = true;
        await _reloadLoadedCache();
      } catch (_) {
        // Retain the visible page if local storage is temporarily unavailable.
      }
    });
  }

  /// Revalidate the downloaded pages already visible, preserving pagination.
  Future<void> _reloadLoadedCache() async {
    if (!mounted || stateIsLoading || _isReloadingCache) return;
    _isReloadingCache = true;
    try {
      while (mounted && _cacheReloadPending && !stateIsLoading) {
        _cacheReloadPending = false;
        final generation = stateLoadGeneration;
        final requests = Map<String, ExpiredHikesCursor?>.from(_loadedRequests);
        final pages = Map<String, ExpiredHikesPage>.from(_loadedPages);
        for (final entry in requests.entries) {
          if (_revokedPages.contains(entry.key)) {
            pages.remove(entry.key);
            continue;
          }
          try {
            pages[entry.key] = await readCacheLoader()(entry.value);
          } catch (_) {
            // Mutation invalidation or a local read failure retains this page
            // until its replacement download arrives. Revocation clears it.
            if (_revokedPages.contains(entry.key)) pages.remove(entry.key);
          }
        }
        if (!mounted) return;
        if (generation != stateLoadGeneration || stateIsLoading) {
          _cacheReloadPending = true;
          return;
        }
        _publish(() {
          _loadedPages
            ..clear()
            ..addAll(pages);
          _loadedRequests.removeWhere((key, _) => !pages.containsKey(key));
          _mergeLoadedPages();
        });
      }
    } finally {
      _isReloadingCache = false;
      if (mounted && _cacheReloadPending && !stateIsLoading) {
        unawaited(_reloadLoadedCache());
      }
    }
  }

  void _mergeLoadedPages() {
    final byId = <String, UpcomingHike>{};
    for (final page in _loadedPages.values) {
      for (final hike in page.hikes) {
        byId.putIfAbsent(hike.id, () => hike);
      }
    }
    stateHikes = byId.values.toList()
      ..sort((a, b) {
        final date = b.departureTime.compareTo(a.departureTime);
        return date != 0 ? date : b.id.compareTo(a.id);
      });
    final lastKey = _loadedPages.keys.lastOrNull;
    final requested = lastKey == null ? null : _loadedRequests[lastKey];
    final next = lastKey == null ? null : _loadedPages[lastKey]?.nextCursor;
    stateCursor =
        next != null &&
            next.hikeId == requested?.hikeId &&
            next.departureTimeLocal == requested?.departureTimeLocal
        ? null
        : next;
    stateIsFromCache = _loadedPages.values.any((page) => page.isFromCache);
  }

  /// Keep expired-hike pagination separate from refresh so existing rows remain visible while loading more.
  Future<void> commandLoad({
    bool refresh = false,
    bool force = false,
    bool cacheOnly = false,
  }) async {
    if (!refresh && (stateIsLoading || stateCursor == null)) return;
    final generation = ++stateLoadGeneration;
    final requested = refresh ? null : stateCursor;
    final requestedKey = _pageKey(requested);
    _activeLoadKey = requestedKey;
    stateFailedRefresh = refresh;
    _publish(() {
      stateIsLoading = true;
      stateError = null;
    });
    try {
      final loader = cacheOnly
          ? readCacheLoader()
          : force
          ? readRefreshLoader()
          : readLoader();
      final page = await loader(requested);
      if (!mounted || generation != stateLoadGeneration) return;
      _publish(() {
        if (refresh) {
          _loadedRequests.clear();
          _loadedPages.clear();
        }
        _loadedRequests[requestedKey] = requested;
        _loadedPages[requestedKey] = page;
        _revokedPages.remove(requestedKey);
        _mergeLoadedPages();
      });
    } catch (error) {
      if (mounted && generation == stateLoadGeneration) {
        _publish(() => stateError = error);
      }
    } finally {
      if (mounted && generation == stateLoadGeneration) {
        _activeLoadKey = null;
        _publish(() => stateIsLoading = false);
        if (_cacheReloadPending) unawaited(_reloadLoadedCache());
      }
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    _cacheChanges?.cancel();
    super.dispose();
  }
}

/// Owns the state and non-visual actions of HikeHistoryDetailPage.
class _HikeHistoryDetailPageStateViewModel extends ChangeNotifier {
  /// Creates hike history detail page state view model.
  _HikeHistoryDetailPageStateViewModel({
    required this.readLoadDetail,
    required this.readRefreshDetail,
    required this.readSummary,
  });
  final HikeHistoryDetailLoader Function() readLoadDetail;
  final HikeHistoryDetailLoader Function() readRefreshDetail;
  final HikeHistorySummary Function() readSummary;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late Future<HikeHistoryDetail> stateDetailFuture;
  StreamSubscription<CacheResourceUpdate>? _cacheChanges;

  void watchCachedDetail(HikerCircleFirebaseRepository repository) {
    _cacheChanges = repository.cachedReadUpdates.listen((change) async {
      if (!mounted ||
          change.type != 'hike_history_detail' ||
          change.id != readSummary().sessionId) {
        return;
      }
      try {
        final owner =
            (await repository.localDatabase.loadSession())?.phoneNumber;
        if (!mounted || change.owner != owner) return;
        _publish(
          () => stateDetailFuture = repository.loadMyHikeHistoryDetail(
            change.id,
            cacheOnly: true,
          ),
        );
      } catch (_) {
        // Retain the visible detail if local storage is temporarily unavailable.
      }
    });
  }

  /// Refreshes.
  Future<void> commandRefresh() async {
    final future = readRefreshDetail()(readSummary().sessionId);
    _publish(() => stateDetailFuture = future);
    await future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        // Keep the failure on stateDetailFuture for the visible retry control.
      },
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    _cacheChanges?.cancel();
    super.dispose();
  }
}

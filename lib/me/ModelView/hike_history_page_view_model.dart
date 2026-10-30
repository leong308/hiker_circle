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

  /// Loads.
  Future<List<HikeHistorySummary>> commandLoad() =>
      readLoadHistory()?.call() ?? readRepository().loadMyHikeHistory();

  /// Refreshes.
  Future<void> commandRefresh() async {
    final future =
        readLoadHistory()?.call() ??
        readRepository().loadMyHikeHistory(force: true);
    _publish(() => stateHistoryFuture = future);
    await future;
  }

  StreamSubscription<String>? _sharedHistory;
  Timer? _sharedRefresh;

  /// Refreshes visible common history cards after another hiker's result is finalized.
  void watchSharedHistory(String phone) {
    _sharedHistory = readRepository().watchTeamHistoryChanges(phone).listen((
      _,
    ) {
      _sharedRefresh?.cancel();
      _sharedRefresh = Timer(const Duration(milliseconds: 250), () async {
        if (!mounted) return;
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
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _ExpiredHikeHistoryList.
class _ExpiredHikeHistoryListStateViewModel extends ChangeNotifier {
  /// Creates expired hike history list state view model.
  _ExpiredHikeHistoryListStateViewModel({required this.readLoader});
  final ExpiredHikesPageLoader Function() readLoader;
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

  /// Keep expired-hike pagination separate from refresh so existing rows remain visible while loading more.
  Future<void> commandLoad({bool refresh = false}) async {
    if (!refresh && (stateIsLoading || stateCursor == null)) return;
    final generation = ++stateLoadGeneration;
    final requested = refresh ? null : stateCursor;
    stateFailedRefresh = refresh;
    _publish(() {
      stateIsLoading = true;
      stateError = null;
    });
    try {
      final page = await readLoader()(requested);
      if (!mounted || generation != stateLoadGeneration) return;
      _publish(() {
        final byId = <String, UpcomingHike>{
          if (!refresh)
            for (final hike in stateHikes) hike.id: hike,
        };
        for (final hike in page.hikes) {
          byId[hike.id] = hike;
        }
        stateHikes = byId.values.toList()
          ..sort((a, b) {
            final date = b.departureTime.compareTo(a.departureTime);
            return date != 0 ? date : b.id.compareTo(a.id);
          });
        final next = page.nextCursor;
        stateCursor =
            next != null &&
                next.hikeId == requested?.hikeId &&
                next.departureTimeLocal == requested?.departureTimeLocal
            ? null
            : next;
        stateIsFromCache = page.isFromCache;
      });
    } catch (error) {
      if (mounted && generation == stateLoadGeneration) {
        _publish(() => stateError = error);
      }
    } finally {
      if (mounted && generation == stateLoadGeneration) {
        _publish(() => stateIsLoading = false);
      }
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of HikeHistoryDetailPage.
class _HikeHistoryDetailPageStateViewModel extends ChangeNotifier {
  /// Creates hike history detail page state view model.
  _HikeHistoryDetailPageStateViewModel({
    required this.readLoadDetail,
    required this.readSummary,
  });
  final HikeHistoryDetailLoader Function() readLoadDetail;
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

  /// Refreshes.
  Future<void> commandRefresh() async {
    final future = readLoadDetail()(readSummary().sessionId);
    _publish(() => stateDetailFuture = future);
    await future;
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

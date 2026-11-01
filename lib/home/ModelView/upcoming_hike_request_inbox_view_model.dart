import 'package:flutter/foundation.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../Model/upcoming_hike_request_inbox.dart';

/// Loads pending requests and history independently, including after a host decision.
class UpcomingHikeRequestInboxViewModel extends ChangeNotifier {
  /// Starts with the host's selected hike and listens for confirmed decisions.
  UpcomingHikeRequestInboxViewModel({
    required this.repository,
    required this.hikeId,
  }) {
    repository.upcomingHikeJoinRequestRevision.addListener(refresh);
  }
  final HikerCircleFirebaseRepository repository;
  final String hikeId;
  final Map<bool, List<UpcomingHikeRequestEntry>> _rows = {false: [], true: []};
  final Map<bool, String?> _cursors = {};
  final Map<bool, bool> _more = {};
  bool history = false, loading = false, loadingMore = false;
  int pendingCount = 0;
  String? error;
  bool _disposed = false;
  int _generation = 0;

  /// Exposes only the currently selected list.
  List<UpcomingHikeRequestEntry> get rows => List.unmodifiable(_rows[history]!);

  /// Indicates whether another canonical page is available.
  bool get hasMore => _more[history] == true;

  /// Switches tabs without mixing pending and decided requests.
  void select(bool value) {
    if (history == value || _disposed) return;
    history = value;
    refresh();
  }

  /// Replaces the current list and ignores stale results after tab changes.
  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation, bucket = history;
    loading = true;
    loadingMore = false;
    error = null;
    notifyListeners();
    try {
      final page = await repository.loadUpcomingHikeJoinRequests(
        hikeId: hikeId,
        history: bucket,
      );
      if (_disposed || generation != _generation) return;
      _rows[bucket] = page.rows;
      _cursors[bucket] = page.nextCursor;
      _more[bucket] = page.hasMore;
      pendingCount = page.pendingCount;
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      error = failure is HikerCircleFirebaseRepositoryException
          ? failure.message
          : 'Unable to load join requests. Please try again.';
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// Appends one page while retaining already visible history if loading fails.
  Future<void> loadMore() async {
    if (_disposed || loading || loadingMore || !hasMore) return;
    final generation = _generation, bucket = history;
    loadingMore = true;
    error = null;
    notifyListeners();
    try {
      final page = await repository.loadUpcomingHikeJoinRequests(
        hikeId: hikeId,
        history: bucket,
        afterRequestId: _cursors[bucket],
      );
      if (_disposed || generation != _generation) return;
      final ids = _rows[bucket]!.map((row) => row.id).toSet();
      _rows[bucket] = [
        ..._rows[bucket]!,
        ...page.rows.where((row) => ids.add(row.id)),
      ];
      _cursors[bucket] = page.nextCursor;
      _more[bucket] = page.hasMore;
      pendingCount = page.pendingCount;
    } catch (failure) {
      if (!_disposed && generation == _generation) {
        error = 'More requests couldn’t be loaded. Please try again.';
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  /// Detaches live invalidation and prevents late responses publishing state.
  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    repository.upcomingHikeJoinRequestRevision.removeListener(refresh);
    super.dispose();
  }
}

/// Fetches badges in batches, retaining the last confirmed counts on connection errors.
class UpcomingHikeRequestCountsViewModel extends ChangeNotifier {
  /// Receives the same repository as the host's inbox.
  UpcomingHikeRequestCountsViewModel(this.repository);
  final HikerCircleFirebaseRepository repository;
  Map<String, int> counts = {};
  bool _disposed = false, _busy = false, _refreshAgain = false;
  int _generation = 0;
  List<String> _ids = [];

  /// Rebinds counts when the account's hosted hike set changes.
  void setHikes(List<String> ids) {
    final sorted = List<String>.of(ids)..sort();
    if (listEquals(sorted, _ids)) return;
    _ids = sorted;
    ++_generation;
    counts = {
      for (final id in _ids)
        if (counts[id] != null) id: counts[id]!,
    };
    refresh();
  }

  /// Queries only current host-owned IDs and ignores responses from an older hike set.
  Future<void> refresh() async {
    if (_disposed || _ids.isEmpty) return;
    if (_busy) {
      _refreshAgain = true;
      return;
    }
    final generation = _generation, ids = List<String>.of(_ids);
    _busy = true;
    try {
      final result = <String, int>{};
      for (var offset = 0; offset < ids.length; offset += 30) {
        result.addAll(
          await repository.loadUpcomingHikeJoinRequestCounts(
            ids.sublist(offset, (offset + 30).clamp(0, ids.length)),
          ),
        );
      }
      if (!_disposed && generation == _generation) {
        counts = {
          for (final id in ids)
            if (result[id] != null) id: result[id]!,
        };
        notifyListeners();
      }
    } catch (_) {
      // A connection failure must not invent a zero pending count.
    } finally {
      _busy = false;
      if (!_disposed && (generation != _generation || _refreshAgain)) {
        _refreshAgain = false;
        refresh();
      }
    }
  }

  /// Drops stale in-flight responses after leaving the dashboard.
  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../Data/admin_safety_repository.dart';
import '../Model/admin_hazard_report.dart';

/// Owns live lifecycle grouping, search, paging and expiry refreshes.
class AdminSafetyViewModel extends ChangeNotifier {
  /// Allows a fixed clock and repository in tests without accessing Firebase.
  AdminSafetyViewModel({required this.repository, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AdminSafetyRepository repository;
  final DateTime Function() _now;
  StreamSubscription<List<AdminHazardReport>>? _subscription;
  Timer? _expiryTimer;
  Timer? _loadTimer;
  Completer<void>? _pendingLoad;
  int _generation = 0;
  bool _disposed = false;
  List<AdminHazardReport> _reports = const [];

  /// Exposes a read-only snapshot for workspace diagnostics.
  List<AdminHazardReport> get reports => List.unmodifiable(_reports);
  AdminHazardStage selectedStage = AdminHazardStage.reported;
  String query = '';
  String? error;
  bool loading = false;
  bool hasData = false;
  int _limit = pageSize;
  static const pageSize = 20;

  /// Gives all lifecycle calculations the same injectable clock.
  DateTime get now => _now();

  /// Reconnects the listener, retaining previous records if refresh fails.
  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation;
    _finishLoad();
    _pendingLoad = Completer<void>();
    final pending = _pendingLoad!.future;
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _subscription?.cancel();
      if (_disposed || generation != _generation) return;
      _loadTimer = Timer(const Duration(seconds: 20), () {
        if (_disposed || generation != _generation) return;
        loading = false;
        error =
            'Reports are taking longer to load. Check your connection and retry.';
        _finishLoad();
        notifyListeners();
      });
      _subscription = repository.watchReports().listen(
        (reports) {
          if (_disposed || generation != _generation) return;
          _reports = reports.where((report) => report.isVisible).toList();
          hasData = true;
          loading = false;
          error = null;
          _finishLoad();
          _scheduleExpiry();
          notifyListeners();
        },
        onError: (Object _) {
          if (_disposed || generation != _generation) return;
          loading = false;
          error =
              'Safety reports could not refresh. Check your connection and retry.';
          _finishLoad();
          notifyListeners();
        },
      );
    } catch (_) {
      if (!_disposed && generation == _generation) {
        loading = false;
        error = 'Safety reports could not load. Please retry.';
        _finishLoad();
        notifyListeners();
      }
    }
    await pending;
  }

  /// Counts each tab independently of search and the visible page limit.
  int count(AdminHazardStage stage) {
    final instant = now;
    return _reports.where((report) => report.stageAt(instant) == stage).length;
  }

  /// Returns matching reports with stable ordering across live updates.
  List<AdminHazardReport> get matchingReports {
    final instant = now;
    final rows = _reports
        .where(
          (report) =>
              report.stageAt(instant) == selectedStage && report.matches(query),
        )
        .toList();
    rows.sort((a, b) {
      final order = (b.activityAt(instant)?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.activityAt(instant)?.millisecondsSinceEpoch ?? 0);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
    return rows;
  }

  /// Limits rendered cards while retaining the full lifecycle counts.
  List<AdminHazardReport> get visibleReports =>
      matchingReports.take(_limit).toList();

  /// Offers another page whenever matching older reports remain.
  bool get hasMore => matchingReports.length > _limit;

  /// Finds the latest record so an open detail view follows live changes too.
  AdminHazardReport? reportById(String id) {
    for (final report in _reports) {
      if (report.id == id) return report;
    }
    return null;
  }

  /// Switches lifecycle tabs and starts the selected list at its first page.
  void selectStage(AdminHazardStage stage) {
    if (selectedStage == stage) return;
    selectedStage = stage;
    _limit = pageSize;
    notifyListeners();
  }

  /// Filters the selected tab without changing its overall count.
  void setQuery(String value) {
    final next = value.trim().toLowerCase();
    if (query == next) return;
    query = next;
    _limit = pageSize;
    notifyListeners();
  }

  /// Reveals another page without silently omitting older resolved reports.
  void showMore() {
    _limit += pageSize;
    notifyListeners();
  }

  /// Moves reports at their expiry without waiting for a server-side write.
  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final instant = now;
    final dates =
        _reports
            .where((report) => !report.confirmedResolved)
            .map((report) => report.expiresAt)
            .whereType<DateTime>()
            .where((time) => time.isAfter(instant))
            .toList()
          ..sort();
    if (dates.isEmpty) return;
    final remaining = dates.first.difference(instant);
    final delay = remaining > const Duration(minutes: 1)
        ? const Duration(minutes: 1)
        : remaining;
    _expiryTimer = Timer(delay, () {
      if (_disposed) return;
      _scheduleExpiry();
      notifyListeners();
    });
  }

  /// Completes refresh callers once a snapshot, error or timeout arrives.
  void _finishLoad() {
    _loadTimer?.cancel();
    if (_pendingLoad?.isCompleted == false) _pendingLoad!.complete();
  }

  /// Stops listeners and timers when the administrator leaves the workspace.
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_subscription?.cancel());
    _expiryTimer?.cancel();
    _finishLoad();
    super.dispose();
  }
}

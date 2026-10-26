import 'dart:async';

import 'package:flutter/foundation.dart';

import '../Data/trail_caution_details_repository.dart';
import '../Model/caution_update.dart';
import '../Model/community_hazard.dart';

/// Owns live caution state and prevents self or duplicate confirmations.
class TrailCautionDetailsViewModel extends ChangeNotifier {
  /// Starts account-scoped subscriptions for one caution.
  TrailCautionDetailsViewModel({
    required CommunityHazard report,
    required TrailCautionDetailsRepository repository,
    required this.allowFeedback,
    DateTime Function()? clock,
  }) : _report = report,
       _repository = repository,
       _clock = clock ?? DateTime.now {
    _reportSubscription = _repository
        .watchReport(report.id)
        .listen(_receiveReport, onError: (Object _) {});
    _updatesSubscription = _repository
        .watchUpdates(report.id)
        .listen(
          (updates) {
            if (_disposed) return;
            _updates = List.unmodifiable(updates);
            _updatesUnavailable = false;
            notifyListeners();
          },
          onError: (Object _) {
            if (_disposed) return;
            _updatesUnavailable = true;
            notifyListeners();
          },
        );
    _viewerSubscription = _repository.watchViewer().listen(
      _receiveViewer,
      onError: (Object _) => _receiveViewer(null),
    );
    _expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_disposed) notifyListeners();
    });
  }

  final TrailCautionDetailsRepository _repository;
  final DateTime Function() _clock;
  final bool allowFeedback;
  late final StreamSubscription<CommunityHazard?> _reportSubscription;
  late final StreamSubscription<List<CautionUpdate>> _updatesSubscription;
  late final StreamSubscription<String?> _viewerSubscription;
  StreamSubscription<CautionViewerVotes>? _votesSubscription;
  Timer? _expiryTimer;
  CommunityHazard _report;
  List<CautionUpdate> _updates = const [];
  CautionViewerVotes _votes = const CautionViewerVotes();
  String? _viewerUid;
  int _voteGeneration = 0;
  bool _available = true, _disposed = false, _busy = false;
  bool _updatesUnavailable = false;
  bool _hasLiveReport = false;
  bool _locallyConfirmed = false, _locallyConfirmedResolution = false;
  Object? _error;

  /// Returns the latest report, retaining initial content while offline.
  CommunityHazard get report => _report;

  /// Returns the loaded update history in server order.
  List<CautionUpdate> get updates => _updates;

  /// Returns whether the source report still exists and is visible.
  bool get available => _available;

  /// Returns whether the seven-day map display window remains open.
  bool get active => available && _report.isActiveAt(_clock());

  /// Returns whether a confirmation request is in flight.
  bool get busy => _busy;

  /// Returns a failed save for the view's existing error formatter.
  Object? get error => _error;

  /// Returns whether update history could not be refreshed.
  bool get updatesUnavailable => _updatesUnavailable;

  /// Returns the account used to recognize the viewer's own content.
  String? get viewerUid => _viewerUid;

  /// Returns true only for the account that shared the original caution.
  bool get isOwnReport =>
      _viewerUid != null && _report.reportedBy == _viewerUid;

  /// Includes both the initial report vote and subsequent confirmations.
  bool get confirmedByViewer =>
      isOwnReport ||
      _votes.confirmed ||
      _locallyConfirmed ||
      _updates.any(
        (update) =>
            update.uid.isNotEmpty &&
            update.uid == _viewerUid &&
            update.cycle == _report.cycle &&
            const {'confirm', 'reopen'}.contains(update.action),
      );

  /// Includes the resolution author's initial vote and any later confirmation.
  bool get resolutionConfirmedByViewer =>
      _votes.resolutionConfirmed ||
      _locallyConfirmedResolution ||
      _updates.any(
        (update) =>
            update.uid.isNotEmpty &&
            update.uid == _viewerUid &&
            (update.id == _report.resolutionId ||
                (update.cycle == _report.cycle &&
                    const {
                      'resolve',
                      'confirmResolution',
                    }.contains(update.action))),
      );

  /// Allows feedback only for a signed-in viewer and a currently visible report.
  bool get canGiveFeedback => allowFeedback && _viewerUid != null && active;

  /// Never offers an upvote for an owned report or an already counted vote.
  bool get canConfirm =>
      canGiveFeedback &&
      !_report.isResolved &&
      _report.reportedBy.isNotEmpty &&
      _votes.authoritative &&
      !confirmedByViewer;

  /// Requires independent confirmations; the resolution author's vote is counted.
  bool get canConfirmResolution =>
      canGiveFeedback &&
      !_report.isResolved &&
      _report.resolutionId != null &&
      _votes.authoritative &&
      !resolutionConfirmedByViewer;

  /// Keeps evidence-backed resolution reports separate from upvotes.
  bool get canReportResolution => canGiveFeedback && !_report.isResolved;

  /// A reopened caution still requires the existing evidence submission flow.
  bool get canReopen => canGiveFeedback && _report.isResolved;

  /// Refreshes parent-supplied data until a live report has taken ownership.
  void updateInitialReport(CommunityHazard report) {
    if (_disposed || _hasLiveReport || report.id != _report.id) return;
    final changedVoteScope =
        report.cycle != _report.cycle ||
        report.resolutionId != _report.resolutionId;
    _report = report;
    if (changedVoteScope) _watchVotes();
    notifyListeners();
  }

  /// Changes the report and invalidates votes from an older cycle.
  void _receiveReport(CommunityHazard? report) {
    if (_disposed) return;
    _hasLiveReport = true;
    _available = report != null;
    if (report != null) {
      final changedVoteScope =
          report.cycle != _report.cycle ||
          report.resolutionId != _report.resolutionId;
      _report = report;
      if (changedVoteScope) {
        _error = null;
        _watchVotes();
      }
    }
    notifyListeners();
  }

  /// Clears the previous account's state before listening to another account.
  void _receiveViewer(String? uid) {
    if (_disposed) return;
    final normalized = uid?.trim();
    final viewer = normalized == null || normalized.isEmpty ? null : normalized;
    if (_viewerUid == viewer) return;
    _viewerUid = viewer;
    _error = null;
    _watchVotes();
    notifyListeners();
  }

  /// Fences late vote events after account changes, reopenings or disposal.
  void _watchVotes() {
    final generation = ++_voteGeneration;
    unawaited(_votesSubscription?.cancel());
    _votesSubscription = null;
    _votes = const CautionViewerVotes();
    _locallyConfirmed = false;
    _locallyConfirmedResolution = false;
    final uid = _viewerUid;
    if (uid == null || !allowFeedback) return;
    _votesSubscription = _repository
        .watchVotes(_report.id, uid, _report.cycle)
        .listen(
          (votes) {
            if (_disposed || generation != _voteGeneration) return;
            _votes = votes;
            notifyListeners();
          },
          onError: (Object _) {
            if (_disposed || generation != _voteGeneration) return;
            _votes = const CautionViewerVotes();
            notifyListeners();
          },
        );
  }

  /// Rechecks ownership immediately before sending a confirmation.
  Future<bool?> confirm(String action) async {
    if (_disposed || _busy) return null;
    if (action != 'confirm' && action != 'confirmResolution') return null;
    if (action == 'confirm' ? !canConfirm : !canConfirmResolution) return null;
    final uid = _viewerUid, cycle = _report.cycle;
    final generation = _voteGeneration;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _repository.confirm(_report.id, action);
      if (_disposed ||
          uid != _viewerUid ||
          cycle != _report.cycle ||
          generation != _voteGeneration) {
        return null;
      }
      if (action == 'confirm') {
        _locallyConfirmed = true;
      } else {
        _locallyConfirmedResolution = true;
      }
      return saved;
    } catch (error) {
      if (!_disposed &&
          uid == _viewerUid &&
          cycle == _report.cycle &&
          generation == _voteGeneration) {
        _error = error;
      }
      return null;
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  /// Releases only the subscriptions and clock owned by this caution card.
  @override
  void dispose() {
    _disposed = true;
    _voteGeneration++;
    unawaited(_reportSubscription.cancel());
    unawaited(_updatesSubscription.cancel());
    unawaited(_viewerSubscription.cancel());
    unawaited(_votesSubscription?.cancel());
    _expiryTimer?.cancel();
    super.dispose();
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../Model/hike_session_models.dart';
import '../ModelView/upcoming_hike_request_inbox_view_model.dart';
import 'upcoming_hike_request_inbox_page.dart';

/// Supplies one host-count loader to all upcoming cards in the dashboard.
class UpcomingHikeRequestHost extends StatefulWidget {
  /// Keeps request loading scoped to the signed-in account and visible dashboard.
  const UpcomingHikeRequestHost({
    super.key,
    required this.session,
    required this.repository,
    required this.hikes,
    required this.visible,
    required this.onReview,
    required this.child,
  });
  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final List<UpcomingHike> hikes;
  final bool visible;
  final Future<void> Function(String) onReview;
  final Widget child;

  /// Creates lifecycle-aware badge presentation.
  @override
  State<UpcomingHikeRequestHost> createState() =>
      _UpcomingHikeRequestHostState();
}

/// Pauses count polling in the background and refreshes immediately after decisions.
class _UpcomingHikeRequestHostState extends State<UpcomingHikeRequestHost>
    with WidgetsBindingObserver {
  late UpcomingHikeRequestCountsViewModel _model;
  Timer? _timer;
  bool _foreground = true;

  /// Binds one account-scoped count source.
  void _bind() {
    _model = UpcomingHikeRequestCountsViewModel(widget.repository);
    widget.repository.upcomingHikeJoinRequestRevision.addListener(_refresh);
    _sync();
  }

  /// Loads only hosted hikes and never treats unsynced local plans as cloud IDs.
  void _sync() {
    if (!widget.visible || !_foreground) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _model.setHikes(
      widget.hikes
          .where(
            (hike) =>
                !hike.isLocalPendingSync &&
                hike.creatorPhone == widget.session.phoneNumber &&
                hike.isUpcomingAt(DateTime.now()),
          )
          .map((hike) => hike.id)
          .toList(),
    );
    _timer ??= Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  /// Refreshes only while the dashboard can display the badge.
  void _refresh() {
    if (widget.visible && _foreground) unawaited(_model.refresh());
  }

  /// Starts lifecycle and confirmed-decision subscriptions.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bind();
  }

  /// Rebinds after account changes and refreshes when returning to Home.
  @override
  void didUpdateWidget(covariant UpcomingHikeRequestHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.session.phoneNumber != widget.session.phoneNumber) {
      oldWidget.repository.upcomingHikeJoinRequestRevision.removeListener(
        _refresh,
      );
      _model.dispose();
      _bind();
    } else {
      _sync();
      if (!oldWidget.visible && widget.visible) _refresh();
    }
  }

  /// Stops polling when the app leaves the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
    if (_foreground) _refresh();
  }

  /// Opens the host-only inbox without activating the card's preparation action.
  Future<void> _open(BuildContext context, UpcomingHike hike) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UpcomingHikeRequestInboxPage(
          hike: hike,
          repository: widget.repository,
          onReview: widget.onReview,
        ),
      ),
    );
    _refresh();
  }

  /// Detaches all account and app lifecycle callbacks.
  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.repository.upcomingHikeJoinRequestRevision.removeListener(_refresh);
    _model.dispose();
    super.dispose();
  }

  /// Publishes count changes without rebuilding unrelated Home state.
  @override
  Widget build(BuildContext context) => _RequestScope(
    notifier: _model,
    open: (hike) => _open(context, hike),
    child: widget.child,
  );
}

/// Shares counts and navigation through the existing dashboard widget tree.
class _RequestScope
    extends InheritedNotifier<UpcomingHikeRequestCountsViewModel> {
  /// Creates the dashboard's request source.
  const _RequestScope({
    required super.notifier,
    required this.open,
    required super.child,
  });
  final Future<void> Function(UpcomingHike) open;
}

/// Compact solo/team indicator, with a host-only pending request badge.
class UpcomingHikePeopleButton extends StatelessWidget {
  /// Works in standalone briefings as well as the hosted dashboard scope.
  const UpcomingHikePeopleButton({
    super.key,
    required this.hike,
    required this.viewerPhone,
  });
  final UpcomingHike hike;
  final String viewerPhone;

  /// Uses the requested person/group icons and never exposes other hosts' queues.
  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_RequestScope>();
    final host = hike.creatorPhone == viewerPhone;
    final count = host ? scope?.notifier?.counts[hike.id] ?? 0 : 0;
    final team = hike.hikeType == 'team';
    final participants = hike.participantCount;
    final rosterLabel =
        team ? '$participants ${participants == 1 ? 'hiker' : 'hikers'}' : 'Solo hike';
    final requestLabel = '$count pending join ${count == 1 ? 'request' : 'requests'}';
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Badge(
          isLabelVisible: count > 0,
          label: Text(count > 99 ? '99+' : '$count'),
          child: Icon(
            team ? Icons.groups_rounded : Icons.person_rounded,
            size: 23,
          ),
        ),
        if (team) ...[
          const SizedBox(width: 8),
          Text(
            '${hike.participantCount}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ],
    );
    return Semantics(
      label: host ? '$rosterLabel, $requestLabel' : rosterLabel,
      child: Tooltip(
        message: host ? 'Join requests' : 'Hikers',
        child: TextButton(
          key: ValueKey('upcoming-hike-requests-${hike.id}'),
          style: TextButton.styleFrom(
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 7),
          ),
          onPressed: host && scope != null && !hike.isLocalPendingSync
              ? () => scope.open(hike)
              : null,
          child: child,
        ),
      ),
    );
  }
}

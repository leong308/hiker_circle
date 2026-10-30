part of '../hike_history_page_feature.dart';

typedef ExpiredHikesPageLoader =
    Future<ExpiredHikesPage> Function(ExpiredHikesCursor? cursor);

typedef HikeHistoryListLoader = Future<List<HikeHistorySummary>> Function();
typedef HikeHistoryDetailLoader =
    Future<HikeHistoryDetail> Function(String sessionId);

/// Displays the hike history page.
class HikeHistoryPage extends StatefulWidget {
  /// Creates hike history page.
  const HikeHistoryPage({
    super.key,
    required this.repository,
    this.session,
    this.loadHistory,
    this.loadDetail,
    this.loadExpiredHikes,
    this.onRescheduleExpiredHike,
    this.enableInteractiveRoute = true,
  });

  final HikerCircleFirebaseRepository repository;
  final AppSession? session;
  final HikeHistoryListLoader? loadHistory;
  final HikeHistoryDetailLoader? loadDetail;
  final ExpiredHikesPageLoader? loadExpiredHikes;
  final Future<void> Function(UpcomingHike)? onRescheduleExpiredHike;
  final bool enableInteractiveRoute;

  /// Creates the presentation state for this widget.
  @override
  State<HikeHistoryPage> createState() => _HikeHistoryPageState();
}

/// Manages the hike history page presentation and lifecycle.
class _HikeHistoryPageState extends State<HikeHistoryPage> {
  late final _HikeHistoryPageStateViewModel _screenModel;

  /// Returns history future.
  Future<List<HikeHistorySummary>> get _historyFuture =>
      _screenModel.stateHistoryFuture;

  /// Updates history future.
  set _historyFuture(Future<List<HikeHistorySummary>> value) =>
      _screenModel.stateHistoryFuture = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _HikeHistoryPageStateViewModel(
      readLoadHistory: () => widget.loadHistory,
      readRepository: () => widget.repository,
    )..addListener(_renderScreenModel);

    _historyFuture = _load();
    if (widget.loadHistory == null && widget.session != null) {
      _screenModel.watchSharedHistory(widget.session!.phoneNumber);
    }
  }

  /// Delegates load to the ViewModel.
  Future<List<HikeHistorySummary>> _load() => _screenModel.commandLoad();

  /// Delegates refresh to the ViewModel.
  Future<void> _refresh() => _screenModel.commandRefresh();

  /// Opens detail.
  void _openDetail(HikeHistorySummary hike) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => HikeHistoryDetailPage(
          summary: hike,
          loadDetail:
              widget.loadDetail ?? widget.repository.loadMyHikeHistoryDetail,
          repository: widget.repository,
          session: widget.session,
          enableInteractiveRoute: widget.enableInteractiveRoute,
        ),
      ),
    );
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _HistoryColors.backgroundFor(context),
        appBar: PageHeaderAppBar(
          backgroundColor: _HistoryColors.backgroundFor(context),
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            child: const Icon(CupertinoIcons.back, size: 22),
          ),
          title: const Text(
            'Hike history',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Completed'),
              Tab(text: 'Expired'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _completedHistory(),
            _ExpiredHikeHistoryList(
              onReschedule: widget.onRescheduleExpiredHike,
              loader:
                  widget.loadExpiredHikes ??
                  (cursor) =>
                      _HikeHistoryPageDataActions.loadPage(
                        ExpiredHikesRepository(
                          localDatabase: widget.repository.localDatabase,
                        ),
                      )(
                        ownerPhoneNumber: widget.session?.phoneNumber ?? '',
                        cursor: cursor,
                      ),
            ),
          ],
        ),
      ),
    );
  }

  /// Computes completed history.
  Widget _completedHistory() => FutureBuilder<List<HikeHistorySummary>>(
    future: _historyFuture,
    builder: (context, snapshot) {
      final isLoading = snapshot.connectionState != ConnectionState.done;
      if (isLoading && !snapshot.hasData) {
        return Stack(
          children: [
            HikerCircleLoadingToastOverlay(
              message: 'Loading your hike history…',
              detail: 'Getting your completed hikes and route records.',
              dimBackground: false,
              timeout: const Duration(seconds: 30),
              onTimeout: () {
                if (mounted) {
                  setState(() {
                    _historyFuture = Future<List<HikeHistorySummary>>.error(
                      'Timed out loading hike history',
                    );
                  });
                }
              },
            ),
          ],
        );
      }
      if (snapshot.hasError) {
        return _HistoryMessage(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load hike history',
          message: _historyError(snapshot.error),
          actionLabel: 'Try again',
          onAction: _refresh,
        );
      }
      final hikes = snapshot.data ?? const [];
      if (hikes.isEmpty) {
        return _HistoryMessage(
          icon: Icons.hiking_rounded,
          title: 'No completed hikes yet',
          message:
              'Completed hikes will appear here with their recorded route, safety events, and performance details.',
          actionLabel: 'Refresh',
          onAction: _refresh,
        );
      }
      final totalDistance = hikes.fold<double>(
        0,
        (sum, hike) => sum + hike.distanceKm,
      );
      final totalDuration = hikes.fold<Duration>(
        Duration.zero,
        (sum, hike) => sum + hike.duration,
      );
      final content = RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _HistoryOverview(
              hikeCount: hikes.length,
              totalDistanceKm: totalDistance,
              totalDuration: totalDuration,
            ),
            const SizedBox(height: 18),
            const SectionLabel(label: 'PAST HIKES'),
            const SizedBox(height: 9),
            for (final hike in hikes) ...[
              _HikeHistoryCard(hike: hike, onTap: () => _openDetail(hike)),
              const SizedBox(height: 12),
            ],
          ],
        ),
      );
      return Stack(
        children: [
          content,
          if (isLoading)
            HikerCircleLoadingToastOverlay(
              message: 'Refreshing your hike history…',
              detail: 'Getting the latest completed hike records.',
              timeout: const Duration(seconds: 30),
              onTimeout: () {
                if (mounted) {
                  setState(() {
                    _historyFuture = Future<List<HikeHistorySummary>>.error(
                      'Timed out refreshing hike history',
                    );
                  });
                }
              },
            ),
        ],
      );
    },
  );

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }
}

/// Displays the expired hike history list.
class _ExpiredHikeHistoryList extends StatefulWidget {
  /// Creates expired hike history list.
  const _ExpiredHikeHistoryList({required this.loader, this.onReschedule});
  final ExpiredHikesPageLoader loader;
  final Future<void> Function(UpcomingHike)? onReschedule;

  /// Creates the presentation state for this widget.
  @override
  State<_ExpiredHikeHistoryList> createState() =>
      _ExpiredHikeHistoryListState();
}

/// Manages the expired hike history list presentation and lifecycle.
class _ExpiredHikeHistoryListState extends State<_ExpiredHikeHistoryList> {
  late final _ExpiredHikeHistoryListStateViewModel _screenModel;

  /// Returns hikes.
  List<UpcomingHike> get _hikes => _screenModel.stateHikes;

  /// Returns cursor.
  ExpiredHikesCursor? get _cursor => _screenModel.stateCursor;

  /// Returns is loading.
  bool get _isLoading => _screenModel.stateIsLoading;

  /// Returns is from cache.
  bool get _isFromCache => _screenModel.stateIsFromCache;

  /// Returns error.
  Object? get _error => _screenModel.stateError;

  /// Returns failed refresh.
  bool get _failedRefresh => _screenModel.stateFailedRefresh;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _ExpiredHikeHistoryListStateViewModel(
      readLoader: () => widget.loader,
    )..addListener(_renderScreenModel);

    unawaited(_load(refresh: true));
  }

  /// Keep expired-hike pagination separate from refresh so existing rows remain visible while loading more.
  Future<void> _load({bool refresh = false}) =>
      _screenModel.commandLoad(refresh: refresh);

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (_isLoading && _hikes.isEmpty) {
      return const HikerCircleLoadingView(
        message: 'Loading expired plans…',
        detail: 'Getting your past scheduled hikes.',
      );
    }
    if (_error != null && _hikes.isEmpty) {
      return _HistoryMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load expired plans',
        message: 'Check your connection and try again.',
        actionLabel: 'Try again',
        onAction: () => _load(refresh: true),
      );
    }
    if (_hikes.isEmpty && _cursor == null) {
      return _HistoryMessage(
        icon: Icons.event_available_rounded,
        title: 'No expired plans',
        message:
            'Past scheduled hikes that were never started will appear here.',
        actionLabel: 'Refresh',
        onAction: () => _load(refresh: true),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ExpiredHikesOverview(),
                  if (_isFromCache)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud_off_rounded,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'Saved on this phone · Refresh when connected',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (var i = 0; i < _hikes.length; i++) ...[
                    if (i == 0 ||
                        expiredHikeMonth(_hikes[i].departureTime) !=
                            expiredHikeMonth(_hikes[i - 1].departureTime))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
                        child: Text(
                          expiredHikeMonth(
                            _hikes[i].departureTime,
                          ).toUpperCase(),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: _HistoryColors.secondaryFor(context),
                                fontWeight: FontWeight.w700,
                                letterSpacing: .6,
                              ),
                        ),
                      ),
                    ExpiredHikeCard(
                      key: Key('expired-hike-${_hikes[i].id}'),
                      hike: _hikes[i],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ExpiredHikeDetailPage(
                            hike: _hikes[i],
                            onReschedule: widget.onReschedule,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _failedRefresh
                    ? 'The latest plans could not be refreshed. Your saved plans are still here.'
                    : 'Older plans could not be loaded. Try again when connected.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_error != null)
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () => _load(refresh: _failedRefresh),
              child: const Text('Try again'),
            ),
          if (_cursor != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton(
                onPressed: _isLoading ? null : () => _load(),
                child: Text(_isLoading ? 'Loading…' : 'Load older plans'),
              ),
            ),
        ],
      ),
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }
}

/// Displays the hike history detail page.
class HikeHistoryDetailPage extends StatefulWidget {
  /// Creates hike history detail page.
  const HikeHistoryDetailPage({
    super.key,
    required this.summary,
    required this.loadDetail,
    this.repository,
    this.session,
    this.enableInteractiveRoute = true,
  });

  final HikeHistorySummary summary;
  final HikeHistoryDetailLoader loadDetail;
  final HikerCircleFirebaseRepository? repository;
  final AppSession? session;
  final bool enableInteractiveRoute;

  /// Creates the presentation state for this widget.
  @override
  State<HikeHistoryDetailPage> createState() => _HikeHistoryDetailPageState();
}

/// Manages the hike history detail page presentation and lifecycle.
class _HikeHistoryDetailPageState extends State<HikeHistoryDetailPage> {
  late final _HikeHistoryDetailPageStateViewModel _screenModel;

  /// Returns detail future.
  Future<HikeHistoryDetail> get _detailFuture => _screenModel.stateDetailFuture;

  /// Updates detail future.
  set _detailFuture(Future<HikeHistoryDetail> value) =>
      _screenModel.stateDetailFuture = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _HikeHistoryDetailPageStateViewModel(
      readLoadDetail: () => widget.loadDetail,
      readSummary: () => widget.summary,
    )..addListener(_renderScreenModel);

    _detailFuture = widget.loadDetail(widget.summary.sessionId);
  }

  /// Delegates refresh to the ViewModel.
  Future<void> _refresh() => _screenModel.commandRefresh();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _HistoryColors.backgroundFor(context),
      appBar: PageHeaderAppBar(
        backgroundColor: _HistoryColors.backgroundFor(context),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.back, size: 22),
        ),
        title: Text(
          widget.summary.trailName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: FutureBuilder<HikeHistoryDetail>(
        future: _detailFuture,
        builder: (context, snapshot) {
          final isLoading = snapshot.connectionState != ConnectionState.done;
          if (isLoading && !snapshot.hasData) {
            return Stack(
              children: [
                HikerCircleLoadingToastOverlay(
                  message: 'Loading hike details…',
                  detail: 'Preparing the route and safety records.',
                  dimBackground: false,
                  timeout: const Duration(seconds: 30),
                  onTimeout: () {
                    if (mounted) {
                      setState(() {
                        _detailFuture = Future<HikeHistoryDetail>.error(
                          'Timed out loading hike details',
                        );
                      });
                    }
                  },
                ),
              ],
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return _HistoryMessage(
              icon: Icons.route_rounded,
              title: 'Could not load hike details',
              message: _historyError(snapshot.error),
              actionLabel: 'Try again',
              onAction: _refresh,
            );
          }
          final content = _HikeHistoryDetailBody(
            detail: snapshot.data!,
            onRefresh: _refresh,
            repository: widget.repository,
            session: widget.session,
            enableInteractiveRoute: widget.enableInteractiveRoute,
          );
          return Stack(
            children: [
              content,
              if (isLoading)
                HikerCircleLoadingToastOverlay(
                  message: 'Refreshing hike details…',
                  detail: 'Getting the latest route and safety records.',
                  timeout: const Duration(seconds: 30),
                  onTimeout: () {
                    if (mounted) {
                      setState(() {
                        _detailFuture = Future<HikeHistoryDetail>.error(
                          'Timed out refreshing hike details',
                        );
                      });
                    }
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }
}

/// Displays the hike history detail body.
class _HikeHistoryDetailBody extends StatelessWidget {
  /// Creates hike history detail body.
  const _HikeHistoryDetailBody({
    required this.detail,
    required this.onRefresh,
    this.repository,
    this.session,
    this.enableInteractiveRoute = true,
  });

  final HikeHistoryDetail detail;
  final Future<void> Function() onRefresh;
  final HikerCircleFirebaseRepository? repository;
  final AppSession? session;
  final bool enableInteractiveRoute;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    if (detail.sharedTeamSummary != null) {
      return StreamBuilder<TeamHikeSession?>(
        stream: repository?.watchTeamHikeSession(detail.teamHikeSessionId),
        builder: (context, snapshot) {
          final stored = snapshot.data?.summarySnapshot;
          final shared = stored == null
              ? detail.sharedTeamSummary!
              : detail.sharedTeamSummary!.prefer(
                  SharedTeamHikeSummary.fromMap(stored),
                );
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 36),
              children: [TeamHikeSummaryPanel(summary: shared)],
            ),
          );
        },
      );
    }
    final overview = RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 36),
        children: [
          _RecordedRouteCard(
            detail: detail,
            enableInteractiveRoute: enableInteractiveRoute,
          ),
          const SizedBox(height: 14),
          _MetricGrid(
            metrics: [
              _Metric(
                Icons.straighten_rounded,
                'Distance',
                '${summary.distanceKm.toStringAsFixed(2)} km',
              ),
              _Metric(
                Icons.timer_outlined,
                'Duration',
                _formatDuration(summary.duration),
              ),
              _Metric(
                Icons.speed_rounded,
                'Avg speed',
                '${detail.averageSpeedKmh.toStringAsFixed(1)} km/h',
              ),
              _Metric(
                Icons.directions_walk_rounded,
                'Avg pace',
                detail.paceMinutesPerKm > 0
                    ? '${detail.paceMinutesPerKm.toStringAsFixed(1)} min/km'
                    : 'No data',
              ),
            ],
          ),
          _DetailSection(
            title: 'Actual hike',
            icon: Icons.query_stats_rounded,
            rows: [
              _RowData('Started', _formatDateTime(summary.startedAt)),
              _RowData('Finished', _formatDateTime(summary.endedAt)),
              _RowData('Elapsed time', _formatDuration(summary.duration)),
              _RowData(
                'Recorded distance',
                '${summary.distanceKm.toStringAsFixed(2)} km',
              ),
              _RowData('Recorded GPS points', '${summary.routePointCount}'),
              _RowData(
                'Stored route points',
                '${detail.storedRoutePointCount}',
              ),
              _RowData('Raw telemetry points', '${detail.telemetryPointCount}'),
              _RowData(
                'Route storage',
                detail.routePointsDownsampled
                    ? 'Downsampled for cloud storage'
                    : 'Full captured route',
              ),
              if (detail.routePoints.isNotEmpty)
                _RowData(
                  'Route start',
                  _coordinateLabel(detail.routePoints.first),
                ),
              if (detail.routePoints.length > 1)
                _RowData(
                  'Route finish',
                  _coordinateLabel(detail.routePoints.last),
                ),
              if (detail.minAltitudeMeters != null)
                _RowData(
                  'Lowest altitude',
                  '${detail.minAltitudeMeters!.round()} m',
                ),
              if (detail.maxAltitudeMeters != null)
                _RowData(
                  'Highest altitude',
                  '${detail.maxAltitudeMeters!.round()} m',
                ),
            ],
          ),
          _DetailSection(
            title: 'Plan and timeline',
            icon: Icons.event_note_rounded,
            rows: [
              _RowData(
                'Start point',
                _valueOrUnavailable(detail.startPointName),
              ),
              _RowData(
                'Destination',
                _valueOrUnavailable(detail.destinationName),
              ),
              _RowData(
                'Planned departure',
                _formatDateTime(detail.plannedStartTime),
              ),
              _RowData(
                'Estimated arrival',
                _formatDateTime(detail.estimatedArrivalTime),
              ),
              _RowData(
                'Estimated return',
                _formatDateTime(detail.estimatedReturnTime),
              ),
              _RowData(
                'Planned distance',
                detail.plannedDistanceKm > 0
                    ? '${detail.plannedDistanceKm.toStringAsFixed(1)} km'
                    : 'Not recorded',
              ),
              _RowData(
                'Estimated duration',
                detail.estimatedDurationMinutes > 0
                    ? _formatDuration(
                        Duration(minutes: detail.estimatedDurationMinutes),
                      )
                    : 'Not recorded',
              ),
              _RowData(
                'Planned elevation gain',
                detail.elevationGainMeters > 0
                    ? '${detail.elevationGainMeters} m'
                    : 'Not recorded',
              ),
            ],
            child: detail.checkpoints.isEmpty
                ? null
                : _CheckpointTimeline(checkpoints: detail.checkpoints),
          ),
          _DetailSection(
            title: 'Safety record',
            icon: Icons.health_and_safety_rounded,
            rows: [
              _RowData('Safety check-ins', '${summary.checkIns}'),
              _RowData(
                'Path deviation alerts',
                '${detail.pathDeviationAlertCount}',
              ),
              _RowData(
                'Check-in interval',
                _formatInterval(detail.safetyCheckInIntervalSeconds),
              ),
              _RowData(
                'Location recording interval',
                _formatInterval(detail.locationRecordingIntervalSeconds),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FeatureWrap(detail: detail),
                if (detail.completedChecklistItems.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Completed gear checklist', style: _subheading(context)),
                  const SizedBox(height: 7),
                  for (final item in detail.completedChecklistItems)
                    _EventLine(
                      icon: Icons.check_circle_rounded,
                      title: item,
                      subtitle: 'Completed before departure',
                    ),
                ],
                if (detail.checkInRecords.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Check-in timeline', style: _subheading(context)),
                  const SizedBox(height: 7),
                  for (final checkIn in detail.checkInRecords)
                    _EventLine(
                      icon: Icons.verified_user_rounded,
                      title: checkIn.status == 'safe'
                          ? 'Safe check-in'
                          : checkIn.status,
                      subtitle:
                          '${_formatDateTime(checkIn.checkedInAt)}${checkIn.batteryLevel > 0 ? ' · Battery ${checkIn.batteryLevel}%' : ''}${checkIn.coordinate != null ? ' · ${_coordinateLabel(checkIn.coordinate!)}' : ''}',
                    ),
                ],
              ],
            ),
          ),
          _DetailSection(
            title: 'Battery and tracking',
            icon: Icons.battery_charging_full_rounded,
            rows: [
              _RowData('Battery at start', '${summary.batteryStartPercent}%'),
              _RowData('Battery at finish', '${summary.batteryEndPercent}%'),
              _RowData('Battery used', '${detail.batteryUsedPercent}%'),
              if (detail.lowestRecordedBatteryPercent != null)
                _RowData(
                  'Lowest recorded',
                  '${detail.lowestRecordedBatteryPercent}%',
                ),
              _RowData(
                'Route capture',
                detail.routeCaptureAvailable ? 'Saved' : 'Summary only',
              ),
            ],
          ),
          _DetailSection(
            title: 'Trail',
            icon: Icons.terrain_rounded,
            rows: [
              _RowData('Trail', summary.trailName),
              _RowData('Location', _valueOrUnavailable(summary.location)),
              _RowData('Difficulty', _valueOrUnavailable(summary.difficulty)),
              _RowData(
                'Trail verification',
                detail.isVerifiedTrail ? 'Verified trail' : 'Not verified',
              ),
              _RowData(
                'Trail rating',
                detail.trailRatingCount > 0
                    ? '${detail.trailRatingAverage.toStringAsFixed(1)} / 5 (${detail.trailRatingCount} ratings)'
                    : 'No route ratings yet',
              ),
            ],
          ),
          if (summary.isTeam || detail.teamBuddyNames.isNotEmpty)
            _DetailSection(
              title: 'Hiking team',
              icon: Icons.groups_2_rounded,
              rows: [
                _RowData('Hike type', 'Group'),
                _RowData('Team size', '${summary.teamMemberCount} hikers'),
                _RowData(
                  'Other hikers',
                  detail.teamBuddyNames.isEmpty
                      ? 'Names unavailable'
                      : detail.teamBuddyNames.join(', '),
                ),
              ],
            ),
          _DetailSection(
            title: 'Your route rating',
            icon: Icons.star_rounded,
            rows: [
              _RowData(
                'Your rating',
                detail.ratingStars > 0
                    ? '${detail.ratingStars} / 5 stars'
                    : 'Not rated',
              ),
              if (detail.ratingDifficulty.isNotEmpty)
                _RowData(
                  'Your difficulty vote',
                  _titleCaseWords(detail.ratingDifficulty),
                ),
              if (detail.ratingComment.isNotEmpty)
                _RowData('Your comment', detail.ratingComment),
            ],
          ),
          if (detail.insights.isNotEmpty)
            _DetailSection(
              title: 'Recorded insights',
              icon: Icons.auto_graph_rounded,
              rows: const [],
              child: Column(
                children: [
                  for (final insight in detail.insights)
                    _EventLine(
                      icon: Icons.insights_rounded,
                      title: insight,
                      subtitle: '',
                    ),
                ],
              ),
            ),
          _DetailSection(
            title: 'Record information',
            icon: Icons.fingerprint_rounded,
            rows: [
              _RowData('Session ID', summary.sessionId),
              _RowData('Hike type', summary.isTeam ? 'Group' : 'Solo'),
              if (detail.sourceUpcomingHikeId.isNotEmpty)
                _RowData('Upcoming hike source', detail.sourceUpcomingHikeId),
              if (detail.teamHikeSessionId.isNotEmpty)
                _RowData('Team session', detail.teamHikeSessionId),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'This history is private to your signed-in account.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _HistoryColors.secondaryFor(context),
              ),
            ),
          ),
        ],
      ),
    );
    final tabs = <Tab>[
      const Tab(text: 'Overview'),
      const Tab(text: 'Analysis'),
      const Tab(text: 'Safety'),
      if (summary.isTeam) const Tab(text: 'Team'),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          Material(
            color: _HistoryColors.backgroundFor(context),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: summary.isTeam
                  ? const Color(0xFF6C63D9)
                  : _HistoryColors.green,
              labelColor: _HistoryColors.textFor(context),
              unselectedLabelColor: _HistoryColors.secondaryFor(context),
              tabs: tabs,
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                overview,
                _HistoryAnalysisTab(detail: detail, onRefresh: onRefresh),
                _HistorySafetyTab(detail: detail, onRefresh: onRefresh),
                if (summary.isTeam)
                  _HistoryTeamTab(
                    detail: detail,
                    onRefresh: onRefresh,
                    repository: repository,
                    session: session,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Computes analysis for history.
HikeRouteAnalysis _analysisForHistory(HikeHistoryDetail detail) {
  return analyzeHikeRoute(
    routePoints: detail.routePoints,
    fallbackStartedAt: detail.summary.startedAt,
    checkpoints: detail.checkpoints
        .map(
          (checkpoint) => HikeAnalysisCheckpoint(
            name: checkpoint.name,
            order: checkpoint.order,
            latitude: checkpoint.latitude,
            longitude: checkpoint.longitude,
          ),
        )
        .toList(),
  );
}

/// Displays the pace chart.
class _PaceChart extends StatelessWidget {
  /// Creates pace chart.
  const _PaceChart({required this.samples});

  final List<HikePaceSample> samples;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (samples.length < 2) {
      return Container(
        height: 150,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _HistoryColors.backgroundFor(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'More timestamped GPS samples are needed for a pace graph.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _HistoryColors.secondaryFor(context)),
        ),
      );
    }
    final maxPace = samples
        .map((sample) => sample.paceMinutesPerKm)
        .reduce(math.max)
        .clamp(10.0, 90.0);
    return SizedBox(
      height: 210,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: math.max(0.1, samples.last.distanceKm),
          minY: 0,
          maxY: maxPace * 1.12,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: _HistoryColors.separatorFor(context),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: const Text('min/km'),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (value, _) => Text(
                  value.round().toString(),
                  style: TextStyle(
                    color: _HistoryColors.secondaryFor(context),
                    fontSize: 10,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget: const Text('distance (km)'),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, _) => Text(
                  value.toStringAsFixed(1),
                  style: TextStyle(
                    color: _HistoryColors.secondaryFor(context),
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map(
                    (spot) => LineTooltipItem(
                      '${spot.y.toStringAsFixed(1)} min/km\n${spot.x.toStringAsFixed(2)} km',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: samples
                  .map(
                    (sample) => FlSpot(
                      sample.distanceKm,
                      sample.paceMinutesPerKm.clamp(0, maxPace),
                    ),
                  )
                  .toList(),
              isCurved: true,
              curveSmoothness: 0.2,
              color: _HistoryColors.green,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: _HistoryColors.green.withValues(alpha: 0.13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the team route replay.
class _TeamRouteReplay extends StatefulWidget {
  /// Creates team route replay.
  const _TeamRouteReplay({required this.tracks});

  final List<HikeHistoryMemberTrack> tracks;

  /// Creates the presentation state for this widget.
  @override
  State<_TeamRouteReplay> createState() => _TeamRouteReplayState();
}

/// Manages the team route replay presentation and lifecycle.
class _TeamRouteReplayState extends State<_TeamRouteReplay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Container(
    height: 250,
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: const Color(0xFF151633),
      borderRadius: BorderRadius.circular(20),
    ),
    clipBehavior: Clip.antiAlias,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => CustomPaint(
        painter: _TeamReplayPainter(
          tracks: widget.tracks,
          progress: Curves.easeInOut.transform(_controller.value),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'TEAM ROUTE REPLAY',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Represents team replay painter.
class _TeamReplayPainter extends CustomPainter {
  /// Creates team replay painter.
  _TeamReplayPainter({required this.tracks, required this.progress});

  final List<HikeHistoryMemberTrack> tracks;
  final double progress;
  static const colors = [
    Color(0xFF71E099),
    Color(0xFFFFB65B),
    Color(0xFF74B9FF),
    Color(0xFFFF78A5),
    Color(0xFFD6A7FF),
  ];

  /// Computes paint.
  @override
  void paint(Canvas canvas, Size size) {
    final allPoints = tracks.expand((track) => track.routePoints).toList();
    if (allPoints.length < 2) return;
    final minLat = allPoints.map((point) => point.latitude).reduce(math.min);
    final maxLat = allPoints.map((point) => point.latitude).reduce(math.max);
    final minLng = allPoints.map((point) => point.longitude).reduce(math.min);
    final maxLng = allPoints.map((point) => point.longitude).reduce(math.max);
    final globalStart = allPoints
        .map((point) => point.capturedAt.millisecondsSinceEpoch)
        .reduce(math.min);
    final globalEnd = allPoints
        .map((point) => point.capturedAt.millisecondsSinceEpoch)
        .reduce(math.max);

    /// Computes position.
    Offset position(HikeCoordinate point) => Offset(
      24 +
          (point.longitude - minLng) /
              math.max(maxLng - minLng, 0.000001) *
              (size.width - 48),
      45 +
          (1 -
                  (point.latitude - minLat) /
                      math.max(maxLat - minLat, 0.000001)) *
              (size.height - 75),
    );
    final grid = Paint()..color = const Color(0x132FA76B);
    for (var x = 0.0; x < size.width; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var trackIndex = 0; trackIndex < tracks.length; trackIndex++) {
      final points = [...tracks[trackIndex].routePoints]
        ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
      if (points.length < 2) continue;
      final color = colors[trackIndex % colors.length];
      final fullPath = Path()
        ..moveTo(position(points.first).dx, position(points.first).dy);
      for (final point in points.skip(1)) {
        fullPath.lineTo(position(point).dx, position(point).dy);
      }
      canvas.drawPath(
        fullPath,
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final target =
          globalStart + ((globalEnd - globalStart) * progress).round();
      if (target < points.first.capturedAt.millisecondsSinceEpoch) continue;
      var currentIndex = 0;
      while (currentIndex + 1 < points.length &&
          points[currentIndex + 1].capturedAt.millisecondsSinceEpoch <=
              target) {
        currentIndex++;
      }
      final traveled = Path()
        ..moveTo(position(points.first).dx, position(points.first).dy);
      for (final point in points.take(currentIndex + 1).skip(1)) {
        traveled.lineTo(position(point).dx, position(point).dy);
      }
      canvas.drawPath(
        traveled,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = tracks[trackIndex].isCurrentUser ? 4 : 3,
      );
      final marker = position(points[currentIndex]);
      canvas.drawCircle(marker, 7, Paint()..color = color);
      canvas.drawCircle(marker, 3, Paint()..color = Colors.white);
      final label = TextPainter(
        text: TextSpan(
          text: tracks[trackIndex].name,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 90);
      label.paint(canvas, marker + const Offset(9, -7));
    }
  }

  /// Computes should repaint.
  @override
  bool shouldRepaint(covariant _TeamReplayPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.tracks != tracks;
}

/// Displays the history overview.
class _HistoryOverview extends StatelessWidget {
  /// Creates history overview.
  const _HistoryOverview({
    required this.hikeCount,
    required this.totalDistanceKm,
    required this.totalDuration,
  });
  final int hikeCount;
  final double totalDistanceKm;
  final Duration totalDuration;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF176B3A), Color(0xFF34A853)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.landscape_rounded, color: Colors.white, size: 30),
          const SizedBox(height: 20),
          const Text(
            'Your hiking journey',
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _OverviewValue(
                value: '$hikeCount',
                label: hikeCount == 1 ? 'hike' : 'hikes',
              ),
              _OverviewValue(
                value: '${totalDistanceKm.toStringAsFixed(1)} km',
                label: 'distance',
              ),
              _OverviewValue(
                value: _formatDuration(totalDuration),
                label: 'trail time',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Displays the overview value.
class _OverviewValue extends StatelessWidget {
  /// Creates overview value.
  const _OverviewValue({required this.value, required this.label});
  final String value;
  final String label;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12),
        ),
      ],
    ),
  );
}

/// Displays the history image fallback.
class _HistoryImageFallback extends StatelessWidget {
  /// Creates history image fallback.
  const _HistoryImageFallback();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFDCEFE2), Color(0xFF9FD2AD)],
      ),
    ),
    child: Center(
      child: Icon(Icons.terrain_rounded, color: Color(0xFF176B3A), size: 34),
    ),
  );
}

/// Computes trail for history.
Trail _trailForHistory(HikeHistoryDetail detail) {
  final first = detail.routePoints.isNotEmpty
      ? detail.routePoints.first
      : HikeCoordinate(
          latitude: 0,
          longitude: 0,
          capturedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
  return Trail.fromPersistence({
    'trailId': detail.summary.trailId,
    'name': detail.summary.trailName,
    'area': detail.summary.location,
    'state': '',
    'country': '',
    'latitude': first.latitude,
    'longitude': first.longitude,
    'distanceKm': detail.summary.distanceKm,
    'difficulty': detail.summary.difficulty,
    'estimatedDurationMinutes': detail.estimatedDurationMinutes,
    'elevationGainMeters': detail.elevationGainMeters,
    'ratingAverage': detail.trailRatingAverage,
    'ratingCount': detail.trailRatingCount,
    'offlineMapAvailable': false,
    'offlineMapDownloaded': false,
    'isVerifiedTrail': detail.isVerifiedTrail,
    'routeFilePath': '',
    'coverColorValue': 0xFF176B3A,
    if (detail.summary.coverImageUrl.isNotEmpty)
      'coverImageUrl': detail.summary.coverImageUrl,
    'checkpoints': detail.checkpoints
        .map(
          (checkpoint) => {
            'name': checkpoint.name,
            'latitude': checkpoint.latitude,
            'longitude': checkpoint.longitude,
            'order': checkpoint.order,
          },
        )
        .toList(),
    'weather': const <String, dynamic>{},
    'hazards': const <Map<String, dynamic>>[],
  });
}

/// Represents route trace painter.
class _RouteTracePainter extends CustomPainter {
  /// Creates route trace painter.
  _RouteTracePainter({required this.points, required this.checkIns});
  final List<HikeCoordinate> points;
  final List<HikeHistoryCheckIn> checkIns;

  /// Computes paint.
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0x1834A853)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 34) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 34) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (points.length < 2) return;
    final minLat = points.map((p) => p.latitude).reduce(math.min);
    final maxLat = points.map((p) => p.latitude).reduce(math.max);
    final minLng = points.map((p) => p.longitude).reduce(math.min);
    final maxLng = points.map((p) => p.longitude).reduce(math.max);

    /// Computes position.
    Offset position(HikeCoordinate point) {
      final dx =
          (point.longitude - minLng) / math.max(maxLng - minLng, 0.000001);
      final dy =
          (point.latitude - minLat) / math.max(maxLat - minLat, 0.000001);
      return Offset(
        28 + dx * (size.width - 56),
        40 + (1 - dy) * (size.height - 100),
      );
    }

    final path = Path()
      ..moveTo(position(points.first).dx, position(points.first).dy);
    for (final point in points.skip(1)) {
      path.lineTo(position(point).dx, position(point).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x5534A853)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF59D17C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final point in [points.first, points.last]) {
      canvas.drawCircle(
        position(point),
        7,
        Paint()
          ..color = point == points.first
              ? const Color(0xFF34A853)
              : const Color(0xFFE74C3C),
      );
      canvas.drawCircle(position(point), 3, Paint()..color = Colors.white);
    }
    for (final checkIn in checkIns) {
      if (checkIn.coordinate != null) {
        canvas.drawCircle(
          position(checkIn.coordinate!),
          4,
          Paint()..color = const Color(0xFF64B5F6),
        );
      }
    }
  }

  /// Computes should repaint.
  @override
  bool shouldRepaint(covariant _RouteTracePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.checkIns != checkIns;
}

/// Displays the metric grid.
class _MetricGrid extends StatelessWidget {
  /// Creates metric grid.
  const _MetricGrid({required this.metrics});
  final List<_Metric> metrics;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 10,
    crossAxisSpacing: 10,
    childAspectRatio: 2.25,
    children: [
      for (final metric in metrics)
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: _HistoryColors.surfaceFor(context),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(metric.icon, color: _HistoryColors.green, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _HistoryColors.textFor(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      metric.label,
                      style: TextStyle(
                        color: _HistoryColors.secondaryFor(context),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Displays the checkpoint timeline.
class _CheckpointTimeline extends StatelessWidget {
  /// Creates checkpoint timeline.
  const _CheckpointTimeline({required this.checkpoints});
  final List<HikeHistoryCheckpoint> checkpoints;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < checkpoints.length; index++)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: index == 0
                        ? _HistoryColors.green
                        : index == checkpoints.length - 1
                        ? const Color(0xFFE74C3C)
                        : _HistoryColors.green.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: index == 0 || index == checkpoints.length - 1
                          ? Colors.white
                          : _HistoryColors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (index < checkpoints.length - 1)
                  Container(
                    width: 2,
                    height: 30,
                    color: _HistoryColors.separatorFor(context),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      checkpoints[index].name,
                      style: TextStyle(
                        color: _HistoryColors.textFor(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${checkpoints[index].latitude.toStringAsFixed(5)}, ${checkpoints[index].longitude.toStringAsFixed(5)}',
                      style: TextStyle(
                        color: _HistoryColors.secondaryFor(context),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
    ],
  );
}

/// Displays the feature wrap.
class _FeatureWrap extends StatelessWidget {
  /// Creates feature wrap.
  const _FeatureWrap({required this.detail});
  final HikeHistoryDetail detail;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final features = <(String, bool)>[
      ('Live location', detail.shareLiveLocation),
      ('Fall detection', detail.fallDetectionEnabled),
      ('Path deviation', detail.pathDeviationEnabled),
      ('Physical alert', detail.offlinePhysicalAlertEnabled),
      ('Duress protection', detail.duressEnabled),
    ];
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final feature in features)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color:
                  (feature.$2
                          ? _HistoryColors.green
                          : _HistoryColors.secondaryFor(context))
                      .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  feature.$2
                      ? Icons.check_circle_rounded
                      : Icons.remove_circle_outline_rounded,
                  color: feature.$2
                      ? _HistoryColors.green
                      : _HistoryColors.secondaryFor(context),
                  size: 15,
                ),
                const SizedBox(width: 5),
                Text(
                  '${feature.$1}: ${feature.$2 ? 'On' : 'Off'}',
                  style: TextStyle(
                    color: _HistoryColors.textFor(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Displays the event line.
class _EventLine extends StatelessWidget {
  /// Creates event line.
  const _EventLine({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _HistoryColors.green, size: 19),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: _HistoryColors.textFor(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: TextStyle(
                    color: _HistoryColors.secondaryFor(context),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Displays the history message.
class _HistoryMessage extends StatelessWidget {
  /// Creates history message.
  const _HistoryMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: _HistoryColors.green.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _HistoryColors.green, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _HistoryColors.textFor(context),
              fontWeight: FontWeight.w800,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _HistoryColors.secondaryFor(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 17),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              backgroundColor: _HistoryColors.green,
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    ),
  );
}

/// Computes subheading.
TextStyle _subheading(BuildContext context) => TextStyle(
  color: _HistoryColors.textFor(context),
  fontWeight: FontWeight.w800,
  fontSize: 14,
);

/// Computes history error.
String _historyError(Object? error) =>
    error is HikerCircleFirebaseRepositoryException
    ? error.message
    : 'Check your connection and try again.';

/// Computes value or unavailable.
String _valueOrUnavailable(String value) =>
    value.trim().isEmpty ? 'Not recorded' : value.trim();

/// Computes title case words.
String _titleCaseWords(String value) => value
    .trim()
    .split(RegExp(r'\s+'))
    .where((word) => word.isNotEmpty)
    .map((word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
    .join(' ');

/// Formats duration.
String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '${math.max(0, minutes)}m';
  return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
}

/// Formats date time.
String _formatDateTime(DateTime? value) {
  if (value == null) return 'Not recorded';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final minute = value.minute.toString().padLeft(2, '0');
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  return '${value.day} ${months[value.month - 1]} ${value.year}, $hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
}

/// Formats history date.
String _formatHistoryDate(DateTime? value) =>
    value == null ? 'Completion date unavailable' : _formatDateTime(value);

/// Formats interval.
String _formatInterval(int seconds) {
  if (seconds <= 0) return 'Not recorded';
  if (seconds < 60) return '$seconds seconds';
  final minutes = seconds ~/ 60;
  return minutes == 1 ? '1 minute' : '$minutes minutes';
}

/// Computes coordinate label.
String _coordinateLabel(HikeCoordinate point) =>
    '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';

/// Represents history colors.
abstract final class _HistoryColors {
  static const green = Color(0xFF34A853);

  /// Computes dark.
  static bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Computes background for.
  static Color backgroundFor(BuildContext context) =>
      _dark(context) ? const Color(0xFF0C120F) : const Color(0xFFF2F2F7);

  /// Computes surface for.
  static Color surfaceFor(BuildContext context) =>
      _dark(context) ? const Color(0xFF141C17) : Colors.white;

  /// Computes text for.
  static Color textFor(BuildContext context) =>
      _dark(context) ? const Color(0xFFEAF4EE) : const Color(0xFF111111);

  /// Computes secondary for.
  static Color secondaryFor(BuildContext context) =>
      _dark(context) ? const Color(0xFFA8B8AE) : const Color(0xFF6E6E73);

  /// Computes separator for.
  static Color separatorFor(BuildContext context) =>
      _dark(context) ? const Color(0xFF2B3A31) : const Color(0xFFE1E5E2);
}

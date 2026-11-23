part of '../../hike_history_page_feature.dart';

/// Displays the history analysis tab.
class _HistoryAnalysisTab extends StatelessWidget {
  /// Creates history analysis tab.
  const _HistoryAnalysisTab({required this.detail, required this.onRefresh});

  final HikeHistoryDetail detail;
  final Future<void> Function() onRefresh;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final analysis = _analysisForHistory(detail);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
        children: [
          _MetricGrid(
            metrics: [
              _Metric(
                Icons.directions_walk_rounded,
                'Moving time',
                _formatDuration(analysis.movingDuration),
              ),
              _Metric(
                Icons.pause_circle_outline_rounded,
                'Stopped time',
                _formatDuration(analysis.stoppedDuration),
              ),
              _Metric(
                Icons.bolt_rounded,
                'Fastest pace',
                analysis.fastestPaceMinutesPerKm > 0
                    ? '${analysis.fastestPaceMinutesPerKm.toStringAsFixed(1)} min/km'
                    : 'No data',
              ),
              _Metric(
                Icons.radar_rounded,
                'GPS distance',
                '${analysis.totalDistanceKm.toStringAsFixed(2)} km',
              ),
            ],
          ),
          _DetailSection(
            title: 'Pace profile',
            icon: Icons.show_chart_rounded,
            rows: const [],
            child: _PaceChart(samples: analysis.samples),
          ),
          _DetailSection(
            title: 'Checkpoint analysis',
            icon: Icons.flag_circle_rounded,
            rows: const [],
            child: analysis.checkpoints.isEmpty
                ? const Text('No checkpoints were saved for this hike.')
                : Column(
                    children: [
                      for (
                        var index = 0;
                        index < analysis.checkpoints.length;
                        index++
                      ) ...[
                        _CheckpointAnalysisRow(
                          checkpoint: analysis.checkpoints[index],
                          index: index,
                        ),
                        if (index < analysis.checkpoints.length - 1)
                          Divider(
                            height: 1,
                            color: _HistoryColors.separatorFor(context),
                          ),
                      ],
                    ],
                  ),
          ),
          _DetailSection(
            title: 'Recording quality',
            icon: Icons.gps_fixed_rounded,
            rows: [
              _RowData('Recorded GPS points', '${detail.routePoints.length}'),
              _RowData('Raw telemetry points', '${detail.telemetryPointCount}'),
              _RowData(
                'Cloud route',
                detail.routeCaptureAvailable ? 'Available' : 'Summary only',
              ),
              _RowData(
                'Storage resolution',
                detail.routePointsDownsampled
                    ? 'Optimized copy'
                    : 'Full capture',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Displays the checkpoint analysis row.
class _CheckpointAnalysisRow extends StatelessWidget {
  /// Creates checkpoint analysis row.
  const _CheckpointAnalysisRow({required this.checkpoint, required this.index});

  final HikeCheckpointAnalysis checkpoint;
  final int index;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final reached = checkpoint.reached;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: reached
                  ? _HistoryColors.green
                  : _HistoryColors.secondaryFor(
                      context,
                    ).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: reached
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 19)
                : Text('${index + 1}'),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  checkpoint.name,
                  style: TextStyle(
                    color: _HistoryColors.textFor(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reached
                      ? 'Reached ${_formatDateTime(checkpoint.reachedAt)}'
                      : 'No recorded point within 100 m (nearest ${checkpoint.distanceFromTrackMeters.round()} m)',
                  style: TextStyle(
                    color: reached
                        ? _HistoryColors.secondaryFor(context)
                        : const Color(0xFFE07A36),
                    fontSize: 12,
                  ),
                ),
                if (reached) ...[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _AnalysisChip(
                        icon: Icons.timer_outlined,
                        text: checkpoint.timeFromPrevious == null
                            ? 'Starting point'
                            : _formatDuration(checkpoint.timeFromPrevious!),
                      ),
                      _AnalysisChip(
                        icon: Icons.straighten_rounded,
                        text:
                            '${checkpoint.distanceFromPreviousKm.toStringAsFixed(2)} km',
                      ),
                      _AnalysisChip(
                        icon: Icons.directions_walk_rounded,
                        text: checkpoint.paceMinutesPerKm > 0
                            ? '${checkpoint.paceMinutesPerKm.toStringAsFixed(1)} min/km'
                            : 'Pace unavailable',
                      ),
                      _AnalysisChip(
                        icon: Icons.speed_rounded,
                        text: checkpoint.speedKmh > 0
                            ? '${checkpoint.speedKmh.toStringAsFixed(1)} km/h'
                            : 'Speed unavailable',
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the analysis chip.
class _AnalysisChip extends StatelessWidget {
  /// Creates analysis chip.
  const _AnalysisChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: _HistoryColors.backgroundFor(context),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: _HistoryColors.green),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}

/// Displays the history safety tab.
class _HistorySafetyTab extends StatelessWidget {
  /// Creates history safety tab.
  const _HistorySafetyTab({required this.detail, required this.onRefresh});

  final HikeHistoryDetail detail;
  final Future<void> Function() onRefresh;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
      children: [
        _DetailSection(
          title: 'Safety overview',
          icon: Icons.health_and_safety_rounded,
          rows: [
            _RowData('Safe check-ins', '${detail.checkInRecords.length}'),
            _RowData('Deviation alerts', '${detail.pathDeviationAlertCount}'),
            _RowData('Battery used', '${detail.batteryUsedPercent}%'),
          ],
          child: _FeatureWrap(detail: detail),
        ),
        if (detail.checkInRecords.isNotEmpty)
          _DetailSection(
            title: 'Check-in timeline',
            icon: Icons.verified_user_rounded,
            rows: const [],
            child: Column(
              children: detail.checkInRecords
                  .map(
                    (record) => _EventLine(
                      icon: Icons.verified_user_rounded,
                      title: record.status == 'safe'
                          ? 'Safe check-in'
                          : record.status,
                      subtitle:
                          '${_formatDateTime(record.checkedInAt)}${record.batteryLevel > 0 ? ' · Battery ${record.batteryLevel}%' : ''}',
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    ),
  );
}

/// Displays the history team tab.
class _HistoryTeamTab extends StatefulWidget {
  /// Creates history team tab.
  const _HistoryTeamTab({
    required this.detail,
    required this.onRefresh,
    this.repository,
    this.session,
  });

  final HikeHistoryDetail detail;
  final Future<void> Function() onRefresh;
  final HikerCircleFirebaseRepository? repository;
  final AppSession? session;

  /// Creates the presentation state for this widget.
  @override
  State<_HistoryTeamTab> createState() => _HistoryTeamTabState();
}

/// Manages the history team tab presentation and lifecycle.
class _HistoryTeamTabState extends State<_HistoryTeamTab> {
  late final _HistoryTeamTabStateViewModel _screenModel;

  /// Returns opening chat.
  bool get _openingChat => _screenModel.stateOpeningChat;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Delegates open chat to the ViewModel.
  Future<void> _openChat() => _screenModel.commandOpenChat();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final tracks = widget.detail.memberTracks.isNotEmpty
        ? widget.detail.memberTracks
        : [
            HikeHistoryMemberTrack(
              name: 'You',
              isCurrentUser: true,
              routePoints: widget.detail.routePoints,
            ),
          ];
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4941A8), Color(0xFF7168DD)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.groups_2_rounded,
                  color: Colors.white,
                  size: 30,
                ),
                const SizedBox(height: 9),
                Text(
                  '${widget.detail.summary.teamMemberCount} hikers completed ${widget.detail.summary.trailName}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Replay timing follows each member’s recorded GPS timestamps.',
                  style: TextStyle(color: Color(0xDDFFFFFF)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _TeamRouteReplay(tracks: tracks),
          _DetailSection(
            title: 'Hiking team',
            icon: Icons.people_alt_rounded,
            rows: [
              _RowData(
                'Team size',
                '${widget.detail.summary.teamMemberCount} hikers',
              ),
              _RowData('Recorded member tracks', '${tracks.length}'),
              for (final name in widget.detail.teamBuddyNames)
                _RowData('Member', name),
            ],
          ),
          if (widget.detail.groupChatId.isNotEmpty &&
              widget.repository != null &&
              widget.session != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('open-history-group-chat'),
              onPressed: _openingChat ? null : _openChat,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF5C54C7),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _openingChat
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: HikerCircleMinorLoadingIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.forum_rounded),
              label: const Text('Open this hike’s group chat'),
            ),
          ],
        ],
      ),
    );
  }

  /// Presents the open chat effect1 UI.
  void _presentOpenChatEffect1() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('This hike chat is no longer available.'),
      behavior: SnackBarBehavior.floating,
    ),
  );

  /// Presents the open chat effect2 UI.
  Future<void> _presentOpenChatEffect2(
    GroupChat chat,
    AppSession session,
    HikerCircleFirebaseRepository repository,
  ) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => GroupChatDetailPage(
        chat: chat,
        session: session,
        repository: repository,
      ),
    ),
  );

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _HistoryTeamTabStateViewModel()
      ..addListener(_renderScreenModel);
    _screenModel.readDetail = () => widget.detail;
    _screenModel.readSession = () => widget.session;
    _screenModel.readRepository = () => widget.repository;
    _screenModel.effectPresentOpenChatEffect2 = _presentOpenChatEffect2;
    _screenModel.effectPresentOpenChatEffect1 = _presentOpenChatEffect1;
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }
}

/// Displays the hike history card.
class _HikeHistoryCard extends StatelessWidget {
  /// Creates hike history card.
  const _HikeHistoryCard({required this.hike, required this.onTap});
  final HikeHistorySummary hike;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: _HistoryColors.surfaceFor(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: Key('hike-history-${hike.sessionId}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 72,
                  height: 82,
                  child: hike.coverImageUrl.isNotEmpty
                      ? CachedTrailImage(
                          key: Key('hike-history-cover-${hike.sessionId}'),
                          imageUrl: hike.coverImageUrl,
                          width: 72,
                          height: 82,
                          fit: BoxFit.cover,
                          semanticLabel: '${hike.trailName} trail cover',
                          fallbackBuilder: (_) => const _HistoryImageFallback(),
                        )
                      : const _HistoryImageFallback(),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            hike.trailName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _HistoryColors.textFor(context),
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        _TypePill(isTeam: hike.isTeam),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatHistoryDate(hike.endedAt ?? hike.startedAt),
                      style: TextStyle(
                        color: _HistoryColors.secondaryFor(context),
                        fontSize: 13,
                      ),
                    ),
                    if (hike.pendingSync || hike.awaitingHistory)
                      Text(
                        hike.awaitingHistory
                            ? 'Synced · Updating history'
                            : 'Saved on this phone · Waiting to sync',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _MiniMetric(
                          icon: Icons.straighten_rounded,
                          label: '${hike.distanceKm.toStringAsFixed(1)} km',
                        ),
                        const SizedBox(width: 13),
                        _MiniMetric(
                          icon: Icons.schedule_rounded,
                          label: _formatDuration(hike.duration),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: _HistoryColors.secondaryFor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the recorded route card.
class _RecordedRouteCard extends StatelessWidget {
  /// Creates recorded route card.
  const _RecordedRouteCard({
    required this.detail,
    required this.enableInteractiveRoute,
  });
  final HikeHistoryDetail detail;
  final bool enableInteractiveRoute;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final points =
        detail.routePoints.where((point) => point.hasValidPosition).toList()
          ..sort(
            (first, second) => first.capturedAt.compareTo(second.capturedAt),
          );
    final trail = _trailForHistory(detail);
    final checkIns = detail.checkInRecords
        .map((record) => record.coordinate)
        .whereType<HikeCoordinate>()
        .map(
          (point) => mapbox.Point(
            coordinates: mapbox.Position(point.longitude, point.latitude),
          ),
        )
        .toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        color: const Color(0xFF10271A),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              key: const ValueKey('history-route-header'),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Text(
                points.length >= 2 ? 'RECORDED ROUTE' : 'ROUTE SUMMARY',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            SizedBox(
              key: const ValueKey('history-route-map-area'),
              height: 260,
              child: points.length >= 2 && enableInteractiveRoute
                  ? RoutePreviewMap(
                      key: const Key('hike-history-actual-route-map'),
                      trail: trail,
                      recordedTrackPoints: [
                        for (final point in points)
                          mapbox.Point(
                            coordinates: mapbox.Position(
                              point.longitude,
                              point.latitude,
                            ),
                          ),
                      ],
                      checkInPoints: checkIns,
                      animateRoute: kReleaseMode,
                      animationDuration: const Duration(seconds: 10),
                      captureAllGestures: true,
                    )
                  : CustomPaint(
                      key: const ValueKey('history-route-paint-fallback'),
                      painter: _RouteTracePainter(
                        points: points,
                        checkIns: detail.checkInRecords,
                      ),
                    ),
            ),
            Padding(
              key: const ValueKey('history-route-footer'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 15),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.summary.trailName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          points.length >= 2
                              ? '${points.length} saved route points'
                              : 'Route geometry was not captured for this hike',
                          style: const TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Tooltip(
                    message: 'Private hike',
                    child: Icon(
                      Icons.lock_rounded,
                      color: Colors.white,
                      size: 19,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the detail section.
class _DetailSection extends StatelessWidget {
  /// Creates detail section.
  const _DetailSection({
    required this.title,
    required this.icon,
    required this.rows,
    this.child,
  });
  final String title;
  final IconData icon;
  final List<_RowData> rows;
  final Widget? child;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: _HistoryColors.surfaceFor(context),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _HistoryColors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _HistoryColors.green, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                color: _HistoryColors.textFor(context),
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
          ],
        ),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 13),
          for (var index = 0; index < rows.length; index++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      rows[index].label,
                      style: TextStyle(
                        color: _HistoryColors.secondaryFor(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      rows[index].value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: _HistoryColors.textFor(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (index < rows.length - 1)
              Divider(height: 1, color: _HistoryColors.separatorFor(context)),
          ],
        ],
        if (child != null) ...[const SizedBox(height: 14), child!],
      ],
    ),
  );
}

/// Displays the type pill.
class _TypePill extends StatelessWidget {
  /// Creates type pill.
  const _TypePill({required this.isTeam});
  final bool isTeam;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: _HistoryColors.green.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      isTeam ? 'Group' : 'Solo',
      style: const TextStyle(
        color: _HistoryColors.green,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Displays the mini metric.
class _MiniMetric extends StatelessWidget {
  /// Creates mini metric.
  const _MiniMetric({required this.icon, required this.label});
  final IconData icon;
  final String label;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: _HistoryColors.green),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(
          color: _HistoryColors.textFor(context),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

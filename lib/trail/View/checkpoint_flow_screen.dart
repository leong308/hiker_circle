part of '../checkpoint_flow_feature.dart';

/// Keep the displayed checkpoint order aligned with the trail route timeline.
class CheckpointFlow extends StatefulWidget {
  /// Creates checkpoint flow.
  const CheckpointFlow({
    super.key,
    required this.checkpoints,
    required this.highlightedIndex,
    required this.onShowOnMap,
    this.playback,
  });
  final List<TrailCheckpoint> checkpoints;
  final int? highlightedIndex;
  final ValueChanged<int> onShowOnMap;
  final ValueListenable<RouteCheckpointProgress>? playback;

  /// Creates the presentation state for this widget.
  @override
  State<CheckpointFlow> createState() => _CheckpointFlowState();
}

/// Manages the checkpoint flow presentation and lifecycle.
class _CheckpointFlowState extends State<CheckpointFlow> {
  late final _CheckpointFlowStateViewModel _screenModel;

  /// Returns following.
  bool get _following => _screenModel.stateFollowing;

  /// Updates following.
  set _following(bool value) => _screenModel.stateFollowing = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  static const _extent = 176.0;
  static const _blue = Color(0xFF007AFF);
  final _scroll = ScrollController();

  bool _scrollScheduled = false;

  /// Returns progress.
  RouteCheckpointProgress get _progress => _screenModel.commandProgress;

  /// Returns order.
  List<int> get _order => _screenModel.commandOrder;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _CheckpointFlowStateViewModel(
      readCheckpoints: () => widget.checkpoints,
      readOnShowOnMap: () => widget.onShowOnMap,
      readPlayback: () => widget.playback,
      effectScheduleFollow: _scheduleFollow,
    )..addListener(_renderScreenModel);

    widget.playback?.addListener(_onPlayback);
    _scheduleFollow();
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant CheckpointFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playback != widget.playback) {
      oldWidget.playback?.removeListener(_onPlayback);
      widget.playback?.addListener(_onPlayback);
    }
    _scheduleFollow();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    widget.playback?.removeListener(_onPlayback);
    _scroll.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates on playback to the ViewModel.
  void _onPlayback() => _screenModel.commandOnPlayback();

  /// Computes schedule follow.
  void _scheduleFollow() {
    if (!_following || _scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_following || !_scroll.hasClients) return;
      final offset =
          (_progress.positionIn(_order) * _extent +
                  _extent / 2 -
                  _scroll.position.viewportDimension / 2)
              .clamp(0.0, _scroll.position.maxScrollExtent);
      // Follow the map's playhead directly; a separate looping animation would
      // drift during checkpoint pauses, speed changes and route replays.
      if ((_scroll.offset - offset).abs() > .25) _scroll.jumpTo(offset);
    });
  }

  /// Delegates select to the ViewModel.
  void _select(int index) => _screenModel.commandSelect(index);

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = _order;
    final progress = _progress;
    final position = progress.positionIn(order);
    final next = progress.nextIndex;
    final title = !progress.isReady
        ? '${order.length} checkpoints'
        : progress.isComplete
        ? 'Route complete'
        : next == null
        ? 'Following route'
        : 'Next · ${widget.checkpoints[next].name}';
    final cardHeight =
        112.0 + (MediaQuery.textScalerOf(context).scale(14) - 14) * 5;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 0),
            child: Row(
              children: [
                Icon(
                  progress.isComplete
                      ? Icons.check_circle_rounded
                      : Icons.route_rounded,
                  size: 18,
                  color: _blue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (progress.isReady)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '${(progress.progress * 100).round()}%',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: _blue,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: !_following
                      ? () {
                          setState(() => _following = true);
                          _scheduleFollow();
                        }
                      : null,
                  child: Text(_following ? 'Following' : 'Follow'),
                ),
              ],
            ),
          ),
          NotificationListener<ScrollStartNotification>(
            onNotification: (notification) {
              if (notification.dragDetails != null && _following) {
                setState(() => _following = false);
              }
              return false;
            },
            child: SingleChildScrollView(
              key: const ValueKey('checkpoint-timeline-scroll'),
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: SizedBox(
                width: order.length * _extent,
                height: cardHeight + 68,
                child: Stack(
                  children: [
                    Positioned(
                      left: _extent / 2,
                      right: _extent / 2,
                      top: 31,
                      height: 6,
                      child: CustomPaint(
                        painter: _TimelinePainter(
                          fraction: order.length < 2 || !progress.isReady
                              ? 0
                              : position / (order.length - 1),
                          track: theme.colorScheme.outlineVariant,
                          showPlayhead: progress.isReady,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var ordinal = 0; ordinal < order.length; ordinal++)
                          _stop(
                            context,
                            order[ordinal],
                            ordinal,
                            order.length,
                            cardHeight,
                          ),
                      ],
                    ),
                    for (var i = 0; i < order.length - 1; i++)
                      Positioned(
                        left: _extent * (i + 1) - 48,
                        top: 0,
                        width: 96,
                        height: 26,
                        child: _legChip(order[i], order[i + 1]),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Delegates distance label to the ViewModel.
  String _distanceLabel(double meters) =>
      _screenModel.commandDistanceLabel(meters);

  /// Computes leg chip.
  Widget _legChip(int from, int to) {
    final distance = _progress.legDistanceMeters(from, to);
    if (distance == null) return const SizedBox.shrink();
    return Tooltip(
      message: 'View route distance and leg progress',
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: ValueKey('checkpoint-leg-$from-$to'),
          onTap: () => _showLeg(from, to),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.route_rounded, size: 12, color: _blue),
                const SizedBox(width: 4),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _distanceLabel(distance),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _blue,
                      ),
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 12, color: _blue),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Shows leg.
  void _showLeg(int from, int to) {
    final playback = widget.playback;
    if (playback == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: ValueListenableBuilder<RouteCheckpointProgress>(
            valueListenable: playback,
            builder: (context, value, _) {
              final length = value.legDistanceMeters(from, to);
              final fraction = value.legProgress(from, to);
              final total = value.checkpointDistancesMeters.values.fold<double>(
                0,
                (a, b) => a > b ? a : b,
              );
              final minutes = total > 0 && length != null
                  ? (value.estimatedDuration.inMinutes * length / total).round()
                  : 0;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.checkpoints[from].name} → ${widget.checkpoints[to].name}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    length == null
                        ? 'Route distance unavailable'
                        : _distanceLabel(length),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: _blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Text('Distance along the trail'),
                  if (minutes > 0)
                    Text('About $minutes min at the estimated hiking pace'),
                  const SizedBox(height: 20),
                  LinearProgressIndicator(
                    value: fraction,
                    color: _blue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    fraction >= 1
                        ? 'Leg complete'
                        : fraction == 0
                        ? 'Upcoming leg'
                        : '${(fraction * 100).round()}% of this leg · ${_distanceLabel((length ?? 0) * (1 - fraction))} remaining',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _select(to);
                    },
                    icon: const Icon(Icons.near_me_outlined),
                    label: const Text('Show destination on map'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Stops.
  Widget _stop(
    BuildContext context,
    int index,
    int ordinal,
    int count,
    double height,
  ) {
    final checkpoint = widget.checkpoints[index];
    final theme = Theme.of(context);
    final progress = _progress;
    final fraction = progress.checkpointFractions[index];
    final reached = fraction != null && progress.progress >= fraction - 1e-6;
    final next = progress.nextIndex == index;
    final selected = !_following && widget.highlightedIndex == index;
    final active =
        selected || next || (progress.isComplete && ordinal == count - 1);
    final label = !checkpoint.hasValidCoordinate
        ? 'LOCATION UNAVAILABLE'
        : ordinal == 0
        ? 'START'
        : ordinal == count - 1
        ? 'FINISH'
        : 'CHECKPOINT ${ordinal + 1}';
    return SizedBox(
      width: _extent,
      child: Column(
        children: [
          SizedBox(
            height: 68,
            child: Center(
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: reached ? _blue : theme.colorScheme.surface,
                  border: Border.all(
                    color: reached || next
                        ? _blue
                        : theme.colorScheme.outlineVariant,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: reached
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: Colors.white,
                        )
                      : Text(
                          '${ordinal + 1}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: next
                                ? _blue
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Semantics(
              selected: selected,
              label:
                  '${checkpoint.name}, ${reached
                      ? 'reached'
                      : next
                      ? 'next checkpoint'
                      : 'upcoming'}',
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: height,
                decoration: BoxDecoration(
                  color: active
                      ? _blue.withValues(alpha: .09)
                      : theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: active
                        ? _blue
                        : theme.colorScheme.outlineVariant.withValues(
                            alpha: .5,
                          ),
                  ),
                ),
                child: InkWell(
                  key: ValueKey('checkpoint-stop-$index'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: checkpoint.hasValidCoordinate
                      ? () => _select(index)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .7,
                            color: active
                                ? _blue
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Expanded(
                          child: Text(
                            checkpoint.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                reached
                                    ? 'Reached'
                                    : next
                                    ? 'Up next'
                                    : 'View checkpoint',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                tooltip: 'Show on map',
                                onPressed: checkpoint.hasValidCoordinate
                                    ? () => _select(index)
                                    : null,
                                icon: const Icon(
                                  Icons.near_me_outlined,
                                  size: 16,
                                ),
                                color: _blue,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Represents timeline painter.
class _TimelinePainter extends CustomPainter {
  /// Creates timeline painter.
  const _TimelinePainter({
    required this.fraction,
    required this.track,
    required this.showPlayhead,
  });
  final double fraction;
  final Color track;
  final bool showPlayhead;

  /// Computes paint.
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint..color = track,
    );
    if (!showPlayhead) return;
    final head = Offset(size.width * fraction.clamp(0, 1), size.height / 2);
    canvas.drawLine(
      Offset(0, size.height / 2),
      head,
      paint..color = const Color(0xFF007AFF),
    );
    canvas.drawCircle(head, 7, Paint()..color = const Color(0x447DD3FC));
    canvas.drawCircle(head, 4, Paint()..color = const Color(0xFF007AFF));
  }

  /// Computes should repaint.
  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.fraction != fraction ||
      old.track != track ||
      old.showPlayhead != showPlayhead;
}

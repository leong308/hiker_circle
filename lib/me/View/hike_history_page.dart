import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../core/widgets/loading_toast.dart';
import '../../home/Model/hike_session_models.dart';
import '../Model/hike_history_models.dart';

typedef HikeHistoryListLoader = Future<List<HikeHistorySummary>> Function();
typedef HikeHistoryDetailLoader =
    Future<HikeHistoryDetail> Function(String sessionId);

class HikeHistoryPage extends StatefulWidget {
  const HikeHistoryPage({
    super.key,
    required this.repository,
    this.loadHistory,
    this.loadDetail,
  });

  final HikerCircleFirebaseRepository repository;
  final HikeHistoryListLoader? loadHistory;
  final HikeHistoryDetailLoader? loadDetail;

  @override
  State<HikeHistoryPage> createState() => _HikeHistoryPageState();
}

class _HikeHistoryPageState extends State<HikeHistoryPage> {
  late Future<List<HikeHistorySummary>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _load();
  }

  Future<List<HikeHistorySummary>> _load() =>
      widget.loadHistory?.call() ?? widget.repository.loadMyHikeHistory();

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _historyFuture = future);
    await future;
  }

  void _openDetail(HikeHistorySummary hike) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => HikeHistoryDetailPage(
          summary: hike,
          loadDetail:
              widget.loadDetail ?? widget.repository.loadMyHikeHistoryDetail,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _HistoryColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: _HistoryColors.backgroundFor(context),
        surfaceTintColor: Colors.transparent,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.back, size: 22),
        ),
        title: const Text(
          'Hike history',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: FutureBuilder<List<HikeHistorySummary>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          final isLoading = snapshot.connectionState != ConnectionState.done;
          if (isLoading && !snapshot.hasData) {
            return const Stack(
              children: [
                HikerCircleLoadingToastOverlay(
                  message: 'Synchronising hike history, please wait…',
                  detail: 'Loading your completed hikes securely.',
                  dimBackground: false,
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
                Text(
                  'PAST HIKES',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _HistoryColors.secondaryFor(context),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
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
                const HikerCircleLoadingToastOverlay(
                  message: 'Synchronising hike history, please wait…',
                  detail: 'Refreshing your completed hikes securely.',
                ),
            ],
          );
        },
      ),
    );
  }
}

class HikeHistoryDetailPage extends StatefulWidget {
  const HikeHistoryDetailPage({
    super.key,
    required this.summary,
    required this.loadDetail,
  });

  final HikeHistorySummary summary;
  final HikeHistoryDetailLoader loadDetail;

  @override
  State<HikeHistoryDetailPage> createState() => _HikeHistoryDetailPageState();
}

class _HikeHistoryDetailPageState extends State<HikeHistoryDetailPage> {
  late Future<HikeHistoryDetail> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = widget.loadDetail(widget.summary.sessionId);
  }

  Future<void> _refresh() async {
    final future = widget.loadDetail(widget.summary.sessionId);
    setState(() => _detailFuture = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _HistoryColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: _HistoryColors.backgroundFor(context),
        surfaceTintColor: Colors.transparent,
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
            return const Stack(
              children: [
                HikerCircleLoadingToastOverlay(
                  message: 'Synchronising hike details, please wait…',
                  detail: 'Loading route and safety records securely.',
                  dimBackground: false,
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
          );
          return Stack(
            children: [
              content,
              if (isLoading)
                const HikerCircleLoadingToastOverlay(
                  message: 'Synchronising hike details, please wait…',
                  detail: 'Refreshing route and safety records securely.',
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HikeHistoryDetailBody extends StatelessWidget {
  const _HikeHistoryDetailBody({required this.detail, required this.onRefresh});

  final HikeHistoryDetail detail;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 36),
        children: [
          _RecordedRouteCard(detail: detail),
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
              _RowData('Pinned locations', '${summary.manualPins}'),
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
                if (detail.manualPins.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Pinned locations', style: _subheading(context)),
                  const SizedBox(height: 7),
                  for (var index = 0; index < detail.manualPins.length; index++)
                    _EventLine(
                      icon: Icons.location_pin,
                      title: 'Pin ${index + 1}',
                      subtitle:
                          '${_formatDateTime(detail.manualPins[index].pinnedAt.toLocal())} · ${_coordinateLabel(detail.manualPins[index].coordinate)}',
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
  }
}

class _HistoryOverview extends StatelessWidget {
  const _HistoryOverview({
    required this.hikeCount,
    required this.totalDistanceKm,
    required this.totalDuration,
  });
  final int hikeCount;
  final double totalDistanceKm;
  final Duration totalDuration;

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

class _OverviewValue extends StatelessWidget {
  const _OverviewValue({required this.value, required this.label});
  final String value;
  final String label;
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

class _HikeHistoryCard extends StatelessWidget {
  const _HikeHistoryCard({required this.hike, required this.onTap});
  final HikeHistorySummary hike;
  final VoidCallback onTap;

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
              Container(
                width: 72,
                height: 82,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFDCEFE2), Color(0xFF9FD2AD)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.terrain_rounded,
                  color: Color(0xFF176B3A),
                  size: 34,
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

class _RecordedRouteCard extends StatelessWidget {
  const _RecordedRouteCard({required this.detail});
  final HikeHistoryDetail detail;

  @override
  Widget build(BuildContext context) {
    final points = detail.routePoints;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 260,
        color: const Color(0xFF10271A),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _RouteTracePainter(
                  points: points,
                  pins: detail.manualPins,
                  checkIns: detail.checkInRecords,
                ),
              ),
            ),
            Positioned(
              left: 16,
              top: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xE61A3022),
                  borderRadius: BorderRadius.circular(999),
                ),
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
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 15,
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
                  const Icon(Icons.lock_rounded, color: Colors.white, size: 19),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteTracePainter extends CustomPainter {
  _RouteTracePainter({
    required this.points,
    required this.pins,
    required this.checkIns,
  });
  final List<HikeCoordinate> points;
  final List<HikeManualPin> pins;
  final List<HikeHistoryCheckIn> checkIns;

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
    for (final pin in pins) {
      canvas.drawCircle(
        position(pin.coordinate),
        5,
        Paint()..color = const Color(0xFFFFC107),
      );
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

  @override
  bool shouldRepaint(covariant _RouteTracePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.pins != pins ||
      oldDelegate.checkIns != checkIns;
}

class _Metric {
  const _Metric(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});
  final List<_Metric> metrics;
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

class _RowData {
  const _RowData(this.label, this.value);
  final String label;
  final String value;
}

class _DetailSection extends StatelessWidget {
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

class _CheckpointTimeline extends StatelessWidget {
  const _CheckpointTimeline({required this.checkpoints});
  final List<HikeHistoryCheckpoint> checkpoints;
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

class _FeatureWrap extends StatelessWidget {
  const _FeatureWrap({required this.detail});
  final HikeHistoryDetail detail;
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

class _EventLine extends StatelessWidget {
  const _EventLine({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;
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

class _TypePill extends StatelessWidget {
  const _TypePill({required this.isTeam});
  final bool isTeam;
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

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.icon, required this.label});
  final IconData icon;
  final String label;
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

class _HistoryMessage extends StatelessWidget {
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

TextStyle _subheading(BuildContext context) => TextStyle(
  color: _HistoryColors.textFor(context),
  fontWeight: FontWeight.w800,
  fontSize: 14,
);

String _historyError(Object? error) =>
    error is HikerCircleFirebaseRepositoryException
    ? error.message
    : 'Check your connection and try again.';
String _valueOrUnavailable(String value) =>
    value.trim().isEmpty ? 'Not recorded' : value.trim();
String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '${math.max(0, minutes)}m';
  return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
}

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

String _formatHistoryDate(DateTime? value) =>
    value == null ? 'Completion date unavailable' : _formatDateTime(value);
String _formatInterval(int seconds) {
  if (seconds <= 0) return 'Not recorded';
  if (seconds < 60) return '$seconds seconds';
  final minutes = seconds ~/ 60;
  return minutes == 1 ? '1 minute' : '$minutes minutes';
}

String _coordinateLabel(HikeCoordinate point) =>
    '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';

abstract final class _HistoryColors {
  static const green = Color(0xFF34A853);
  static bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
  static Color backgroundFor(BuildContext context) =>
      _dark(context) ? const Color(0xFF0C120F) : const Color(0xFFF2F2F7);
  static Color surfaceFor(BuildContext context) =>
      _dark(context) ? const Color(0xFF141C17) : Colors.white;
  static Color textFor(BuildContext context) =>
      _dark(context) ? const Color(0xFFEAF4EE) : const Color(0xFF111111);
  static Color secondaryFor(BuildContext context) =>
      _dark(context) ? const Color(0xFFA8B8AE) : const Color(0xFF6E6E73);
  static Color separatorFor(BuildContext context) =>
      _dark(context) ? const Color(0xFF2B3A31) : const Color(0xFFE1E5E2);
}

import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../../circle/View/group_chat_detail_page.dart';
import '../../core/models/hike_route_analysis.dart';
import '../../core/services/hiking_route_service.dart';
import '../../core/widgets/loading_toast.dart';
import '../../core/widgets/cached_trail_image.dart';
import '../../core/widgets/route_preview_map.dart';
import '../../home/Model/hike_session_models.dart';
import '../../trail/Model/trail_models.dart';
import '../Model/hike_history_models.dart';
import '../Data/expired_hikes_repository.dart';

typedef ExpiredHikesPageLoader =
    Future<ExpiredHikesPage> Function(ExpiredHikesCursor? cursor);

typedef HikeHistoryListLoader = Future<List<HikeHistorySummary>> Function();
typedef HikeHistoryDetailLoader =
    Future<HikeHistoryDetail> Function(String sessionId);

class HikeHistoryPage extends StatefulWidget {
  const HikeHistoryPage({
    super.key,
    required this.repository,
    this.session,
    this.loadHistory,
    this.loadDetail,
    this.loadExpiredHikes,
    this.enableInteractiveRoute = true,
  });

  final HikerCircleFirebaseRepository repository;
  final AppSession? session;
  final HikeHistoryListLoader? loadHistory;
  final HikeHistoryDetailLoader? loadDetail;
  final ExpiredHikesPageLoader? loadExpiredHikes;
  final bool enableInteractiveRoute;

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
          repository: widget.repository,
          session: widget.session,
          enableInteractiveRoute: widget.enableInteractiveRoute,
        ),
      ),
    );
  }

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
              loader:
                  widget.loadExpiredHikes ??
                  (cursor) =>
                      ExpiredHikesRepository(
                        localDatabase: widget.repository.localDatabase,
                      ).loadPage(
                        ownerPhoneNumber: widget.session?.phoneNumber ?? '',
                        cursor: cursor,
                      ),
            ),
          ],
        ),
      ),
    );
  }

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
}

class _ExpiredHikeHistoryList extends StatefulWidget {
  const _ExpiredHikeHistoryList({required this.loader});
  final ExpiredHikesPageLoader loader;
  @override
  State<_ExpiredHikeHistoryList> createState() =>
      _ExpiredHikeHistoryListState();
}

class _ExpiredHikeHistoryListState extends State<_ExpiredHikeHistoryList> {
  List<UpcomingHike> _hikes = [];
  ExpiredHikesCursor? _cursor;
  bool _isLoading = true;
  bool _isFromCache = false;
  Object? _error;
  int _loadGeneration = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_load(refresh: true));
  }

  Future<void> _load({bool refresh = false}) async {
    if (!refresh && (_isLoading || _cursor == null)) return;
    final generation = ++_loadGeneration;
    final requested = refresh ? null : _cursor;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final page = await widget.loader(requested);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        final byId = <String, UpcomingHike>{
          if (!refresh)
            for (final hike in _hikes) hike.id: hike,
        };
        for (final hike in page.hikes) {
          byId[hike.id] = hike;
        }
        _hikes = byId.values.toList();
        final next = page.nextCursor;
        _cursor =
            next != null &&
                next.hikeId == requested?.hikeId &&
                next.departureTimeLocal == requested?.departureTimeLocal
            ? null
            : next;
        _isFromCache = page.isFromCache;
      });
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _hikes.isEmpty) {
      return const HikerCircleLoadingView(
        message: 'Loading expired plans…',
        detail: 'Getting your past scheduled hikes.',
        compact: true,
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
    if (_hikes.isEmpty) {
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
          Text(
            'Past scheduled hikes that were never started.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (_isFromCache)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Saved on this phone · Refresh when connected'),
            ),
          const SizedBox(height: 16),
          for (final hike in _hikes)
            Card(
              child: ListTile(
                key: Key('expired-hike-${hike.id}'),
                leading: const Icon(Icons.event_busy_rounded),
                title: Text(
                  hike.trailName.isEmpty ? 'Scheduled hike' : hike.trailName,
                ),
                subtitle: Text(
                  '${_expiredDate(hike.departureTime)} · ${hike.hikeType == 'team' ? 'Team' : 'Solo'} plan',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ExpiredHikeDetailPage(hike: hike),
                  ),
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Older plans could not be loaded. Try again when connected.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
}

String _expiredDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class ExpiredHikeDetailPage extends StatelessWidget {
  const ExpiredHikeDetailPage({super.key, required this.hike});
  final UpcomingHike hike;

  @override
  Widget build(BuildContext context) {
    final draft = hike.draft;
    return Scaffold(
      appBar: PageHeaderAppBar(title: const Text('Expired hike plan')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            hike.trailName.isEmpty ? 'Scheduled hike' : hike.trailName,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'This scheduled hike was never started. Its original plan is kept here for reference.',
          ),
          const SizedBox(height: 20),
          _planRow('Planned departure', _expiredDate(hike.departureTime)),
          _planRow('Expected return', _expiredDate(hike.expectedReturnTime)),
          _planRow('Hike type', hike.hikeType == 'team' ? 'Team' : 'Solo'),
          if (hike.creatorName.isNotEmpty)
            _planRow('Organizer', hike.creatorName),
          _planRow('Planned participants', '${hike.participantCount}'),
          if (hike.area.isNotEmpty)
            _planRow(
              'Area',
              [
                hike.area,
                hike.state,
                hike.country,
              ].where((part) => part.isNotEmpty).join(', '),
            ),
          _planRow(
            'Planned distance',
            '${hike.distanceKm.toStringAsFixed(1)} km',
          ),
          _planRow('Estimated duration', '${hike.durationMinutes} min'),
          if (hike.difficulty.isNotEmpty)
            _planRow('Difficulty', hike.difficulty),
          if (hike.startPointName.isNotEmpty)
            _planRow('Start', hike.startPointName),
          if (hike.destinationName.isNotEmpty)
            _planRow('Destination', hike.destinationName),
          if (draft != null) ...[
            const Divider(height: 32),
            Text(
              'Planned safety settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            _planRow(
              'Fall detection',
              draft.fallDetectionEnabled ? 'Enabled' : 'Disabled',
            ),
            _planRow(
              'Live location sharing',
              draft.shareLiveLocation ? 'Enabled' : 'Disabled',
            ),
            _planRow(
              'Check-in interval',
              '${draft.safetyCheckInInterval.inMinutes} min',
            ),
            const Divider(height: 32),
            Text(
              'Planned checkpoints',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final checkpoint in draft.effectiveCheckpoints)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined),
                title: Text(checkpoint.name),
              ),
          ],
        ],
      ),
    );
  }

  Widget _planRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value),
      ],
    ),
  );
}

class HikeHistoryDetailPage extends StatefulWidget {
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
}

class _HikeHistoryDetailBody extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
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

class _HistoryAnalysisTab extends StatelessWidget {
  const _HistoryAnalysisTab({required this.detail, required this.onRefresh});

  final HikeHistoryDetail detail;
  final Future<void> Function() onRefresh;

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

class _PaceChart extends StatelessWidget {
  const _PaceChart({required this.samples});

  final List<HikePaceSample> samples;

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

class _CheckpointAnalysisRow extends StatelessWidget {
  const _CheckpointAnalysisRow({required this.checkpoint, required this.index});

  final HikeCheckpointAnalysis checkpoint;
  final int index;

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

class _AnalysisChip extends StatelessWidget {
  const _AnalysisChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

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

class _HistorySafetyTab extends StatelessWidget {
  const _HistorySafetyTab({required this.detail, required this.onRefresh});

  final HikeHistoryDetail detail;
  final Future<void> Function() onRefresh;

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
            _RowData('Pinned locations', '${detail.manualPins.length}'),
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
        if (detail.manualPins.isNotEmpty)
          _DetailSection(
            title: 'Pinned locations',
            icon: Icons.location_pin,
            rows: const [],
            child: Column(
              children: [
                for (var index = 0; index < detail.manualPins.length; index++)
                  _EventLine(
                    icon: Icons.push_pin_rounded,
                    title: 'Pin ${index + 1}',
                    subtitle:
                        '${_formatDateTime(detail.manualPins[index].pinnedAt)} · ${_coordinateLabel(detail.manualPins[index].coordinate)}',
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _HistoryTeamTab extends StatefulWidget {
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

  @override
  State<_HistoryTeamTab> createState() => _HistoryTeamTabState();
}

class _HistoryTeamTabState extends State<_HistoryTeamTab> {
  bool _openingChat = false;

  Future<void> _openChat() async {
    final repository = widget.repository;
    final session = widget.session;
    if (repository == null || session == null || _openingChat) return;
    setState(() => _openingChat = true);
    try {
      final chat = await repository.loadGroupChatById(
        widget.detail.groupChatId,
      );
      if (!mounted) return;
      if (chat == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This hike chat is no longer available.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => GroupChatDetailPage(
            chat: chat,
            session: session,
            repository: repository,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

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
}

class _TeamRouteReplay extends StatefulWidget {
  const _TeamRouteReplay({required this.tracks});

  final List<HikeHistoryMemberTrack> tracks;

  @override
  State<_TeamRouteReplay> createState() => _TeamRouteReplayState();
}

class _TeamRouteReplayState extends State<_TeamRouteReplay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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

class _TeamReplayPainter extends CustomPainter {
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

  @override
  bool shouldRepaint(covariant _TeamReplayPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.tracks != tracks;
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
  const _RecordedRouteCard({
    required this.detail,
    required this.enableInteractiveRoute,
  });
  final HikeHistoryDetail detail;
  final bool enableInteractiveRoute;

  @override
  Widget build(BuildContext context) {
    final points = detail.routePoints;
    final trail = _trailForHistory(detail);
    final route = _routeForHistory(detail);
    final pins = detail.manualPins
        .map(
          (pin) => mapbox.Point(
            coordinates: mapbox.Position(
              pin.coordinate.longitude,
              pin.coordinate.latitude,
            ),
          ),
        )
        .toList();
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
        height: 260,
        color: const Color(0xFF10271A),
        child: Stack(
          children: [
            Positioned.fill(
              child: points.length >= 2 && enableInteractiveRoute
                  ? RoutePreviewMap(
                      key: const Key('hike-history-actual-route-map'),
                      trail: trail,
                      route: route,
                      customCheckpoints: trail.checkpoints,
                      pinnedPoints: pins,
                      checkInPoints: checkIns,
                      animateRoute: kReleaseMode,
                      animationDuration: const Duration(seconds: 10),
                      captureAllGestures: true,
                    )
                  : CustomPaint(
                      painter: _RouteTracePainter(
                        points: points,
                        pins: detail.manualPins,
                        checkIns: detail.checkInRecords,
                      ),
                    ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        const Color(0xB510271A),
                      ],
                    ),
                  ),
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

class _HistoryImageFallback extends StatelessWidget {
  const _HistoryImageFallback();

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

HikingRouteResult? _routeForHistory(HikeHistoryDetail detail) {
  final points =
      detail.routePoints.where((point) => point.hasValidPosition).toList()
        ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
  if (points.length < 2) return null;
  final encoded = PolylineCodec.encode(
    points.map((point) => LatLng(point.latitude, point.longitude)).toList(),
  );
  if (encoded.isEmpty) return null;
  return HikingRouteResult(
    distanceMeters: (detail.summary.distanceKm * 1000).round(),
    duration: detail.summary.duration,
    encodedPolyline: encoded,
    elevationGainMeters: detail.elevationGainMeters.toDouble(),
    sourceLabel: 'Recorded GPS route',
  );
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
String _titleCaseWords(String value) => value
    .trim()
    .split(RegExp(r'\s+'))
    .where((word) => word.isNotEmpty)
    .map((word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
    .join(' ');
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

import 'hike_departure_countdown.dart';
import 'hiking_forecast_sheet.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../trail/Model/trail_models.dart';
import '../Data/hike_briefing_weather_service.dart';
import '../Model/hike_session_models.dart';
import '../Model/hike_weather_briefing.dart';

/// The nearest scheduled hike; countdown is local, weather is at the trail.
class NextHikeBriefing extends StatefulWidget {
  const NextHikeBriefing({
    super.key,
    required this.hike,
    required this.phoneNumber,
    this.plannedHike,
    this.trail,
    this.onReview,
    this.isVisible = true,
    this.weatherService,
  });
  final UpcomingHike hike;
  final String phoneNumber;
  final PlannedHike? plannedHike;
  final Trail? trail;
  final VoidCallback? onReview;
  final bool isVisible;
  final HikeBriefingWeatherService? weatherService;

  @override
  State<NextHikeBriefing> createState() => _NextHikeBriefingState();
}

class _NextHikeBriefingState extends State<NextHikeBriefing>
    with WidgetsBindingObserver {
  Timer? _timer;
  TrailWeather? _weather;
  bool _loading = false;
  bool _failed = false;
  bool _foreground = true;
  DateTime? _retryAt;
  int _generation = 0;
  HikeBriefingWeatherService get _service =>
      widget.weatherService ?? HikeBriefingWeatherService.shared;
  bool get _beyondForecast =>
      widget.hike.departureTime.toUtc().difference(DateTime.now().toUtc()) >=
      const Duration(days: 7);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _seed();
    _tick();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  void _seed() {
    final weather = widget.trail?.weather;
    // Old summary-only caches cannot describe a future hiking window.
    if (weather != null &&
        weather.forecastData['hourly'] is Map &&
        weather.forecastData['utc_offset_seconds'] is num) {
      _weather = weather;
    }
  }

  @override
  void didUpdateWidget(covariant NextHikeBriefing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hike.id != widget.hike.id ||
        oldWidget.hike.latitude != widget.hike.latitude ||
        oldWidget.hike.longitude != widget.hike.longitude ||
        oldWidget.hike.departureTime != widget.hike.departureTime ||
        oldWidget.hike.expectedReturnTime != widget.hike.expectedReturnTime) {
      _generation++;
      _loading = false;
      _failed = false;
      _weather = null;
      _retryAt = null;
      _seed();
    }
    _tick();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _tick();
  }

  void _tick() {
    if (!mounted || !widget.isVisible || !_foreground) return;
    setState(() {});
    if (_loading ||
        _beyondForecast ||
        (_retryAt?.isAfter(DateTime.now()) ?? false)) {
      return;
    }
    final weather = _weather;
    final covered =
        weather != null &&
        HikeWeatherBriefing.fromWeather(
          weather,
          widget.hike.departureTime,
          widget.hike.expectedReturnTime,
        ).covered;
    if (weather == null || weather.isStale || !covered) unawaited(_load());
  }

  Future<void> _load({bool force = false}) async {
    if (_loading) return;
    final generation = _generation;
    setState(() {
      _loading = true;
    });
    try {
      final weather = await _service.fetch(
        widget.hike.latitude,
        widget.hike.longitude,
        force: force,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _weather = weather;
        _failed = false;
        _retryAt = DateTime.now().add(HikeBriefingWeatherService.freshness);
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _retryAt = DateTime.now().add(const Duration(minutes: 15));
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hike = widget.hike;
    final plan = widget.plannedHike?.withGearProgress();
    return Container(
      key: const ValueKey('next-hike-briefing'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.hiking_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                'NEXT HIKE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hike.hikeType == 'team' ? 'Group hike' : 'Solo hike',
                  textAlign: TextAlign.end,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: scheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            hike.trailName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            _dateTime(hike.departureTime).split(' · ').first,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _scheduleTime(
                  context,
                  'Departure',
                  _clockTime(hike.departureTime),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Icons.arrow_forward_rounded, size: 18),
              ),
              Expanded(
                child: _scheduleTime(
                  context,
                  'Estimated finish',
                  _returnTime(hike.departureTime, hike.expectedReturnTime),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${hike.distanceKm.toStringAsFixed(1)} km · ${(widget.trail ?? plan?.trail)?.difficultyDisplayLabel ?? 'Difficulty not rated'}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          HikeDepartureCountdown(
            departure: hike.departureTime,
            enabled: widget.isVisible,
          ),
          const SizedBox(height: 14),
          _buildWeather(context),
          const SizedBox(height: 10),
          _BriefingAction(
            title: 'Final preparation review',
            onTap: widget.onReview,
            leading: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: plan == null || plan.checklistTotal == 0
                        ? 0
                        : plan.checklistCompleted / plan.checklistTotal,
                    strokeWidth: 3,
                    backgroundColor: scheme.outlineVariant,
                  ),
                ),
                Icon(Icons.backpack_outlined, size: 20, color: scheme.primary),
              ],
            ),
            subtitle: Text(
              plan == null
                  ? 'Build your trail-specific packing list'
                  : '${plan.checklistCompleted}/${plan.checklistTotal} packed · gear & safety',
            ),
          ),
        ],
      ),
    );
  }

  String _clockTime(DateTime value) {
    final date = value.toLocal();
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _scheduleTime(BuildContext context, String label, String value) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 3),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      );

  Widget _buildWeather(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final weather = _weather;
    final briefing = weather == null
        ? null
        : HikeWeatherBriefing.fromWeather(
            weather,
            widget.hike.departureTime,
            widget.hike.expectedReturnTime,
          );
    final available = briefing?.covered == true;
    final message = _beyondForecast
        ? 'Forecast available closer to departure'
        : _loading
        ? 'Checking hike weather…'
        : _failed
        ? 'Couldn’t refresh weather. Retry.'
        : 'Forecast does not cover this hike yet';
    return _BriefingAction(
      title: 'Hike weather',
      onTap: available
          ? () => _showForecast(context, briefing!, weather!)
          : !_loading && !_beyondForecast
          ? () => _load(force: true)
          : null,
      leading: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outlineVariant, width: 3),
        ),
        child: Icon(Icons.cloud_outlined, size: 20, color: scheme.primary),
      ),
      subtitle: available
          ? Wrap(
              spacing: 6,
              runSpacing: 3,
              children: [
                Text(
                  briefing!.minTemperature == null
                      ? 'Temperature unavailable'
                      : '${briefing.minTemperature!.round()}–${briefing.maxTemperature!.round()}°C',
                ),
                const Text('·'),
                Text(
                  briefing.peakRainChance == null
                      ? 'Rain unavailable'
                      : '${briefing.peakRainChance!.round()}% peak chance',
                ),
                if (weather!.isStale)
                  Text('Outdated', style: TextStyle(color: scheme.error)),
              ],
            )
          : Text(message),
      trailing: _loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : !available && !_beyondForecast
          ? Tooltip(
              message: 'Refresh hike weather',
              child: Icon(Icons.refresh_rounded, color: scheme.primary),
            )
          : null,
    );
  }

  void _showForecast(
    BuildContext context,
    HikeWeatherBriefing briefing,
    TrailWeather weather,
  ) {
    final hikeId = widget.hike.id;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => HikingForecastSheet(
        hike: widget.hike,
        weather: weather,
        service: _service,
        onWeatherChanged: (updated) {
          if (!mounted || widget.hike.id != hikeId) return;
          setState(() {
            _weather = updated;
            _failed = false;
          });
        },
        elevationGain:
            (widget.trail ?? widget.plannedHike?.trail)?.elevationGainMeters ??
            0,
      ),
    );
  }
}

/// Shared geometry keeps forecast and preparation equally prominent.
class _BriefingAction extends StatelessWidget {
  const _BriefingAction({
    required this.title,
    required this.leading,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });
  final String title;
  final Widget leading, subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 78),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                SizedBox(width: 38, height: 38, child: leading),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      DefaultTextStyle(
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        child: subtitle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Center(
                    child:
                        trailing ??
                        Icon(
                          Icons.chevron_right_rounded,
                          color: onTap == null
                              ? scheme.outline
                              : scheme.primary,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _returnTime(DateTime start, DateTime end) {
  final a = start.toLocal(), b = end.toLocal();
  return a.year == b.year && a.month == b.month && a.day == b.day
      ? _clock(b)
      : _dateTime(end);
}

String _clock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
String _dateTime(DateTime time, {bool convertLocal = true}) {
  final local = convertLocal ? time.toLocal() : time;
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
  return '${local.day} ${months[local.month - 1]} · ${_clock(local)}';
}

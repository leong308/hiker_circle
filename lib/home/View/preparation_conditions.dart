import 'package:flutter/material.dart';
import '../../trail/Model/trail_models.dart';
import '../../trail/View/weather_presentation.dart';
import '../Model/hike_weather_briefing.dart';
import '../Model/route_gear_assessment.dart';

/// Shows conditions now separately from the forecast for a future hike.
class PreparationConditions extends StatelessWidget {
  const PreparationConditions({
    super.key,
    required this.weather,
    required this.departure,
    required this.returning,
    this.assessment,
    this.now,
  });
  final TrailWeather weather;
  final DateTime departure, returning;
  final DateTime? now;
  final RouteGearAssessment? assessment;

  double? _number(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : null;
  String _reading(double? value, String unit) =>
      value == null ? 'Unavailable' : '${value.toStringAsFixed(1)}$unit';

  @override
  Widget build(BuildContext context) {
    final currentTime = (now ?? DateTime.now()).toUtc();
    final raw = weather.forecastData['current'];
    final current = raw is Map ? raw : const {};
    final seconds = _number(current['time']);
    final observedAt = seconds != null && seconds >= 0 && seconds < 253402300800
        ? DateTime.fromMillisecondsSinceEpoch(
            (seconds * 1000).round(),
            isUtc: true,
          )
        : null;
    final recent =
        observedAt != null &&
        currentTime.difference(observedAt) <= const Duration(hours: 1) &&
        !observedAt.isAfter(currentTime.add(const Duration(minutes: 5)));
    final hourly = HikeWeatherBriefing.fromWeather(
      weather,
      currentTime,
      currentTime.add(const Duration(milliseconds: 1)),
    ).hours.firstOrNull;
    double? value(String key) =>
        recent ? _number(current[key]) : hourly?.value(key);
    final session = HikeWeatherBriefing.fromWeather(
      weather,
      departure,
      returning,
    );
    final theme = Theme.of(context);
    final terrain = assessment?.usable == true ? assessment : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          recent
              ? 'Current conditions at the trail'
              : 'Hourly forecast for now',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        if (!recent && hourly == null)
          const Text(
            'Current conditions are unavailable. Refresh or check local conditions.',
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              weatherMetric(
                context,
                forecastWeatherIcon(value('weather_code')),
                'Temperature',
                _reading(value('temperature_2m'), '°C'),
              ),
              weatherMetric(
                context,
                Icons.thermostat_outlined,
                'Feels like',
                _reading(value('apparent_temperature'), '°C'),
              ),
              weatherMetric(
                context,
                Icons.air,
                'Wind',
                _reading(value('wind_speed_10m'), ' km/h'),
              ),
              weatherMetric(
                context,
                Icons.water_drop_outlined,
                'Rainfall',
                _reading(value('precipitation'), ' mm'),
              ),
              weatherMetric(
                context,
                Icons.water_outlined,
                'Humidity',
                _reading(value('relative_humidity_2m'), '%'),
              ),
            ],
          ),
        const SizedBox(height: 8),
        Text(
          '${weather.isStale ? 'Saved data' : 'Updated'} · ${_time(weather.cachedAt)}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        Text('During your hike', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            weatherMetric(
              context,
              Icons.thermostat_outlined,
              'Temperature range',
              session.minTemperature == null || session.maxTemperature == null
                  ? 'Unavailable'
                  : '${session.minTemperature!.toStringAsFixed(1)}–${session.maxTemperature!.toStringAsFixed(1)}°C',
            ),
            weatherMetric(
              context,
              Icons.umbrella_outlined,
              'Peak rain chance',
              session.peakRainChance == null
                  ? 'Unavailable'
                  : '${session.peakRainChance!.round()}%',
            ),
          ],
        ),
        if (!session.covered) ...[
          const SizedBox(height: 8),
          const Text('The forecast does not cover the whole planned hike.'),
        ],
        const SizedBox(height: 20),
        Text('Route findings', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (terrain == null)
          const Text(
            'Route conditions are unavailable. Check the terrain at the trail.',
          )
        else ...[
          if (terrain.rough) const Text('• Uneven ground'),
          if (terrain.technical) const Text('• Technical terrain'),
          if (terrain.muddy) const Text('• Mapped muddy ground'),
          if (terrain.possibleCrossing) const Text('• Possible river crossing'),
          if (terrain.waterNearby) const Text('• Water near the route'),
          if (!terrain.rough &&
              !terrain.technical &&
              !terrain.muddy &&
              !terrain.possibleCrossing &&
              !terrain.waterNearby)
            const Text(
              'No additional terrain flags were found in the available map data. This does not confirm that the route is clear.',
            ),
          if (!terrain.isFresh || terrain.status == 'partial') ...[
            const SizedBox(height: 8),
            Text(
              !terrain.isFresh
                  ? 'These route findings are saved and may be out of date.'
                  : 'Only part of the route could be assessed.',
            ),
          ],
        ],
      ],
    );
  }

  String _time(DateTime date) {
    final offset =
        _number(weather.forecastData['utc_offset_seconds'])?.toInt() ?? 0;
    final local = date.toUtc().add(Duration(seconds: offset));
    return '${local.day}/${local.month} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} (trail time)';
  }
}

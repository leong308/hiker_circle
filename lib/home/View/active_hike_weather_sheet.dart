import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/loading_toast.dart';
import '../Data/active_hike_weather_controller.dart';
import '../Data/active_hike_weather_service.dart';

class ActiveHikeWeatherSheet extends StatelessWidget {
  const ActiveHikeWeatherSheet({
    super.key,
    this.locationOnly = false,
    required this.weatherState,
    required this.onRetry,
  });

  final ValueListenable<ActiveHikeWeatherViewState> weatherState;
  final bool locationOnly;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ValueListenableBuilder<ActiveHikeWeatherViewState>(
        valueListenable: weatherState,
        builder: (context, state, _) {
          final snapshot = state.snapshot;
          final samples =
              snapshot?.samples ?? const <ActiveHikeWeatherSample>[];
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  locationOnly
                      ? 'Weather at your location'
                      : 'Weather along your hike',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  snapshot == null
                      ? (locationOnly
                            ? 'Only your current position is sampled; the route ahead is unknown.'
                            : 'Checking your location and the trail ahead.')
                      : 'Refreshes every 15 minutes · Open-Meteo',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (samples.isEmpty && state.isLoading)
                  HikerCircleLoadingView(
                    message: 'Checking hike weather…',
                    detail: locationOnly
                        ? 'Loading conditions at your current location.'
                        : 'Loading conditions along the trail ahead.',
                    compact: true,
                    padding: EdgeInsets.symmetric(vertical: 16),
                  )
                else if (samples.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Text(
                          'Weather is temporarily unavailable.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed:
                              state.nextRefreshAt == null ||
                                  !DateTime.now().isBefore(state.nextRefreshAt!)
                              ? onRetry
                              : null,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retry'),
                        ),
                        if (state.nextRefreshAt != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Next refresh at ${activeWeatherTimeLabel(state.nextRefreshAt!)}',
                          ),
                        ],
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < samples.length;
                            index++
                          ) ...[
                            if (index > 0) const SizedBox(height: 10),
                            _ActiveHikeWeatherCard(sample: samples[index]),
                          ],
                          if (state.error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Latest refresh failed. Showing the previous update.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ],
                          if (state.isLoading) ...[
                            const SizedBox(height: 12),
                            const LinearProgressIndicator(),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (snapshot != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Last updated ${snapshot.fetchedAt.toLocal().day}/${snapshot.fetchedAt.toLocal().month} · ${activeWeatherTimeLabel(snapshot.fetchedAt)}',
                    key: const ValueKey('active-hike-weather-last-updated'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ActiveHikeWeatherCard extends StatelessWidget {
  const _ActiveHikeWeatherCard({required this.sample});

  final ActiveHikeWeatherSample sample;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                activeWeatherIconForCode(sample.weatherCode),
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sample.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    sample.summary,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Feels ${sample.apparentTemperatureCelsius.round()}° · '
                    '${sample.humidityPercent}% humidity · '
                    '${sample.windSpeedKph.toStringAsFixed(1)} km/h wind',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${sample.temperatureCelsius.round()}°',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

IconData activeWeatherIconForCode(int? code) {
  if (code == null) {
    return Icons.cloud_sync_rounded;
  }
  if (code == 0 || code == 1) {
    return Icons.wb_sunny_rounded;
  }
  if (code == 2 || code == 3) {
    return Icons.cloud_rounded;
  }
  if (code == 45 || code == 48) {
    return Icons.foggy;
  }
  if (code >= 95) {
    return Icons.thunderstorm_rounded;
  }
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
    return Icons.water_drop_rounded;
  }
  if ((code >= 71 && code <= 77) || code >= 85) {
    return Icons.ac_unit_rounded;
  }
  return Icons.cloud_rounded;
}

String activeWeatherTimeLabel(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

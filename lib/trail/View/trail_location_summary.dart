import 'package:flutter/material.dart';

import '../../core/widgets/loading_toast.dart';

/// Displays the trail location summary.
class TrailLocationSummary extends StatelessWidget {
  /// Creates trail location summary.
  const TrailLocationSummary({
    super.key,
    required this.area,
    required this.state,
    required this.country,
    required this.isLoading,
    required this.hasError,
    required this.onRetry,
  });

  final String area;
  final String state;
  final String country;
  final bool isLoading;
  final bool hasError;
  final VoidCallback onRetry;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final location = [area, state, country]
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(', ');
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 36,
                child: isLoading
                    ? const Center(
                        child: HikerCircleMinorLoadingIndicator(size: 22),
                      )
                    : Icon(
                        Icons.location_on_outlined,
                        color: hasError ? colors.error : colors.primary,
                        size: 25,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Location',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isLoading
                          ? 'Finding location…'
                          : hasError || location.isEmpty
                          ? 'Location unavailable'
                          : location,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasError && !isLoading) ...[
                const SizedBox(width: 8),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ],
          ),
          if (hasError && !isLoading) ...[
            const SizedBox(height: 8),
            Text(
              'Retry or choose another starting point to find the location.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

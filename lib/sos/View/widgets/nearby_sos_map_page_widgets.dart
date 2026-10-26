part of '../../nearby_sos_map_page_feature.dart';

/// Displays the nearby map header.
class _NearbyMapHeader extends StatelessWidget {
  /// Creates nearby map header.
  const _NearbyMapHeader({required this.onBack});

  final VoidCallback onBack;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) =>
      PageHeader(title: 'Nearby SOS route', onBack: onBack);
}

/// Displays the walking route status card.
class _WalkingRouteStatusCard extends StatelessWidget {
  /// Creates walking route status card.
  const _WalkingRouteStatusCard({
    required this.route,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
  });

  final HikingRouteResult? route;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final route = this.route;
    return _NearbySurface(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            const Icon(
              Icons.directions_walk_rounded,
              color: Color(0xFF34A853),
              size: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route != null ? 'Walking route ready' : 'Walking route',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: _NearbyMapColors.textFor(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    route != null
                        ? '${route.distanceLabel} • about ${route.durationLabel}'
                        : isLoading
                        ? 'Calculating distance and estimated time…'
                        : errorMessage ?? 'Waiting for current phone location…',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _NearbyMapColors.secondaryFor(context),
                    ),
                  ),
                ],
              ),
            ),
            if (isLoading)
              const SizedBox.square(
                dimension: 20,
                child: HikerCircleMinorLoadingIndicator(strokeWidth: 2),
              )
            else if (errorMessage != null)
              IconButton(
                tooltip: 'Retry walking route',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

/// Displays the radius explanation card.
class _RadiusExplanationCard extends StatelessWidget {
  /// Creates radius explanation card.
  const _RadiusExplanationCard();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _NearbySurface(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFF0A84FF)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'The button did not provide a GPS location, so an exact '
                'direction or walking route cannot be calculated. The blue '
                'area shows the estimated reception radius.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _NearbyMapColors.textFor(context),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

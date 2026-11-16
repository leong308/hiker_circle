part of '../../location_sharing_page_feature.dart';

/// Displays the header.
class _Header extends StatelessWidget {
  /// Creates header.
  const _Header({required this.onBack});

  final VoidCallback onBack;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
    child: PageHeader(title: 'Live Location', onBack: onBack),
  );
}

/// Displays the map panel.
class _MapPanel extends StatelessWidget {
  /// Creates map panel.
  const _MapPanel({
    required this.location,
    required this.isLoading,
    required this.errorMessage,
  });

  final SosTriggerLocation? location;
  final bool isLoading;
  final String? errorMessage;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(color: _LocationColors.surfaceFor(context)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (location case final location?)
              _LiveLocationMap(location: location)
            else
              ColoredBox(color: _LocationColors.mapFallbackFor(context)),
            if (location == null) const Center(child: _MapPin()),
            if (isLoading)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: const Center(
                  child: HikerCircleMinorLoadingIndicator(size: 24),
                ),
              ),
            if (errorMessage case final errorMessage?)
              Align(
                alignment: Alignment.bottomCenter,
                child: _MapMessage(message: errorMessage),
              ),
          ],
        ),
      ),
    );
  }
}

part of '../../final_preparation_review_page_feature.dart';

/// Displays the shirt color advice card.
class _ShirtColorAdviceCard extends StatelessWidget {
  /// Creates shirt color advice card.
  const _ShirtColorAdviceCard({required this.advice});

  final HikeShirtColorAdvice advice;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final (accent, background, icon) = switch (advice.tone) {
      HikeShirtColorSuitability.recommended => (
        scheme.primary,
        scheme.primaryContainer.withValues(alpha: .62),
        Icons.thumb_up_alt_outlined,
      ),
      HikeShirtColorSuitability.visible => (
        scheme.tertiary,
        scheme.tertiaryContainer.withValues(alpha: .62),
        Icons.visibility_outlined,
      ),
      HikeShirtColorSuitability.avoidInDaylight => (
        scheme.error,
        scheme.errorContainer.withValues(alpha: .62),
        Icons.warning_amber_rounded,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: .55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  advice.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(advice.summary),
          const SizedBox(height: 10),
          for (final point in advice.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(child: Text(point)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

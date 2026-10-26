part of '../../trail_precaution_card_feature.dart';

/// Displays the trail precaution card.
class TrailPrecautionCard extends StatefulWidget {
  /// Creates trail precaution card.
  const TrailPrecautionCard({
    super.key,
    required this.caution,
    this.title,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
  });
  final TrailPrecaution caution;
  final String? title;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  /// Creates the presentation state for this widget.
  @override
  State<TrailPrecautionCard> createState() => _TrailPrecautionCardState();
}

/// Manages the trail precaution card presentation and lifecycle.
class _TrailPrecautionCardState extends State<TrailPrecautionCard> {
  late bool _expanded = widget.initiallyExpanded;

  /// Toggles.
  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onExpansionChanged?.call(_expanded);
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final caution = widget.caution;
    final title = widget.title ?? caution.title;
    final accent = precautionAccentColor(context, caution.priority);
    final action = caution.quickAction?.trim();
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final details = _expanded
        ? Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Divider(height: 1, color: colors.outlineVariant),
                const SizedBox(height: 12),
                Text(
                  caution.priority >= 3
                      ? 'Important'
                      : caution.priority == 2
                      ? 'Caution'
                      : 'Prepare',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (caution.quickFacts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final fact in caution.quickFacts)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            fact,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (action != null &&
                    action.isNotEmpty &&
                    action != caution.message.trim()) ...[
                  const SizedBox(height: 10),
                  Text(
                    action,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ],
                if (title != caution.title) ...[
                  const SizedBox(height: 12),
                  Text(
                    caution.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  caution.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          )
        : const SizedBox(width: double.infinity);
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withValues(alpha: .18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: _expanded,
            child: InkWell(
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: CautionIcon(
                        icon: precautionIcon(caution),
                        seriousRisk: caution.priority >= 3,
                        color: accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: _expanded
                          ? 'Collapse details'
                          : 'Expand details',
                      child: AnimatedRotation(
                        turns: _expanded ? .5 : 0,
                        duration: duration,
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 22,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (duration == Duration.zero)
            details
          else
            AnimatedSize(
              duration: duration,
              alignment: Alignment.topCenter,
              curve: Curves.easeInOutCubic,
              child: details,
            ),
        ],
      ),
    );
  }
}

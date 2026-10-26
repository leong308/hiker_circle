part of '../../trail_caution_details_feature.dart';

/// Displays the trail caution history card.
class TrailCautionHistoryCard extends StatefulWidget {
  /// Creates trail caution history card.
  const TrailCautionHistoryCard({
    super.key,
    required this.report,
    required this.active,
    required this.archived,
  });
  final CommunityHazard report;
  final bool active, archived;

  /// Creates the presentation state for this widget.
  @override
  State<TrailCautionHistoryCard> createState() =>
      _TrailCautionHistoryCardState();
}

/// Manages the trail caution history card presentation and lifecycle.
class _TrailCautionHistoryCardState extends State<TrailCautionHistoryCard>
    with SingleTickerProviderStateMixin {
  late final pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  /// Synchronizes pulse.
  void syncPulse() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!pulse.isAnimating) pulse.repeat(reverse: true);
    } else {
      pulse.stop();
      pulse.value = 0;
    }
  }

  /// Refreshes presentation dependencies.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncPulse();
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant TrailCautionHistoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncPulse();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final report = widget.report;
    final radius = BorderRadius.circular(18);
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final glow = Curves.easeInOut.transform(pulse.value);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: widget.active
                ? Color.alphaBlend(
                    colors.error.withValues(alpha: .04 + glow * .05),
                    colors.surfaceContainerLow,
                  )
                : colors.surfaceContainerLow,
            border: Border.all(
              color: widget.active
                  ? colors.error.withValues(alpha: .25 + glow * .3)
                  : colors.outlineVariant.withValues(alpha: .5),
            ),
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: colors.error.withValues(alpha: .06 + glow * .13),
                      blurRadius: 8 + glow * 10,
                      spreadRadius: glow * 1.5,
                    ),
                  ]
                : const [],
          ),
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          leading: CautionIcon(
            icon: report.isResolved
                ? Icons.check_circle_outline_rounded
                : trailHazardIconFor(report.type),
            seriousRisk: widget.active && report.isFatal,
            color: widget.active ? colors.error : colors.onSurfaceVariant,
          ),
          title: Text(
            report.type,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${widget.archived
                ? 'Archived'
                : report.isResolved
                ? 'Resolved'
                : 'Active'} · '
            '${report.reportCount} report${report.reportCount == 1 ? '' : 's'}'
            '${report.reportedAt == null ? '' : '\n${cautionDate(report.reportedAt!)}'}',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => showCommunityHazardDetails(
            context,
            CommunityHazardCluster([report]),
          ),
        ),
      ),
    );
  }
}

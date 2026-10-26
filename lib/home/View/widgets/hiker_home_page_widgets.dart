part of '../../hiker_home_page_feature.dart';

/// Displays the locked team safety row.
class _LockedTeamSafetyRow extends StatelessWidget {
  /// Creates locked team safety row.
  const _LockedTeamSafetyRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final colors = _SafetyTheme.of(context);
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.lock_rounded, color: colors.green),
      title: Text(
        title,
        style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.secondaryText,
          letterSpacing: 0,
        ),
      ),
      trailing: Icon(icon, color: colors.green),
    );
  }
}

/// Displays the ready launch button.
class _ReadyLaunchButton extends StatelessWidget {
  /// Creates ready launch button.
  const _ReadyLaunchButton({
    required this.label,
    required this.subtitle,
    required this.enabled,
    required this.busy,
    required this.onPressed,
    this.countdown,
  });

  final String label;
  final String subtitle;
  final bool enabled;
  final bool busy;
  final int? countdown;
  final VoidCallback onPressed;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final countdownValue = countdown;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: enabled ? onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 112,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled
                ? Colors.white
                : Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.36)),
          ),
          child: busy
              ? const SizedBox.square(
                  dimension: 28,
                  child: HikerCircleMinorLoadingIndicator(strokeWidth: 3),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      countdownValue == null ? label : '$countdownValue',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: enabled
                            ? const Color(0xFF0F5132)
                            : Colors.white.withValues(alpha: 0.76),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    Text(
                      countdownValue == null ? subtitle : label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: enabled
                            ? const Color(0xFF0F5132)
                            : Colors.white.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Displays the team launch status card.
class _TeamLaunchStatusCard extends StatelessWidget {
  /// Creates team launch status card.
  const _TeamLaunchStatusCard({
    required this.teamSession,
    required this.currentPhoneNumber,
    this.onRemovePendingInvitees,
  });

  final TeamHikeSession teamSession;
  final String currentPhoneNumber;
  final VoidCallback? onRemovePendingInvitees;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF10291B),
            const Color(0xFF07140D).withValues(alpha: 0.96),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF7EE0A0).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Text(
            'TEAM ASSEMBLY',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF7EE0A0),
              fontWeight: FontWeight.w900,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${teamSession.readyCount} / ${teamSession.participants.length} READY',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  (constraints.maxWidth -
                      (teamSession.participants.length > 3 ? 24 : 16)) /
                  (teamSession.participants.length > 3 ? 3 : 2);
              return Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 18,
                children: [
                  for (final participant in teamSession.participants)
                    SizedBox(
                      width: width.clamp(92, 132),
                      child: _TeamReadyPlayerSlot(
                        participant: participant,
                        isSelf: _sameTeamPhone(
                          participant.phoneNumber,
                          currentPhoneNumber,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  teamSession.everyoneReady
                      ? Icons.verified_rounded
                      : Icons.sync_rounded,
                  color: teamSession.everyoneReady
                      ? const Color(0xFF7EE0A0)
                      : Colors.white70,
                  size: 17,
                ),
                const SizedBox(width: 7),
                Text(
                  teamSession.everyoneReady
                      ? 'All safety checks complete'
                      : 'Waiting for safety checks',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (onRemovePendingInvitees != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRemovePendingInvitees,
              icon: const Icon(Icons.person_remove_alt_1_rounded),
              label: const Text('Continue without pending invitees'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFBBF24),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Displays the summary card.
class _SummaryCard extends StatelessWidget {
  /// Creates summary card.
  const _SummaryCard({required this.child});

  final Widget child;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(color: _SummaryColors.surfaceFor(context)),
        child: child,
      ),
    );
  }
}

/// Displays the summary event row.
class _SummaryEventRow extends StatelessWidget {
  /// Creates summary event row.
  const _SummaryEventRow({
    required this.icon,
    required this.label,
    required this.time,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String time;
  final String? subtitle;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0A84FF), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _SummaryColors.textFor(context),
                    letterSpacing: 0,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SummaryColors.secondaryTextFor(context),
                      fontSize: 11,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            time,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _SummaryColors.secondaryTextFor(context),
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the summary checkpoint performance row.
class _SummaryCheckpointPerformanceRow extends StatelessWidget {
  /// Creates summary checkpoint performance row.
  const _SummaryCheckpointPerformanceRow({required this.checkpoint});

  final HikeCheckpointAnalysis checkpoint;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    /// Computes clock.
    String clock(DateTime? value) {
      if (value == null) {
        return 'Not reached';
      }
      final local = value.toLocal();
      return '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}:'
          '${local.second.toString().padLeft(2, '0')}';
    }

    /// Computes elapsed.
    String elapsed(Duration? value) {
      if (value == null) {
        return 'Start';
      }
      final hours = value.inHours;
      final minutes = value.inMinutes.remainder(60);
      return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
    }

    return Padding(
      padding: const EdgeInsets.all(13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: checkpoint.reached
                  ? _SummaryColors.green
                  : _SummaryColors.secondaryTextFor(
                      context,
                    ).withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(
              checkpoint.reached
                  ? Icons.check_rounded
                  : Icons.horizontal_rule_rounded,
              color: checkpoint.reached
                  ? Colors.white
                  : _SummaryColors.secondaryTextFor(context),
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  checkpoint.name,
                  style: TextStyle(
                    color: _SummaryColors.textFor(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  checkpoint.reached
                      ? '${clock(checkpoint.reachedAt)} · ${elapsed(checkpoint.timeFromPrevious)} · ${checkpoint.distanceFromPreviousKm.toStringAsFixed(2)} km'
                      : 'No GPS sample within 100 m',
                  style: TextStyle(
                    color: _SummaryColors.secondaryTextFor(context),
                    fontSize: 11,
                  ),
                ),
                if (checkpoint.reached && checkpoint.paceMinutesPerKm > 0)
                  Text(
                    '${checkpoint.paceMinutesPerKm.toStringAsFixed(1)} min/km · ${checkpoint.speedKmh.toStringAsFixed(1)} km/h',
                    style: const TextStyle(
                      color: _SummaryColors.green,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the summary metric.
class _SummaryMetric extends StatelessWidget {
  /// Creates summary metric.
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _SummaryColors.textFor(context),
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _SummaryColors.secondaryTextFor(context),
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the insight row.
class _InsightRow extends StatelessWidget {
  /// Creates insight row.
  const _InsightRow({required this.text});

  final String text;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.auto_graph_rounded,
            color: _SummaryColors.green,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _SummaryColors.textFor(context),
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the metric chip.
class _MetricChip extends StatelessWidget {
  /// Creates metric chip.
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

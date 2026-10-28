part of '../../active_tracking_map_view_feature.dart';

/// Displays the active tracking legend.
class _ActiveTrackingLegend extends StatelessWidget {
  /// Creates active tracking legend.
  const _ActiveTrackingLegend({required this.selfColor, required this.isTeam});

  final Color? selfColor;
  final bool isTeam;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            const _LegendDot(color: Color(0xFF34A853), label: 'Recorded trail'),
            const _LegendDot(color: Color(0xFF0A84FF), label: 'Latest GPS'),
            if (selfColor != null) _LegendDot(color: selfColor!, label: 'You'),
            if (isTeam) const Text('Team markers use assigned colours'),
          ],
        ),
      ),
    );
  }
}

/// Displays the team participant panel.
class _TeamParticipantPanel extends StatelessWidget {
  /// Creates team participant panel.
  const _TeamParticipantPanel({
    required this.participants,
    required this.currentPhoneNumber,
  });

  final List<TeamHikeParticipant> participants;
  final String currentPhoneNumber;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SizedBox(
        width: 152,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Text(
                  'Team',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF6E6E73),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 1),
              for (var i = 0; i < participants.length; i++)
                _ParticipantRow(
                  color: _displayColorForParticipant(
                    participants[i],
                    i,
                    currentPhoneNumber,
                  ),
                  name: participants[i].buddy.shortName,
                  photoURL: participants[i].buddy.photoURL,
                  isLeader: participants[i].isLeader,
                  hasLocation: participants[i].hasFreshLocationAt(now),
                  status: participants[i].status,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the participant row.
class _ParticipantRow extends StatelessWidget {
  /// Creates participant row.
  const _ParticipantRow({
    required this.color,
    required this.name,
    required this.photoURL,
    required this.isLeader,
    required this.hasLocation,
    required this.status,
  });

  final Color color;
  final String name;
  final String photoURL;
  final bool isLeader;
  final bool hasLocation;
  final TeamHikeParticipantStatus status;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final isEnded = status == TeamHikeParticipantStatus.ended;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: isEnded ? const Color(0xFF6E6E73) : color,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: photoURL.trim().isEmpty
                ? Text(
                    name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : Image.network(
                    photoURL.trim(),
                    width: 22,
                    height: 22,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Text(
                      name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: isEnded ? const Color(0xFF6E6E73) : null,
                decoration: isEnded ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (isLeader && !isEnded) ...[
            const SizedBox(width: 4),
            Icon(Icons.star_rounded, size: 14, color: color),
          ],
          if (isEnded) ...[
            const SizedBox(width: 4),
            Text(
              'Ended',
              style: theme.textTheme.labelSmall?.copyWith(
                color: const Color(0xFF6E6E73),
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ] else if (!hasLocation) ...[
            const SizedBox(width: 4),
            Text(
              'Away',
              style: theme.textTheme.labelSmall?.copyWith(
                color: const Color(0xFF6E6E73),
                letterSpacing: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

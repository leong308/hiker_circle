part of '../../sos_button_pairing_sheet_feature.dart';

/// Displays the instruction tile.
class _InstructionTile extends StatelessWidget {
  /// Creates instruction tile.
  const _InstructionTile({
    required this.number,
    required this.title,
    required this.detail,
  });

  final int number;
  final String title;
  final String detail;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              child: Text(
                '$number',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(detail),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the searching panel.
class _SearchingPanel extends StatelessWidget {
  /// Creates searching panel.
  const _SearchingPanel({
    required this.elapsedSeconds,
    required this.scanWindowSeconds,
  });

  final int elapsedSeconds;
  final int scanWindowSeconds;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remainingSeconds = (scanWindowSeconds - elapsedSeconds).clamp(
      0,
      scanWindowSeconds,
    );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          LinearProgressIndicator(value: remainingSeconds / scanWindowSeconds),
          const SizedBox(height: 14),
          Text(
            'App scan: ${_formatSetupCountdown(remainingSeconds)} remaining',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Once an updated button is detected, this changes to its exact setup-mode countdown.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Displays the setup mode countdown card.
class _SetupModeCountdownCard extends StatelessWidget {
  /// Creates setup mode countdown card.
  const _SetupModeCountdownCard({required this.remainingSeconds});

  final int? remainingSeconds;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final seconds = remainingSeconds;
    final expired = seconds == 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: expired
            ? scheme.errorContainer
            : scheme.primaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            seconds == null
                ? Icons.timer_off_outlined
                : expired
                ? Icons.timer_off_rounded
                : Icons.timer_outlined,
            color: expired
                ? scheme.onErrorContainer
                : scheme.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  seconds == null
                      ? 'Setup countdown unavailable'
                      : expired
                      ? 'Setup mode expired'
                      : '${_formatSetupCountdown(seconds)} remaining',
                  style: TextStyle(
                    color: expired
                        ? scheme.onErrorContainer
                        : scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  seconds == null
                      ? 'This button uses older firmware. Pairing still works, but it does not report its setup timer.'
                      : expired
                      ? 'Restart setup mode before continuing.'
                      : 'Physical SOS button setup mode',
                  style: TextStyle(
                    color: expired
                        ? scheme.onErrorContainer
                        : scheme.onPrimaryContainer,
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

/// Displays the pairing activity panel.
class _PairingActivityPanel extends StatelessWidget {
  /// Creates pairing activity panel.
  const _PairingActivityPanel({
    required this.headline,
    required this.detail,
    this.emphasize = false,
  });

  final String headline;
  final String detail;
  final bool emphasize;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: emphasize,
      child: HikerCircleLoadingToast(
        message: headline,
        detail: detail,
        compact: true,
      ),
    );
  }
}

/// Displays the info banner.
class _InfoBanner extends StatelessWidget {
  /// Creates info banner.
  const _InfoBanner({
    required this.icon,
    required this.text,
    required this.color,
    required this.foregroundColor,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Color foregroundColor;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foregroundColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: foregroundColor, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

part of '../../paired_sos_button_page_feature.dart';

/// Displays the pairing hero card.
class _PairingHeroCard extends StatelessWidget {
  /// Creates pairing hero card.
  const _PairingHeroCard({
    required this.scheme,
    required this.enabled,
    required this.onAdd,
  });

  final ColorScheme scheme;
  final bool enabled;
  final VoidCallback onAdd;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, Colors.black, 0.22)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.sos_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connect your SOS button',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'A guided setup will walk you through detection, secure pairing, and physical confirmation.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.84),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: enabled ? onAdd : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
            label: const Text('Detect and add a button'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: scheme.primary,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.35),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.75),
              minimumSize: const Size.fromHeight(50),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the readiness card.
class _ReadinessCard extends StatelessWidget {
  /// Creates readiness card.
  const _ReadinessCard({
    required this.readiness,
    required this.loading,
    required this.onRefresh,
    required this.onOpenBatterySettings,
  });

  final SosButtonReadiness? readiness;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onOpenBatterySettings;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final value = readiness;
    final scheme = Theme.of(context).colorScheme;
    final allReady = value != null && value.blockingWarnings.isEmpty;
    return Card(
      elevation: 0,
      color: allReady
          ? scheme.primaryContainer.withValues(alpha: 0.45)
          : scheme.errorContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  allReady
                      ? Icons.verified_user_rounded
                      : Icons.warning_rounded,
                  color: allReady ? scheme.primary : scheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    allReady
                        ? value.hasPairedButton
                              ? 'SOS system ready'
                              : 'Phone SOS ready'
                        : 'Readiness needs attention',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (loading)
                  const SizedBox.square(
                    dimension: 18,
                    child: HikerCircleMinorLoadingIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    onPressed: onRefresh,
                    tooltip: 'Refresh readiness',
                    icon: const Icon(Icons.refresh_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (value == null)
              const Text('Checking Bluetooth and background monitoring…')
            else ...[
              _readinessLine('Bluetooth', value.bluetoothEnabled),
              _readinessLine(
                'Bluetooth permissions',
                value.scanPermissionGranted && value.connectPermissionGranted,
              ),
              _readinessLine(
                'Alert notifications',
                value.notificationPermissionGranted &&
                    value.notificationsEnabled,
              ),
              _readinessLine('Background monitor', value.monitorHealthy),
              _readinessLine(
                value.hasPairedButton
                    ? 'Paired button seen recently'
                    : 'No SOS button paired',
                value.hasPairedButton ? value.buttonSeenRecently() : null,
                neutralColor: scheme.onSurfaceVariant,
              ),
              _readinessLine(
                'Battery optimization unrestricted',
                value.batteryOptimizationExempt,
                advisory: true,
              ),
              if (value.lastFailure case final failure?) ...[
                const SizedBox(height: 6),
                Text('Monitor report: $failure'),
              ],
              if (!value.batteryOptimizationExempt)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton.icon(
                    onPressed: onOpenBatterySettings,
                    icon: const Icon(Icons.battery_saver_rounded),
                    label: const Text('Battery settings'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Computes readiness line.
  Widget _readinessLine(
    String label,
    bool? ready, {
    bool advisory = false,
    Color? neutralColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            ready == null
                ? Icons.remove_circle_outline_rounded
                : ready
                ? Icons.check_circle_rounded
                : advisory
                ? Icons.info_rounded
                : Icons.cancel_rounded,
            size: 18,
            color: ready == null
                ? neutralColor
                : ready
                ? Colors.green
                : advisory
                ? Colors.orange
                : Colors.red,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

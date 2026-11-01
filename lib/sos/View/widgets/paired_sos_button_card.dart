import 'package:flutter/material.dart';
import '../../../core/services/hiker_ble_service.dart';
import '../../../core/widgets/loading_toast.dart';

/// Shows current presence and clear actions without crowding the device name.
class PairedSosButtonCard extends StatelessWidget {
  /// Uses the same checked-at snapshot as the readiness summary.
  const PairedSosButtonCard({
    super.key,
    required this.button,
    required this.checkedAt,
    required this.onTest,
    required this.onLogs,
    required this.onUnpair,
    this.testing = false,
    this.downloading = false,
  });
  final PairedSosButton button;
  final DateTime checkedAt;
  final VoidCallback? onTest, onLogs, onUnpair;
  final bool testing, downloading;

  /// Formats a compact local timestamp instead of the raw ISO date.
  String _seenLabel(BuildContext context) {
    final seen = button.lastSeenAt?.toLocal();
    if (seen == null) return 'Not seen yet';
    final age = checkedAt.difference(seen);
    if (age.inMinutes < 1) return 'Seen just now';
    if (age.inHours < 1) return 'Seen ${age.inMinutes} min ago';
    final local = MaterialLocalizations.of(context);
    return 'Last seen ${local.formatMediumDate(seen)} · ${local.formatTimeOfDay(TimeOfDay.fromDateTime(seen))}';
  }

  /// Preserves test, log download and unpair actions in an adaptive card layout.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recent =
        button.lastSeenAt != null &&
        checkedAt.difference(button.lastSeenAt!) <= const Duration(minutes: 2);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.sos_rounded, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      button.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID ${button.deviceId}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Button options',
                enabled: onLogs != null || onUnpair != null,
                onSelected: (action) {
                  if (action == 'logs') onLogs?.call();
                  if (action == 'unpair') onUnpair?.call();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'logs',
                    enabled: onLogs != null,
                    child: const Text('Download event log'),
                  ),
                  PopupMenuItem(
                    value: 'unpair',
                    enabled: onUnpair != null,
                    child: Text(
                      'Unpair button',
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(
                  Icons.circle,
                  size: 9,
                  color: recent ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _seenLabel(context),
                  style: TextStyle(
                    color: recent ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: onTest,
                icon: testing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: HikerCircleMinorLoadingIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_circle_outline_rounded),
                label: Text(testing ? 'Testing…' : 'Test button'),
              ),
              if (downloading)
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 16,
                      child: HikerCircleMinorLoadingIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Downloading log…'),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

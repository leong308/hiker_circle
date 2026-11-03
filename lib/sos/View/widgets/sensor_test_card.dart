import 'package:flutter/material.dart';

/// The shared presentation for isolated motion tests in Test Settings.
class SensorTestCard extends StatelessWidget {
  const SensorTestCard({
    super.key,
    required this.icon,
    required this.title,
    required this.instruction,
    required this.progress,
    required this.status,
    required this.actionLabel,
    required this.onAction,
    this.actionKey,
    this.statusKey,
    this.progressValueLabel,
  });

  final IconData icon;
  final String title;
  final String instruction;
  final double progress;
  final String status;
  final String actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;
  final Key? statusKey;
  final String? progressValueLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const green = Color(0xFF34A853);
    final secondary = dark ? const Color(0xFFA8B8AE) : const Color(0xFF6E6E73);
    final button = FilledButton(
      key: actionKey,
      onPressed: onAction,
      child: Text(actionLabel),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackAction =
              constraints.maxWidth < 260 ||
              MediaQuery.textScalerOf(context).scale(14) > 21;
          return Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: green,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: dark
                            ? const Color(0xFFEAF4EE)
                            : const Color(0xFF111111),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      instruction,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 5,
                        color: green,
                        backgroundColor: dark
                            ? const Color(0xFF183625)
                            : const Color(0xFFEAF7EE),
                        semanticsLabel: title,
                        semanticsValue: progressValueLabel,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        status,
                        key: statusKey,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: secondary,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    if (stackAction) ...[
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: button),
                    ],
                  ],
                ),
              ),
              if (!stackAction) ...[const SizedBox(width: 10), button],
            ],
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// A moving indicator for live acceleration, relative to the chosen test target.
class FallAccelerationMeter extends StatelessWidget {
  /// Creates fall acceleration meter.
  const FallAccelerationMeter({
    super.key,
    required this.progress,
    required this.active,
    required this.passed,
  });
  final double progress;
  final bool active, passed;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = progress.clamp(0.0, 1.0);
    return Semantics(
      label: 'Live acceleration',
      value: passed
          ? 'Target reached'
          : active
          ? '${(value * 100).round()} percent of the test target'
          : 'Test is not running',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  passed ? Icons.check_circle_rounded : Icons.sensors_rounded,
                  color: scheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Live acceleration',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) => TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 100),
                builder: (context, position, _) => SizedBox(
                  height: 38,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 10,
                        right: 10,
                        top: 14,
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: scheme.outlineVariant.withValues(alpha: .5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: position,
                              heightFactor: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (constraints.maxWidth - 20) * position,
                        top: 9,
                        child: Container(
                          key: const ValueKey('fall-test-meter-indicator'),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.surface, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: scheme.shadow.withValues(alpha: .12),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Low',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: Text(
                    passed ? 'Target reached' : 'Test target',
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

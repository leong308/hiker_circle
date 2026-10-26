// Scheduled-hike clocks update locally without rebuilding forecast or preparation content.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'split_flap_number.dart';

/// Displays the hike departure countdown.
class HikeDepartureCountdown extends StatelessWidget {
  /// Creates hike departure countdown.
  const HikeDepartureCountdown({
    super.key,
    required this.departure,
    this.enabled = true,
    this.now,
  });
  final DateTime departure;
  final bool enabled;
  final DateTime Function()? now;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => _DepartureClock(
    enabled: enabled,
    now: now,
    builder: (context, currentTime) {
      final remaining = departure.difference(currentTime);
      final seconds = math.max(0, remaining.inSeconds);
      final reached = !currentTime.isBefore(departure);
      final values = [
        seconds ~/ 86400,
        seconds ~/ 3600 % 24,
        seconds ~/ 60 % 60,
        seconds % 60,
      ];
      final scheme = Theme.of(context).colorScheme;
      return Semantics(
        label: reached
            ? 'Departure time reached'
            : '${values[0]} days, ${values[1]} hours, ${values[2]} minutes to departure',
        child: ExcludeSemantics(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          SplitFlapNumber(
                            key: ValueKey('flap-$i'),
                            valueKey: ValueKey('${i}_${values[i]}'),
                            value: values[i].toString().padLeft(2, '0'),
                          ),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              ['Days', 'Hours', 'Min', 'Sec'][i],
                              maxLines: 1,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Time left before an unstarted plan leaves Upcoming and enters history.
class HikeDepartureExpiryLabel extends StatelessWidget {
  /// Creates hike departure expiry label.
  const HikeDepartureExpiryLabel({
    super.key,
    required this.departure,
    required this.expiresAt,
    this.enabled = true,
    this.now,
  });
  final DateTime departure;
  final DateTime expiresAt;
  final bool enabled;
  final DateTime Function()? now;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => _DepartureClock(
    enabled: enabled,
    now: now,
    builder: (context, currentTime) {
      if (currentTime.isBefore(departure)) return const SizedBox.shrink();
      final seconds =
          (expiresAt.difference(currentTime).inMicroseconds /
                  Duration.microsecondsPerSecond)
              .ceil();
      if (seconds <= 0) return const SizedBox.shrink();
      final minutes = seconds ~/ 60;
      final remainder = seconds % 60;
      final clock =
          '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
      final colors = Theme.of(context).colorScheme;
      final style = Theme.of(context).textTheme.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: colors.error,
      );
      return Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Semantics(
          label:
              'Expires in $minutes minutes and $remainder seconds',
          excludeSemantics: true,
          child: Tooltip(
            message: 'Expires in $clock',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: colors.errorContainer.withValues(alpha: .4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.hourglass_bottom_rounded,
                    size: 12,
                    color: colors.error,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Expires in',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    clock,
                    key: const ValueKey('hike-expiry-countdown'),
                    maxLines: 1,
                    style: style?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Foreground-only ticks rebuild each clock rather than the entire upcoming-hike card.
class _DepartureClock extends StatefulWidget {
  /// Creates departure clock.
  const _DepartureClock({
    required this.enabled,
    required this.now,
    required this.builder,
  });
  final bool enabled;
  final DateTime Function()? now;
  final Widget Function(BuildContext context, DateTime now) builder;

  /// Creates the presentation state for this widget.
  @override
  State<_DepartureClock> createState() => _DepartureClockState();
}

/// Manages the departure clock presentation and lifecycle.
class _DepartureClockState extends State<_DepartureClock>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant _DepartureClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
    if (mounted) setState(() {});
  }

  /// Synchronizes.
  void _sync() {
    _timer?.cancel();
    if (widget.enabled && _foreground) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.now?.call() ?? DateTime.now());
}

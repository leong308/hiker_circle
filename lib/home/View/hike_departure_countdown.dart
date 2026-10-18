// HikeDepartureCountdown updates only the local countdown and start controls for a scheduled hike.
import 'split_flap_number.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Only this small section rebuilds each second; it never fetches weather.
class HikeDepartureCountdown extends StatefulWidget {
  const HikeDepartureCountdown({
    super.key,
    required this.departure,
    this.enabled = true,
    this.now,
  });
  final DateTime departure;
  final bool enabled;
  final DateTime Function()? now;
  @override
  State<HikeDepartureCountdown> createState() => _CountdownState();
}

class _CountdownState extends State<HikeDepartureCountdown>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  @override
  void didUpdateWidget(covariant HikeDepartureCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    _timer?.cancel();
    if (widget.enabled && _foreground) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.departure.difference(
      widget.now?.call() ?? DateTime.now(),
    );
    final seconds = math.max(0, remaining.inSeconds);
    final values = [
      seconds ~/ 86400,
      seconds ~/ 3600 % 24,
      seconds ~/ 60 % 60,
      seconds % 60,
    ];
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: seconds == 0
          ? 'Departure time reached'
          : '${values[0]} days, ${values[1]} hours, ${values[2]} minutes to departure',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (seconds == 0) ...[
              Text(
                'Departure time reached',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Center(
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
                            Text(
                              ['Days', 'Hours', 'Min', 'Sec'][i],
                              maxLines: 1,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
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
          ],
        ),
      ),
    );
  }
}

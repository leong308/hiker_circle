import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// The bundled GPS animation is shared by live-location and hike starts.
class GpsStartingProgress extends StatelessWidget {
  const GpsStartingProgress({
    super.key,
    required this.title,
    required this.message,
    this.animationSize = 180,
  });

  static const assetPath = 'assets/animations/gps_location.json';

  final String title;
  final String message;
  final double animationSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: SizedBox.square(
              dimension: animationSize,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Lottie.asset(
                  assetPath,
                  key: const Key('gps-starting-animation'),
                  fit: BoxFit.contain,
                  animate: !reduceMotion,
                  repeat: !reduceMotion,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.gps_fixed_rounded,
                    size: animationSize * 0.42,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// A route-owned busy state; completion remains controlled by the operation.
/// A watchdog preserves callers' existing timeout behavior where configured.
class GpsStartingOverlay extends StatefulWidget {
  const GpsStartingOverlay({
    super.key,
    required this.title,
    required this.message,
    this.animationSize = 180,
    this.dimBackground = true,
    this.timeout = Duration.zero,
    this.onTimeout,
  });

  final String title;
  final String message;
  final double animationSize;
  final bool dimBackground;
  final Duration timeout;
  final VoidCallback? onTimeout;

  @override
  State<GpsStartingOverlay> createState() => _GpsStartingOverlayState();
}

class _GpsStartingOverlayState extends State<GpsStartingOverlay> {
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    _scheduleWatchdog();
  }

  @override
  void didUpdateWidget(GpsStartingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeout != widget.timeout ||
        oldWidget.onTimeout != widget.onTimeout) {
      _scheduleWatchdog();
    }
  }

  void _scheduleWatchdog() {
    _watchdog?.cancel();
    if (widget.timeout <= Duration.zero || widget.onTimeout == null) return;
    _watchdog = Timer(widget.timeout, () {
      if (mounted) widget.onTimeout?.call();
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: BlockSemantics(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ModalBarrier(
                dismissible: false,
                color: widget.dimBackground
                    ? const Color(0x66000000)
                    : Colors.transparent,
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 340),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GpsStartingProgress(
                          title: widget.title,
                          message: widget.message,
                          animationSize: widget.animationSize,
                        ),
                        const SizedBox(height: 20),
                        const ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          child: LinearProgressIndicator(minHeight: 5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Keeps the condition visible while a separate badge signals serious risk.
class CautionIcon extends StatelessWidget {
  /// Creates caution icon.
  const CautionIcon({
    super.key,
    required this.icon,
    this.seriousRisk = false,
    this.color,
    this.size = 24,
  });

  final IconData icon;
  final bool seriousRisk;
  final Color? color;
  final double size;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size + 12,
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Icon(icon, color: color, size: size),
        if (seriousRisk)
          const Positioned(top: 0, right: 0, child: _SeriousRiskBadge()),
      ],
    ),
  );
}

/// Displays the serious risk badge.
class _SeriousRiskBadge extends StatefulWidget {
  /// Creates serious risk badge.
  const _SeriousRiskBadge();

  /// Creates the presentation state for this widget.
  @override
  State<_SeriousRiskBadge> createState() => _SeriousRiskBadgeState();
}

/// Manages the serious risk badge presentation and lifecycle.
class _SeriousRiskBadgeState extends State<_SeriousRiskBadge>
    with SingleTickerProviderStateMixin {
  late final _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// Refreshes presentation dependencies.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _blink.stop();
      _blink.value = 0;
    } else if (!_blink.isAnimating) {
      _blink.repeat(reverse: true);
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Serious risk',
    child: FadeTransition(
      opacity: Tween<double>(begin: 1, end: .25).animate(_blink),
      child: Container(
        width: 15,
        height: 15,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFD32F2F),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.3),
        ),
        child: const Text(
          '!',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ),
  );
}

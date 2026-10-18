// SplitFlapNumber animates changing countdown digits with hinged top and bottom panels.
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Two hinged half-panels: old top folds away, then new bottom settles.
class SplitFlapNumber extends StatefulWidget {
  const SplitFlapNumber({super.key, required this.value, this.valueKey});
  final String value;
  final Key? valueKey;
  @override
  State<SplitFlapNumber> createState() => _SplitFlapState();
}

class _SplitFlapState extends State<SplitFlapNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    value: 1,
  );
  late String _previous = widget.value;
  bool _reduceMotion = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant SplitFlapNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _previous = oldWidget.value;
      if (_reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final height = math.max(
      72.0,
      MediaQuery.textScalerOf(context).scale(32) * 1.8,
    );
    final top = Color.alphaBlend(
      scheme.primary.withValues(alpha: .13),
      scheme.surface,
    );
    final bottom = Color.alphaBlend(
      scheme.primary.withValues(alpha: .08),
      scheme.surface,
    );
    final style = theme.textTheme.headlineSmall?.copyWith(
      fontSize: 32,
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: scheme.primary,
      height: 1,
    );
    Widget half(String value, bool upper, {double shade = 0}) => ClipRect(
      child: SizedBox(
        height: height / 2,
        child: Stack(
          fit: StackFit.expand,
          children: [
            OverflowBox(
              minHeight: height,
              maxHeight: height,
              alignment: upper ? Alignment.topCenter : Alignment.bottomCenter,
              child: Container(
                height: height,
                alignment: Alignment.center,
                color: upper ? top : bottom,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value, maxLines: 1, style: style),
                ),
              ),
            ),
            if (shade > 0)
              ColoredBox(color: Colors.black.withValues(alpha: shade)),
          ],
        ),
      ),
    );
    return SizedBox(
      key: widget.valueKey,
      height: height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .1),
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value,
                  fold = Curves.easeInCubic.transform((t * 2).clamp(0.0, 1.0)),
                  settle = Curves.easeOutCubic.transform(
                    ((t - .5) * 2).clamp(0.0, 1.0),
                  );
              final moving = t < 1;
              return Stack(
                children: [
                  Column(
                    children: [
                      half(widget.value, true),
                      half(moving ? _previous : widget.value, false),
                    ],
                  ),
                  if (moving && t < .5)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Transform(
                        alignment: Alignment.bottomCenter,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, .003)
                          ..rotateX(-fold * math.pi / 2),
                        child: half(_previous, true, shade: fold * .18),
                      ),
                    ),
                  if (moving && t >= .5)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Transform(
                        alignment: Alignment.topCenter,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, .003)
                          ..rotateX((1 - settle) * math.pi / 2),
                        child: half(
                          widget.value,
                          false,
                          shade: (1 - settle) * .18,
                        ),
                      ),
                    ),
                  Positioned(
                    top: height / 2 - .5,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 1,
                      color: scheme.onSurface.withValues(alpha: .15),
                    ),
                  ),
                  for (final left in [true, false])
                    Positioned(
                      top: height / 2 - 2,
                      left: left ? 0 : null,
                      right: left ? null : 0,
                      child: Container(
                        width: 3,
                        height: 4,
                        decoration: BoxDecoration(
                          color: scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

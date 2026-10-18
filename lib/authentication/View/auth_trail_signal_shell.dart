// AuthTrailSignalShell surrounds the unchanged login card with themed route-line animation.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/privacy_policy_link.dart';
import 'auth_brand_panel.dart';

/// Animated cartographic linework around the existing authentication card.
class AuthTrailSignalShell extends StatelessWidget {
  const AuthTrailSignalShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: isDark
                ? const Color(0xFF17271F)
                : const Color(0xFFEAF0E8),
            systemNavigationBarIconBrightness: isDark
                ? Brightness.light
                : Brightness.dark,
          ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _TrailSignalBackdrop(isDark: isDark)),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(0, constraints.maxHeight - 48),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const AuthBrandPanel(),
                            const SizedBox(height: 28),
                            child,
                            const SizedBox(height: 12),
                            const Align(
                              alignment: Alignment.center,
                              child: PrivacyPolicyLink(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TrailSignalBackdrop extends StatefulWidget {
  const _TrailSignalBackdrop({required this.isDark});

  final bool isDark;

  @override
  State<_TrailSignalBackdrop> createState() => _TrailSignalBackdropState();
}

/// Own the backdrop animation lifecycle while the existing authentication card remains interactive.
class _TrailSignalBackdropState extends State<_TrailSignalBackdrop>
    with SingleTickerProviderStateMixin {
  late final _signal = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
    value: 0.12,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _signal.stop();
      _signal.value = 0.12;
    } else if (!_signal.isAnimating) {
      _signal.repeat();
    }
  }

  @override
  void dispose() {
    _signal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: _SignalSurfacePainter(isDark: widget.isDark),
              ),
            ),
            // Only the trail repaints as its marker moves. The form and
            // the softly textured surface remain in their own layers.
            RepaintBoundary(
              child: CustomPaint(
                painter: _SignalRoutePainter(_signal, isDark: widget.isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalSurfacePainter extends CustomPainter {
  const _SignalSurfacePainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF111D17), Color(0xFF1A2D22), Color(0xFF14231C)]
              : const [Color(0xFFF5F7F2), Color(0xFFE9EFE7), Color(0xFFEEF2EA)],
        ).createShader(bounds),
    );
    _light(
      canvas,
      Offset(size.width * 0.08, size.height * 0.05),
      math.max(size.width * 0.45, 280),
      isDark ? const Color(0xFF66996C) : const Color(0xFFB5CFAC),
      isDark ? 0.10 : 0.25,
    );
    _light(
      canvas,
      Offset(size.width * 0.95, size.height * 0.95),
      math.max(size.width * 0.35, 220),
      isDark ? const Color(0xFF86A183) : const Color(0xFFD5DEC2),
      isDark ? 0.06 : 0.32,
    );

    // Sparse registration dots give the empty edges a tactile map quality.
    final dot = Paint()
      ..color = (isDark ? const Color(0xFFA4BEA0) : const Color(0xFF678369))
          .withValues(alpha: isDark ? 0.10 : 0.12);
    final center = size.width / 2;
    for (var x = 22.0; x < size.width; x += 36) {
      for (var y = 22.0; y < size.height; y += 36) {
        if ((x - center).abs() > math.min(300, size.width * 0.40) ||
            y < size.height * 0.10 ||
            y > size.height * 0.92) {
          canvas.drawCircle(Offset(x, y), 0.65, dot);
        }
      }
    }

    final contourColor = isDark
        ? const Color(0xFF91AE92)
        : const Color(0xFF64856C);
    _contours(
      canvas,
      Offset(-size.width * 0.06, size.height * 0.21),
      contourColor,
      -0.32,
      1,
    );
    _contours(
      canvas,
      Offset(size.width * 1.02, size.height * 0.86),
      contourColor,
      0.75,
      1.15,
    );
  }

  void _contours(
    Canvas canvas,
    Offset center,
    Color color,
    double angle,
    double scale,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.scale(scale);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = color.withValues(alpha: isDark ? 0.13 : 0.14);
    for (var i = 0; i < 12; i++) {
      final radius = 40.0 + i * 14;
      final path = Path()
        ..moveTo(radius, 0)
        ..cubicTo(
          radius * 1.12,
          -radius * 0.35,
          radius * 0.42,
          -radius * 0.86,
          -radius * 0.12,
          -radius * 0.70,
        )
        ..cubicTo(
          -radius * 0.78,
          -radius * 0.53,
          -radius * 1.04,
          -radius * 0.17,
          -radius * 0.84,
          radius * 0.27,
        )
        ..cubicTo(
          -radius * 0.55,
          radius * 0.83,
          radius * 0.04,
          radius * 0.39,
          radius * 0.38,
          radius * 0.43,
        )
        ..cubicTo(
          radius * 0.77,
          radius * 0.50,
          radius * 0.91,
          radius * 0.28,
          radius,
          0,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  void _light(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double alpha,
  ) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_SignalSurfacePainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

class _SignalRoutePainter extends CustomPainter {
  _SignalRoutePainter(this.signal, {required this.isDark})
    : super(repaint: signal);

  final Animation<double> signal;
  final bool isDark;
  Size? _cachedSize;
  final _routes = <Path>[];
  final _metrics = <ui.PathMetric>[];
  final _branches = <Path>[];
  final _junctions = <Offset>[];

  void _layout(Size size) {
    if (_cachedSize == size) return;
    _cachedSize = size;
    _routes.clear();
    _metrics.clear();
    _branches.clear();
    _junctions.clear();
    final w = size.width;
    final h = size.height;
    // Two asymmetric trails flow through the entire composition instead of
    // forming a border around the card. Their ends continue off the canvas.
    _routes.add(
      Path()
        ..moveTo(-w * 0.14, h * 0.36)
        ..cubicTo(w * 0.04, h * 0.31, w * 0.13, h * 0.34, w * 0.19, h * 0.24)
        ..cubicTo(w * 0.25, h * 0.14, w * 0.58, h * 0.03, w * 0.83, h * 0.11)
        ..cubicTo(w * 1.06, h * 0.18, w * 0.86, h * 0.29, w * 0.94, h * 0.43)
        ..cubicTo(w * 1.03, h * 0.55, w * 0.83, h * 0.66, w * 0.86, h * 0.78)
        ..cubicTo(w * 0.90, h * 0.95, w * 0.57, h * 0.92, w * 0.48, h * 1.08),
    );
    _routes.add(
      Path()
        ..moveTo(-w * 0.10, -h * 0.04)
        ..cubicTo(w * 0.15, -h * 0.06, w * 0.46, h * 0.09, w * 0.32, h * 0.20)
        ..cubicTo(w * 0.18, h * 0.31, -w * 0.03, h * 0.26, w * 0.04, h * 0.47)
        ..cubicTo(w * 0.12, h * 0.65, -w * 0.07, h * 0.72, w * 0.14, h * 0.85)
        ..cubicTo(w * 0.34, h * 1.03, w * 0.62, h * 0.77, w * 0.82, h * 0.90)
        ..cubicTo(w * 0.99, h * 0.99, w * 1.12, h * 0.93, w * 1.10, h * 1.08),
    );
    _metrics.addAll(_routes.map((path) => path.computeMetrics().single));

    // Real connecting junctions make this a small trail network.
    for (final fractions in const [(0.24, 0.15), (0.77, 0.76)]) {
      final start = _metrics[0].getTangentForOffset(
        _metrics[0].length * fractions.$1,
      )!;
      final end = _metrics[1].getTangentForOffset(
        _metrics[1].length * fractions.$2,
      )!;
      final bend = math.min(w * 0.18, 130.0);
      _branches.add(
        Path()
          ..moveTo(start.position.dx, start.position.dy)
          ..cubicTo(
            start.position.dx + bend,
            start.position.dy - h * 0.05,
            end.position.dx - bend,
            end.position.dy + h * 0.04,
            end.position.dx,
            end.position.dy,
          ),
      );
      _junctions.addAll([start.position, end.position]);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _layout(size);
    final green = isDark ? const Color(0xFFACCEA3) : const Color(0xFF587A60);
    final sage = isDark ? const Color(0xFF89AAA2) : const Color(0xFF73958B);
    final fill = isDark ? const Color(0xFF192B21) : const Color(0xFFEDF2E9);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var index = 0; index < _routes.length; index++) {
      final color = index == 0 ? green : sage;
      canvas.drawPath(
        _routes[index],
        stroke
          ..strokeWidth = 5
          ..color = color.withValues(alpha: isDark ? 0.025 : 0.035),
      );
      canvas.drawPath(
        _routes[index],
        stroke
          ..strokeWidth = index == 0 ? 1.3 : 1.0
          ..color = color.withValues(alpha: isDark ? 0.30 : 0.31),
      );

      final metric = _metrics[index];
      final progress = (signal.value + index * 0.43) % 1;
      final distance = metric.length * progress;
      for (final fraction in const [0.16, 0.39, 0.64, 0.85]) {
        final checkpoint = metric
            .getTangentForOffset(metric.length * fraction)!
            .position;
        final nearby = (1 - (metric.length * fraction - distance).abs() / 55)
            .clamp(0.0, 1.0);
        _checkpoint(canvas, checkpoint, color, fill, nearby);
      }
      _movingSignal(canvas, metric, progress, color, fill, stroke);
    }

    for (var index = 0; index < _branches.length; index++) {
      final branch = _branches[index];
      stroke
        ..strokeWidth = 0.85
        ..color = green.withValues(alpha: isDark ? 0.23 : 0.26);
      if (index == 0) {
        canvas.drawPath(branch, stroke);
      } else {
        for (final metric in branch.computeMetrics()) {
          for (var distance = 0.0; distance < metric.length; distance += 7) {
            canvas.drawPath(
              metric.extractPath(
                distance,
                math.min(distance + 2.5, metric.length),
              ),
              stroke,
            );
          }
        }
      }
    }
    for (final junction in _junctions) {
      canvas.drawCircle(junction, 5.5, Paint()..color = fill);
      canvas.drawCircle(
        junction,
        5.5,
        stroke
          ..strokeWidth = 0.85
          ..color = green.withValues(alpha: 0.4),
      );
      canvas.drawCircle(
        junction,
        2,
        Paint()..color = green.withValues(alpha: 0.5),
      );
    }
  }

  void _checkpoint(
    Canvas canvas,
    Offset point,
    Color color,
    Color fill,
    double nearby,
  ) {
    canvas.drawCircle(point, 3.7, Paint()..color = fill);
    canvas.drawCircle(
      point,
      3.7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = color.withValues(alpha: 0.38 + nearby * 0.3),
    );
    canvas.drawCircle(point, 1, Paint()..color = color.withValues(alpha: 0.48));
  }

  void _movingSignal(
    Canvas canvas,
    ui.PathMetric metric,
    double progress,
    Color color,
    Color fill,
    Paint stroke,
  ) {
    final distance = metric.length * progress;
    // Open paths begin and end outside the screen, so the loop stays seamless.
    for (var i = 0; i < 24; i++) {
      final from = (distance - 96 + i * 4) % metric.length;
      canvas.drawPath(
        metric.extractPath(from, math.min(from + 4, metric.length)),
        stroke
          ..strokeWidth = 1.8
          ..color = color.withValues(alpha: (i + 1) / 24 * 0.6),
      );
    }
    final point = metric.getTangentForOffset(distance)!.position;
    final pulse = (math.sin(progress * math.pi * 12) + 1) / 2;
    final radius = 14 + pulse * 3;
    canvas.drawCircle(
      point,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.24), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: point, radius: radius)),
    );
    canvas.drawCircle(point, 5, Paint()..color = fill);
    canvas.drawCircle(
      point,
      2.8,
      Paint()..color = color.withValues(alpha: 0.95),
    );
    canvas.drawCircle(
      point - const Offset(0.6, 0.7),
      0.8,
      Paint()..color = isDark ? const Color(0xFFE8F5DB) : Colors.white,
    );
  }

  @override
  bool shouldRepaint(_SignalRoutePainter oldDelegate) =>
      oldDelegate.signal != signal || oldDelegate.isDark != isDark;
}

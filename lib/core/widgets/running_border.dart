import 'package:flutter/material.dart';

class RunningBorder extends StatefulWidget {
  const RunningBorder({
    super.key,
    required this.child,
    required this.color,
    this.radius = 18,
  });
  final Widget child;
  final Color color;
  final double radius;
  @override
  State<RunningBorder> createState() => _RunningBorderState();
}

class _RunningBorderState extends State<RunningBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => CustomPaint(
                painter: BorderTravelPainter(
                  progress: _controller.value,
                  color: widget.color,
                  radius: widget.radius,
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class BorderTravelPainter extends CustomPainter {
  BorderTravelPainter({
    required this.progress,
    required this.color,
    this.radius = 14,
  });

  final double progress;
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    final dimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withValues(alpha: 0.15);
    canvas.drawRRect(rrect, dimPaint);

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final totalLength = metrics.fold<double>(0.0, (s, m) => s + m.length);
    if (totalLength <= 0) return;

    const segmentFraction = 0.1;
    final segmentLength = totalLength * segmentFraction;

    final anticlockwisePos = 1.0 - progress;
    final start = anticlockwisePos * totalLength;
    final end = start + segmentLength;

    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color;

    double processed = 0;
    for (final metric in metrics) {
      final metricStart = processed;
      final metricEnd = processed + metric.length;

      if (end <= totalLength) {
        final overlapStart = start.clamp(metricStart, metricEnd);
        final overlapEnd = end.clamp(metricStart, metricEnd);
        if (overlapEnd > overlapStart) {
          final segment = metric.extractPath(
            overlapStart - metricStart,
            overlapEnd - metricStart,
          );
          canvas.drawPath(segment, highlightPaint);
        }
      } else {
        final wrapStart = 0.0;
        final wrapEnd = end - totalLength;
        if (wrapEnd > 0) {
          final overlapStart = wrapStart.clamp(metricStart, metricEnd);
          final overlapEnd = wrapEnd.clamp(metricStart, metricEnd);
          if (overlapEnd > overlapStart) {
            final segment = metric.extractPath(
              overlapStart - metricStart,
              overlapEnd - metricStart,
            );
            canvas.drawPath(segment, highlightPaint);
          }
        }
        final normalStart = start.clamp(metricStart, metricEnd);
        final normalEnd = totalLength.clamp(metricStart, metricEnd);
        if (normalEnd > normalStart) {
          final segment = metric.extractPath(
            normalStart - metricStart,
            normalEnd - metricStart,
          );
          canvas.drawPath(segment, highlightPaint);
        }
      }
      processed = metricEnd;
    }
  }

  @override
  bool shouldRepaint(BorderTravelPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.radius != radius;
}

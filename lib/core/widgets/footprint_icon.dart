import 'package:flutter/material.dart';

/// Displays the footprint icon.
class FootprintIcon extends StatelessWidget {
  /// Creates footprint icon.
  const FootprintIcon({super.key});

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Center(
    widthFactor: 1,
    heightFactor: 1,
    child: SizedBox.square(
      dimension: 24,
      child: CustomPaint(
        painter: _Footprints(
          IconTheme.of(context).color ??
              Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

/// Represents footprints.
class _Footprints extends CustomPainter {
  /// Creates footprints.
  const _Footprints(this.color);
  final Color color;

  /// Computes paint.
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()..color = color;
    for (final (x, y, angle) in [(7.0, 14.0, -.3), (17.0, 9.0, .3)]) {
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-2.3, -2.0, 4.6, 8),
          const Radius.circular(2.4),
        ),
        paint,
      );
      canvas.drawOval(const Rect.fromLTWH(-2.6, -7, 5.2, 4), paint);
      canvas.restore();
    }
  }

  /// Computes should repaint.
  @override
  bool shouldRepaint(covariant _Footprints oldDelegate) =>
      oldDelegate.color != color;
}

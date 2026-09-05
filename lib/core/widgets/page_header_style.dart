import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class PageHeaderStyle {
  static TextStyle title(BuildContext context, Color color) =>
      Theme.of(context).textTheme.headlineSmall!.copyWith(
        color: color,
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        height: 1.2,
      );

  static TextStyle subtitle(BuildContext context, Color color) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(
        color: color,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.4,
      );
}

class PageHeaderAction extends StatelessWidget {
  const PageHeaderAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.color,
    required this.surface,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final Color surface;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size.square(44),
      onPressed: onPressed,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: surface, shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 19),
      ),
    ),
  );
}

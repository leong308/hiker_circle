import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class PageHeaderStyle {
  static const double titleSize = 26;
  static const double iconSize = 19;
  static const double actionDiameter = 36;
  static const double actionTapSize = 44;
  static const double toolbarHeight = 76;

  static TextStyle title(BuildContext context, Color color) =>
      Theme.of(context).textTheme.headlineSmall!.copyWith(
        color: color == Colors.white
            ? Colors.white
            : Theme.of(context).colorScheme.onSurface,
        fontFamily: 'Inter',
        fontSize: titleSize,
        fontWeight: FontWeight.w800,
        fontStyle: FontStyle.normal,
        letterSpacing: -0.5,
        height: 1.2,
      );

  static TextStyle subtitle(BuildContext context, Color color) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(
        color: color == Colors.white
            ? Colors.white
            : Theme.of(context).colorScheme.onSurfaceVariant,
        fontFamily: 'Inter',
        fontSize: 13,
        fontWeight: FontWeight.w400,
        fontStyle: FontStyle.normal,
        letterSpacing: 0,
        height: 1.4,
      );

  static const appBarTheme = AppBarThemeData(
    centerTitle: false,
    toolbarHeight: toolbarHeight,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
    titleTextStyle: TextStyle(
      fontFamily: 'Inter',
      fontSize: titleSize,
      fontWeight: FontWeight.w800,
      fontStyle: FontStyle.normal,
      letterSpacing: -0.5,
      height: 1.2,
    ),
    iconTheme: IconThemeData(size: iconSize),
    actionsIconTheme: IconThemeData(size: iconSize),
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
  final VoidCallback? onPressed;
  final Color color;
  final Color surface;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size.square(PageHeaderStyle.actionTapSize),
      onPressed: onPressed,
      child: Container(
        width: PageHeaderStyle.actionDiameter,
        height: PageHeaderStyle.actionDiameter,
        decoration: BoxDecoration(
          color: color == Colors.white
              ? surface
              : Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: onPressed == null
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : color == Colors.white
              ? Colors.white
              : Theme.of(context).colorScheme.primary,
          size: PageHeaderStyle.iconSize,
        ),
      ),
    ),
  );
}

/// A shared navigation header for pages which keep their header in the body.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.leading,
    this.actions = const [],
    this.foregroundColor,
  });
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? leading;
  final List<Widget> actions;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (leading != null || onBack != null) ...[
          leading ??
              PageHeaderAction(
                tooltip: 'Back',
                icon: CupertinoIcons.chevron_back,
                onPressed: onBack,
                color: colors.primary,
                surface: colors.surface,
              ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PageHeaderStyle.title(
                  context,
                  foregroundColor ?? colors.onSurface,
                ),
              ),
              if (subtitle?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PageHeaderStyle.subtitle(
                    context,
                    foregroundColor ?? colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        for (final action in actions) ...[const SizedBox(width: 6), action],
      ],
    );
  }
}

/// Scaffold app bars use the same typography and circular controls as body
/// headers. Search fields, tabs, disabled callbacks and media contrast remain
/// owned by the page.
class PageHeaderAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PageHeaderAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions = const [],
    this.bottom,
    this.backgroundColor,
    this.foregroundColor,
    this.automaticallyImplyLeading = true,
  });
  final Widget? title, leading;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final Color? backgroundColor, foregroundColor;
  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize => Size.fromHeight(
    PageHeaderStyle.toolbarHeight + (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final textColor =
        foregroundColor ??
        (backgroundColor == Colors.black ? Colors.white : colors.onSurface);
    final iconColor =
        foregroundColor ??
        (backgroundColor == Colors.black ? Colors.white : colors.primary);
    final surface = backgroundColor == Colors.black
        ? Colors.white.withValues(alpha: .12)
        : colors.surface;
    Widget action(Widget widget) =>
        _standardHeaderControl(context, widget, iconColor, surface);
    final impliedBack =
        automaticallyImplyLeading && Navigator.of(context).canPop();
    final back = leading != null
        ? action(leading!)
        : impliedBack
        ? PageHeaderAction(
            tooltip: 'Back',
            icon: CupertinoIcons.chevron_back,
            onPressed: () => Navigator.of(context).maybePop(),
            color: iconColor,
            surface: surface,
          )
        : null;
    return AppBar(
      automaticallyImplyLeading: false,
      leading: back == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 18, right: 12),
              child: Center(child: back),
            ),
      leadingWidth: 74,
      titleSpacing: back == null ? 18 : 0,
      centerTitle: false,
      toolbarHeight: PageHeaderStyle.toolbarHeight,
      backgroundColor: backgroundColor ?? theme.scaffoldBackgroundColor,
      foregroundColor: textColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: title == null
          ? null
          : _standardHeaderTitle(context, title!, textColor),
      actions: [
        for (final widget in actions)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Center(child: action(widget)),
          ),
        if (actions.isNotEmpty) const SizedBox(width: 18),
      ],
      bottom: bottom,
    );
  }
}

class PageHeaderControl extends StatelessWidget {
  const PageHeaderControl({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => _standardHeaderControl(
    context,
    child,
    Theme.of(context).colorScheme.primary,
    Theme.of(context).colorScheme.surface,
  );
}

Widget _standardHeaderTitle(
  BuildContext context,
  Widget title,
  Color color, {
  bool subtitle = false,
}) {
  if (title is Text && title.data != null) {
    return Text(
      title.data!,
      maxLines: subtitle ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      semanticsLabel: title.semanticsLabel,
      style: subtitle
          ? PageHeaderStyle.subtitle(context, color)
          : PageHeaderStyle.title(context, color),
    );
  }
  if (title is Column) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < title.children.length; i++)
          _standardHeaderTitle(
            context,
            title.children[i],
            color,
            subtitle: i > 0,
          ),
      ],
    );
  }
  return title;
}

Icon? _headerIcon(Widget? widget) {
  if (widget is Icon) return widget;
  if (widget is Container) return _headerIcon(widget.child);
  if (widget is SizedBox) return _headerIcon(widget.child);
  if (widget is DecoratedBox) return _headerIcon(widget.child);
  if (widget is Padding) return _headerIcon(widget.child);
  if (widget is Center) return _headerIcon(widget.child);
  return null;
}

Widget _standardHeaderControl(
  BuildContext context,
  Widget widget,
  Color color,
  Color surface,
) {
  if (widget is IconButton && widget.icon is Icon) {
    final icon = widget.icon as Icon;
    return PageHeaderAction(
      key: widget.key,
      tooltip:
          widget.tooltip ?? icon.semanticLabel ?? _headerActionLabel(icon.icon),
      icon: icon.icon ?? Icons.more_horiz_rounded,
      onPressed: widget.onPressed,
      color: color,
      surface: surface,
    );
  }
  if (widget is CupertinoButton && _headerIcon(widget.child) != null) {
    final icon = _headerIcon(widget.child)!;
    return PageHeaderAction(
      key: widget.key,
      tooltip: icon.icon == CupertinoIcons.xmark ? 'Close' : 'Back',
      icon: icon.icon!,
      onPressed: widget.onPressed,
      color: color,
      surface: surface,
    );
  }
  if (widget is TextButton && widget.child is Text) {
    final label = (widget.child as Text).data ?? 'Save';
    return PageHeaderAction(
      key: widget.key,
      tooltip: label,
      icon: label.toLowerCase().contains('cancel')
          ? Icons.close_rounded
          : Icons.check_rounded,
      onPressed: widget.onPressed,
      color: color,
      surface: surface,
    );
  }
  if (widget is PopupMenuButton) {
    // Keep the original typed menu and callbacks. Rebuilding it as a dynamic
    // menu loses the callback's generic type (including chat's enum actions).
    return PopupMenuTheme(
      data: PopupMenuTheme.of(
        context,
      ).copyWith(iconSize: PageHeaderStyle.iconSize, iconColor: color),
      child: SizedBox.square(
        dimension: PageHeaderStyle.actionTapSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            IgnorePointer(
              child: Container(
                width: PageHeaderStyle.actionDiameter,
                height: PageHeaderStyle.actionDiameter,
                decoration: BoxDecoration(
                  color: surface,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned.fill(child: widget),
          ],
        ),
      ),
    );
  }
  return IconTheme(
    data: IconThemeData(color: color, size: PageHeaderStyle.iconSize),
    child: widget,
  );
}

String _headerActionLabel(IconData? icon) {
  if ({Icons.close_rounded, Icons.close, CupertinoIcons.xmark}.contains(icon)) {
    return 'Close';
  }
  if ({
    Icons.arrow_back,
    Icons.arrow_back_rounded,
    CupertinoIcons.back,
    CupertinoIcons.chevron_back,
  }.contains(icon)) {
    return 'Back';
  }
  if ({Icons.refresh, Icons.refresh_rounded}.contains(icon)) return 'Refresh';
  if ({Icons.search, Icons.search_rounded}.contains(icon)) return 'Search';
  if ({Icons.history, Icons.history_rounded}.contains(icon)) return 'History';
  if ({Icons.add, Icons.add_rounded}.contains(icon)) return 'Add';
  return 'Action';
}

// HikerCircleToast renders consistent transient feedback for informational, success and error
// states.
import 'dart:ui';

import 'package:flutter/material.dart';

enum HikerCircleToastTone { info, success, warning, error }

abstract final class HikerCircleToast {
  static const Duration defaultDuration = Duration(seconds: 4);
  static const AnimationStyle _animationStyle = AnimationStyle(
    duration: Duration(milliseconds: 360),
    reverseDuration: Duration(milliseconds: 280),
  );

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    BuildContext context,
    String message, {
    HikerCircleToastTone tone = HikerCircleToastTone.info,
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? onTap,
    Duration duration = defaultDuration,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);

    messenger.clearSnackBars();
    return messenger.showSnackBar(
      _HikerCircleToastSnackBar(
        message: message,
        tone: tone,
        title: title,
        actionLabel: actionLabel,
        onAction: onAction,
        onTap: onTap,
        duration: duration,
      ),
      snackBarAnimationStyle: reduceMotion
          ? AnimationStyle.noAnimation
          : _animationStyle,
    );
  }
}

class _HikerCircleToastSnackBar extends SnackBar {
  _HikerCircleToastSnackBar({
    required String message,
    required HikerCircleToastTone tone,
    required Duration duration,
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? onTap,
  }) : this._(
         message: message,
         tone: tone,
         duration: duration,
         title: title,
         actionLabel: actionLabel,
         onAction: onAction,
         onTap: onTap,
         animation: null,
       );

  _HikerCircleToastSnackBar._({
    super.key,
    required String message,
    required HikerCircleToastTone tone,
    required super.duration,
    required super.animation,
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? onTap,
  }) : _message = message,
       _tone = tone,
       _title = title,
       _actionLabel = actionLabel,
       _onAction = onAction,
       _onTap = onTap,
       _duration = duration,
       super(
         content: HikerCircleToastCard(
           message: message,
           tone: tone,
           title: title,
           actionLabel: actionLabel,
           onAction: onAction,
           onTap: onTap,
           animation: animation,
         ),
         behavior: SnackBarBehavior.floating,
         backgroundColor: Colors.transparent,
         elevation: 0,
         padding: EdgeInsets.zero,
         margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
         dismissDirection: DismissDirection.down,
         clipBehavior: Clip.none,
         showCloseIcon: false,
       );

  final String _message;
  final HikerCircleToastTone _tone;
  final String? _title;
  final String? _actionLabel;
  final VoidCallback? _onAction;
  final VoidCallback? _onTap;
  final Duration _duration;

  @override
  SnackBar withAnimation(Animation<double> newAnimation, {Key? fallbackKey}) {
    return _HikerCircleToastSnackBar._(
      key: key ?? fallbackKey,
      message: _message,
      tone: _tone,
      title: _title,
      actionLabel: _actionLabel,
      onAction: _onAction,
      onTap: _onTap,
      duration: _duration,
      animation: newAnimation,
    );
  }
}

/// The shared notice surface, also used by warnings whose lifetime is owned by
/// playback rather than ScaffoldMessenger's short snackbar timer.
class HikerCircleToastCard extends StatelessWidget {
  const HikerCircleToastCard({
    super.key,
    required this.message,
    this.tone = HikerCircleToastTone.info,
    this.title,
    this.actionLabel,
    this.onAction,
    this.onTap,
    this.animation,
    this.onDismiss,
  });

  final String message;
  final HikerCircleToastTone tone;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onTap;
  final Animation<double>? animation;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentFor(tone, isDark);
    final messenger = ScaffoldMessenger.of(context);

    void dismiss() {
      if (onDismiss != null) {
        onDismiss!();
      } else {
        messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss);
      }
    }

    void performAction() {
      onAction?.call();
      dismiss();
    }

    final surface = RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.14),
              blurRadius: 28,
              spreadRadius: -8,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: accent.withValues(alpha: isDark ? 0.17 : 0.1),
              blurRadius: 22,
              spreadRadius: -10,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            key: const ValueKey('hiker-circle-toast-glass'),
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap == null
                    ? null
                    : () {
                        onTap?.call();
                        dismiss();
                      },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              const Color(0xFF17221B).withValues(alpha: 0.94),
                              const Color(0xFF111915).withValues(alpha: 0.88),
                            ]
                          : [
                              Colors.white.withValues(alpha: 0.94),
                              const Color(0xFFF2F7F3).withValues(alpha: 0.88),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark
                          ? accent.withValues(alpha: 0.28)
                          : const Color(0xFFCFE5D6),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(13, 12, 8, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: accent.withValues(
                              alpha: isDark ? 0.22 : 0.12,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: accent.withValues(
                                alpha: isDark ? 0.38 : 0.2,
                              ),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Icon(_iconFor(tone), color: accent, size: 21),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title ?? _defaultTitle(tone),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                message,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                  letterSpacing: 0,
                                ),
                              ),
                              if (actionLabel != null && onAction != null) ...[
                                const SizedBox(height: 7),
                                TextButton.icon(
                                  key: const ValueKey(
                                    'hiker-circle-toast-action',
                                  ),
                                  onPressed: performAction,
                                  style: TextButton.styleFrom(
                                    foregroundColor: accent,
                                    minimumSize: const Size(0, 32),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  icon: const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 16,
                                  ),
                                  label: Text(actionLabel!),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('hiker-circle-toast-close'),
                          tooltip: 'Dismiss',
                          onPressed: dismiss,
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          color: colors.onSurfaceVariant,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final toast = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: surface,
      ),
    );
    final parentAnimation = animation;
    if (parentAnimation == null) return toast;

    final curvedAnimation = parentAnimation.drive(
      CurveTween(curve: const Cubic(0.22, 1, 0.36, 1)),
    );
    return SlideTransition(
      key: const ValueKey('hiker-circle-toast-slide'),
      position: Tween<Offset>(
        begin: const Offset(0, 1.15),
        end: Offset.zero,
      ).animate(curvedAnimation),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.28, end: 1).animate(curvedAnimation),
        child: toast,
      ),
    );
  }
}

Color _accentFor(HikerCircleToastTone tone, bool isDark) {
  return switch (tone) {
    HikerCircleToastTone.info =>
      isDark ? const Color(0xFF8BC8FF) : const Color(0xFF2474A8),
    HikerCircleToastTone.success =>
      isDark ? const Color(0xFF7AD69C) : const Color(0xFF3F8F5E),
    HikerCircleToastTone.warning =>
      isDark ? const Color(0xFFFBC65D) : const Color(0xFFD58400),
    HikerCircleToastTone.error =>
      isDark ? const Color(0xFFFF8A8A) : const Color(0xFFC43D3D),
  };
}

IconData _iconFor(HikerCircleToastTone tone) {
  return switch (tone) {
    HikerCircleToastTone.info => Icons.info_outline_rounded,
    HikerCircleToastTone.success => Icons.check_rounded,
    HikerCircleToastTone.warning => Icons.warning_amber_rounded,
    HikerCircleToastTone.error => Icons.error_outline_rounded,
  };
}

String _defaultTitle(HikerCircleToastTone tone) {
  return switch (tone) {
    HikerCircleToastTone.info => 'HikerCircle',
    HikerCircleToastTone.success => 'All set',
    HikerCircleToastTone.warning => 'Check this',
    HikerCircleToastTone.error => 'Something went wrong',
  };
}

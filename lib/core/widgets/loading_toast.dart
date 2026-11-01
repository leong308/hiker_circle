// HikerCircleLoadingToast widgets show bounded loading feedback; callers retain control of the
// underlying operation and timeout handling.
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';

const _minorLoadingAnimation = 'assets/animations/loading_spinner.json';
const _brandedAnimationScale = 2.0;
const _loadingLogo = 'assets/icons/HikerCircle-Loader-Transparent.png';

/// Resolves the animation's logo to its bundled key, independently of relative JSON image paths.
ImageProvider? _loadingImageProvider(LottieImageAsset asset) =>
    asset.id == 'hiker_circle_app_icon' ? const AssetImage(_loadingLogo) : null;

/// Compact loading motion for buttons, tiles, map callouts, and other places
/// where the full branded loading card cannot fit without obscuring content.
///
/// A non-null [value] remains a determinate Material progress ring because it
/// communicates measurable progress rather than an indeterminate wait.
class HikerCircleMinorLoadingIndicator extends StatelessWidget {
  /// Creates hiker circle minor loading indicator.
  const HikerCircleMinorLoadingIndicator({
    super.key,
    this.value,
    this.size = 36,
    this.strokeWidth = 4,
    this.strokeAlign = 0,
    this.color,
    this.backgroundColor,
    this.valueColor,
    this.semanticsLabel,
    this.semanticsValue,
  });

  /// Creates hiker circle minor loading indicator using adaptive.
  const HikerCircleMinorLoadingIndicator.adaptive({
    super.key,
    this.value,
    this.size = 36,
    this.strokeWidth = 4,
    this.strokeAlign = 0,
    this.color,
    this.backgroundColor,
    this.valueColor,
    this.semanticsLabel,
    this.semanticsValue,
  });

  final double? value;
  final double size;
  final double strokeWidth;
  final double strokeAlign;
  final Color? color;
  final Color? backgroundColor;
  final Animation<Color?>? valueColor;
  final String? semanticsLabel;
  final String? semanticsValue;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (value != null) {
      return CircularProgressIndicator(
        value: value,
        strokeWidth: strokeWidth,
        strokeAlign: strokeAlign,
        color: color,
        backgroundColor: backgroundColor,
        valueColor: valueColor,
        semanticsLabel: semanticsLabel,
        semanticsValue: semanticsValue,
      );
    }
    return Semantics(
      label: semanticsLabel ?? 'Loading',
      liveRegion: true,
      child: SizedBox.square(
        dimension: size,
        child: ExcludeSemantics(
          child: Transform.scale(
            scale: 2,
            child: Lottie.asset(
              _minorLoadingAnimation,
              fit: BoxFit.contain,
              repeat: true,
            ),
          ),
        ),
      ),
    );
  }
}

/// HikerCircle's shared loading treatment, based on SenzoCG's animated
/// loading animation. Its bundled image layer places the real app icon inside the moving document.
class HikerCircleLoadingToast extends StatefulWidget {
  /// Creates hiker circle loading toast.
  const HikerCircleLoadingToast({
    super.key,
    required this.message,
    this.detail = 'This may take a moment.',
    this.progress,
    this.compact = false,
  });

  final String message;
  final String detail;
  final ValueListenable<double>? progress;
  final bool compact;

  /// Creates the presentation state for this widget.
  @override
  State<HikerCircleLoadingToast> createState() =>
      _HikerCircleLoadingToastState();
}

/// Manages the hiker circle loading toast presentation and lifecycle.
class _HikerCircleLoadingToastState extends State<HikerCircleLoadingToast> {
  bool _showFileTransfer = false;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1B261F) : Colors.white;
    final text = isDark ? const Color(0xFFEAF4EE) : const Color(0xFF172019);
    final secondary = isDark
        ? const Color(0xFFA8B8AE)
        : const Color(0xFF66716A);
    final compact = widget.compact;

    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1)),
      child: Align(
        alignment: Alignment.center,
        widthFactor: 1,
        heightFactor: 1,
        child: Material(
          type: MaterialType.transparency,
          textStyle: Theme.of(
            context,
          ).textTheme.bodyMedium!.copyWith(decoration: TextDecoration.none),
          child: Semantics(
            liveRegion: true,
            label: widget.message,
            child: Container(
              key: const Key('hiker-circle-loading-toast'),
              constraints: BoxConstraints(maxWidth: compact ? 292 : 330),
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 20,
                compact ? 10 : 12,
                compact ? 16 : 20,
                compact ? 15 : 20,
              ),
              decoration: BoxDecoration(
                color: surface.withValues(alpha: 0.98),
                borderRadius: BorderRadius.circular(compact ? 17 : 21),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF33463A)
                      : const Color(0xFFE1E9E4),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x30000000),
                    blurRadius: 30,
                    offset: Offset(0, 13),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    key: const Key('hiker-circle-loading-animation'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      setState(() => _showFileTransfer = !_showFileTransfer);
                    },
                    child: SizedBox(
                      width: double.infinity,
                      height: compact ? 108 : 180,
                      child: _showFileTransfer
                          ? Image.asset(
                              'assets/animations/file_transfer.gif',
                              fit: BoxFit.contain,
                            )
                          : ClipRect(
                              child: Transform.scale(
                                key: const Key(
                                  'hiker-circle-loading-animation-scale',
                                ),
                                scale: _brandedAnimationScale,
                                child: Lottie.asset(
                                  'assets/animations/hiker_circle_loading.json',
                                  key: const Key(
                                    'hiker-circle-loading-branded-animation',
                                  ),
                                  fit: BoxFit.contain,
                                  repeat: true,
                                  imageProviderFactory: _loadingImageProvider,
                                ),
                              ),
                            ),
                    ),
                  ),
                  SizedBox(height: compact ? 4 : 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('⌛', style: TextStyle(fontSize: compact ? 16 : 19)),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          widget.message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: text,
                            fontSize: compact ? 14 : 16,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.detail.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.detail,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: secondary,
                        fontSize: compact ? 11 : 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                  SizedBox(height: compact ? 12 : 17),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: widget.progress == null
                        ? LinearProgressIndicator(
                            key: const Key('hiker-circle-loading-progress'),
                            minHeight: compact ? 5 : 7,
                            color: const Color(0xFF49A86C),
                            backgroundColor: isDark
                                ? const Color(0xFF31483A)
                                : const Color(0xFFD9EFE1),
                          )
                        : ValueListenableBuilder<double>(
                            valueListenable: widget.progress!,
                            builder: (context, value, child) {
                              return LinearProgressIndicator(
                                key: const Key('hiker-circle-loading-progress'),
                                value: value.clamp(0, 1),
                                minHeight: compact ? 5 : 7,
                                color: const Color(0xFF49A86C),
                                backgroundColor: isDark
                                    ? const Color(0xFF31483A)
                                    : const Color(0xFFD9EFE1),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bounded loading dialog with its own Material text and blocked interactive dismissal.
class HikerCircleLoadingDialog extends StatelessWidget {
  /// Keeps modal loading cards separate from inline loading views and overlays.
  const HikerCircleLoadingDialog({
    super.key,
    required this.message,
    this.detail = 'This may take a moment.',
    this.progress,
    this.compact = false,
  });
  final String message, detail;
  final ValueListenable<double>? progress;
  final bool compact;

  /// Centers a content-sized loading card instead of letting a route stretch it to the screen.
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: HikerCircleLoadingToast(
          message: message,
          detail: detail,
          progress: progress,
          compact: compact,
        ),
      ),
    ),
  );
}

/// Owns one loading route so delayed cleanup cannot dismiss the review or another popup.
class HikerCircleLoadingDialogRoute extends DialogRoute<void> {
  /// Presents the same bounded branded loading treatment from every modal entry point.
  HikerCircleLoadingDialogRoute({
    required super.context,
    required String message,
    String detail = 'This may take a moment.',
    ValueListenable<double>? progress,
    bool compact = false,
  }) : super(
         barrierDismissible: false,
         builder: (_) => HikerCircleLoadingDialog(
           message: message,
           detail: detail,
           progress: progress,
           compact: compact,
         ),
       );

  /// Removes only this route, including when another dialog has since opened above it.
  void close() {
    final owner = navigator;
    if (isActive && owner != null) owner.removeRoute(this);
  }
}

/// Displays the hiker circle loading view.
class HikerCircleLoadingView extends StatelessWidget {
  /// Creates hiker circle loading view.
  const HikerCircleLoadingView({
    super.key,
    required this.message,
    this.detail = 'This may take a moment.',
    this.progress,
    this.compact = false,
    this.padding = const EdgeInsets.all(24),
  });

  final String message;
  final String detail;
  final ValueListenable<double>? progress;
  final bool compact;
  final EdgeInsetsGeometry padding;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: HikerCircleLoadingToast(
          message: message,
          detail: detail,
          progress: progress,
          compact: compact,
        ),
      ),
    );
  }
}

/// Displays the hiker circle loading toast overlay.
class HikerCircleLoadingToastOverlay extends StatefulWidget {
  /// Creates hiker circle loading toast overlay.
  const HikerCircleLoadingToastOverlay({
    super.key,
    required this.message,
    this.detail = 'This may take a moment.',
    this.progress,
    this.dimBackground = true,
    this.compact = false,
    this.timeout = Duration.zero,
    this.onTimeout,
  });

  final String message;
  final String detail;
  final ValueListenable<double>? progress;
  final bool dimBackground;
  final bool compact;

  /// Optional watchdog. A zero duration keeps the overlay until its owner
  /// removes it, while a positive duration invokes [onTimeout].
  final Duration timeout;
  final VoidCallback? onTimeout;

  /// Creates the presentation state for this widget.
  @override
  State<HikerCircleLoadingToastOverlay> createState() =>
      _HikerCircleLoadingToastOverlayState();
}

/// Manages the hiker circle loading toast overlay presentation and lifecycle.
class _HikerCircleLoadingToastOverlayState
    extends State<HikerCircleLoadingToastOverlay> {
  Timer? _timeoutTimer;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _scheduleTimeout();
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(HikerCircleLoadingToastOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeout != widget.timeout ||
        oldWidget.onTimeout != widget.onTimeout) {
      _scheduleTimeout();
    }
  }

  /// Computes schedule timeout.
  void _scheduleTimeout() {
    _timeoutTimer?.cancel();
    if (widget.timeout <= Duration.zero || widget.onTimeout == null) return;
    _timeoutTimer = Timer(widget.timeout, () {
      if (mounted) widget.onTimeout!.call();
    });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: AbsorbPointer(
          child: ColoredBox(
            color: widget.dimBackground
                ? const Color(0x66000000)
                : Colors.transparent,
            child: HikerCircleLoadingView(
              message: widget.message,
              detail: widget.detail,
              progress: widget.progress,
              compact: widget.compact,
            ),
          ),
        ),
      ),
    );
  }
}

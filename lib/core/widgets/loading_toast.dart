import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:lottie/lottie.dart';

/// HikerCircle's shared loading treatment, based on SenzoCG's animated
/// [LoadingToast]. The original animation's SENZO text layer is replaced at
/// render time so the animation remains reusable and carries HikerCircle's
/// name instead.
class HikerCircleLoadingToast extends StatefulWidget {
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

  @override
  State<HikerCircleLoadingToast> createState() =>
      _HikerCircleLoadingToastState();
}

class _HikerCircleLoadingToastState extends State<HikerCircleLoadingToast> {
  bool _showFileTransfer = false;

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
              color: isDark ? const Color(0xFF33463A) : const Color(0xFFE1E9E4),
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
                  height: compact ? 72 : 180,
                  child: _showFileTransfer
                      ? Image.asset(
                          'assets/animations/file_transfer.gif',
                          fit: BoxFit.contain,
                        )
                      : Lottie.asset(
                          'assets/animations/hiker_circle_loading.json',
                          fit: BoxFit.contain,
                          repeat: true,
                          delegates: LottieDelegates(
                            text: (initialText) => initialText == 'SENZO'
                                ? 'HIKER CIRCLE'
                                : initialText,
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
    );
  }
}

class HikerCircleLoadingView extends StatelessWidget {
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

class HikerCircleLoadingToastOverlay extends StatelessWidget {
  const HikerCircleLoadingToastOverlay({
    super.key,
    required this.message,
    this.detail = 'This may take a moment.',
    this.progress,
    this.dimBackground = true,
    this.compact = false,
  });

  final String message;
  final String detail;
  final ValueListenable<double>? progress;
  final bool dimBackground;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: dimBackground ? const Color(0x66000000) : Colors.transparent,
          child: HikerCircleLoadingView(
            message: message,
            detail: detail,
            progress: progress,
            compact: compact,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

class HikerCircleLoadingToast extends StatelessWidget {
  const HikerCircleLoadingToast({
    super.key,
    required this.message,
    this.detail = 'This may take a moment.',
  });

  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1B261F) : Colors.white;
    final text = isDark ? const Color(0xFFEAF4EE) : const Color(0xFF111111);
    final secondary = isDark
        ? const Color(0xFFA8B8AE)
        : const Color(0xFF6E6E73);

    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1)),
      child: Semantics(
        liveRegion: true,
        label: message,
        child: Container(
          key: const Key('hiker-circle-loading-toast'),
          constraints: const BoxConstraints(maxWidth: 310),
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          decoration: BoxDecoration(
            color: surface.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? const Color(0xFF324439) : const Color(0xFFE2E8E4),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF34A853),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: text,
                  fontSize: 15,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (detail.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: secondary, fontSize: 12, height: 1.3),
                ),
              ],
            ],
          ),
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
    this.dimBackground = true,
  });

  final String message;
  final String detail;
  final bool dimBackground;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: dimBackground ? const Color(0x26000000) : Colors.transparent,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: HikerCircleLoadingToast(message: message, detail: detail),
            ),
          ),
        ),
      ),
    );
  }
}

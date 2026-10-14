import 'package:flutter/material.dart';

import '../../core/widgets/app_toast.dart';
import '../ModelView/active_hike_precaution_announcer.dart';

/// Lives inside the hike's page, above its bottom bar and below modal safety UI.
class ActiveHikePrecautionNoticeView extends StatelessWidget {
  const ActiveHikePrecautionNoticeView({super.key, required this.announcer});
  final ActiveHikePrecautionAnnouncer announcer;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: announcer,
    builder: (context, _) {
      final notice = announcer.notice;
      if (notice == null) return const SizedBox.shrink();
      return LayoutBuilder(
        builder: (context, constraints) {
          final padding = MediaQuery.paddingOf(context);
          return Stack(
            children: [
              Positioned(
                left: 16,
                right: 16,
                bottom: padding.bottom + 16,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 540,
                      maxHeight: (constraints.maxHeight - padding.vertical - 32)
                          .clamp(80, 540),
                    ),
                    child: SingleChildScrollView(
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey(notice.requestId),
                        tween: Tween(begin: 0, end: 1),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 360),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) => Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, (1 - value) * 24),
                            child: child,
                          ),
                        ),
                        child: HikerCircleToastCard(
                          title: 'Hike precautions',
                          message: notice.message,
                          onDismiss: announcer.dismiss,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

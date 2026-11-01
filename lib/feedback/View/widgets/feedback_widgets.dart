import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../Model/feedback_report.dart';

/// Shared surfaces keep both feedback pages aligned with Profile settings.
abstract final class FeedbackStyle {
  /// Uses the same page background in light and dark appearances.
  static Color background(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF0C120F)
      : const Color(0xFFF2F2F7);
}

/// Provides a rounded Material surface with visible ink feedback for actions.
class FeedbackSurface extends StatelessWidget {
  /// Creates an inset card, optionally used as a navigable report row.
  const FeedbackSurface({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Preserves readable borders and tap effects in either theme.
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.65),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: onTap == null
        ? Padding(padding: padding, child: child)
        : InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
  );
}

/// Uses the same soft green icon tile as HikerCircle's other settings pages.
class FeedbackGlyph extends StatelessWidget {
  /// Creates the icon corresponding to an existing report category.
  const FeedbackGlyph({super.key, required this.kind});
  final FeedbackReportKind kind;

  /// Keeps category icons clear without adding category pills.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        switch (kind) {
          FeedbackReportKind.problem => Icons.bug_report_outlined,
          FeedbackReportKind.suggestion => Icons.lightbulb_outline_rounded,
          FeedbackReportKind.other => Icons.chat_bubble_outline_rounded,
        },
        color: colors.primary,
        size: 22,
      ),
    );
  }
}

/// Displays review state as quiet text and an icon rather than a chip.
class FeedbackStatusLabel extends StatelessWidget {
  /// Creates one status label for the inbox or selected report.
  const FeedbackStatusLabel({super.key, required this.status});
  final String status;

  /// Uses distinct icons while keeping resolved reports visually subdued.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = status == 'New' ? colors.primary : colors.onSurfaceVariant;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                switch (status) {
                  'New' => Icons.mark_email_unread_outlined,
                  'In review' => Icons.schedule_rounded,
                  'Resolved' => Icons.check_circle_outline_rounded,
                  _ => Icons.info_outline_rounded,
                },
                size: 14,
                color: color,
              ),
            ),
          ),
          TextSpan(text: status),
        ],
      ),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Gives loading failures and empty inboxes the same card treatment as reports.
class FeedbackStateCard extends StatelessWidget {
  /// Creates a concise state message with an optional retry action.
  const FeedbackStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  /// Lets state copy grow naturally at larger accessibility sizes.
  @override
  Widget build(BuildContext context) => FeedbackSurface(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ],
    ),
  );
}

/// Presents the message first and keeps category, status and date secondary.
class FeedbackReportTile extends StatelessWidget {
  /// Creates a report row using its existing navigation callback.
  const FeedbackReportTile({
    super.key,
    required this.report,
    required this.onTap,
  });
  final FeedbackReport report;
  final VoidCallback onTap;

  /// Uses flexible rows so messages and metadata wrap on narrow screens.
  @override
  Widget build(BuildContext context) => FeedbackSurface(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FeedbackGlyph(kind: report.kind),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 5,
                    children: [
                      Text(
                        report.category,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      FeedbackStatusLabel(status: report.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    report.message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            Text(
              feedbackDisplayDate(context, report.submittedAt),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (report.screenshotPath.isNotEmpty)
              Text.rich(
                const TextSpan(
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.image_outlined, size: 14),
                      ),
                    ),
                    TextSpan(text: 'Screenshot attached'),
                  ],
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

/// Keeps report information aligned without using editable-looking fields.
class FeedbackInfoRow extends StatelessWidget {
  /// Creates one label/value row for platform or submission time.
  const FeedbackInfoRow({super.key, required this.label, required this.value});
  final String label;
  final String value;

  /// Stacks long values at large text sizes rather than squeezing them.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final caption = Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
        final detail = Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        );
        if (constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(14) > 19) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [caption, const SizedBox(height: 4), detail],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 90, child: caption),
            const SizedBox(width: 14),
            Expanded(child: detail),
          ],
        );
      },
    ),
  );
}

/// Uses the same date/time formatter on report cards and details.
String feedbackDisplayDate(BuildContext context, DateTime? date) {
  if (date == null) return 'Submission time unavailable';
  final local = MaterialLocalizations.of(context);
  return '${local.formatMediumDate(date)} · ${local.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
}

/// Shows the attachment as an image while preserving its existing zoom support.
class FeedbackScreenshot extends StatelessWidget {
  /// Receives already-authorized bytes without exposing their storage path.
  const FeedbackScreenshot({
    super.key,
    required this.bytes,
    required this.onRetry,
  });
  final Uint8List bytes;
  final VoidCallback onRetry;

  /// Gives an unreadable attachment its own retry action.
  Widget _invalid(BuildContext context, Object error, StackTrace? stack) =>
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 8),
              const Text(
                'Screenshot could not be displayed.',
                textAlign: TextAlign.center,
              ),
              TextButton.icon(
                onPressed: () {
                  if (ModalRoute.of(context) is PopupRoute) {
                    Navigator.of(context).pop();
                  }
                  onRetry();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reload screenshot'),
              ),
            ],
          ),
        ),
      );

  /// Opens a larger view without downloading or sharing the report elsewhere.
  Future<void> _enlarge(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Screenshot',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close screenshot',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: _invalid,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );

  /// Keeps the preview bounded while providing an explicit enlargement action.
  @override
  Widget build(BuildContext context) => FeedbackSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 280,
            child: InteractiveViewer(
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                errorBuilder: _invalid,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const ValueKey('enlarge-feedback-screenshot'),
          onPressed: () => _enlarge(context),
          icon: const Icon(Icons.open_in_full_rounded, size: 18),
          label: const Text('View screenshot'),
        ),
      ],
    ),
  );
}

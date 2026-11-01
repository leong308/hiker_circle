import 'package:flutter/material.dart';

import '../../Model/hike_reminder_timeline.dart';

/// Shows the current time, reminder slots and hike start on one vertical line.
class HikeReminderTimeline extends StatefulWidget {
  /// Creates a timeline whose longer reminder list can scroll between anchors.
  const HikeReminderTimeline({
    super.key,
    required this.entries,
    required this.timeZoneLabel,
    required this.hint,
  });

  final List<HikeReminderTimelineEntry> entries;
  final String timeZoneLabel;
  final String hint;

  /// Creates the scroll-controller lifecycle.
  @override
  State<HikeReminderTimeline> createState() => _HikeReminderTimelineState();
}

/// Owns only the timeline's scrolling presentation.
class _HikeReminderTimelineState extends State<HikeReminderTimeline> {
  final _scrollController = ScrollController();

  /// Releases the reminder list's scroll controller.
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Keeps both anchors visible even when there are many reminder slots.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final reminders = widget.entries
        .where((entry) => entry.kind == HikeReminderTimelineKind.reminder)
        .toList();
    final scrolls = reminders.length > 5;
    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final entry in reminders) _TimelineRow(entry: entry)],
    );
    return Container(
      key: const ValueKey('hike-reminder-timeline'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reminder timeline',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${reminders.length} reminder${reminders.length == 1 ? '' : 's'} planned',
            style: text.bodyMedium?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.timeZoneLabel,
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          _TimelineRow(entry: widget.entries.first, first: true),
          if (scrolls)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  key: const ValueKey('reminder-timeline-slots'),
                  controller: _scrollController,
                  child: rows,
                ),
              ),
            )
          else
            rows,
          if (scrolls)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 9),
                child: SizedBox(
                  width: 2,
                  height: 12,
                  child: ColoredBox(
                    color: colors.primary.withValues(alpha: 0.24),
                  ),
                ),
              ),
            ),
          _TimelineRow(entry: widget.entries.last, last: true),
          if (scrolls) ...[
            const SizedBox(height: 8),
            Text(
              'Scroll to see all reminders',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            widget.hint,
            style: text.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          if (reminders.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Past reminders are skipped. Delivery may take a few minutes.',
              style: text.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Draws a flexible-height point and the connecting line beside its labels.
class _TimelineRow extends StatelessWidget {
  /// Creates a row, optionally ending the line at either timeline anchor.
  const _TimelineRow({
    required this.entry,
    this.first = false,
    this.last = false,
  });

  final HikeReminderTimelineEntry entry;
  final bool first;
  final bool last;

  /// Lets long times and larger text wrap without displacing the timeline line.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isStart = entry.kind == HikeReminderTimelineKind.start;
    final isNow = entry.kind == HikeReminderTimelineKind.now;
    return Stack(
      children: [
        if (!first || !last)
          Positioned(
            left: 9,
            top: first ? 10 : 0,
            bottom: last ? null : 0,
            height: last ? 10 : null,
            width: 2,
            child: ColoredBox(color: colors.primary.withValues(alpha: 0.24)),
          ),
        Padding(
          padding: EdgeInsets.only(left: 34, right: 8, bottom: last ? 0 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title,
                style: text.labelLarge?.copyWith(
                  color: isNow || isStart
                      ? colors.primary
                      : colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                entry.timeLabel,
                style: text.bodyLarge?.copyWith(
                  fontWeight: isStart ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              if (entry.detail != null) ...[
                const SizedBox(height: 2),
                Text(
                  entry.detail!,
                  style: text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          left: 0,
          top: 1,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isStart || isNow ? colors.primary : colors.surface,
              border: Border.all(color: colors.primary, width: 2),
            ),
            child: isStart
                ? Icon(Icons.flag_rounded, size: 12, color: colors.onPrimary)
                : isNow
                ? Icon(Icons.circle, size: 7, color: colors.onPrimary)
                : null,
          ),
        ),
      ],
    );
  }
}

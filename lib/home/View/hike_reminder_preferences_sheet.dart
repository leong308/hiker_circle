// HikeReminderPreferencesEditor edits reminder offsets and previews their scheduled times.
import 'dart:async';

import 'package:flutter/material.dart';

import '../Model/hike_session_models.dart';

/// Shows hike reminder preferences sheet.
Future<HikeReminderPreference?> showHikeReminderPreferencesSheet(
  BuildContext context, {
  required String hikeName,
  required DateTime departureTime,
  HikeReminderPreference initialPreference = const HikeReminderPreference(),
}) {
  return showModalBottomSheet<HikeReminderPreference>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => _HikeReminderPreferencesSheet(
      hikeName: hikeName,
      departureTime: departureTime,
      initialPreference: initialPreference,
    ),
  );
}

/// Keep the edited offsets and reminder preview attached to the selected hike's departure time.
class HikeReminderPreferencesEditor extends StatefulWidget {
  /// Creates hike reminder preferences editor.
  const HikeReminderPreferencesEditor({
    super.key,
    required this.preference,
    required this.departureTime,
    required this.onChanged,
    this.now,
  });

  final HikeReminderPreference preference;
  final DateTime departureTime;
  final ValueChanged<HikeReminderPreference> onChanged;
  final DateTime Function()? now;

  /// Creates the presentation state for this widget.
  @override
  State<HikeReminderPreferencesEditor> createState() =>
      _HikeReminderPreferencesEditorState();
}

/// Manages the hike reminder preferences editor presentation and lifecycle.
class _HikeReminderPreferencesEditorState
    extends State<HikeReminderPreferencesEditor> {
  late final Timer _clock;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final now = (widget.now ?? DateTime.now)();
    final firstOptions = HikeReminderPreference.availableFirstReminders(
      widget.departureTime,
      now,
    );
    final value = widget.preference.fitToDeparture(widget.departureTime, now);
    final repeatOptions = HikeReminderPreference.repeatIntervalOptions.where(
      (minutes) =>
          minutes == 0 ||
          value.firstReminderMinutesBefore - minutes >=
              value.finalReminderMinutesBefore,
    );
    final capacity = value.repeatIntervalMinutes == 0
        ? 1
        : (value.firstReminderMinutesBefore -
                      value.finalReminderMinutesBefore) ~/
                  value.repeatIntervalMinutes +
              1;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: colors.primaryContainer.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile.adaptive(
            value: value.enabled,
            onChanged: firstOptions.isEmpty
                ? null
                : (enabled) =>
                      widget.onChanged(value.copyWith(enabled: enabled)),
            secondary: Icon(
              value.enabled
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_rounded,
              color: colors.primary,
            ),
            title: const Text(
              'Departure reminders',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              firstOptions.isEmpty
                  ? 'No future reminder time remains before departure.'
                  : value.enabled
                  ? 'Only your reminders for this hike are changed.'
                  : 'You will not receive departure reminders for this hike.',
            ),
          ),
        ),
        if (value.enabled) ...[
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            key: ValueKey('first-${value.firstReminderMinutesBefore}'),
            initialValue: value.firstReminderMinutesBefore,
            decoration: const InputDecoration(
              labelText: 'First reminder',
              prefixIcon: Icon(Icons.schedule_rounded),
            ),
            items: [
              for (final minutes in firstOptions)
                DropdownMenuItem(
                  value: minutes,
                  child: Text('${_durationLabel(minutes)} before'),
                ),
            ],
            onChanged: (minutes) {
              if (minutes == null) return;
              widget.onChanged(
                value.copyWith(firstReminderMinutesBefore: minutes),
              );
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey('repeat-${value.repeatIntervalMinutes}'),
            initialValue: value.repeatIntervalMinutes,
            decoration: const InputDecoration(
              labelText: 'Frequency',
              prefixIcon: Icon(Icons.repeat_rounded),
            ),
            items: [
              for (final minutes in repeatOptions)
                DropdownMenuItem(
                  value: minutes,
                  child: Text(
                    minutes == 0
                        ? 'Once only'
                        : 'Repeat every ${_durationLabel(minutes)}',
                  ),
                ),
            ],
            onChanged: (minutes) {
              if (minutes == null) return;
              widget.onChanged(
                value.copyWith(
                  repeatIntervalMinutes: minutes,
                  maximumReminders:
                      value.repeatIntervalMinutes == 0 && minutes > 0
                      ? 4
                      : value.maximumReminders,
                ),
              );
            },
          ),
          if (value.repeatIntervalMinutes > 0) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey('stop-${value.finalReminderMinutesBefore}'),
              initialValue: value.finalReminderMinutesBefore,
              decoration: const InputDecoration(
                labelText: 'Stop repeating',
                prefixIcon: Icon(Icons.timer_off_outlined),
              ),
              items: [
                for (final minutes
                    in HikeReminderPreference.finalReminderOptions.where(
                      (minutes) =>
                          minutes <=
                          value.firstReminderMinutesBefore -
                              value.repeatIntervalMinutes,
                    ))
                  DropdownMenuItem(
                    value: minutes,
                    child: Text('${_durationLabel(minutes)} before departure'),
                  ),
              ],
              onChanged: (minutes) {
                if (minutes == null) return;
                widget.onChanged(
                  value.copyWith(finalReminderMinutesBefore: minutes),
                );
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey('maximum-${value.maximumReminders}'),
              initialValue: value.maximumReminders,
              decoration: const InputDecoration(
                labelText: 'Maximum reminders',
                prefixIcon: Icon(Icons.format_list_numbered_rounded),
              ),
              items: [
                for (final count
                    in HikeReminderPreference.maximumReminderOptions.where(
                      (count) => count <= capacity,
                    ))
                  DropdownMenuItem(
                    value: count,
                    child: Text('$count reminder${count == 1 ? '' : 's'}'),
                  ),
              ],
              onChanged: (count) {
                if (count == null) return;
                widget.onChanged(value.copyWith(maximumReminders: count));
              },
            ),
          ],
          const SizedBox(height: 14),
          _ReminderPreview(
            preference: value,
            departureTime: widget.departureTime,
            now: now,
          ),
        ],
      ],
    );
  }
}

/// Displays the hike reminder preferences sheet.
class _HikeReminderPreferencesSheet extends StatefulWidget {
  /// Creates hike reminder preferences sheet.
  const _HikeReminderPreferencesSheet({
    required this.hikeName,
    required this.departureTime,
    required this.initialPreference,
  });

  final String hikeName;
  final DateTime departureTime;
  final HikeReminderPreference initialPreference;

  /// Creates the presentation state for this widget.
  @override
  State<_HikeReminderPreferencesSheet> createState() =>
      _HikeReminderPreferencesSheetState();
}

/// Manages the hike reminder preferences sheet presentation and lifecycle.
class _HikeReminderPreferencesSheetState
    extends State<_HikeReminderPreferencesSheet> {
  late HikeReminderPreference _preference;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _preference = widget.initialPreference.normalized();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          18,
          2,
          18,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Set your hike reminders',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              widget.hikeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            HikeReminderPreferencesEditor(
              preference: _preference,
              departureTime: widget.departureTime,
              onChanged: (value) => setState(() => _preference = value),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Not now'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(
                      _preference.fitToDeparture(
                        widget.departureTime,
                        DateTime.now(),
                      ),
                    ),
                    icon: const Icon(Icons.notifications_active_rounded),
                    label: const Text('Save reminders'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the reminder preview.
class _ReminderPreview extends StatelessWidget {
  /// Creates reminder preview.
  const _ReminderPreview({
    required this.preference,
    required this.departureTime,
    required this.now,
  });

  final HikeReminderPreference preference;
  final DateTime departureTime;
  final DateTime now;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final times = preference.scheduledTimes(departureTime, after: now);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${times.length} reminder${times.length == 1 ? '' : 's'} scheduled',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            times.isEmpty
                ? 'No reminder will be sent before this departure time.'
                : times.map(_dateTimeLabel).join('  •  '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            'Times adjust to the time left before departure. Missed reminders are skipped. Delivery may take a few minutes.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Computes duration label.
String _durationLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  if (minutes % 60 == 0) {
    final hours = minutes ~/ 60;
    return '$hours hour${hours == 1 ? '' : 's'}';
  }
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

/// Computes date time label.
String _dateTimeLabel(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.day}/${local.month} $hour:$minute $period';
}

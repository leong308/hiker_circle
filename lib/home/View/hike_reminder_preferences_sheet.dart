import 'package:flutter/material.dart';

import '../Model/hike_session_models.dart';

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

class HikeReminderPreferencesEditor extends StatelessWidget {
  const HikeReminderPreferencesEditor({
    super.key,
    required this.preference,
    required this.departureTime,
    required this.onChanged,
  });

  final HikeReminderPreference preference;
  final DateTime departureTime;
  final ValueChanged<HikeReminderPreference> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = preference.normalized();
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
            onChanged: (enabled) => onChanged(value.copyWith(enabled: enabled)),
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
              value.enabled
                  ? 'Only your reminders for this hike are changed.'
                  : 'You will not receive departure reminders for this hike.',
            ),
          ),
        ),
        if (value.enabled) ...[
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            initialValue: value.firstReminderMinutesBefore,
            decoration: const InputDecoration(
              labelText: 'First reminder',
              prefixIcon: Icon(Icons.schedule_rounded),
            ),
            items: [
              for (final minutes in HikeReminderPreference.firstReminderOptions)
                DropdownMenuItem(
                  value: minutes,
                  child: Text('${_durationLabel(minutes)} before'),
                ),
            ],
            onChanged: (minutes) {
              if (minutes == null) return;
              onChanged(value.copyWith(firstReminderMinutesBefore: minutes));
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: value.repeatIntervalMinutes,
            decoration: const InputDecoration(
              labelText: 'Frequency',
              prefixIcon: Icon(Icons.repeat_rounded),
            ),
            items: [
              for (final minutes
                  in HikeReminderPreference.repeatIntervalOptions)
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
              onChanged(value.copyWith(repeatIntervalMinutes: minutes));
            },
          ),
          if (value.repeatIntervalMinutes > 0) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: value.finalReminderMinutesBefore,
              decoration: const InputDecoration(
                labelText: 'Stop repeating',
                prefixIcon: Icon(Icons.timer_off_outlined),
              ),
              items: [
                for (final minutes
                    in HikeReminderPreference.finalReminderOptions)
                  DropdownMenuItem(
                    value: minutes,
                    child: Text('${_durationLabel(minutes)} before departure'),
                  ),
              ],
              onChanged: (minutes) {
                if (minutes == null) return;
                onChanged(value.copyWith(finalReminderMinutesBefore: minutes));
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: value.maximumReminders,
              decoration: const InputDecoration(
                labelText: 'Maximum reminders',
                prefixIcon: Icon(Icons.format_list_numbered_rounded),
              ),
              items: [
                for (final count
                    in HikeReminderPreference.maximumReminderOptions)
                  DropdownMenuItem(
                    value: count,
                    child: Text('$count reminder${count == 1 ? '' : 's'}'),
                  ),
              ],
              onChanged: (count) {
                if (count == null) return;
                onChanged(value.copyWith(maximumReminders: count));
              },
            ),
          ],
          const SizedBox(height: 14),
          _ReminderPreview(preference: value, departureTime: departureTime),
        ],
      ],
    );
  }
}

class _HikeReminderPreferencesSheet extends StatefulWidget {
  const _HikeReminderPreferencesSheet({
    required this.hikeName,
    required this.departureTime,
    required this.initialPreference,
  });

  final String hikeName;
  final DateTime departureTime;
  final HikeReminderPreference initialPreference;

  @override
  State<_HikeReminderPreferencesSheet> createState() =>
      _HikeReminderPreferencesSheetState();
}

class _HikeReminderPreferencesSheetState
    extends State<_HikeReminderPreferencesSheet> {
  late HikeReminderPreference _preference;

  @override
  void initState() {
    super.initState();
    _preference = widget.initialPreference.normalized();
  }

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
                    onPressed: () => Navigator.of(context).pop(_preference),
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

class _ReminderPreview extends StatelessWidget {
  const _ReminderPreview({
    required this.preference,
    required this.departureTime,
  });

  final HikeReminderPreference preference;
  final DateTime departureTime;

  @override
  Widget build(BuildContext context) {
    final times = _reminderTimes(preference, departureTime);
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
            'Reminder preview',
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
        ],
      ),
    );
  }
}

List<DateTime> _reminderTimes(
  HikeReminderPreference raw,
  DateTime departureTime,
) {
  final preference = raw.normalized();
  if (!preference.enabled) return const [];
  final result = <DateTime>[
    departureTime.subtract(
      Duration(minutes: preference.firstReminderMinutesBefore),
    ),
  ];
  if (preference.repeatIntervalMinutes <= 0) return result;
  final lastAllowed = departureTime.subtract(
    Duration(minutes: preference.finalReminderMinutesBefore),
  );
  while (result.length < preference.maximumReminders) {
    final next = result.last.add(
      Duration(minutes: preference.repeatIntervalMinutes),
    );
    if (next.isAfter(lastAllowed)) break;
    result.add(next);
  }
  return result;
}

String _durationLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  if (minutes % 60 == 0) {
    final hours = minutes ~/ 60;
    return '$hours hour${hours == 1 ? '' : 's'}';
  }
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

String _dateTimeLabel(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.day}/${local.month} $hour:$minute $period';
}

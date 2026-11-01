// HikeReminderPreferencesEditor edits reminder offsets and previews their scheduled times.
import 'package:flutter/material.dart';

import '../Model/hike_session_models.dart';
import '../Model/hike_reminder_timeline.dart';
import '../ModelView/hike_reminder_preferences_view_model.dart';
import 'widgets/hike_reminder_timeline.dart';

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
  late final HikeReminderPreferencesViewModel _viewModel;

  /// Binds reminder calculations and their clock to this editor's lifecycle.
  @override
  void initState() {
    super.initState();
    _viewModel = HikeReminderPreferencesViewModel(
      preference: widget.preference,
      departureTime: widget.departureTime,
      now: widget.now,
    );
  }

  /// Follows changes from the containing wizard or reminder sheet.
  @override
  void didUpdateWidget(covariant HikeReminderPreferencesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _viewModel.updateInputs(
      preference: widget.preference,
      departureTime: widget.departureTime,
      now: widget.now,
    );
  }

  /// Releases the editor's clock and settings subscription.
  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  /// Renders only the first/frequency choices and their proposed timeline.
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final value = _viewModel.preference;
        final firstOptions = _viewModel.firstOptions;
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
                    : (enabled) => widget.onChanged(
                        _viewModel.select(value.copyWith(enabled: enabled)),
                      ),
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
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'First reminder',
                  prefixIcon: Icon(Icons.schedule_rounded),
                ),
                items: [
                  for (final minutes in firstOptions)
                    DropdownMenuItem(
                      value: minutes,
                      child: Text(
                        '${hikeReminderDurationLabel(minutes)} before',
                      ),
                    ),
                ],
                onChanged: (minutes) {
                  if (minutes == null) return;
                  widget.onChanged(
                    _viewModel.select(
                      value.copyWith(firstReminderMinutesBefore: minutes),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey('repeat-${value.repeatIntervalMinutes}'),
                initialValue: value.repeatIntervalMinutes,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Frequency',
                  prefixIcon: Icon(Icons.repeat_rounded),
                ),
                items: [
                  for (final minutes in _viewModel.repeatOptions)
                    DropdownMenuItem(
                      value: minutes,
                      child: Text(
                        minutes == 0
                            ? 'Once only'
                            : 'Every ${hikeReminderDurationLabel(minutes)}',
                      ),
                    ),
                ],
                onChanged: (minutes) {
                  if (minutes == null) return;
                  widget.onChanged(
                    _viewModel.select(
                      value.copyWith(repeatIntervalMinutes: minutes),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 14),
            HikeReminderTimeline(
              entries: _viewModel.timeline,
              timeZoneLabel: _viewModel.timeZoneLabel,
              hint: _viewModel.scheduleHint,
            ),
          ],
        );
      },
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

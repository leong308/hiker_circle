import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../Model/hike_arrival_timing.dart';
import '../../Model/hike_session_models.dart';

/// Presents a calculated earliest arrival and an editable latest arrival.
class HikeArrivalTimeFields extends StatelessWidget {
  /// Binds the arrival fields to the wizard's existing draft.
  const HikeArrivalTimeFields({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final HikeSessionDraft draft;
  final ValueChanged<HikeSessionDraft> onChanged;

  /// Includes the date for overnight arrivals so the displayed time is unambiguous.
  String _formatArrival(BuildContext context, DateTime arrival) {
    final localizations = MaterialLocalizations.of(context);
    final localArrival = arrival.toLocal();
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(localArrival),
    );
    return DateUtils.isSameDay(draft.departureTime.toLocal(), localArrival)
        ? time
        : '${localizations.formatShortDate(localArrival)} · $time';
  }

  /// Commits the date-and-time selection only when the hiker presses Done.
  Future<void> _pickLatestArrival(BuildContext context) async {
    final minimum = HikeArrivalTiming.minimumLatestArrival(draft).toLocal();
    final maximum = HikeArrivalTiming.maximumLatestArrival(draft).toLocal();
    if (minimum.isAfter(maximum)) return;
    var selected = draft.expectedReturnTime.isBefore(minimum)
        ? minimum
        : draft.expectedReturnTime.isAfter(maximum)
        ? maximum
        : draft.expectedReturnTime.toLocal();
    final result = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: 300,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Estimated Latest Time of Arrival',
                        style: Theme.of(sheetContext).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(selected),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.dateAndTime,
                  initialDateTime: selected,
                  minimumDate: minimum,
                  maximumDate: maximum,
                  use24hFormat: MediaQuery.alwaysUse24HourFormatOf(
                    sheetContext,
                  ),
                  onDateTimeChanged: (value) => selected = value,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null && context.mounted) {
      onChanged(HikeArrivalTiming.withLatestArrival(draft, result));
    }
  }

  /// Uses the wizard's existing field appearance and edit affordance.
  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );
    return Column(
      children: [
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Estimated Earliest Time of Arrival',
            prefixIcon: Icon(Icons.flag_rounded),
          ),
          child: Text(
            _formatArrival(context, draft.expectedArrivalTime),
            style: textStyle,
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _pickLatestArrival(context),
          borderRadius: BorderRadius.circular(4),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Estimated Latest Time of Arrival',
              prefixIcon: const Icon(Icons.schedule_rounded),
              suffixIcon: Icon(
                Icons.edit_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            child: Text(
              _formatArrival(context, draft.expectedReturnTime),
              style: textStyle,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'If recorded footprints do not confirm arrival at a saved peak or the trail end, you will be asked if you are okay. You have 5 minutes to respond before your emergency contacts are alerted. GPS and connectivity are needed to confirm arrival, cancel a cloud alert or notify contacts.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

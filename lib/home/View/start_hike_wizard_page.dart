import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../trail/Data/trail_repository.dart';
import '../../trail/Model/trail_models.dart';
import '../Model/hike_session_models.dart';

class StartHikeWizardPage extends StatefulWidget {
  const StartHikeWizardPage({
    super.key,
    this.preselectedTrail,
    this.trailRepository = const TrailRepository(),
  });

  final Trail? preselectedTrail;
  final TrailRepository trailRepository;

  @override
  State<StartHikeWizardPage> createState() => _StartHikeWizardPageState();
}

class _StartHikeWizardPageState extends State<StartHikeWizardPage> {
  static const int _lastStep = 4;
  static const List<String> _checklistItems = [
    'Drinking water',
    'Charged phone',
    'Power bank',
    'Torch',
    'First-aid kit',
    'Rain protection',
  ];

  late final List<Trail> _trails;
  late HikeSessionDraft _draft;
  int _stepIndex = 0;

  @override
  void initState() {
    super.initState();
    _trails = widget.trailRepository.loadTrails();
    final selectedTrail = _trails.firstWhere(
      (trail) => trail.trailId == widget.preselectedTrail?.trailId,
      orElse: () => _trails.first,
    );
    _draft = HikeSessionDraft.fromTrail(selectedTrail);
  }

  void _next() {
    if (_stepIndex == _lastStep) {
      Navigator.of(context).pop(ActiveHikeSession.fromDraft(_draft));
      return;
    }

    setState(() {
      _stepIndex += 1;
    });
  }

  void _back() {
    if (_stepIndex == 0) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _stepIndex -= 1;
    });
  }

  void _updateDraft(HikeSessionDraft draft) {
    setState(() {
      _draft = draft;
    });
  }

  @override
  Widget build(BuildContext context) {
    final step = _stepForIndex(_stepIndex);

    return Scaffold(
      backgroundColor: _WizardColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(onBack: _back),
                  const SizedBox(height: 16),
                  _StepProgress(currentStep: _stepIndex),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(key: ValueKey(_stepIndex), child: step),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _back,
                          child: Text(_stepIndex == 0 ? 'Cancel' : 'Back'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _next,
                          icon: Icon(
                            _stepIndex == _lastStep
                                ? Icons.play_arrow_rounded
                                : Icons.arrow_forward_rounded,
                          ),
                          label: Text(
                            _stepIndex == _lastStep
                                ? 'Start Hiking Session'
                                : 'Continue',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepForIndex(int index) {
    switch (index) {
      case 0:
        return _HikeTypeStep(draft: _draft, onChanged: _updateDraft);
      case 1:
        return _TrailSelectionStep(
          draft: _draft,
          trails: _trails,
          onChanged: _updateDraft,
        );
      case 2:
        return _TimingStep(draft: _draft, onChanged: _updateDraft);
      case 3:
        return _SafetySettingsStep(draft: _draft, onChanged: _updateDraft);
      default:
        return _PreparationStep(
          draft: _draft,
          checklistItems: _checklistItems,
          onChanged: _updateDraft,
        );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Tooltip(
          message: 'Back',
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(36),
            onPressed: onBack,
            child: const _CircleIcon(icon: CupertinoIcons.chevron_back),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create Hiking Session',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _WizardColors.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              Text(
                'Plan timing, safety, and offline preparation',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _WizardColors.secondaryText,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < 5; index++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 5,
              decoration: BoxDecoration(
                color: index <= currentStep
                    ? _WizardColors.green
                    : _WizardColors.separator,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          if (index != 4) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _HikeTypeStep extends StatelessWidget {
  const _HikeTypeStep({required this.draft, required this.onChanged});

  final HikeSessionDraft draft;
  final ValueChanged<HikeSessionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return _StepCard(
      title: 'Choose your hiking mode',
      subtitle: 'Select how this active session should behave.',
      children: [
        _ChoiceTile(
          selected: draft.hikeType == HikeType.solo,
          icon: Icons.person_pin_circle_rounded,
          title: 'Solo Hike',
          subtitle: 'Track your own route and optionally share location.',
          onTap: () => onChanged(draft.copyWith(hikeType: HikeType.solo)),
        ),
        const SizedBox(height: 10),
        _ChoiceTile(
          selected: draft.hikeType == HikeType.team,
          icon: Icons.groups_2_rounded,
          title: 'Team Hike',
          subtitle: 'Create a session for friends or join an existing group.',
          onTap: () => onChanged(draft.copyWith(hikeType: HikeType.team)),
        ),
      ],
    );
  }
}

class _TrailSelectionStep extends StatelessWidget {
  const _TrailSelectionStep({
    required this.draft,
    required this.trails,
    required this.onChanged,
  });

  final HikeSessionDraft draft;
  final List<Trail> trails;
  final ValueChanged<HikeSessionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    final checkpointNames = draft.trail.checkpoints
        .map((checkpoint) => checkpoint.name)
        .toList();

    return _StepCard(
      title: 'Select Trail',
      subtitle: 'Pick a verified trail or add custom checkpoints later.',
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: 'Search trail name or location...',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onSubmitted: (_) {},
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: draft.trail.trailId,
          decoration: const InputDecoration(labelText: 'Selected Trail'),
          items: [
            for (final trail in trails)
              DropdownMenuItem<String>(
                value: trail.trailId,
                child: Text(trail.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (trailId) {
            if (trailId == null) {
              return;
            }
            final nextTrail = trails.firstWhere(
              (trail) => trail.trailId == trailId,
            );
            onChanged(HikeSessionDraft.fromTrail(nextTrail));
          },
        ),
        const SizedBox(height: 12),
        _TrailSummary(trail: draft.trail),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: checkpointNames.contains(draft.startPointName)
              ? draft.startPointName
              : checkpointNames.first,
          decoration: const InputDecoration(labelText: 'Start Point'),
          items: [
            for (final checkpoint in checkpointNames)
              DropdownMenuItem<String>(
                value: checkpoint,
                child: Text(checkpoint),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              onChanged(draft.copyWith(startPointName: value));
            }
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: checkpointNames.contains(draft.destinationName)
              ? draft.destinationName
              : checkpointNames.last,
          decoration: const InputDecoration(labelText: 'Destination'),
          items: [
            for (final checkpoint in checkpointNames)
              DropdownMenuItem<String>(
                value: checkpoint,
                child: Text(checkpoint),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              onChanged(draft.copyWith(destinationName: value));
            }
          },
        ),
        const SizedBox(height: 14),
        _CheckpointList(checkpoints: draft.trail.checkpoints),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Manual checkpoint drafting will be added next.',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                ),
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Add Checkpoint'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Route preview uses the trail detail map.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                ),
                icon: const Icon(Icons.route_rounded),
                label: const Text('View Route'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TimingStep extends StatelessWidget {
  const _TimingStep({required this.draft, required this.onChanged});

  final HikeSessionDraft draft;
  final ValueChanged<HikeSessionDraft> onChanged;

  static const List<Duration> _checkInOptions = [
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(hours: 1),
  ];
  static const List<Duration> _recordingOptions = [
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
  ];

  @override
  Widget build(BuildContext context) {
    return _StepCard(
      title: 'Timing and Tracking',
      subtitle: 'Check-ins ask for confirmation; GPS recording runs quietly.',
      children: [
        _ReadOnlyField(
          label: 'Departure Date',
          value: _formatDate(draft.departureTime),
          icon: Icons.calendar_today_rounded,
        ),
        const SizedBox(height: 12),
        _ReadOnlyField(
          label: 'Departure Time',
          value: _formatTime(draft.departureTime),
          icon: Icons.schedule_rounded,
        ),
        const SizedBox(height: 12),
        _ReadOnlyField(
          label: 'Expected Arrival at Destination',
          value: _formatTime(draft.expectedArrivalTime),
          icon: Icons.flag_rounded,
        ),
        const SizedBox(height: 12),
        _ReadOnlyField(
          label: 'Expected Return Time',
          value: _formatTime(draft.expectedReturnTime),
          icon: Icons.assignment_return_rounded,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<Duration>(
          initialValue: draft.safetyCheckInInterval,
          decoration: const InputDecoration(
            labelText: 'Safety Check-In Interval',
            prefixIcon: Icon(Icons.verified_user_rounded),
          ),
          items: [
            for (final duration in _checkInOptions)
              DropdownMenuItem<Duration>(
                value: duration,
                child: Text('Every ${_durationLabel(duration)}'),
              ),
          ],
          onChanged: (duration) {
            if (duration != null) {
              onChanged(draft.copyWith(safetyCheckInInterval: duration));
            }
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<Duration>(
          initialValue: draft.locationRecordingInterval,
          decoration: const InputDecoration(
            labelText: 'Location Recording Interval',
            prefixIcon: Icon(Icons.my_location_rounded),
          ),
          items: [
            for (final duration in _recordingOptions)
              DropdownMenuItem<Duration>(
                value: duration,
                child: Text('Every ${_durationLabel(duration)}'),
              ),
          ],
          onChanged: (duration) {
            if (duration != null) {
              onChanged(draft.copyWith(locationRecordingInterval: duration));
            }
          },
        ),
      ],
    );
  }
}

class _SafetySettingsStep extends StatelessWidget {
  const _SafetySettingsStep({required this.draft, required this.onChanged});

  final HikeSessionDraft draft;
  final ValueChanged<HikeSessionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return _StepCard(
      title: 'Safety Settings',
      subtitle: 'Choose who receives updates and which monitors are active.',
      children: [
        _ContactsPreview(names: draft.emergencyContactNames),
        const SizedBox(height: 12),
        _SwitchRow(
          label: 'Live Location Sharing',
          value: draft.shareLiveLocation,
          onChanged: (value) =>
              onChanged(draft.copyWith(shareLiveLocation: value)),
        ),
        _SwitchRow(
          label: 'Fall and Stillness Detection',
          value: draft.fallDetectionEnabled,
          onChanged: (value) =>
              onChanged(draft.copyWith(fallDetectionEnabled: value)),
        ),
        _SwitchRow(
          label: 'Path Deviation Alert',
          value: draft.pathDeviationEnabled,
          onChanged: (value) =>
              onChanged(draft.copyWith(pathDeviationEnabled: value)),
        ),
        _SwitchRow(
          label: 'Offline Flash and Audio SOS',
          value: draft.offlinePhysicalAlertEnabled,
          onChanged: (value) =>
              onChanged(draft.copyWith(offlinePhysicalAlertEnabled: value)),
        ),
        _SwitchRow(
          label: 'Duress Silent SOS',
          value: draft.duressEnabled,
          onChanged: (value) => onChanged(draft.copyWith(duressEnabled: value)),
        ),
      ],
    );
  }
}

class _PreparationStep extends StatelessWidget {
  const _PreparationStep({
    required this.draft,
    required this.checklistItems,
    required this.onChanged,
  });

  final HikeSessionDraft draft;
  final List<String> checklistItems;
  final ValueChanged<HikeSessionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return _StepCard(
      title: 'Before You Start',
      subtitle: 'Confirm offline preparation and equipment before tracking.',
      children: [
        const _PreparationStatusList(),
        const SizedBox(height: 14),
        Text(
          'Equipment Checklist',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: _WizardColors.text,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        _ChecklistGroup(
          items: checklistItems,
          completedItems: draft.completedChecklistItems,
          onChanged: (item, selected) {
            final nextItems = Set<String>.of(draft.completedChecklistItems);
            if (selected == true) {
              nextItems.add(item);
            } else {
              nextItems.remove(item);
            }
            onChanged(draft.copyWith(completedChecklistItems: nextItems));
          },
        ),
        const SizedBox(height: 14),
        _ForecastCard(trail: draft.trail),
        const SizedBox(height: 14),
        const _StartupActionsCard(),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _WizardColors.text,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _WizardColors.secondaryText,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _WizardColors.green : _WizardColors.secondaryText;

    return Material(
      color: selected ? _WizardColors.greenSoft : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? _WizardColors.green : _WizardColors.separator,
            ),
          ),
          child: Row(
            children: [
              _Glyph(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _WizardColors.text,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _WizardColors.secondaryText,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: _WizardColors.green,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrailSummary extends StatelessWidget {
  const _TrailSummary({required this.trail});

  final Trail trail;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _WizardColors.greenSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trail.name,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _WizardColors.text,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${trail.locationLabel} - ${trail.distanceLabel} - ${trail.difficulty}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _WizardColors.secondaryText,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckpointList extends StatelessWidget {
  const _CheckpointList({required this.checkpoints});

  final List<TrailCheckpoint> checkpoints;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _WizardColors.separator),
      ),
      child: Column(
        children: [
          for (var index = 0; index < checkpoints.length; index++) ...[
            _StatusRow(
              label: '${checkpoints[index].order}. ${checkpoints[index].name}',
              value: 'Checkpoint',
            ),
            if (index != checkpoints.length - 1) const _HorizontalSeparator(),
          ],
        ],
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      child: Text(
        value,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: _WizardColors.text,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _ContactsPreview extends StatelessWidget {
  const _ContactsPreview({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _WizardColors.separator),
      ),
      child: Column(
        children: [
          for (var index = 0; index < names.length; index++) ...[
            _StatusRow(label: names[index], value: 'Receives SOS'),
            if (index != names.length - 1) const _HorizontalSeparator(),
          ],
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: _WizardColors.green,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: _WizardColors.text,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _PreparationStatusList extends StatelessWidget {
  const _PreparationStatusList();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _WizardColors.separator),
      ),
      child: const Column(
        children: [
          _StatusRow(label: 'Offline trail map', value: 'Downloaded'),
          _HorizontalSeparator(),
          _StatusRow(label: 'Weather forecast', value: 'Cached'),
          _HorizontalSeparator(),
          _StatusRow(label: 'Emergency numbers', value: 'Stored Offline'),
        ],
      ),
    );
  }
}

class _ChecklistGroup extends StatelessWidget {
  const _ChecklistGroup({
    required this.items,
    required this.completedItems,
    required this.onChanged,
  });

  final List<String> items;
  final Set<String> completedItems;
  final void Function(String item, bool? selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _WizardColors.separator),
      ),
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            CheckboxListTile(
              value: completedItems.contains(items[index]),
              onChanged: (value) => onChanged(items[index], value),
              dense: true,
              activeColor: _WizardColors.green,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                items[index],
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _WizardColors.text,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ),
            if (index != items.length - 1) const _HorizontalSeparator(),
          ],
        ],
      ),
    );
  }
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({required this.trail});

  final Trail trail;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _WizardColors.greenSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Forecast',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _WizardColors.text,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              trail.weather.summary,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _WizardColors.secondaryText,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Temperature: ${trail.weather.temperatureRange}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _WizardColors.secondaryText,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartupActionsCard extends StatelessWidget {
  const _StartupActionsCard();

  @override
  Widget build(BuildContext context) {
    const actions = [
      'Create hike session document',
      'Create local session record',
      'Load offline map file',
      'Begin periodic GPS recording',
      'Enable fall-and-stillness listener',
      'Enable check-in timer',
      'Start live location sharing when available',
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _WizardColors.separator),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'When session starts',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _WizardColors.text,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            for (final action in actions)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '- $action',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _WizardColors.secondaryText,
                    letterSpacing: 0,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _WizardColors.text,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _WizardColors.secondaryText,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: _WizardColors.green, size: 20),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, this.color = _WizardColors.green});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }
}

class _HorizontalSeparator extends StatelessWidget {
  const _HorizontalSeparator();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 0.7,
      color: _WizardColors.separator,
    );
  }
}

String _formatDate(DateTime dateTime) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${dateTime.day} ${months[dateTime.month - 1]} ${dateTime.year}';
}

String _formatTime(DateTime dateTime) {
  final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final period = dateTime.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

String _durationLabel(Duration duration) {
  if (duration.inMinutes < 60) {
    return '${duration.inMinutes} minutes';
  }
  return '${duration.inHours} hour';
}

abstract final class _WizardColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
}

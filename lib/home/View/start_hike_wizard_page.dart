import 'dart:async';
import 'dart:math' as math;

import 'package:animated_toggle_switch/animated_toggle_switch.dart';
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
      backgroundColor: _WizardColors.backgroundFor(context),
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
                  color: _WizardColors.textFor(context),
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              Text(
                'Plan timing, safety, and offline preparation',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _WizardColors.secondaryTextFor(context),
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
                    : _WizardColors.separatorFor(context),
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
      subtitle: 'Pick a verified trail and pin any extra checkpoints.',
      children: [
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
        _CheckpointList(
          checkpoints: draft.trail.checkpoints,
          onPreview: (checkpoint) =>
              _showCheckpointPreview(context, draft.trail, checkpoint),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _addCheckpoint(context),
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Add Checkpoint'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _viewRoute(context),
                icon: const Icon(Icons.route_rounded),
                label: const Text('View Route'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _addCheckpoint(BuildContext context) async {
    final checkpoint = await showModalBottomSheet<TrailCheckpoint>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: _WizardColors.surfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              6,
              18,
              18 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: _CheckpointPickerSheet(trail: draft.trail),
          ),
        );
      },
    );
    if (checkpoint == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    final deviationMeters = _distanceFromRouteMeters(
      draft.trail.checkpoints,
      checkpoint.latitude,
      checkpoint.longitude,
    );
    if (deviationMeters > 120) {
      final shouldAdd = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) {
          return CupertinoAlertDialog(
            title: const Text('Checkpoint Away From Route'),
            content: Text(
              'This pinned checkpoint is about ${deviationMeters.round()} m away from the obtained trail route. Add it anyway?',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Add Checkpoint'),
              ),
            ],
          );
        },
      );
      if (shouldAdd != true) {
        return;
      }
    }

    final checkpoints = [...draft.trail.checkpoints, checkpoint]
      ..sort((a, b) => a.order.compareTo(b.order));
    onChanged(
      draft.copyWith(
        trail: draft.trail.copyWith(checkpoints: checkpoints),
        destinationName: checkpoint.name,
      ),
    );
  }

  void _viewRoute(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: _WizardColors.surfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 22),
            child: _RoutePreviewSheet(trail: draft.trail),
          ),
        );
      },
    );
  }

  void _showCheckpointPreview(
    BuildContext context,
    Trail trail,
    TrailCheckpoint checkpoint,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(checkpoint.name),
          content: SizedBox(
            width: 320,
            height: 240,
            child: _CheckpointRouteMap(
              trail: trail,
              highlightedCheckpoint: checkpoint,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
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
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 3),
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
        _DurationPickerField(
          label: 'Expected Hours and Minutes Needed',
          value: draft.expectedArrivalTime.difference(draft.departureTime),
          onChanged: (duration) {
            final arrival = draft.departureTime.add(duration);
            onChanged(
              draft.copyWith(
                expectedArrivalTime: arrival,
                expectedReturnTime: arrival.add(const Duration(hours: 2)),
              ),
            );
          },
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
              if (duration < const Duration(minutes: 1)) {
                unawaited(_showFrequentRecordingWarning(context));
              }
              onChanged(draft.copyWith(locationRecordingInterval: duration));
            }
          },
        ),
      ],
    );
  }

  Future<void> _showFrequentRecordingWarning(BuildContext context) async {
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('Frequent GPS Recording'),
          content: const Text(
            'Recording below 1 minute can drain battery faster than usual, but it is recommended when you want stronger safety tracking.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}

class _SafetySettingsStep extends StatelessWidget {
  const _SafetySettingsStep({required this.draft, required this.onChanged});

  final HikeSessionDraft draft;
  final ValueChanged<HikeSessionDraft> onChanged;

  static const List<Duration> _responseCountdownOptions = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 3),
    Duration(minutes: 5),
  ];

  @override
  Widget build(BuildContext context) {
    final fallDetectionSettings = draft.fallDetectionSettings;

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
        _SensorSensitivitySlider(
          enabled: draft.fallDetectionEnabled,
          value: fallDetectionSettings.sensorSensitivity,
          label: fallDetectionSettings.sensitivityLabel,
          showFalseAlarmWarning: fallDetectionSettings.isHighSensitivity,
          onChanged: (value) {
            onChanged(
              draft.copyWith(
                fallDetectionSettings: FallDetectionSettings(
                  sensorSensitivity: value,
                  stillnessDuration: fallDetectionSettings.stillnessDuration,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<Duration>(
          initialValue:
              _responseCountdownOptions.contains(
                fallDetectionSettings.stillnessDuration,
              )
              ? fallDetectionSettings.stillnessDuration
              : _responseCountdownOptions[1],
          decoration: const InputDecoration(
            labelText: 'Response Countdown Before SOS',
            prefixIcon: Icon(Icons.timer_rounded),
          ),
          items: [
            for (final duration in _responseCountdownOptions)
              DropdownMenuItem<Duration>(
                value: duration,
                child: Text(_durationLabel(duration)),
              ),
          ],
          onChanged: draft.fallDetectionEnabled
              ? (duration) {
                  if (duration == null) {
                    return;
                  }
                  onChanged(
                    draft.copyWith(
                      fallDetectionSettings: FallDetectionSettings(
                        sensorSensitivity:
                            fallDetectionSettings.sensorSensitivity,
                        stillnessDuration: duration,
                      ),
                    ),
                  );
                }
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          'After free fall, impact, and a fixed stillness check, HikerCircle uses this countdown for the final tap response before sending Fall SOS.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _WizardColors.secondaryTextFor(context),
            letterSpacing: 0,
          ),
        ),
        _SwitchRow(
          label: 'Path Deviation Alert',
          value: draft.pathDeviationEnabled,
          onChanged: (value) {
            if (!value) {
              unawaited(_showPathDeviationWarning(context));
            }
            onChanged(draft.copyWith(pathDeviationEnabled: value));
          },
        ),
      ],
    );
  }

  Future<void> _showPathDeviationWarning(BuildContext context) async {
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('Path Deviation Alert Off'),
          content: const Text(
            'HikerCircle will stop warning you when your recorded route moves away from the selected trail. This can reduce safety on unfamiliar hikes.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}

class _SensorSensitivitySlider extends StatelessWidget {
  const _SensorSensitivitySlider({
    required this.enabled,
    required this.value,
    required this.label,
    required this.showFalseAlarmWarning,
    required this.onChanged,
  });

  final bool enabled;
  final double value;
  final String label;
  final bool showFalseAlarmWarning;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Sensor Sensitivity',
          prefixIcon: Icon(Icons.sensors_rounded),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$label (${value.round()}/10)',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _WizardColors.textFor(context),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                Text(
                  enabled ? 'Active' : 'Off',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: enabled
                        ? _WizardColors.green
                        : _WizardColors.secondaryTextFor(context),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
            Slider(
              value: value,
              min: FallDetectionSettings.minSensorSensitivity,
              max: FallDetectionSettings.maxSensorSensitivity,
              divisions:
                  (FallDetectionSettings.maxSensorSensitivity -
                          FallDetectionSettings.minSensorSensitivity)
                      .round(),
              activeColor: _WizardColors.green,
              inactiveColor: _WizardColors.separatorFor(context),
              label: '$label ${value.round()}/10',
              onChanged: enabled ? onChanged : null,
            ),
            if (enabled && showFalseAlarmWarning) ...[
              const SizedBox(height: 6),
              Text(
                'High sensitivity can detect softer hiking falls, but it may also cause more false alarms from backpack drops or sitting down hard.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _WizardColors.redFor(context),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
          ],
        ),
      ),
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
            color: _WizardColors.textFor(context),
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
                color: _WizardColors.textFor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _WizardColors.secondaryTextFor(context),
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
    final color = selected
        ? _WizardColors.green
        : _WizardColors.secondaryTextFor(context);

    return Material(
      color: selected
          ? _WizardColors.greenSoftFor(context)
          : _WizardColors.surfaceFor(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? _WizardColors.green
                  : _WizardColors.separatorFor(context),
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
                        color: _WizardColors.textFor(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _WizardColors.secondaryTextFor(context),
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
        color: _WizardColors.greenSoftFor(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trail.name,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _WizardColors.textFor(context),
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${trail.locationLabel} - ${trail.distanceLabel} - ${trail.difficulty}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _WizardColors.secondaryTextFor(context),
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckpointPickerSheet extends StatefulWidget {
  const _CheckpointPickerSheet({required this.trail});

  final Trail trail;

  @override
  State<_CheckpointPickerSheet> createState() => _CheckpointPickerSheetState();
}

class _CheckpointPickerSheetState extends State<_CheckpointPickerSheet> {
  late final TextEditingController _nameController;
  late final int _nextOrder;
  late double _latitude;
  late double _longitude;

  @override
  void initState() {
    super.initState();
    final checkpoints = widget.trail.checkpoints;
    _nextOrder =
        checkpoints.fold<int>(
          0,
          (maxOrder, checkpoint) => math.max(maxOrder, checkpoint.order),
        ) +
        1;
    _nameController = TextEditingController(text: 'Checkpoint $_nextOrder');
    _latitude = widget.trail.latitude;
    _longitude = widget.trail.longitude;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = TrailCheckpoint(
      name: _nameController.text.trim().isEmpty
          ? 'Checkpoint $_nextOrder'
          : _nameController.text.trim(),
      latitude: _latitude,
      longitude: _longitude,
      order: _nextOrder,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pin Checkpoint',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: _WizardColors.textFor(context),
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap the route map to place the checkpoint at the actual trail position.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _WizardColors.secondaryTextFor(context),
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Checkpoint Name',
            prefixIcon: Icon(Icons.flag_rounded),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 280,
          child: _TappableCheckpointRouteMap(
            trail: widget.trail,
            selectedCheckpoint: selected,
            onSelected: (latitude, longitude) {
              setState(() {
                _latitude = latitude;
                _longitude = longitude;
              });
            },
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${_latitude.toStringAsFixed(5)}, ${_longitude.toStringAsFixed(5)}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: _WizardColors.secondaryTextFor(context),
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(selected),
          icon: const Icon(Icons.add_location_alt_rounded),
          label: const Text('Add Checkpoint'),
        ),
      ],
    );
  }
}

class _RoutePreviewSheet extends StatelessWidget {
  const _RoutePreviewSheet({required this.trail});

  final Trail trail;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Route Preview',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: _WizardColors.textFor(context),
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${trail.name} - ${trail.checkpoints.length} checkpoints',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _WizardColors.secondaryTextFor(context),
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(height: 320, child: _CheckpointRouteMap(trail: trail)),
      ],
    );
  }
}

class _TappableCheckpointRouteMap extends StatelessWidget {
  const _TappableCheckpointRouteMap({
    required this.trail,
    required this.selectedCheckpoint,
    required this.onSelected,
  });

  final Trail trail;
  final TrailCheckpoint selectedCheckpoint;
  final void Function(double latitude, double longitude) onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final bounds = _RouteBounds.fromCheckpoints(
          trail.checkpoints,
          extra: selectedCheckpoint,
        );
        return GestureDetector(
          onTapDown: (details) {
            final coordinate = bounds.unproject(details.localPosition, size);
            onSelected(coordinate.latitude, coordinate.longitude);
          },
          child: _CheckpointRouteMap(
            trail: trail,
            highlightedCheckpoint: selectedCheckpoint,
          ),
        );
      },
    );
  }
}

class _CheckpointRouteMap extends StatelessWidget {
  const _CheckpointRouteMap({required this.trail, this.highlightedCheckpoint});

  final Trail trail;
  final TrailCheckpoint? highlightedCheckpoint;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CustomPaint(
        painter: _CheckpointRoutePainter(
          trail: trail,
          highlightedCheckpoint: highlightedCheckpoint,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _CheckpointRoutePainter extends CustomPainter {
  const _CheckpointRoutePainter({
    required this.trail,
    required this.highlightedCheckpoint,
  });

  final Trail trail;
  final TrailCheckpoint? highlightedCheckpoint;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = _WizardColors.greenSoft;
    final grid = Paint()
      ..color = _WizardColors.green.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    final routePaint = Paint()
      ..color = _WizardColors.green
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final routeGlowPaint = Paint()
      ..color = _WizardColors.green.withValues(alpha: 0.22)
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawRect(Offset.zero & size, background);
    for (var index = 1; index < 5; index++) {
      final x = size.width * index / 5;
      final y = size.height * index / 5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final checkpoints = [...trail.checkpoints]
      ..sort((a, b) => a.order.compareTo(b.order));
    if (checkpoints.isEmpty) {
      return;
    }

    final bounds = _RouteBounds.fromCheckpoints(
      checkpoints,
      extra: highlightedCheckpoint,
    );
    final points = checkpoints
        .map(
          (checkpoint) =>
              bounds.project(checkpoint.latitude, checkpoint.longitude, size),
        )
        .toList();
    if (points.length >= 2) {
      final route = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        route.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(route, routeGlowPaint);
      canvas.drawPath(route, routePaint);
    }

    for (var index = 0; index < checkpoints.length; index++) {
      _drawMarker(
        canvas,
        points[index],
        index == 0
            ? _WizardColors.green
            : index == checkpoints.length - 1
            ? _WizardColors.red
            : _WizardColors.secondaryText,
        7,
      );
    }

    final highlighted = highlightedCheckpoint;
    if (highlighted != null) {
      _drawMarker(
        canvas,
        bounds.project(highlighted.latitude, highlighted.longitude, size),
        _WizardColors.orange,
        11,
      );
    }
  }

  void _drawMarker(Canvas canvas, Offset center, Color color, double radius) {
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, fill);
    canvas.drawCircle(center, radius, stroke);
  }

  @override
  bool shouldRepaint(covariant _CheckpointRoutePainter oldDelegate) {
    return oldDelegate.trail != trail ||
        oldDelegate.highlightedCheckpoint != highlightedCheckpoint;
  }
}

class _RouteBounds {
  const _RouteBounds({
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
  });

  factory _RouteBounds.fromCheckpoints(
    List<TrailCheckpoint> checkpoints, {
    TrailCheckpoint? extra,
  }) {
    final points = [...checkpoints, if (extra != null) extra];
    var minLatitude = points.first.latitude;
    var maxLatitude = points.first.latitude;
    var minLongitude = points.first.longitude;
    var maxLongitude = points.first.longitude;
    for (final point in points.skip(1)) {
      minLatitude = math.min(minLatitude, point.latitude);
      maxLatitude = math.max(maxLatitude, point.latitude);
      minLongitude = math.min(minLongitude, point.longitude);
      maxLongitude = math.max(maxLongitude, point.longitude);
    }
    if ((maxLatitude - minLatitude).abs() < 0.0001) {
      minLatitude -= 0.00005;
      maxLatitude += 0.00005;
    }
    if ((maxLongitude - minLongitude).abs() < 0.0001) {
      minLongitude -= 0.00005;
      maxLongitude += 0.00005;
    }
    return _RouteBounds(
      minLatitude: minLatitude,
      maxLatitude: maxLatitude,
      minLongitude: minLongitude,
      maxLongitude: maxLongitude,
    );
  }

  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;

  Offset project(double latitude, double longitude, Size size) {
    const padding = 24.0;
    final xRatio = (longitude - minLongitude) / (maxLongitude - minLongitude);
    final yRatio = 1 - (latitude - minLatitude) / (maxLatitude - minLatitude);
    return Offset(
      padding + xRatio * (size.width - padding * 2),
      padding + yRatio * (size.height - padding * 2),
    );
  }

  ({double latitude, double longitude}) unproject(Offset offset, Size size) {
    const padding = 24.0;
    final xRatio = ((offset.dx - padding) / (size.width - padding * 2))
        .clamp(0.0, 1.0)
        .toDouble();
    final yRatio =
        1 -
        ((offset.dy - padding) / (size.height - padding * 2))
            .clamp(0.0, 1.0)
            .toDouble();
    return (
      latitude: minLatitude + yRatio * (maxLatitude - minLatitude),
      longitude: minLongitude + xRatio * (maxLongitude - minLongitude),
    );
  }
}

double _distanceFromRouteMeters(
  List<TrailCheckpoint> checkpoints,
  double latitude,
  double longitude,
) {
  if (checkpoints.isEmpty) {
    return 0;
  }
  if (checkpoints.length == 1) {
    return _haversineMeters(
      latitude,
      longitude,
      checkpoints.first.latitude,
      checkpoints.first.longitude,
    );
  }

  final originLatitude = checkpoints.first.latitude;
  final target = _projectMeters(latitude, longitude, originLatitude);
  var closest = double.infinity;
  for (var index = 1; index < checkpoints.length; index++) {
    final start = _projectMeters(
      checkpoints[index - 1].latitude,
      checkpoints[index - 1].longitude,
      originLatitude,
    );
    final end = _projectMeters(
      checkpoints[index].latitude,
      checkpoints[index].longitude,
      originLatitude,
    );
    closest = math.min(closest, _pointSegmentDistance(target, start, end));
  }
  return closest;
}

({double x, double y}) _projectMeters(
  double latitude,
  double longitude,
  double originLatitude,
) {
  const metersPerDegreeLatitude = 111320.0;
  final metersPerDegreeLongitude =
      metersPerDegreeLatitude * math.cos(originLatitude * math.pi / 180);
  return (
    x: longitude * metersPerDegreeLongitude,
    y: latitude * metersPerDegreeLatitude,
  );
}

double _pointSegmentDistance(
  ({double x, double y}) point,
  ({double x, double y}) start,
  ({double x, double y}) end,
) {
  final dx = end.x - start.x;
  final dy = end.y - start.y;
  if (dx == 0 && dy == 0) {
    return math.sqrt(
      math.pow(point.x - start.x, 2) + math.pow(point.y - start.y, 2),
    );
  }
  final t =
      (((point.x - start.x) * dx + (point.y - start.y) * dy) /
              (dx * dx + dy * dy))
          .clamp(0.0, 1.0)
          .toDouble();
  final projectedX = start.x + t * dx;
  final projectedY = start.y + t * dy;
  return math.sqrt(
    math.pow(point.x - projectedX, 2) + math.pow(point.y - projectedY, 2),
  );
}

double _haversineMeters(
  double startLatitude,
  double startLongitude,
  double endLatitude,
  double endLongitude,
) {
  const earthRadiusMeters = 6371000.0;
  final deltaLatitude = (endLatitude - startLatitude) * math.pi / 180;
  final deltaLongitude = (endLongitude - startLongitude) * math.pi / 180;
  final startRadians = startLatitude * math.pi / 180;
  final endRadians = endLatitude * math.pi / 180;
  final haversine =
      math.sin(deltaLatitude / 2) * math.sin(deltaLatitude / 2) +
      math.cos(startRadians) *
          math.cos(endRadians) *
          math.sin(deltaLongitude / 2) *
          math.sin(deltaLongitude / 2);
  final centralAngle =
      2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  return earthRadiusMeters * centralAngle;
}

class _CheckpointList extends StatelessWidget {
  const _CheckpointList({required this.checkpoints, required this.onPreview});

  final List<TrailCheckpoint> checkpoints;
  final ValueChanged<TrailCheckpoint> onPreview;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _WizardColors.separatorFor(context)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < checkpoints.length; index++) ...[
            _CheckpointStatusRow(
              checkpoint: checkpoints[index],
              onPreview: () => onPreview(checkpoints[index]),
            ),
            if (index != checkpoints.length - 1) const _HorizontalSeparator(),
          ],
        ],
      ),
    );
  }
}

class _CheckpointStatusRow extends StatelessWidget {
  const _CheckpointStatusRow({
    required this.checkpoint,
    required this.onPreview,
  });

  final TrailCheckpoint checkpoint;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${checkpoint.order}. ${checkpoint.name}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _WizardColors.textFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          Tooltip(
            message: 'Preview pinned location',
            child: IconButton(
              onPressed: onPreview,
              icon: const Icon(Icons.map_rounded),
              color: _WizardColors.green,
            ),
          ),
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
          color: _WizardColors.textFor(context),
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _DurationPickerField extends StatelessWidget {
  const _DurationPickerField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final Duration value;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showPicker(context),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Expected Hours and Minutes Needed',
          prefixIcon: Icon(Icons.timer_rounded),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _durationLabel(value),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: _WizardColors.textFor(context),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded),
          ],
        ),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    var selectedHours = value.inHours.clamp(0, 23).toInt();
    var selectedMinutes = value.inMinutes.remainder(60);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: _WizardColors.surfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: 280,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: _WizardColors.textFor(context),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          final duration = Duration(
                            hours: selectedHours,
                            minutes: selectedMinutes,
                          );
                          onChanged(
                            duration == Duration.zero
                                ? const Duration(minutes: 1)
                                : duration,
                          );
                          Navigator.of(context).pop();
                        },
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoPicker(
                          itemExtent: 42,
                          scrollController: FixedExtentScrollController(
                            initialItem: selectedHours,
                          ),
                          onSelectedItemChanged: (value) {
                            selectedHours = value;
                          },
                          children: [
                            for (var hour = 0; hour <= 23; hour++)
                              Center(child: Text('$hour h')),
                          ],
                        ),
                      ),
                      Expanded(
                        child: CupertinoPicker(
                          itemExtent: 42,
                          scrollController: FixedExtentScrollController(
                            initialItem: selectedMinutes,
                          ),
                          onSelectedItemChanged: (value) {
                            selectedMinutes = value;
                          },
                          children: [
                            for (var minute = 0; minute < 60; minute++)
                              Center(
                                child: Text(
                                  '${minute.toString().padLeft(2, '0')} min',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _WizardColors.separatorFor(context)),
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
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: _WizardColors.textFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _WizardAnimatedToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _WizardAnimatedToggle extends StatelessWidget {
  const _WizardAnimatedToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedToggleSwitch<bool>.size(
      current: value,
      values: const [false, true],
      height: 38,
      spacing: 2,
      indicatorSize: const Size.square(32),
      borderWidth: 2,
      style: ToggleStyle(
        backgroundColor: _WizardColors.greenSoftFor(context),
        borderColor: _WizardColors.separatorFor(context),
        borderRadius: BorderRadius.circular(999),
        indicatorBorderRadius: BorderRadius.circular(999),
      ),
      styleBuilder: (enabled) => ToggleStyle(
        indicatorColor: enabled
            ? _WizardColors.green
            : _WizardColors.redFor(context),
      ),
      iconBuilder: (enabled) => Icon(
        enabled ? Icons.check_rounded : Icons.close_rounded,
        color: enabled ? _WizardColors.green : _WizardColors.redFor(context),
        size: 17,
      ),
      foregroundIndicatorIconBuilder: (context, global) {
        final enabled = global.current;
        return Icon(
          enabled ? Icons.check_rounded : Icons.close_rounded,
          color: _WizardColors.surfaceFor(context),
          size: 18,
        );
      },
      iconOpacity: 0.72,
      selectedIconOpacity: 0,
      selectedIconScale: 1,
      animationDuration: const Duration(milliseconds: 260),
      animationCurve: Curves.easeOutCubic,
      onChanged: onChanged,
    );
  }
}

class _PreparationStatusList extends StatelessWidget {
  const _PreparationStatusList();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _WizardColors.separatorFor(context)),
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _WizardColors.separatorFor(context)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            Material(
              color: Colors.transparent,
              child: CheckboxListTile(
                value: completedItems.contains(items[index]),
                onChanged: (value) => onChanged(items[index], value),
                dense: true,
                activeColor: _WizardColors.green,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  items[index],
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _WizardColors.textFor(context),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
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
        color: _WizardColors.greenSoftFor(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Forecast',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _WizardColors.textFor(context),
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              trail.weather.summary,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _WizardColors.secondaryTextFor(context),
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Temperature: ${trail.weather.temperatureRange}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _WizardColors.secondaryTextFor(context),
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _WizardColors.separatorFor(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'When session starts',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _WizardColors.textFor(context),
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
                    color: _WizardColors.secondaryTextFor(context),
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
                color: _WizardColors.textFor(context),
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
                color: _WizardColors.secondaryTextFor(context),
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
      decoration: BoxDecoration(
        color: _WizardColors.surfaceFor(context),
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
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _WizardColors.surfaceFor(context),
          borderRadius: BorderRadius.circular(12),
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
    return Divider(
      height: 1,
      thickness: 0.7,
      color: _WizardColors.separatorFor(context),
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
  if (duration.inSeconds < 60) {
    final seconds = duration.inSeconds;
    return '$seconds sec';
  }
  if (duration.inMinutes < 60) {
    final minutes = duration.inMinutes;
    return '$minutes min';
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (minutes == 0) {
    return '${hours}h';
  }
  return '${hours}h ${minutes}m';
}

abstract final class _WizardColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color red = Color(0xFFE11D48);
  static const Color orange = Color(0xFFFF9500);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : greenSoft;

  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  static Color redFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF6B88) : red;
}

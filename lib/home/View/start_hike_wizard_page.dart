import 'dart:async';
import 'dart:math' as math;

import 'package:animated_toggle_switch/animated_toggle_switch.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../../core/services/hiking_route_service.dart';
import '../../core/widgets/route_preview_map.dart';
import '../../trail/Model/trail_models.dart';
import '../Model/hike_session_models.dart';

enum _StartHikeWizardStep { type, timing, trail, safety }

class StartHikeWizardPage extends StatefulWidget {
  const StartHikeWizardPage({
    super.key,
    this.preselectedTrail,
    this.availableTrails = const [],
    this.repository,
    this.session,
    this.emergencyContactNames = const [],
    this.onScheduled,
  });

  final Trail? preselectedTrail;
  final List<Trail> availableTrails;
  final HikerCircleFirebaseRepository? repository;
  final AppSession? session;
  final List<String> emergencyContactNames;
  final Future<void> Function(HikeSessionDraft draft)? onScheduled;

  @override
  State<StartHikeWizardPage> createState() => _StartHikeWizardPageState();
}

class _StartHikeWizardPageState extends State<StartHikeWizardPage> {
  late final List<Trail> _trails;
  late HikeSessionDraft _draft;
  int _stepIndex = 0;
  bool _startNow = true;
  bool _isScheduling = false;

  bool get _isUpcomingHike => !_startNow;

  List<_StartHikeWizardStep> get _steps => [
    _StartHikeWizardStep.type,
    _StartHikeWizardStep.timing,
    _StartHikeWizardStep.trail,
    if (!_isUpcomingHike) _StartHikeWizardStep.safety,
  ];

  int get _lastStep => _steps.length - 1;
  int get _stepCount => _steps.length;
  int get _visibleStepIndex => _stepIndex;
  bool get _isFinalStep => _stepIndex == _lastStep;

  @override
  void initState() {
    super.initState();
    final trailsById = <String, Trail>{};
    for (final trail in widget.availableTrails) {
      trailsById.putIfAbsent(trail.trailId, () => trail);
    }
    final preselectedTrail = widget.preselectedTrail;
    if (preselectedTrail != null) {
      trailsById.putIfAbsent(preselectedTrail.trailId, () => preselectedTrail);
    }
    _trails = trailsById.values.toList();
    if (_trails.isEmpty) {
      return;
    }
    final selectedTrail = _trails.firstWhere(
      (trail) => trail.trailId == widget.preselectedTrail?.trailId,
      orElse: () => _trails.first,
    );
    _draft = _withPlatformSafetyPolicy(
      HikeSessionDraft.fromTrail(selectedTrail).copyWith(
        emergencyContactNames: {
          for (final name in widget.emergencyContactNames)
            if (name.trim().isNotEmpty) name.trim(),
        }.toList(),
      ),
    );
  }

  void _next() {
    if (_isScheduling) return;
    final currentStep = _steps[_stepIndex];

    if (currentStep == _StartHikeWizardStep.timing &&
        _isUpcomingHike &&
        _draft.departureTime.isBefore(_minimumScheduledDepartureTime())) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Scheduled hikes must start at least 10 minutes from now.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    if (currentStep == _StartHikeWizardStep.trail &&
        (_draft.effectiveCheckpoints.length < 3 ||
            _draft.effectiveCheckpoints.length > 12)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Add between 3 and 12 checkpoints before continuing.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    if (_isFinalStep) {
      if (_isUpcomingHike) {
        unawaited(_scheduleAndFinish());
        return;
      }
      Navigator.of(context).pop(ActiveHikeSession.fromDraft(_draftForNow()));
      return;
    }

    setState(() {
      _stepIndex += 1;
    });
  }

  Future<void> _scheduleAndFinish() async {
    final repo = widget.repository;
    final session = widget.session;
    if (repo == null || session == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Scheduling is unavailable. Please sign in again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    setState(() => _isScheduling = true);
    try {
      final safeDraft = _withPlatformSafetyPolicy(
        _withSafeRecordingInterval(_draft),
      );
      await repo.scheduleUpcomingHike(session: session, draft: safeDraft);
      try {
        await widget.onScheduled?.call(safeDraft);
      } catch (error) {
        debugPrint('Unable to cache the newly scheduled hike: $error');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Hike scheduled for ${_formatDate(_draft.departureTime)} at ${_formatTime(_draft.departureTime)}.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      Navigator.of(context).pop();
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to schedule this hike. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _isScheduling = false);
      }
    }
  }

  void _back() {
    if (_stepIndex <= 0) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _stepIndex -= 1;
    });
  }

  void _updateDraft(HikeSessionDraft draft) {
    setState(() {
      _draft = _withPlatformSafetyPolicy(_withSafeRecordingInterval(draft));
      _clampStepIndex();
    });
  }

  void _updateStartNow(bool startNow) {
    setState(() {
      _startNow = startNow;
      _clampStepIndex();
    });
  }

  void _clampStepIndex() {
    if (_stepIndex < 0) {
      _stepIndex = 0;
    }
    if (_stepIndex > _lastStep) {
      _stepIndex = _lastStep;
    }
  }

  HikeSessionDraft _draftForNow() {
    final now = DateTime.now();
    final hikeDuration = _safePlannedHikeDuration(_draft);
    final expectedArrival = now.add(hikeDuration);
    return _withPlatformSafetyPolicy(
      _withSafeRecordingInterval(_draft),
    ).copyWith(
      departureTime: now,
      expectedArrivalTime: expectedArrival,
      expectedReturnTime: expectedArrival.add(const Duration(hours: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_trails.isEmpty) {
      return Scaffold(
        backgroundColor: _WizardColors.backgroundFor(context),
        appBar: AppBar(title: const Text('Create Hiking Session')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.route_rounded, size: 44),
                const SizedBox(height: 12),
                const Text(
                  'No trails are available to plan a hike.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }
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
                  _StepProgress(
                    currentStep: _visibleStepIndex,
                    totalSteps: _stepCount,
                  ),
                  const SizedBox(height: 18),
                  KeyedSubtree(key: ValueKey(_stepIndex), child: step),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: _back,
                          child: Text(_stepIndex <= 0 ? 'Cancel' : 'Back'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: FilledButton.icon(
                          onPressed: _isScheduling ? null : _next,
                          icon: _isScheduling
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _isFinalStep
                                      ? _isUpcomingHike
                                            ? Icons.event_available_rounded
                                            : Icons.play_arrow_rounded
                                      : Icons.arrow_forward_rounded,
                                ),
                          label: Text(
                            _isScheduling
                                ? 'Scheduling...'
                                : _isFinalStep
                                ? _isUpcomingHike
                                      ? 'Schedule Hike'
                                      : 'Start Hiking Session'
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
    switch (_steps[index]) {
      case _StartHikeWizardStep.type:
        return _HikeTypeStep(draft: _draft, onChanged: _updateDraft);
      case _StartHikeWizardStep.timing:
        return _TimingStep(
          draft: _draft,
          startNow: _startNow,
          onStartNowChanged: _updateStartNow,
          onChanged: _updateDraft,
        );
      case _StartHikeWizardStep.trail:
        return _TrailSelectionStep(
          draft: _draft,
          trails: _trails,
          onChanged: _updateDraft,
        );
      case _StartHikeWizardStep.safety:
        return _SafetySettingsStep(draft: _draft, onChanged: _updateDraft);
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
                'Plan timing, safety, and route preparation',
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
  const _StepProgress({required this.currentStep, required this.totalSteps});

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < totalSteps; index++) ...[
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
          if (index != totalSteps - 1) const SizedBox(width: 6),
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
          onTap: () => onChanged(
            draft.copyWith(hikeType: HikeType.solo, teamBuddies: const []),
          ),
        ),
        const SizedBox(height: 10),
        _ChoiceTile(
          selected: draft.hikeType == HikeType.team,
          icon: Icons.groups_2_rounded,
          title: 'Team Hike',
          subtitle: 'Create a session for friends or join an existing group.',
          onTap: () => onChanged(
            draft.copyWith(hikeType: HikeType.team, teamBuddies: const []),
          ),
        ),
      ],
    );
  }
}

class _TrailSelectionStep extends StatefulWidget {
  const _TrailSelectionStep({
    required this.draft,
    required this.trails,
    required this.onChanged,
  });

  final HikeSessionDraft draft;
  final List<Trail> trails;
  final ValueChanged<HikeSessionDraft> onChanged;

  @override
  State<_TrailSelectionStep> createState() => _TrailSelectionStepState();
}

class _TrailSelectionStepState extends State<_TrailSelectionStep> {
  bool _showMap = true;
  bool _editMode = false;
  int? _highlightedCheckpointIndex;
  late Future<HikingRouteResult> _routeFuture;

  List<TrailCheckpoint> get _checkpoints => widget.draft.effectiveCheckpoints;

  Trail get _routeTrail =>
      widget.draft.trail.copyWith(checkpoints: _checkpoints);

  @override
  void initState() {
    super.initState();
    _routeFuture = HikingRouteService().findHikingRouteForTrailWithCache(
      _routeTrail,
    );
  }

  @override
  void didUpdateWidget(covariant _TrailSelectionStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft.trail.trailId != widget.draft.trail.trailId ||
        HikingRouteService.checkpointsHash(
              oldWidget.draft.effectiveCheckpoints,
            ) !=
            HikingRouteService.checkpointsHash(_checkpoints)) {
      _routeFuture = HikingRouteService().findHikingRouteForTrailWithCache(
        _routeTrail,
      );
      _highlightedCheckpointIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cpsSorted = [..._checkpoints]
      ..sort((a, b) => a.order.compareTo(b.order));

    return _StepCard(
      title: 'Select Trail',
      subtitle:
          'Use 3–12 checkpoints. Start and end stay fixed; middle stops are optimized.',
      children: [
        DropdownButtonFormField<String>(
          initialValue: widget.draft.trail.trailId,
          decoration: const InputDecoration(labelText: 'Selected Trail'),
          items: [
            for (final trail in widget.trails)
              DropdownMenuItem<String>(
                value: trail.trailId,
                child: Text(trail.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (trailId) {
            if (trailId == null) return;
            final nextTrail = widget.trails.firstWhere(
              (trail) => trail.trailId == trailId,
            );
            final current = widget.draft;
            widget.onChanged(
              HikeSessionDraft.fromTrail(nextTrail).copyWith(
                hikeType: current.hikeType,
                departureTime: current.departureTime,
                expectedArrivalTime: current.expectedArrivalTime,
                expectedReturnTime: current.expectedReturnTime,
                safetyCheckInInterval: current.safetyCheckInInterval,
                locationRecordingInterval: current.locationRecordingInterval,
                emergencyContactNames: current.emergencyContactNames,
                shareLiveLocation: current.shareLiveLocation,
                fallDetectionEnabled: current.fallDetectionEnabled,
                fallDetectionSettings: current.fallDetectionSettings,
                pathDeviationEnabled: current.pathDeviationEnabled,
                offlinePhysicalAlertEnabled:
                    current.offlinePhysicalAlertEnabled,
                duressEnabled: current.duressEnabled,
                completedChecklistItems: current.completedChecklistItems,
                teamBuddies: current.teamBuddies,
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _TrailSummary(trail: widget.draft.trail),
        const SizedBox(height: 16),
        if (_showMap)
          SizedBox(
            height: 220,
            child: FutureBuilder<HikingRouteResult>(
              future: _routeFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                return RoutePreviewMap(
                  trail: widget.draft.trail,
                  route: snapshot.data,
                  customCheckpoints: widget.draft.customCheckpoints,
                  highlightedCheckpointIndex: _highlightedCheckpointIndex,
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '${cpsSorted.length} checkpoints',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: _WizardColors.textFor(context),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => _showMap = !_showMap),
              child: Text(_showMap ? 'Hide map' : 'Show map'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${12 - cpsSorted.length} of 12 checkpoint slots remaining',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: cpsSorted.length >= 12
                ? _WizardColors.orange
                : _WizardColors.secondaryTextFor(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        _WizardCheckpointTimeline(
          checkpoints: cpsSorted,
          editMode: _editMode,
          onShowOnMap: (index) {
            setState(() {
              _highlightedCheckpointIndex = _highlightedCheckpointIndex == index
                  ? null
                  : index;
            });
          },
          onEdit: _showEditCheckpointDialog,
          onRemove: _removeCheckpoint,
          onReorder: _reorderCheckpoint,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: cpsSorted.length >= 12 ? null : _addCheckpoint,
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Add Checkpoint'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => setState(() => _editMode = !_editMode),
              icon: Icon(
                _editMode ? Icons.edit_rounded : Icons.edit_note_rounded,
              ),
              isSelected: _editMode,
              tooltip: _editMode ? 'Done editing' : 'Edit checkpoints',
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _addCheckpoint() async {
    if (_checkpoints.length >= 12) return;
    final checkpoint = await showModalBottomSheet<TrailCheckpoint>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: _WizardColors.surfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: mediaQuery.size.height * 0.84,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                child: _CheckpointPickerSheet(
                  trail: widget.draft.trail,
                  existingCheckpoints: _checkpoints,
                ),
              ),
            ),
          ),
        );
      },
    );
    if (checkpoint == null || !mounted) return;
    widget.onChanged(widget.draft.addCheckpoint(checkpoint));
  }

  void _removeCheckpoint(int index) {
    widget.onChanged(widget.draft.removeCheckpointAt(index));
  }

  void _reorderCheckpoint(int oldIndex, int newIndex) {
    widget.onChanged(
      _reorderDraftCheckpoints(widget.draft, oldIndex, newIndex),
    );
  }

  Future<void> _showEditCheckpointDialog(int index) async {
    final cp = _checkpoints.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final checkpoint = cp[index];
    var editedName = checkpoint.name;
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Checkpoint'),
        content: TextFormField(
          initialValue: checkpoint.name,
          decoration: const InputDecoration(labelText: 'Name'),
          autofocus: true,
          onChanged: (value) => editedName = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(editedName.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && mounted) {
      final sorted = [..._checkpoints]
        ..sort((a, b) => a.order.compareTo(b.order));
      final updated = [...sorted];
      updated[index] = checkpoint.copyWith(name: newName);
      widget.onChanged(widget.draft.copyWith(customCheckpoints: updated));
    }
  }
}

class _CheckpointStep extends StatefulWidget {
  const _CheckpointStep({required this.draft, required this.onChanged});

  final HikeSessionDraft draft;
  final ValueChanged<HikeSessionDraft> onChanged;

  @override
  State<_CheckpointStep> createState() => _CheckpointStepState();
}

class _CheckpointStepState extends State<_CheckpointStep> {
  bool _showMap = true;
  bool _editMode = false;
  int? _highlightedCheckpointIndex;
  late Future<HikingRouteResult> _routeFuture;

  List<TrailCheckpoint> get _checkpoints => widget.draft.effectiveCheckpoints;

  Trail get _routeTrail =>
      widget.draft.trail.copyWith(checkpoints: _checkpoints);

  @override
  void initState() {
    super.initState();
    _routeFuture = HikingRouteService().findHikingRouteForTrailWithCache(
      _routeTrail,
    );
  }

  @override
  void didUpdateWidget(covariant _CheckpointStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft.trail.trailId != widget.draft.trail.trailId ||
        HikingRouteService.checkpointsHash(
              oldWidget.draft.effectiveCheckpoints,
            ) !=
            HikingRouteService.checkpointsHash(_checkpoints)) {
      _routeFuture = HikingRouteService().findHikingRouteForTrailWithCache(
        _routeTrail,
      );
    }
  }

  void _addCheckpoint() {
    if (_checkpoints.length >= 12) return;
    showModalBottomSheet<TrailCheckpoint>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: _WizardColors.surfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: mediaQuery.size.height * 0.84,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                child: _CheckpointPickerSheet(
                  trail: widget.draft.trail,
                  existingCheckpoints: _checkpoints,
                ),
              ),
            ),
          ),
        );
      },
    ).then((checkpoint) {
      if (checkpoint == null || !mounted) return;
      widget.onChanged(widget.draft.addCheckpoint(checkpoint));
    });
  }

  void _removeCheckpoint(int index) {
    widget.onChanged(widget.draft.removeCheckpointAt(index));
  }

  void _reorderCheckpoint(int oldIndex, int newIndex) {
    widget.onChanged(
      _reorderDraftCheckpoints(widget.draft, oldIndex, newIndex),
    );
  }

  Future<void> _showEditCheckpointDialog(int index) async {
    final sorted = [..._checkpoints]
      ..sort((a, b) => a.order.compareTo(b.order));
    final checkpoint = sorted[index];
    var editedName = checkpoint.name;
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Checkpoint'),
        content: TextFormField(
          initialValue: checkpoint.name,
          decoration: const InputDecoration(labelText: 'Name'),
          autofocus: true,
          onChanged: (value) => editedName = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(editedName.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && mounted) {
      final updated = [...sorted];
      updated[index] = checkpoint.copyWith(name: newName);
      widget.onChanged(widget.draft.copyWith(customCheckpoints: updated));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cps = _checkpoints;
    final cpsSorted = [...cps]..sort((a, b) => a.order.compareTo(b.order));

    return _StepCard(
      title: 'Checkpoints',
      subtitle:
          'Use 3–12 checkpoints. Trailhead and trail end are fixed; middle stops are optimized.',
      children: [
        if (_showMap)
          SizedBox(
            height: 220,
            child: FutureBuilder<HikingRouteResult>(
              future: _routeFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                return RoutePreviewMap(
                  trail: widget.draft.trail,
                  route: snapshot.data,
                  customCheckpoints: widget.draft.customCheckpoints,
                  highlightedCheckpointIndex: _highlightedCheckpointIndex,
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '${cpsSorted.length} checkpoints',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: _WizardColors.textFor(context),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => _showMap = !_showMap),
              child: Text(_showMap ? 'Hide map' : 'Show map'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _WizardCheckpointTimeline(
          checkpoints: cpsSorted,
          editMode: _editMode,
          onShowOnMap: (index) {
            setState(() {
              _highlightedCheckpointIndex = _highlightedCheckpointIndex == index
                  ? null
                  : index;
            });
          },
          onEdit: _showEditCheckpointDialog,
          onRemove: _removeCheckpoint,
          onReorder: _reorderCheckpoint,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: cpsSorted.length >= 12 ? null : _addCheckpoint,
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Add Checkpoint'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => setState(() => _editMode = !_editMode),
              icon: Icon(
                _editMode ? Icons.edit_rounded : Icons.edit_note_rounded,
              ),
              isSelected: _editMode,
              tooltip: _editMode ? 'Done editing' : 'Edit checkpoints',
            ),
          ],
        ),
      ],
    );
  }
}

class _TimingStep extends StatelessWidget {
  const _TimingStep({
    required this.draft,
    required this.startNow,
    required this.onStartNowChanged,
    required this.onChanged,
  });

  final HikeSessionDraft draft;
  final bool startNow;
  final ValueChanged<bool> onStartNowChanged;
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
  ];

  void _selectStartNow() {
    onStartNowChanged(true);
    final now = DateTime.now();
    final hikeDuration = _safePlannedHikeDuration(draft);
    final expectedArrival = now.add(hikeDuration);
    onChanged(
      draft.copyWith(
        departureTime: now,
        expectedArrivalTime: expectedArrival,
        expectedReturnTime: expectedArrival.add(const Duration(hours: 2)),
      ),
    );
  }

  void _selectScheduledStart(BuildContext context) {
    onStartNowChanged(false);
    final departure =
        draft.departureTime.isBefore(_minimumScheduledDepartureTime())
        ? _minimumScheduledDepartureTime()
        : draft.departureTime;
    _updateDeparture(context, departure, notifyIfAdjusted: false);
  }

  void _updateDeparture(
    BuildContext context,
    DateTime candidate, {
    bool notifyIfAdjusted = true,
  }) {
    var updated = candidate;
    final minimum = _minimumScheduledDepartureTime();
    if (updated.isBefore(minimum)) {
      updated = minimum;
      if (notifyIfAdjusted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Scheduled hikes must start at least 10 minutes from now.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    }
    final diff = _safePlannedHikeDuration(draft);
    onChanged(
      draft.copyWith(
        departureTime: updated,
        expectedArrivalTime: updated.add(diff),
        expectedReturnTime: updated.add(diff).add(const Duration(hours: 2)),
      ),
    );
  }

  Future<void> _pickDepartureDate(BuildContext context) async {
    final minimum = _minimumScheduledDepartureTime();
    final picked = await showDatePicker(
      context: context,
      initialDate: draft.departureTime.isBefore(minimum)
          ? minimum
          : draft.departureTime,
      firstDate: DateTime(minimum.year, minimum.month, minimum.day),
      lastDate: minimum.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    if (!context.mounted) return;
    final updated = DateTime(
      picked.year,
      picked.month,
      picked.day,
      draft.departureTime.hour,
      draft.departureTime.minute,
    );
    _updateDeparture(context, updated);
  }

  Future<void> _pickDepartureTime(BuildContext context) async {
    final minimum = _minimumScheduledDepartureTime();
    final initial = draft.departureTime.isBefore(minimum)
        ? minimum
        : draft.departureTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (picked == null) return;
    if (!context.mounted) return;
    final updated = DateTime(
      draft.departureTime.year,
      draft.departureTime.month,
      draft.departureTime.day,
      picked.hour,
      picked.minute,
    );
    _updateDeparture(context, updated);
  }

  @override
  Widget build(BuildContext context) {
    return _StepCard(
      title: 'Timing and Tracking',
      subtitle: 'Check-ins ask for confirmation; GPS recording runs quietly.',
      children: [
        _ChoiceTile(
          selected: startNow,
          icon: Icons.play_circle_fill_rounded,
          title: 'Start Now',
          subtitle:
              'Continue through safety settings and start the active hike immediately.',
          onTap: _selectStartNow,
        ),
        const SizedBox(height: 10),
        _ChoiceTile(
          selected: !startNow,
          icon: Icons.event_available_rounded,
          title: 'Schedule Time',
          subtitle:
              'Create an upcoming hike. Safety settings are chosen when it starts.',
          onTap: () => _selectScheduledStart(context),
        ),
        if (!startNow) ...[
          const SizedBox(height: 12),
          _TappableField(
            label: 'Departure Date',
            value: _formatDate(draft.departureTime),
            icon: Icons.calendar_today_rounded,
            onTap: () => _pickDepartureDate(context),
          ),
          const SizedBox(height: 12),
          _TappableField(
            label: 'Departure Time',
            value: _formatTime(draft.departureTime),
            icon: Icons.schedule_rounded,
            onTap: () => _pickDepartureTime(context),
          ),
          const SizedBox(height: 8),
          _InlineHint(
            icon: Icons.info_outline_rounded,
            text:
                'Earliest scheduled start: ${_formatDate(_minimumScheduledDepartureTime())} at ${_formatTime(_minimumScheduledDepartureTime())}.',
          ),
        ],
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
          initialValue: _checkInOptions.contains(draft.safetyCheckInInterval)
              ? draft.safetyCheckInInterval
              : _checkInOptions[1],
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
          initialValue:
              _recordingOptions.contains(draft.locationRecordingInterval)
              ? draft.locationRecordingInterval
              : HikeSessionDraft.defaultLocationRecordingInterval,
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
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 3),
    Duration(minutes: 5),
  ];

  static const List<Duration> _longestRestOptions = [
    Duration(minutes: 3),
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 30),
  ];

  @override
  Widget build(BuildContext context) {
    final fallDetectionSettings = draft.fallDetectionSettings;
    final androidNativeSafety =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final responseOptions = androidNativeSafety
        ? const [Duration(seconds: 15)]
        : _responseCountdownOptions;

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
        const SizedBox(height: 16),
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
                  fallResponseDuration:
                      fallDetectionSettings.fallResponseDuration,
                  longestRestDuration:
                      fallDetectionSettings.longestRestDuration,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<Duration>(
          initialValue:
              responseOptions.contains(
                fallDetectionSettings.fallResponseDuration,
              )
              ? fallDetectionSettings.fallResponseDuration
              : responseOptions.first,
          decoration: InputDecoration(
            labelText: androidNativeSafety
                ? 'Safety warning response window'
                : 'Longest response time after a fall',
            prefixIcon: const Icon(Icons.personal_injury_rounded),
          ),
          items: [
            for (final duration in responseOptions)
              DropdownMenuItem<Duration>(
                value: duration,
                child: Text(_durationLabel(duration)),
              ),
          ],
          onChanged: draft.fallDetectionEnabled && !androidNativeSafety
              ? (duration) {
                  if (duration == null) {
                    return;
                  }
                  onChanged(
                    draft.copyWith(
                      fallDetectionSettings: FallDetectionSettings(
                        sensorSensitivity:
                            fallDetectionSettings.sensorSensitivity,
                        fallResponseDuration: duration,
                        longestRestDuration:
                            fallDetectionSettings.longestRestDuration,
                      ),
                    ),
                  );
                }
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          androidNativeSafety
              ? 'Android vibrates, speaks an “Are you okay?” prompt, and shows a lock-screen warning for 15 seconds. No SOS is sent during this warning window.'
              : 'After a fall and fixed stillness check, this is how long you have to cancel before Fall SOS is sent.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _WizardColors.secondaryTextFor(context),
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<Duration>(
          initialValue:
              _longestRestOptions.contains(
                fallDetectionSettings.longestRestDuration,
              )
              ? fallDetectionSettings.longestRestDuration
              : _longestRestOptions.first,
          decoration: const InputDecoration(
            labelText: 'Longest time for a rest',
            prefixIcon: Icon(Icons.self_improvement_rounded),
          ),
          items: [
            for (final duration in _longestRestOptions)
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
                        fallResponseDuration:
                            fallDetectionSettings.fallResponseDuration,
                        longestRestDuration: duration,
                      ),
                    ),
                  );
                }
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          'If your location stays within 5 m for this long, HikerCircle checks for phone movement and asks you to respond before sending a prolonged-stillness SOS.',
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

class _InlineHint extends StatelessWidget {
  const _InlineHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: _WizardColors.secondaryTextFor(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _WizardColors.secondaryTextFor(context),
              letterSpacing: 0,
            ),
          ),
        ),
      ],
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
  const _CheckpointPickerSheet({
    required this.trail,
    required this.existingCheckpoints,
  });

  final Trail trail;
  final List<TrailCheckpoint> existingCheckpoints;

  @override
  State<_CheckpointPickerSheet> createState() => _CheckpointPickerSheetState();
}

class _CheckpointPickerSheetState extends State<_CheckpointPickerSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  late final int _nextOrder;
  late double _latitude;
  late double _longitude;

  bool get _hasValidCoordinateInput {
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    return latitude != null &&
        longitude != null &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  @override
  void initState() {
    super.initState();
    final checkpoints = widget.existingCheckpoints;
    _nextOrder =
        checkpoints.fold<int>(
          0,
          (maxOrder, checkpoint) => math.max(maxOrder, checkpoint.order),
        ) +
        1;
    _nameController = TextEditingController(text: 'Checkpoint $_nextOrder');
    final initialCoordinate = _defaultCheckpointCoordinate(widget.trail);
    _latitude = initialCoordinate.latitude;
    _longitude = initialCoordinate.longitude;
    _latitudeController = TextEditingController(
      text: _latitude.toStringAsFixed(6),
    );
    _longitudeController = TextEditingController(
      text: _longitude.toStringAsFixed(6),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  void _updateCoordinate() {
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    setState(() {
      if (latitude != null &&
          longitude != null &&
          latitude >= -90 &&
          latitude <= 90 &&
          longitude >= -180 &&
          longitude <= 180) {
        _latitude = latitude;
        _longitude = longitude;
      }
    });
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
          'Enter the checkpoint coordinates and verify its position in the route preview.',
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
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _latitudeController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Latitude'),
                onChanged: (_) => _updateCoordinate(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _longitudeController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Longitude'),
                onChanged: (_) => _updateCoordinate(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 280,
          child: RoutePreviewMap(
            trail: widget.trail,
            customCheckpoints: [...widget.existingCheckpoints, selected],
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
        if (!_hasValidCoordinateInput) ...[
          const SizedBox(height: 6),
          Text(
            'Enter a latitude from -90 to 90 and longitude from -180 to 180.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _hasValidCoordinateInput
              ? () => Navigator.of(context).pop(selected)
              : null,
          icon: const Icon(Icons.add_location_alt_rounded),
          label: const Text('Add Checkpoint'),
        ),
      ],
    );
  }
}

({double latitude, double longitude}) _defaultCheckpointCoordinate(
  Trail trail,
) {
  final checkpoints = [...trail.checkpoints]
    ..sort((a, b) => a.order.compareTo(b.order));
  if (checkpoints.isEmpty) {
    return (latitude: trail.latitude, longitude: trail.longitude);
  }

  final middleCheckpoint = checkpoints[checkpoints.length ~/ 2];
  return (
    latitude: middleCheckpoint.latitude,
    longitude: middleCheckpoint.longitude,
  );
}

HikeSessionDraft _reorderDraftCheckpoints(
  HikeSessionDraft draft,
  int oldIndex,
  int newIndex,
) {
  final checkpoints = [...draft.effectiveCheckpoints]
    ..sort((a, b) => a.order.compareTo(b.order));
  if (oldIndex < 0 || oldIndex >= checkpoints.length) return draft;
  if (oldIndex < newIndex) newIndex--;
  newIndex = newIndex.clamp(0, checkpoints.length - 1);
  if (oldIndex == newIndex) return draft;
  final moved = checkpoints.removeAt(oldIndex);
  checkpoints.insert(newIndex, moved);
  final reindexed = checkpoints
      .asMap()
      .entries
      .map((entry) => entry.value.copyWith(order: entry.key + 1))
      .toList();
  return draft.copyWith(
    customCheckpoints: reindexed,
    startPointName: reindexed.first.name,
    destinationName: reindexed.last.name,
  );
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

class _TappableField extends StatelessWidget {
  const _TappableField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: Icon(
            Icons.edit_rounded,
            size: 18,
            color: _WizardColors.secondaryTextFor(context),
          ),
        ),
        child: Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: _WizardColors.textFor(context),
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
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
    final hoursController = FixedExtentScrollController(
      initialItem: selectedHours,
    );
    final minutesController = FixedExtentScrollController(
      initialItem: selectedMinutes,
    );
    try {
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
                            scrollController: hoursController,
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
                            scrollController: minutesController,
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
    } finally {
      hoursController.dispose();
      minutesController.dispose();
    }
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
        children: names.isEmpty
            ? const [
                Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'No emergency contacts selected. Add contacts from Me before starting the hike.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ]
            : [
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

class _WizardCheckpointTimeline extends StatelessWidget {
  const _WizardCheckpointTimeline({
    required this.checkpoints,
    required this.editMode,
    required this.onShowOnMap,
    required this.onEdit,
    required this.onRemove,
    required this.onReorder,
  });

  final List<TrailCheckpoint> checkpoints;
  final bool editMode;
  final void Function(int index) onShowOnMap;
  final void Function(int index) onEdit;
  final void Function(int index) onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    if (editMode) {
      return ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: checkpoints.length,
        onReorderItem: (int oldIndex, int newIndex) {
          onReorder(oldIndex, newIndex);
        },
        proxyDecorator: (child, index, animation) => Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(8),
          child: child,
        ),
        itemBuilder: (context, index) => _buildEditRow(context, index),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < checkpoints.length; index++)
          _buildNormalRow(context, index),
      ],
    );
  }

  Widget _buildNormalRow(BuildContext context, int index) {
    final cp = checkpoints[index];
    final isLast = index == checkpoints.length - 1;
    return IntrinsicHeight(
      key: ValueKey('cp_$index'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  color: _WizardColors.greenSoftFor(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${index + 1}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _WizardColors.green,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: _WizardColors.separatorFor(context),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cp.name,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _WizardColors.textFor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${cp.latitude.toStringAsFixed(5)}, ${cp.longitude.toStringAsFixed(5)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _WizardColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: IconButton(
              onPressed: () => onShowOnMap(index),
              icon: Icon(
                Icons.near_me_rounded,
                size: 20,
                color: _WizardColors.secondaryTextFor(context),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'Show on map',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditRow(BuildContext context, int index) {
    final cp = checkpoints[index];
    final canRemove =
        checkpoints.length > 3 && index > 0 && index < checkpoints.length - 1;
    return Padding(
      key: ValueKey('edit_cp_$index'),
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: _WizardColors.greenSoftFor(context),
        borderRadius: BorderRadius.circular(8),
        child: IntrinsicHeight(
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: _WizardColors.secondaryTextFor(context),
                    size: 24,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cp.name,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _WizardColors.textFor(context),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${cp.latitude.toStringAsFixed(5)}, ${cp.longitude.toStringAsFixed(5)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _WizardColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: () => onEdit(index),
                icon: const Icon(Icons.edit_outlined, size: 20),
                color: _WizardColors.green,
                tooltip: 'Edit name',
              ),
              if (canRemove)
                IconButton(
                  onPressed: () => onRemove(index),
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  color: _WizardColors.red,
                  tooltip: 'Remove',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

DateTime _minimumScheduledDepartureTime() {
  final minimum = DateTime.now().add(const Duration(minutes: 10));
  final minutePrecision = DateTime(
    minimum.year,
    minimum.month,
    minimum.day,
    minimum.hour,
    minimum.minute,
  );
  if (minimum.second == 0 &&
      minimum.millisecond == 0 &&
      minimum.microsecond == 0) {
    return minutePrecision;
  }
  return minutePrecision.add(const Duration(minutes: 1));
}

Duration _safePlannedHikeDuration(HikeSessionDraft draft) {
  final duration = draft.expectedArrivalTime.difference(draft.departureTime);
  if (!duration.isNegative && duration > Duration.zero) {
    return duration;
  }
  return Duration(minutes: math.max(1, draft.trail.estimatedDurationMinutes));
}

HikeSessionDraft _withSafeRecordingInterval(HikeSessionDraft draft) {
  final interval = draft.locationRecordingInterval;
  final safeInterval = interval <= Duration.zero
      ? HikeSessionDraft.defaultLocationRecordingInterval
      : interval > const Duration(minutes: 1)
      ? const Duration(minutes: 1)
      : interval;
  return safeInterval == interval
      ? draft
      : draft.copyWith(locationRecordingInterval: safeInterval);
}

HikeSessionDraft _withPlatformSafetyPolicy(HikeSessionDraft draft) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return draft;
  final settings = draft.fallDetectionSettings;
  const androidWarningWindow = Duration(seconds: 15);
  if (settings.fallResponseDuration == androidWarningWindow) return draft;
  return draft.copyWith(
    fallDetectionSettings: FallDetectionSettings(
      sensorSensitivity: settings.sensorSensitivity,
      fallResponseDuration: androidWarningWindow,
      longestRestDuration: settings.longestRestDuration,
    ),
  );
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
  static const Color orange = Color(0xFFF59E0B);
  static const Color red = Color(0xFFE11D48);

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

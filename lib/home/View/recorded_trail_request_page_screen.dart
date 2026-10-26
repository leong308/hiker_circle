part of '../recorded_trail_request_page_feature.dart';

/// Submit only the chosen recorded hike and named checkpoints as the proposed trail source.
class RecordedTrailRequestPage extends StatefulWidget {
  /// Creates recorded trail request page.
  const RecordedTrailRequestPage({
    super.key,
    required this.session,
    required this.repository,
    required this.hike,
    required this.report,
    this.recordedMapOverride,
  });
  final Widget? recordedMapOverride;
  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final ActiveHikeSession hike;
  final HikeSummaryReport report;

  /// Creates the presentation state for this widget.
  @override
  State<RecordedTrailRequestPage> createState() =>
      _RecordedTrailRequestPageState();
}

/// Manages the recorded trail request page presentation and lifecycle.
class _RecordedTrailRequestPageState extends State<RecordedTrailRequestPage> {
  late final points = HikeSummaryReport.recordedRoutePointsFor(widget.hike);
  late final mapPoints = recordedHikeMapPoints(widget.hike);
  final name = TextEditingController(),
      area = TextEditingController(),
      state = TextEditingController(),
      country = TextEditingController(text: 'Malaysia');
  final form = GlobalKey<FormState>();
  late final selections = <int, String>{
    0: 'Starting point',
    points.length - 1: 'Finish',
  };
  int selected = 0;
  bool saving = false;
  double progress = 0;
  String? error;

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    for (final c in [name, area, state, country]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Adds checkpoint.
  Future<void> addCheckpoint() async {
    if (selections.containsKey(selected) || selections.length >= 12) {
      return;
    }
    final value = await _presentAddCheckpointEffect1();
    if (mounted && value?.isNotEmpty == true) {
      setState(() => selections[selected] = value!);
    }
  }

  /// Validate the recorded trail proposal before saving the request for administrator review.
  Future<void> submit() async {
    if (saving || form.currentState?.validate() != true) {
      return;
    }
    if (points.length < 3 || selections.length < 3) {
      setState(
        () => error =
            'Choose at least one checkpoint between the start and finish.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
      progress = 0;
    });
    try {
      final keys = selections.keys.toList()..sort();
      await _RecordedTrailRequestPageDataActions.submitRecordedTrailRequest(
        widget.repository,
      )(
        session: widget.session,
        activeHike: widget.hike,
        report: widget.report,
        proposed: {
          'name': name.text.trim(),
          'area': area.text.trim(),
          'state': state.text.trim(),
          'country': country.text.trim(),
        },
        checkpointSelections: [
          for (final i in keys) {'index': i, 'name': selections[i]},
        ],
        onProgress: (p) {
          if (mounted) {
            setState(() => progress = p);
          }
        },
      );
      if (mounted) {
        setState(() => saving = false);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is HikerCircleFirebaseRepositoryException
              ? e.message
              : 'Unable to submit. Your recorded route and checkpoint choices are still here; check your connection and retry.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (points.length < 3) {
      return Scaffold(
        appBar: PageHeaderAppBar(title: const Text('Suggest a new trail')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'This hike has too few GPS samples to create a trail. A recorded pathway and at least three checkpoints are required.',
          ),
        ),
      );
    }
    final chosen = points[selected];
    final keys = selections.keys.toList()..sort();
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      PageHeaderAction(
                        tooltip: 'Back',
                        icon: Icons.arrow_back_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        surface: Theme.of(context).colorScheme.surface,
                        onPressed: saving ? null : () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Suggest a new trail',
                          style: PageHeaderStyle.title(
                            context,
                            Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Choose checkpoints on the path you recorded. Admins receive the full GPS track privately. If approved, the route and checkpoints become part of the public trail library.',
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 250,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child:
                          widget.recordedMapOverride ??
                          RoutePreviewMap(
                            trail: widget.hike.trail,
                            recordedTrackPoints: mapPoints,
                            pinnedPoints: [
                              for (final index in selections.keys)
                                mapbox.Point(
                                  coordinates: mapbox.Position(
                                    points[index].longitude,
                                    points[index].latitude,
                                  ),
                                ),
                              if (!selections.containsKey(selected))
                                mapbox.Point(
                                  coordinates: mapbox.Position(
                                    chosen.longitude,
                                    chosen.latitude,
                                  ),
                                ),
                            ],
                            animateRoute: false,
                            captureAllGestures: true,
                          ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Select a point on your recording · ${selected + 1}/${points.length}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Slider(
                    value: selected.toDouble(),
                    min: 0,
                    max: (points.length - 1).toDouble(),
                    onChanged: saving
                        ? null
                        : (v) => setState(() => selected = v.round()),
                  ),
                  Text(
                    '${chosen.latitude.toStringAsFixed(5)}, ${chosen.longitude.toStringAsFixed(5)} · ${chosen.capturedAt.toLocal().hour.toString().padLeft(2, '0')}:${chosen.capturedAt.toLocal().minute.toString().padLeft(2, '0')}',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed:
                        saving ||
                            selections.containsKey(selected) ||
                            selections.length >= 12
                        ? null
                        : addCheckpoint,
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Add checkpoint here'),
                  ),
                  for (final i in keys)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 15,
                        child: Text('${keys.indexOf(i) + 1}'),
                      ),
                      title: Text(selections[i]!),
                      subtitle: Text('Recorded point ${i + 1}'),
                      trailing: i == 0 || i == points.length - 1
                          ? null
                          : IconButton(
                              tooltip: 'Remove checkpoint',
                              onPressed: saving
                                  ? null
                                  : () => setState(() => selections.remove(i)),
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  const SizedBox(height: 16),
                  for (final pair in [
                    ('Trail name', name),
                    ('Area / locality', area),
                    ('State / region', state),
                    ('Country', country),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: pair.$2,
                        enabled: !saving,
                        maxLength: 160,
                        decoration: InputDecoration(
                          labelText: pair.$1,
                          counterText: '',
                        ),
                        validator: (v) =>
                            v?.trim().isNotEmpty == true ? null : 'Required',
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (saving) ...[
                    LinearProgressIndicator(
                      value: progress > 0 ? progress : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      progress == 1
                          ? 'Validating the complete route…'
                          : 'Syncing hike and uploading the recording…',
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: saving ? null : submit,
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Send for admin review'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Presents the add checkpoint effect1 UI.
  Future<String?> _presentAddCheckpointEffect1() => showDialog<String>(
    context: context,
    builder: (_) =>
        _CheckpointNameDialog(initialName: 'Checkpoint ${selections.length}'),
  );
}

/// Displays the checkpoint name dialog.
class _CheckpointNameDialog extends StatefulWidget {
  /// Creates checkpoint name dialog.
  const _CheckpointNameDialog({required this.initialName});
  final String initialName;

  /// Creates the presentation state for this widget.
  @override
  State<_CheckpointNameDialog> createState() => _CheckpointNameDialogState();
}

/// Manages the checkpoint name dialog presentation and lifecycle.
class _CheckpointNameDialogState extends State<_CheckpointNameDialog> {
  late final controller = TextEditingController(text: widget.initialName);

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Name this checkpoint'),
    content: TextField(
      controller: controller,
      maxLength: 100,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Landmark or checkpoint'),
      onSubmitted: (value) => Navigator.pop(context, value.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text.trim()),
        child: const Text('Add checkpoint'),
      ),
    ],
  );
}

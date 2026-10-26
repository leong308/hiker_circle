part of '../recorded_trail_requests_page_feature.dart';

/// Separate the request list from the detailed recorded-route review and approval flow.
class RecordedTrailRequestsPage extends StatefulWidget {
  /// Creates recorded trail requests page.
  const RecordedTrailRequestsPage({
    super.key,
    required this.session,
    required this.repository,
    this.recordedMapBuilder,
  });
  final Widget Function(Trail, List<HikeCoordinate>)? recordedMapBuilder;
  final AppSession session;
  final HikerCircleFirebaseRepository repository;

  /// Creates the presentation state for this widget.
  @override
  State<RecordedTrailRequestsPage> createState() =>
      _RecordedTrailRequestsPageState();
}

/// Manages the recorded trail requests page presentation and lifecycle.
class _RecordedTrailRequestsPageState extends State<RecordedTrailRequestsPage> {
  late final _RecordedTrailRequestsPageStateViewModel _screenModel;

  /// Returns rows.
  List<Map<String, dynamic>>? get rows => _screenModel.stateRows;

  /// Updates rows.
  set rows(List<Map<String, dynamic>>? value) => _screenModel.stateRows = value;

  /// Returns error.
  String? get error => _screenModel.stateError;

  /// Updates error.
  set error(String? value) => _screenModel.stateError = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _RecordedTrailRequestsPageStateViewModel(
      readRepository: () => widget.repository,
      readSession: () => widget.session,
    )..addListener(_renderScreenModel);

    load();
  }

  /// Delegates load to the ViewModel.
  Future<void> load() => _screenModel.commandLoad();

  /// Opens.
  Future<void> open(Map<String, dynamic> request) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RecordedTrailReviewPage(
          session: widget.session,
          repository: widget.repository,
          request: request,
          recordedMapBuilder: widget.recordedMapBuilder,
        ),
      ),
    );
    if (mounted) {
      await load();
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AdminUi.background(context),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            AdminHeading(
              title: 'Undiscovered trail requests',
              subtitle:
                  'Review a hiker’s full recording before adding a route.',
              onBack: () => Navigator.pop(context),
            ),
            const SizedBox(height: 18),
            if (error != null)
              AdminPanel(
                child: Column(
                  children: [
                    Text(error!),
                    TextButton(onPressed: load, child: const Text('Retry')),
                  ],
                ),
              )
            else if (rows == null)
              const Center(child: CircularProgressIndicator())
            else if (rows!.isEmpty)
              const AdminEmptyState(
                title: 'No requests awaiting review',
                message: 'New recorded-route submissions will appear here.',
                icon: Icons.route_outlined,
              )
            else
              for (final request in rows!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AdminPanel(
                    onTap: () => open(request),
                    child: Row(
                      children: [
                        Icon(
                          Icons.route_rounded,
                          color: AdminUi.green(context),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (request['proposed'] as Map)['name'].toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${request['pointCount']} GPS samples · ${(request['checkpoints'] as List).length} checkpoints',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AdminUi.muted(context),
                                ),
                              ),
                              Text(
                                '${(request['proposed'] as Map)['area']} · ${(request['proposed'] as Map)['state']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AdminUi.muted(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    ),
  );

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }
}

/// Displays the recorded trail review page.
class _RecordedTrailReviewPage extends StatefulWidget {
  /// Creates recorded trail review page.
  const _RecordedTrailReviewPage({
    required this.session,
    required this.repository,
    required this.request,
    this.recordedMapBuilder,
  });
  final Widget Function(Trail, List<HikeCoordinate>)? recordedMapBuilder;
  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final Map<String, dynamic> request;

  /// Creates the presentation state for this widget.
  @override
  State<_RecordedTrailReviewPage> createState() =>
      _RecordedTrailReviewPageState();
}

/// Manages the recorded trail review page presentation and lifecycle.
class _RecordedTrailReviewPageState extends State<_RecordedTrailReviewPage> {
  late final _RecordedTrailReviewPageStateViewModel _screenModel;

  /// Returns points.
  List<HikeCoordinate>? get points => _screenModel.statePoints;

  /// Updates points.
  set points(List<HikeCoordinate>? value) => _screenModel.statePoints = value;

  /// Returns error.
  String? get error => _screenModel.stateError;

  /// Updates error.
  set error(String? value) => _screenModel.stateError = value;

  /// Returns saving.
  bool get saving => _screenModel.stateSaving;

  /// Updates saving.
  set saving(bool value) => _screenModel.stateSaving = value;

  /// Returns verified.
  bool get verified => _screenModel.stateVerified;

  /// Updates verified.
  set verified(bool value) => _screenModel.stateVerified = value;

  /// Returns checking duplicate.
  bool get checkingDuplicate => _screenModel.stateCheckingDuplicate;

  /// Updates checking duplicate.
  set checkingDuplicate(bool value) =>
      _screenModel.stateCheckingDuplicate = value;

  /// Returns review allowed.
  bool get reviewAllowed => _screenModel.stateReviewAllowed;

  /// Updates review allowed.
  set reviewAllowed(bool value) => _screenModel.stateReviewAllowed = value;

  /// Returns duplicate dialog open.
  bool get duplicateDialogOpen => _screenModel.stateDuplicateDialogOpen;

  /// Updates duplicate dialog open.
  set duplicateDialogOpen(bool value) =>
      _screenModel.stateDuplicateDialogOpen = value;

  /// Returns duplicate match.
  TrailDuplicateMatch? get duplicateMatch => _screenModel.stateDuplicateMatch;

  /// Updates duplicate match.
  set duplicateMatch(TrailDuplicateMatch? value) =>
      _screenModel.stateDuplicateMatch = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  List<mapbox.Point>? mapPoints;
  Trail? candidate;

  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      area = TextEditingController(),
      state = TextEditingController(),
      country = TextEditingController(),
      duration = TextEditingController(),
      elevation = TextEditingController(),
      note = TextEditingController();

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _RecordedTrailReviewPageStateViewModel(
      readRepository: () => widget.repository,
      effectChooseDuplicateAction: chooseDuplicateAction,
    )..addListener(_renderScreenModel);

    load();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    for (final c in [name, area, state, country, duration, elevation, note]) {
      c.dispose();
    }

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Loads.
  Future<void> load() async {
    try {
      final loaded =
          await _RecordedTrailRequestsPageDataActions.loadRecordedTrailRequestPoints(
            widget.repository,
          )(
            session: widget.session,
            requestId: widget.request['requestId'] as String,
          );
      final trail = recordedTrailCandidate(widget.request, loaded);
      if (!mounted) {
        return;
      }
      setState(() {
        points = loaded;
        mapPoints = [
          for (final p in loaded)
            mapbox.Point(coordinates: mapbox.Position(p.longitude, p.latitude)),
        ];
        candidate = trail;
        name.text = trail.name;
        area.text = trail.area;
        state.text = trail.state;
        country.text = trail.country;
        duration.text = '${trail.estimatedDurationMinutes}';
        elevation.text = '${trail.elevationGainMeters}';
      });
      await checkDuplicate();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is HikerCircleFirebaseRepositoryException
              ? e.message
              : 'The full recording could not load. Reopen this request to retry.',
        );
      }
    }
  }

  /// Delegates check duplicate to the ViewModel.
  Future<void> checkDuplicate() => _screenModel.commandCheckDuplicate();

  /// Computes choose duplicate action.
  Future<void> chooseDuplicateAction() async {
    final match = duplicateMatch;
    if (match == null || saving || duplicateDialogOpen) return;
    duplicateDialogOpen = true;
    try {
      final decision = await showTrailDuplicateDialog(
        context,
        match: match,
        reviewingSubmission: true,
      );
      if (!mounted) return;
      if (decision == TrailDuplicateDecision.proceedReview) {
        setState(() {
          reviewAllowed = true;
          error = null;
        });
      } else if (decision == TrailDuplicateDecision.unapprove) {
        await saveRejection(
          'Duplicate route: ${match.percentage}% overlaps “${match.trailName}” '
          '(within ${TrailRouteSimilarity.toleranceMeters.round()} m).',
        );
      }
    } finally {
      duplicateDialogOpen = false;
    }
  }

  /// Computes publish.
  Future<void> publish() async {
    if (saving ||
        checkingDuplicate ||
        !reviewAllowed ||
        candidate == null ||
        form.currentState?.validate() != true) {
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await _RecordedTrailRequestsPageDataActions.approveRecordedTrailRequest(
        widget.repository,
      )(
        session: widget.session,
        requestId: widget.request['requestId'] as String,
        points: points!,
        trail: candidate!.copyWith(
          name: name.text.trim(),
          area: area.text.trim(),
          state: state.text.trim(),
          country: country.text.trim(),
          estimatedDurationMinutes: int.parse(duration.text),
          elevationGainMeters: int.parse(elevation.text),
          isVerifiedTrail: verified,
        ),
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
              : 'Unable to add this trail. The request remains available; retry after checking your connection.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  /// Computes reject.
  Future<void> reject() async {
    final yes = await _presentRejectEffect1();
    if (yes != true || !mounted) {
      return;
    }
    await saveRejection(note.text);
  }

  /// Saves rejection.
  Future<void> saveRejection(String reviewNote) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await _RecordedTrailRequestsPageDataActions.rejectRecordedTrailRequest(
        widget.repository,
      )(
        session: widget.session,
        requestId: widget.request['requestId'] as String,
        note: reviewNote,
      );
      if (mounted) {
        setState(() => saving = false);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'The decision could not save. Retry before leaving this request.',
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
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      backgroundColor: AdminUi.background(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminHeading(
                  title: 'Review undiscovered trail',
                  subtitle:
                      'Full GPS pathway with the hiker’s chosen checkpoints.',
                  onBack: saving ? null : () => Navigator.pop(context),
                ),
                const SizedBox(height: 18),
                if (candidate == null && error == null)
                  const Center(child: CircularProgressIndicator()),
                if (candidate != null) ...[
                  if (checkingDuplicate) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text(
                      'Checking the full recording against saved trails…',
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (!checkingDuplicate && !reviewAllowed) ...[
                    AdminPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            duplicateMatch != null
                                ? 'Choose how to handle the possible duplicate before reviewing.'
                                : 'Complete the duplicate check before reviewing.',
                          ),
                          TextButton(
                            onPressed: saving
                                ? null
                                : duplicateMatch != null
                                ? chooseDuplicateAction
                                : checkDuplicate,
                            child: Text(
                              duplicateMatch != null
                                  ? 'Review duplicate warning'
                                  : 'Retry duplicate check',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  SizedBox(
                    height: 300,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child:
                          widget.recordedMapBuilder?.call(
                            candidate!,
                            points!,
                          ) ??
                          RoutePreviewMap(
                            trail: candidate!,
                            recordedTrackPoints: mapPoints!,
                            pinnedPoints: [
                              for (final c in candidate!.checkpoints)
                                mapbox.Point(
                                  coordinates: mapbox.Position(
                                    c.longitude,
                                    c.latitude,
                                  ),
                                ),
                            ],
                            animateRoute: false,
                            captureAllGestures: true,
                          ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AdminPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${points!.length} GPS samples · ${candidate!.distanceKm.toStringAsFixed(2)} km recorded',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'The pathway comes from this hiker’s GPS recording. No routing API will redraw it through checkpoints. Review gaps, permissions and terrain before publishing. Typical duration below is editable; the recorded hike duration is only an initial estimate.',
                        ),
                        const SizedBox(height: 8),
                        for (final c in candidate!.checkpoints)
                          Text(
                            '${c.order}. ${c.name} · ${c.latitude.toStringAsFixed(5)}, ${c.longitude.toStringAsFixed(5)}',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
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
                        enabled: !saving && reviewAllowed,
                        maxLength: 160,
                        decoration: InputDecoration(
                          labelText: pair.$1,
                          counterText: '',
                        ),
                        validator: (v) =>
                            v?.trim().isNotEmpty == true ? null : 'Required',
                      ),
                    ),
                  TextFormField(
                    controller: duration,
                    enabled: !saving && reviewAllowed,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Typical duration (minutes)',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n != null && n >= 15 && n <= 10080
                          ? null
                          : 'Enter 15–10080 minutes';
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: elevation,
                    enabled: !saving && reviewAllowed,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Elevation gain (m)',
                      helperText:
                          'Verify this estimate from recorded GPS altitude.',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n != null && n >= 0
                          ? null
                          : 'Enter a non-negative elevation gain';
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mark trail as verified'),
                    value: verified,
                    onChanged: saving || !reviewAllowed
                        ? null
                        : (v) => setState(() => verified = v),
                  ),
                  FilledButton.icon(
                    onPressed: saving || checkingDuplicate || !reviewAllowed
                        ? null
                        : publish,
                    icon: const Icon(Icons.add_road_rounded),
                    label: const Text('Add to trail library'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: saving ? null : reject,
                    child: const Text('Reject request'),
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (saving) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  /// Presents the reject effect1 UI.
  Future<bool?> _presentRejectEffect1() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reject this trail request?'),
      content: TextField(
        controller: note,
        maxLength: 500,
        decoration: const InputDecoration(labelText: 'Review note (optional)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Reject request'),
        ),
      ],
    ),
  );
}

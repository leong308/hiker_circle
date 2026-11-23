part of '../trail_caution_details_feature.dart';

/// Presents nearby cautions as separate cards beneath a fixed sheet header.
class TrailCautionDetailsSheet extends StatelessWidget {
  /// Creates a live sheet with an injectable data source for isolated previews.
  const TrailCautionDetailsSheet({
    super.key,
    required this.reports,
    this.allowFeedback = false,
    this.repository = const FirebaseTrailCautionDetailsRepository(),
  });
  final List<CommunityHazard> reports;
  final bool allowFeedback;
  final TrailCautionDetailsRepository repository;

  /// Keeps the title visible while the caution cards scroll independently.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.min(760, MediaQuery.sizeOf(context).height * .82),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        reports.length == 1
                            ? 'Trail caution'
                            : '${reports.length} nearby cautions',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PageHeaderAction(
                      tooltip: 'Close cautions',
                      icon: Icons.close_rounded,
                      onPressed: () => Navigator.of(context).maybePop(),
                      color: colors.onSurfaceVariant,
                      surface: colors.surface,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: reports.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _CautionDetail(
                    key: ValueKey(reports[index].id),
                    report: reports[index],
                    allowFeedback: allowFeedback,
                    repository: repository,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Binds one caution card to its account-scoped ViewModel and UI effects.
class _CautionDetail extends StatefulWidget {
  /// Creates the presentation binding for one report.
  const _CautionDetail({
    super.key,
    required this.report,
    required this.allowFeedback,
    required this.repository,
  });
  final CommunityHazard report;
  final bool allowFeedback;
  final TrailCautionDetailsRepository repository;

  /// Creates the card's presentation state.
  @override
  State<_CautionDetail> createState() => _CautionDetailState();
}

/// Keeps dialog and snackbar effects in the view while the model owns data.
class _CautionDetailState extends State<_CautionDetail> {
  late TrailCautionDetailsViewModel _viewModel;

  /// Attaches the initial report binding.
  @override
  void initState() {
    super.initState();
    _bindModel();
  }

  /// Starts listening to the report and the current viewer's own votes.
  void _bindModel() {
    _viewModel = TrailCautionDetailsViewModel(
      report: widget.report,
      repository: widget.repository,
      allowFeedback: widget.allowFeedback,
    )..addListener(_render);
  }

  /// Rebuilds the card when its presentation state changes.
  void _render() {
    if (mounted) setState(() {});
  }

  /// Rebinds changed sources and keeps fallback data fresh while offline.
  @override
  void didUpdateWidget(covariant _CautionDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.report.id != oldWidget.report.id ||
        widget.repository != oldWidget.repository ||
        widget.allowFeedback != oldWidget.allowFeedback) {
      _viewModel.removeListener(_render);
      _viewModel.dispose();
      _bindModel();
    } else if (widget.report != oldWidget.report) {
      _viewModel.updateInitialReport(widget.report);
    }
  }

  /// Opens evidence entry for status changes and delegates confirmations.
  Future<void> _act(String action) async {
    if (_viewModel.busy) return;
    if (action == 'resolve' || action == 'reopen') {
      final allowed = action == 'resolve'
          ? _viewModel.canReportResolution
          : _viewModel.canReopen;
      if (allowed) {
        await showCautionEvidenceDialog(context, _viewModel.report, action);
      }
      return;
    }
    final saved = await _viewModel.confirm(action);
    if (!mounted || saved == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Your confirmation was saved.'
              : 'Your confirmation was already counted.',
        ),
      ),
    );
  }

  /// Renders the latest card state without owning cloud subscriptions.
  @override
  Widget build(BuildContext context) => _CautionReportCard(
    model: _viewModel,
    onAction: (action) => unawaited(_act(action)),
  );

  /// Releases the card's subscriptions and expiry timer.
  @override
  void dispose() {
    _viewModel.removeListener(_render);
    _viewModel.dispose();
    super.dispose();
  }
}

/// Computes caution action label.
String cautionActionLabel(String action) => switch (action) {
  'resolve' => 'Reported resolved / not seen',
  'confirmResolution' => 'Confirmed resolved / not seen',
  'reopen' => 'Caution reported present again',
  _ => 'Caution confirmed',
};

/// Computes caution update id.
String cautionUpdateId() => newCautionUpdateId();

/// Computes caution date.
String cautionDate(DateTime time) {
  final local = time.toLocal();
  return '${local.day}/${local.month}/${local.year} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Computes caution error.
String cautionError(Object error) {
  if (error is FirebaseFunctionsException) {
    return error.message ?? 'Unable to save your update. Please retry.';
  }
  if (error is FirebaseException) {
    return 'Media could not upload. Check your connection and retry.';
  }
  return error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');
}

/// Collect additional report evidence before invoking the selected caution action.
Future<void> showCautionEvidenceDialog(
  BuildContext context,
  CommunityHazard report,
  String action, {
  TrailCautionService? service,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  isDismissible: false,
  enableDrag: false,
  builder: (_) => _CautionEvidenceSubmission(
    report: report,
    action: action,
    service: service ?? TrailCautionService(),
  ),
);

/// Displays the caution evidence submission.
class _CautionEvidenceSubmission extends StatefulWidget {
  /// Creates caution evidence submission.
  const _CautionEvidenceSubmission({
    required this.report,
    required this.action,
    required this.service,
  });
  final CommunityHazard report;
  final String action;
  final TrailCautionService service;

  /// Creates the presentation state for this widget.
  @override
  State<_CautionEvidenceSubmission> createState() =>
      _CautionEvidenceSubmissionState();
}

/// Manages the caution evidence submission presentation and lifecycle.
class _CautionEvidenceSubmissionState
    extends State<_CautionEvidenceSubmission> {
  final editor = GlobalKey<CautionEvidenceEditorState>();
  late final requestId = cautionUpdateId();
  bool busy = false, confirmed = false;
  String? error;

  /// Computes submit.
  Future<void> submit() async {
    if (busy) return;
    final route = ModalRoute.of<void>(context);
    final evidence = editor.currentState!;
    final reopening = widget.action == 'reopen';
    if (reopening && (!confirmed || !evidence.hasEvidence)) {
      setState(
        () => error =
            'Confirm the caution is present and add a note or media evidence.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.service.update(
        widget.report.id,
        widget.action,
        requestId: requestId,
        description: evidence.note.text,
        files: evidence.files,
        confirmed: confirmed,
      );
      if (mounted) _presentSubmitEffect1(route);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = cautionError(e);
        });
      }
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.action == 'reopen'
                        ? 'Is this caution present again?'
                        : 'Resolved / Not Seen',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: busy ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.action == 'reopen'
                  ? 'Your evidence will reopen the caution for hikers.'
                  : 'Share what you saw. Three independent confirmations mark the caution resolved.',
            ),
            const SizedBox(height: 16),
            CautionEvidenceEditor(
              key: editor,
              enabled: !busy,
              requiredEvidence: widget.action == 'reopen',
            ),
            if (widget.action == 'reopen')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I confirm this caution is present'),
                value: confirmed,
                onChanged: busy
                    ? null
                    : (value) => setState(() => confirmed = value),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : submit,
              icon: Icon(
                widget.action == 'reopen'
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline,
              ),
              label: Text(
                busy
                    ? 'Submitting…'
                    : widget.action == 'reopen'
                    ? 'Reopen with evidence'
                    : 'Submit update',
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// Presents the submit effect1 UI.
  void _presentSubmitEffect1(ModalRoute<void>? route) =>
      HikeStartNavigation.closeOwnedRoute(route);
}

/// Displays the trail cautions history.
class TrailCautionsHistory extends StatefulWidget {
  /// Creates trail cautions history.
  const TrailCautionsHistory({super.key, required this.trailId});
  final String trailId;

  /// Creates the presentation state for this widget.
  @override
  State<TrailCautionsHistory> createState() => _TrailCautionsHistoryState();
}

/// Manages the trail cautions history presentation and lifecycle.
class _TrailCautionsHistoryState extends State<TrailCautionsHistory> {
  late final timer = Timer.periodic(const Duration(minutes: 1), (_) {
    if (mounted) setState(() {});
  });

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    timer;
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Firebase.apps.isEmpty
      ? const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(label: 'Trail Cautions History'),
            SizedBox(height: 8),
            Text('Sign in to view caution history.'),
          ],
        )
      : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          // Query live hazards on this trail
          stream: FirebaseFirestore.instance
              .collection('hazardReports')
              .where('trailId', isEqualTo: widget.trailId)
              .snapshots(),
          builder: (context, snapshot) {
            final reports =
                snapshot.data?.docs
                    .map(
                      (d) => CommunityHazard.fromMap(
                        d.id,
                        d.data(),
                        includeExpired: true,
                      ),
                    )
                    .whereType<CommunityHazard>()
                    .toList() ??
                [];
            return TrailCautionsHistoryList(
              reports: reports,
              loading: snapshot.connectionState == ConnectionState.waiting,
              hasError: snapshot.hasError,
            );
          },
        );
}

/// Computes sort trail cautions for history.
List<CommunityHazard> sortTrailCautionsForHistory(
  Iterable<CommunityHazard> reports, {
  required DateTime now,
}) {
  /// Computes rank.
  int rank(CommunityHazard report) => !report.isActiveAt(now)
      ? 2
      : report.isResolved
      ? 1
      : 0;
  return reports.toList()..sort((a, b) {
    final statusOrder = rank(a).compareTo(rank(b));
    if (statusOrder != 0) return statusOrder;
    final dateOrder = (b.reportedAt ?? DateTime(2000)).compareTo(
      a.reportedAt ?? DateTime(2000),
    );
    return dateOrder != 0 ? dateOrder : a.id.compareTo(b.id);
  });
}

/// Displays the trail cautions history list.
class TrailCautionsHistoryList extends StatelessWidget {
  /// Creates trail cautions history list.
  const TrailCautionsHistoryList({
    super.key,
    required this.reports,
    this.now,
    this.loading = false,
    this.hasError = false,
  });
  final List<CommunityHazard> reports;
  final DateTime? now;
  final bool loading, hasError;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final currentTime = now ?? DateTime.now();
    final sorted = sortTrailCautionsForHistory(reports, now: currentTime);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(label: 'Trail Cautions History'),
        const SizedBox(height: 12),
        if (hasError && sorted.isEmpty)
          const Text(
            'Caution history could not load. Try again when connected.',
          )
        else if (sorted.isEmpty)
          Text(
            loading
                ? 'Loading caution history…'
                : 'No cautions reported on this trail.',
          ),
        for (final report in sorted)
          TrailCautionHistoryCard(
            key: ValueKey('trail-caution-history-${report.id}'),
            report: report,
            active: report.isActiveAt(currentTime) && !report.isResolved,
            archived: !report.isActiveAt(currentTime),
          ),
      ],
    );
  }
}

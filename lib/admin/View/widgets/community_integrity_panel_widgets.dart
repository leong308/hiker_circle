part of '../../community_integrity_panel_feature.dart';

/// Displays the retained moderation queue without provider-specific controls.
class CommunityIntegrityPanel extends StatefulWidget {
  /// Accepts live sources so the same queue works in Circle and in tests.
  const CommunityIntegrityPanel({
    super.key,
    this.onReviewed,
    this.reviews,
    this.health,
    this.loadReviews,
    this.openReview,
    this.runChecks,
  });
  final VoidCallback? onReviewed;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? reviews;
  final Stream<DocumentSnapshot<Map<String, dynamic>>>? health;
  final Stream<QuerySnapshot<Map<String, dynamic>>> Function(int limit)?
  loadReviews;
  final Future<bool?> Function(CommunityFlag flag)? openReview;
  final Future<Map<String, dynamic>> Function()? runChecks;

  /// Binds the queue's presentation lifecycle.
  @override
  State<CommunityIntegrityPanel> createState() =>
      _CommunityIntegrityPanelState();
}

/// Owns only text entry and the filter/review navigation presentation.
class _CommunityIntegrityPanelState extends State<CommunityIntegrityPanel> {
  late final _CommunityIntegrityPanelStateViewModel _screenModel;
  final _searchController = TextEditingController();

  /// Binds the ViewModel to the selected data sources and review destination.
  @override
  void initState() {
    super.initState();
    _screenModel = _CommunityIntegrityPanelStateViewModel(
      readHealth: () => widget.health,
      readLoadReviews: () => widget.loadReviews,
      readReviews: () => widget.reviews,
      readRunChecks: () => widget.runChecks,
    )..addListener(_render);
    _screenModel.readOpenReview = () => widget.openReview;
    _screenModel.readOnReviewed = () => widget.onReviewed;
    _screenModel.effectPresentOpenEffect1 = _presentReview;
  }

  /// Reconnects when a parent replaces an injected/live data source.
  @override
  void didUpdateWidget(covariant CommunityIntegrityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reviews != widget.reviews ||
        oldWidget.health != widget.health ||
        oldWidget.loadReviews != widget.loadReviews) {
      _screenModel.commandRefresh();
    }
  }

  /// Rebuilds when queue controls or navigation state change.
  void _render() {
    if (mounted) setState(() {});
  }

  /// Releases text entry and ViewModel listeners.
  @override
  void dispose() {
    _searchController.dispose();
    _screenModel.removeListener(_render);
    _screenModel.dispose();
    super.dispose();
  }

  /// Clears both visible text entry and the applied filter model.
  void _clear() {
    _searchController.clear();
    _screenModel.commandClearFilters();
  }

  /// Formats timestamps without exposing model/provider implementation fields.
  String _date(DateTime? date) {
    if (date == null) return 'Time unavailable';
    final local = MaterialLocalizations.of(context);
    return '${local.formatMediumDate(date)} · ${local.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }

  /// Presents scan health, compact controls and the pending review cards.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionLabel(label: 'Community checks'),
      const SizedBox(height: 8),
      AdminPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _FlagGlyph(icon: Icons.fact_check_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Rule-based checks',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const CommunityModerationRulesButton(compact: true),
                IconButton(
                  tooltip: 'Refresh rule-based checks',
                  onPressed: _screenModel.commandCanRunChecks
                      ? () => unawaited(_screenModel.commandRunChecks())
                      : null,
                  icon: _screenModel.stateRefreshing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: HikerCircleMinorLoadingIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Each new public post triggers a check of all public posts and their comments.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AdminUi.muted(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            if (_screenModel.stateHealth != null)
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _screenModel.stateHealth,
                builder: _health,
              )
            else
              _checkStatus(_screenModel.stateManualHealth),
            if (_screenModel.stateRefreshError != null) ...[
              const SizedBox(height: 8),
              Text(
                _screenModel.stateRefreshError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 22),
      if (!_screenModel.commandHasReviews)
        const AdminEmptyState(
          title: 'Connect to load flagged content',
          message:
              'Your review queue will appear when a connection is available.',
          icon: Icons.cloud_off_rounded,
        )
      else ...[
        _controls(),
        const SizedBox(height: 18),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _screenModel.stateReviews,
          builder: _queue,
        ),
      ],
    ],
  );

  /// Keeps operational scan details secondary to the content awaiting review.
  Widget _health(
    BuildContext context,
    AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
  ) {
    final text = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: AdminUi.muted(context), height: 1.4);
    if (_screenModel.stateRefreshing) return _checkStatus(null);
    if (snapshot.hasError) {
      if (_screenModel.stateManualHealth != null) {
        return _checkStatus(_screenModel.stateManualHealth);
      }
      return Text(
        'Scan status could not load. Existing flags can still be reviewed.',
        style: text,
      );
    }
    if (!snapshot.hasData && _screenModel.stateManualHealth == null) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    final data = snapshot.data?.data();
    return _checkStatus(
      CommunityIntegrityStatus.latest(
        data == null
            ? (snapshot.hasData
                  ? const CommunityIntegrityStatus(status: '')
                  : null)
            : CommunityIntegrityStatus.fromMap(data),
        _screenModel.stateManualHealth,
      ),
    );
  }

  /// Shows the latest scan status.
  Widget _checkStatus(CommunityIntegrityStatus? status) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: AdminUi.muted(context), height: 1.4);
    if (_screenModel.stateRefreshing) {
      return Text('Refreshing checks…', style: style);
    }
    if (status == null) {
      return Text('Scan status unavailable while offline.', style: style);
    }
    if (status.isRunning) return Text('Checking now…', style: style);
    if (status.isFailed) {
      return Text('The last scan was incomplete.', style: style);
    }
    final last = status.lastRunAt;
    return Text(
      last == null
          ? 'Waiting for the first check'
          : 'Last checked ${_date(last)}',
      style: style,
    );
  }

  /// Shows search and one filter action instead of several always-open forms.
  Widget _controls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('flag-search'),
              controller: _searchController,
              onChanged: _screenModel.commandSearch,
              decoration: InputDecoration(
                hintText: 'Search flagged content',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          _screenModel.commandSearch('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Filter flagged content',
            onPressed: _showFilters,
            icon: Icon(
              _screenModel.stateFilters.isActive
                  ? Icons.filter_alt_rounded
                  : Icons.filter_list_rounded,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(
            _screenModel.stateFilters.description,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AdminUi.muted(context)),
          ),
          if (_screenModel.stateFilters.isActive)
            TextButton(onPressed: _clear, child: const Text('Reset filters')),
        ],
      ),
    ],
  );

  /// Renders only pending flags from the loaded subset, including older checks.
  Widget _queue(
    BuildContext context,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
  ) {
    if (snapshot.hasError) {
      return AdminPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Could not load flagged content',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text('Check your connection and try again.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _screenModel.commandRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (!snapshot.hasData) {
      return const AdminPanel(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final flags = _screenModel.commandFlags(snapshot.data!);
    final visible = _screenModel.stateFilters.apply(
      flags,
      _screenModel.stateQuery,
    );
    final hasMore = _screenModel.commandHasMore(snapshot.data!.docs.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: SectionLabel(label: 'Pending review')),
            Text(
              '${visible.length} of ${flags.length} loaded',
              key: const ValueKey('flag-results-count'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AdminUi.muted(context)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_screenModel.stateError != null) ...[
          Text(
            _screenModel.stateError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 10),
        ],
        if (snapshot.connectionState == ConnectionState.waiting)
          const LinearProgressIndicator(minHeight: 2),
        if (visible.isEmpty) ...[
          AdminEmptyState(
            title: flags.isEmpty ? 'All caught up' : 'No matching flags',
            message: flags.isEmpty
                ? 'New flags will appear here after a content check.'
                : 'Try another search or change your filters.',
            icon: flags.isEmpty
                ? Icons.task_alt_rounded
                : Icons.search_off_rounded,
          ),
          if (flags.isNotEmpty)
            TextButton(
              onPressed: _clear,
              child: const Text('Clear search and filters'),
            ),
        ],
        for (final flag in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _flagCard(flag),
          ),
        if (hasMore) ...[
          const SizedBox(height: 4),
          Text(
            'Search and sorting apply to loaded reviews. Load more to include the rest.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AdminUi.muted(context)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: snapshot.connectionState == ConnectionState.waiting
                ? null
                : _screenModel.commandLoadMore,
            icon: const Icon(Icons.expand_more_rounded),
            label: const Text('Load more reviews'),
          ),
        ],
      ],
    );
  }

  /// Uses one clear title, safe rule evidence and a quiet metadata line per flag.
  Widget _flagCard(CommunityFlag flag) {
    final colors = Theme.of(context).colorScheme;
    final urgent = const {'high', 'critical'}.contains(flag.severity);
    final opening = _screenModel.stateOpening.contains(flag.id);
    return AdminPanel(
      key: ValueKey('flag-card-${flag.id}'),
      padding: const EdgeInsets.all(16),
      onTap: _screenModel.stateOpening.isNotEmpty
          ? null
          : () => _screenModel.commandOpen(flag),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FlagGlyph(
                icon: flag.isComment
                    ? Icons.chat_bubble_outline_rounded
                    : Icons.article_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${flag.contentTypeLabel} · ${flag.sourceLabel}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AdminUi.muted(context),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      flag.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (opening)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.chevron_right_rounded, color: colors.primary),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            flag.evidenceLabels.isEmpty
                ? 'Read the original content before making a decision.'
                : flag.evidenceLabels.take(2).join(' · '),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AdminUi.muted(context),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(
                _date(flag.flaggedAt),
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: AdminUi.muted(context)),
              ),
              if (flag.severity != 'unknown')
                Text(
                  '${flag.severityLabel} priority',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: urgent ? colors.error : AdminUi.muted(context),
                    fontWeight: urgent ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Opens an editable filter draft; dismissal leaves the applied queue intact.
  Future<void> _showFilters() async {
    var source = _screenModel.stateFilters.source;
    var content = _screenModel.stateFilters.content;
    var sort = _screenModel.stateFilters.sort;
    final result = await showModalBottomSheet<CommunityFlagFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            18,
            4,
            18,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Filter flagged content',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<CommunityFlagSourceFilter>(
                key: ValueKey('flag-source-filter-${source.name}'),
                initialValue: source,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Detected by'),
                items: [
                  for (final value in CommunityFlagSourceFilter.values)
                    DropdownMenuItem(value: value, child: Text(value.label)),
                ],
                onChanged: (value) {
                  if (value != null) update(() => source = value);
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<CommunityFlagContentFilter>(
                key: ValueKey('flag-content-filter-${content.name}'),
                initialValue: content,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Content'),
                items: [
                  for (final value in CommunityFlagContentFilter.values)
                    DropdownMenuItem(value: value, child: Text(value.label)),
                ],
                onChanged: (value) {
                  if (value != null) update(() => content = value);
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<CommunityFlagSort>(
                key: ValueKey('flag-sort-${sort.name}'),
                initialValue: sort,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Sort'),
                items: [
                  for (final value in CommunityFlagSort.values)
                    DropdownMenuItem(value: value, child: Text(value.label)),
                ],
                onChanged: (value) {
                  if (value != null) update(() => sort = value);
                },
              ),
              const SizedBox(height: 18),
              TextButton(
                onPressed: () => update(() {
                  source = CommunityFlagSourceFilter.all;
                  content = CommunityFlagContentFilter.all;
                  sort = CommunityFlagSort.newest;
                }),
                child: const Text('Reset filters'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  CommunityFlagFilters(
                    source: source,
                    content: content,
                    sort: sort,
                  ),
                ),
                child: const Text('Apply filters'),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && result != null) _screenModel.commandFilter(result);
  }

  /// Presents the retained original-content review and human decision flow.
  Future<bool?> _presentReview(CommunityFlag flag) =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => CommunityFlagReviewPage(flag: flag)),
      );
}

/// Shares the Profile-style soft green icon treatment across queue cards.
class _FlagGlyph extends StatelessWidget {
  /// Creates one icon without changing a flag's category or severity.
  const _FlagGlyph({required this.icon});
  final IconData icon;

  /// Builds the fixed icon tile while allowing adjacent text to wrap.
  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
  );
}

// Administrators filter pending flags by source and review the original content.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../Model/community_flag.dart';
import 'admin_ui.dart';
import 'community_flag_review_page.dart';
import 'community_moderation_rules.dart';

class CommunityIntegrityPanel extends StatefulWidget {
  const CommunityIntegrityPanel({
    super.key,
    this.onReviewed,
    this.reviews,
    this.health,
    this.loadReviews,
    this.openReview,
  });
  final VoidCallback? onReviewed;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? reviews;
  final Stream<DocumentSnapshot<Map<String, dynamic>>>? health;
  final Stream<QuerySnapshot<Map<String, dynamic>>> Function(int limit)?
  loadReviews;
  final Future<bool?> Function(CommunityFlag flag)? openReview;

  @override
  State<CommunityIntegrityPanel> createState() =>
      _CommunityIntegrityPanelState();
}

enum _ContentFilter { all, post, comment }

enum _QueueSort { newest, oldest, priority }

class _CommunityIntegrityPanelState extends State<CommunityIntegrityPanel> {
  static const _pageSize = 50;
  int _limit = _pageSize;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _reviews = _reviewStream();
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _health = _healthStream();
  final _searchController = TextEditingController();
  CommunityFlagSourceFilter _source = CommunityFlagSourceFilter.all;
  _ContentFilter _content = _ContentFilter.all;
  _QueueSort _sort = _QueueSort.newest;
  final Set<String> _opening = {};
  final Map<String, String> _resolved = {};

  bool get _connected => Firebase.apps.isNotEmpty;
  bool get _hasReviews =>
      widget.reviews != null || widget.loadReviews != null || _connected;
  bool get _hasHealth => widget.health != null || _connected;

  Stream<QuerySnapshot<Map<String, dynamic>>> _reviewStream() =>
      widget.loadReviews?.call(_limit) ??
      widget.reviews ??
      FirebaseFirestore.instance
          .collection('communityModerationReviews')
          .where('status', isEqualTo: 'pending')
          .limit(_limit)
          .snapshots();
  Stream<DocumentSnapshot<Map<String, dynamic>>> _healthStream() =>
      widget.health ??
      FirebaseFirestore.instance
          .doc('communityModerationStatus/current')
          .snapshots();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() {
      if (_hasReviews) _reviews = _reviewStream();
      if (_hasHealth) _health = _healthStream();
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _source = CommunityFlagSourceFilter.all;
      _content = _ContentFilter.all;
    });
  }

  Future<void> _open(CommunityFlag flag) async {
    if (!_opening.add(flag.id)) return;
    try {
      final reviewed = widget.openReview != null
          ? await widget.openReview!(flag)
          : await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => CommunityFlagReviewPage(flag: flag),
              ),
            );
      if (!mounted || reviewed != true) return;
      setState(() => _resolved[flag.id] = flag.fingerprint);
      widget.onReviewed?.call();
    } finally {
      _opening.remove(flag.id);
    }
  }

  String _date(DateTime? date) {
    if (date == null) return 'Time unavailable';
    final local = MaterialLocalizations.of(context);
    return '${local.formatMediumDate(date)} · ${local.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AdminPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.flag_outlined, color: AdminUi.green(context)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Review queue',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const CommunityModerationRulesButton(compact: true),
                IconButton(
                  tooltip: 'Refresh flagged content',
                  onPressed: _hasReviews ? _retry : null,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            Text(
              'Check what triggered each flag and review the original content.',
              style: TextStyle(color: AdminUi.muted(context), height: 1.4),
            ),
            const SizedBox(height: 8),
            if (_hasHealth)
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _health,
                builder: _buildHealth,
              )
            else
              Text(
                'Scan status is unavailable while offline.',
                style: TextStyle(color: AdminUi.muted(context)),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      if (!_hasReviews)
        const AdminPanel(
          child: Text('Connect to Firebase to load the review queue.'),
        )
      else
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _reviews,
          builder: _buildQueue,
        ),
    ],
  );

  Widget _buildHealth(
    BuildContext context,
    AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
  ) {
    if (snapshot.hasError) {
      return Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Scan status could not load.'),
          TextButton(onPressed: _retry, child: const Text('Retry status')),
        ],
      );
    }
    if (!snapshot.hasData) return const LinearProgressIndicator(minHeight: 3);
    final data = snapshot.data?.data();
    final checkedAt = parseCommunityFlagTimestamp(data?['lastRunAtMillis']);
    if (checkedAt == null) {
      return Text(
        'Waiting for the first scheduled check.',
        style: TextStyle(color: AdminUi.muted(context)),
      );
    }
    final incomplete = const {'failed', 'deferred'}.contains(data?['status']);
    final counts = <String>[
      if (data?['checked'] is num) '${data!['checked']} checked',
      if (data?['flagged'] is num) '${data!['flagged']} flagged',
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (incomplete ? Colors.orange : AdminUi.green(context)).withValues(
          alpha: .08,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 30, top: 4, bottom: 4),
        dense: true,
        visualDensity: VisualDensity.compact,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          incomplete ? Icons.info_outline_rounded : Icons.schedule_rounded,
          size: 20,
          color: incomplete
              ? Theme.of(context).colorScheme.error
              : AdminUi.green(context),
        ),
        title: Text(
          incomplete
              ? 'Some content still needs checking'
              : 'Last scan · ${_date(checkedAt)}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: AdminUi.muted(context),
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              incomplete
                  ? 'Existing flags are ready for review. The remaining content will be checked again.'
                  : '${counts.join(' · ')}${counts.isEmpty ? '' : ' · '}Every 30 min',
              style: TextStyle(color: AdminUi.muted(context), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueue(
    BuildContext context,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
  ) {
    if (snapshot.hasError) {
      return AdminPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The review queue could not load.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text('Check your connection and try again.'),
            TextButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry review queue'),
            ),
          ],
        ),
      );
    }
    if (!snapshot.hasData) {
      return const AdminPanel(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final flags = snapshot.data!.docs
        .map((doc) => CommunityFlag(id: doc.id, data: doc.data()))
        .where((flag) => _resolved[flag.id] != flag.fingerprint)
        .toList();
    final visible = flags
        .where(
          (flag) =>
              flag.matchesSource(_source) &&
              (_content == _ContentFilter.all ||
                  flag.isComment == (_content == _ContentFilter.comment)) &&
              flag.matchesQuery(_searchController.text),
        )
        .toList();
    int time(CommunityFlag flag) => flag.flaggedAt?.millisecondsSinceEpoch ?? 0;
    int priority(CommunityFlag flag) => switch (flag.severity) {
      'critical' => 4,
      'high' => 3,
      'medium' => 2,
      'low' => 1,
      _ => 0,
    };
    visible.sort((a, b) {
      if (_sort == _QueueSort.priority) {
        final comparison = priority(b).compareTo(priority(a));
        if (comparison != 0) return comparison;
      }
      final comparison = _sort == _QueueSort.oldest
          ? time(a).compareTo(time(b))
          : time(b).compareTo(time(a));
      return comparison == 0 ? a.id.compareTo(b.id) : comparison;
    });
    final hasMore =
        widget.reviews == null && snapshot.data!.docs.length >= _limit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('flag-search'),
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Search reasons or keywords',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final source =
                      DropdownButtonFormField<CommunityFlagSourceFilter>(
                        key: const ValueKey('flag-source-filter'),
                        initialValue: _source,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Flagged by',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final filter in CommunityFlagSourceFilter.values)
                            DropdownMenuItem(
                              value: filter,
                              child: Text(
                                filter.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _source = value);
                        },
                      );
                  final content = DropdownButtonFormField<_ContentFilter>(
                    key: const ValueKey('flag-content-filter'),
                    initialValue: _content,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Content',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: _ContentFilter.all,
                        child: Text('All content'),
                      ),
                      DropdownMenuItem(
                        value: _ContentFilter.post,
                        child: Text('Posts'),
                      ),
                      DropdownMenuItem(
                        value: _ContentFilter.comment,
                        child: Text('Comments'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _content = value);
                    },
                  );
                  if (constraints.maxWidth < 330 ||
                      MediaQuery.textScalerOf(context).scale(16) > 21) {
                    return Column(
                      children: [source, const SizedBox(height: 14), content],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: source),
                      const SizedBox(width: 12),
                      Expanded(child: content),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 6,
                children: [
                  Text(
                    '${visible.length} shown · ${flags.length} loaded',
                    key: const ValueKey('flag-results-count'),
                    style: TextStyle(color: AdminUi.muted(context)),
                  ),
                  PopupMenuButton<_QueueSort>(
                    tooltip: 'Sort reviews',
                    initialValue: _sort,
                    onSelected: (value) => setState(() => _sort = value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _QueueSort.newest,
                        child: Text('Newest loaded'),
                      ),
                      PopupMenuItem(
                        value: _QueueSort.oldest,
                        child: Text('Oldest loaded'),
                      ),
                      PopupMenuItem(
                        value: _QueueSort.priority,
                        child: Text('Highest priority loaded'),
                      ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sort_rounded, size: 18),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(switch (_sort) {
                              _QueueSort.newest => 'Newest loaded',
                              _QueueSort.oldest => 'Oldest loaded',
                              _QueueSort.priority => 'Highest priority loaded',
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator(minHeight: 3),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (visible.isEmpty)
          AdminPanel(
            child: Column(
              children: [
                Icon(
                  flags.isEmpty
                      ? Icons.task_alt_rounded
                      : Icons.filter_alt_off_outlined,
                  size: 32,
                  color: AdminUi.green(context),
                ),
                const SizedBox(height: 10),
                Text(
                  flags.isEmpty
                      ? 'No flags awaiting review'
                      : 'No reviews match these filters',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  flags.isEmpty
                      ? 'New flags will appear here after a content check.'
                      : 'Try a different source, content type, or search.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AdminUi.muted(context)),
                ),
                if (flags.isNotEmpty)
                  TextButton(
                    onPressed: _clearFilters,
                    child: const Text('Clear filters'),
                  ),
              ],
            ),
          ),
        for (final flag in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _flagCard(flag),
          ),
        if (hasMore) ...[
          Text(
            'Load more to include the rest of the queue in your search.',
            style: TextStyle(color: AdminUi.muted(context)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: snapshot.connectionState == ConnectionState.waiting
                ? null
                : () => setState(() {
                    _limit += _pageSize;
                    _reviews = _reviewStream();
                  }),
            icon: const Icon(Icons.expand_more_rounded),
            label: const Text('Load more reviews'),
          ),
        ],
      ],
    );
  }

  Widget _flagCard(CommunityFlag flag) {
    final color = switch (flag.source) {
      CommunityFlagSource.gemini =>
        Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFFD2B5FF)
            : const Color(0xFF6B3E9C),
      CommunityFlagSource.keywords =>
        Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFFFFC98C)
            : const Color(0xFF8E520B),
      CommunityFlagSource.pattern => AdminUi.blue(context),
      _ => AdminUi.green(context),
    };
    final icon = switch (flag.source) {
      CommunityFlagSource.gemini => Icons.auto_awesome_outlined,
      CommunityFlagSource.keywords => Icons.text_fields_rounded,
      CommunityFlagSource.pattern => Icons.pattern_rounded,
      CommunityFlagSource.integrity => Icons.fact_check_outlined,
      _ => Icons.info_outline_rounded,
    };
    return AdminPanel(
      key: ValueKey('flag-card-${flag.id}'),
      onTap: () => _open(flag),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _label(
                      flag.contentTypeLabel,
                      flag.isComment
                          ? Icons.chat_bubble_outline_rounded
                          : Icons.article_outlined,
                      AdminUi.muted(context),
                    ),
                    _label(flag.sourceLabel, icon, color),
                    if (flag.severity != 'unknown')
                      _label(
                        '${flag.severityLabel} priority',
                        Icons.outlined_flag_rounded,
                        const {'high', 'critical'}.contains(flag.severity)
                            ? Theme.of(context).colorScheme.error
                            : AdminUi.muted(context),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: AdminUi.muted(context)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            flag.title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          if (flag.evidenceLabels.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final label in flag.evidenceLabels.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  label,
                  style: TextStyle(color: AdminUi.muted(context), height: 1.4),
                ),
              ),
            if (flag.evidenceLabels.length > 3)
              Text(
                '+${flag.evidenceLabels.length - 3} more matches',
                style: TextStyle(color: AdminUi.muted(context)),
              ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              flag.source == CommunityFlagSource.gemini
                  ? 'Open to review the Gemini suggestion.'
                  : flag.source == CommunityFlagSource.localRules
                  ? 'Exact matched rule was not saved for this older flag.'
                  : 'Open to check the original content.',
              style: TextStyle(color: AdminUi.muted(context), height: 1.4),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _date(flag.flaggedAt),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AdminUi.muted(context)),
          ),
        ],
      ),
    );
  }

  Widget _label(String text, IconData icon, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

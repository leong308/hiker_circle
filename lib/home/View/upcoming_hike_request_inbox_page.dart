import 'package:flutter/material.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../core/widgets/page_header_style.dart';
import '../../core/widgets/section_label.dart';
import '../Model/hike_session_models.dart';
import '../Model/upcoming_hike_request_inbox.dart';
import '../ModelView/upcoming_hike_request_inbox_view_model.dart';

/// The host's pending request queue and permanent decision history for one hike.
class UpcomingHikeRequestInboxPage extends StatefulWidget {
  /// Uses the existing authoritative review flow for every pending request.
  const UpcomingHikeRequestInboxPage({
    super.key,
    required this.hike,
    required this.repository,
    required this.onReview,
  });
  final UpcomingHike hike;
  final HikerCircleFirebaseRepository repository;
  final Future<void> Function(String requestId) onReview;

  /// Creates the paged inbox presentation.
  @override
  State<UpcomingHikeRequestInboxPage> createState() =>
      _UpcomingHikeRequestInboxPageState();
}

/// Keeps navigation in the view while the ViewModel owns lists and pagination.
class _UpcomingHikeRequestInboxPageState
    extends State<UpcomingHikeRequestInboxPage> {
  late final UpcomingHikeRequestInboxViewModel _model;
  String? _opening;

  /// Fetches the initial pending page.
  @override
  void initState() {
    super.initState();
    _model = UpcomingHikeRequestInboxViewModel(
      repository: widget.repository,
      hikeId: widget.hike.id,
    )..refresh();
  }

  /// Opens the same fresh host review used by notification taps.
  Future<void> _review(UpcomingHikeRequestEntry row) async {
    if (_opening != null) return;
    setState(() => _opening = row.id);
    try {
      await widget.onReview(row.id);
    } finally {
      if (mounted) {
        setState(() => _opening = null);
        await _model.refresh();
      }
    }
  }

  /// Releases the repository subscription after the page closes.
  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  /// Presents both lists in HikerCircle's shared page layout.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) {
      final theme = Theme.of(context), colors = theme.colorScheme;
      return Scaffold(
        backgroundColor: theme.brightness == Brightness.dark
            ? const Color(0xFF0C120F)
            : const Color(0xFFF2F2F7),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _model.refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PageHeader(
                          title: 'Join requests',
                          subtitle: widget.hike.trailName,
                          onBack: () => Navigator.of(context).pop(),
                          actions: [
                            PageHeaderAction(
                              tooltip: 'Refresh requests',
                              icon: Icons.refresh_rounded,
                              onPressed: _model.loading ? null : _model.refresh,
                              color: colors.primary,
                              surface: colors.surface,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: false,
                              label: Text('Pending (${_model.pendingCount})'),
                            ),
                            const ButtonSegment(
                              value: true,
                              label: Text('History'),
                            ),
                          ],
                          selected: {_model.history},
                          onSelectionChanged: (values) =>
                              _model.select(values.single),
                        ),
                        const SizedBox(height: 20),
                        SectionLabel(
                          label: _model.history
                              ? 'Join history'
                              : 'Waiting for your decision',
                          padding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 8),
                        if (_model.loading)
                          const Padding(
                            padding: EdgeInsets.all(28),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else ...[
                          if (_model.error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                children: [
                                  Text(
                                    _model.error!,
                                    style: TextStyle(color: colors.error),
                                  ),
                                  TextButton(
                                    onPressed: _model.refresh,
                                    child: const Text('Try again'),
                                  ),
                                ],
                              ),
                            ),
                          if (_model.rows.isEmpty && _model.error == null)
                            Material(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Column(
                                  children: [
                                    Icon(
                                      _model.history
                                          ? Icons.history_rounded
                                          : Icons.how_to_reg_outlined,
                                      size: 36,
                                      color: colors.primary,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _model.history
                                          ? 'No join history yet'
                                          : 'You’re all caught up',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _model.history
                                          ? 'Hikers who join and past requests will appear here.'
                                          : 'New requests to join this hike will appear here.',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          for (final row in _model.rows)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _RequestRow(
                                row: row,
                                opening: _opening == row.id,
                                onTap:
                                    row.status == 'pending' && _opening == null
                                    ? () => _review(row)
                                    : null,
                              ),
                            ),
                          if (_model.hasMore)
                            OutlinedButton.icon(
                              onPressed: _model.loadingMore
                                  ? null
                                  : _model.loadMore,
                              icon: const Icon(Icons.expand_more_rounded),
                              label: Text(
                                _model.loadingMore ? 'Loading…' : 'Load more',
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// An accessible request row with explicit decision and timestamps.
class _RequestRow extends StatelessWidget {
  /// Creates a row without making terminal decisions actionable again.
  const _RequestRow({required this.row, required this.opening, this.onTap});
  final UpcomingHikeRequestEntry row;
  final bool opening;
  final VoidCallback? onTap;

  /// Formats a local timestamp consistently for requested and decided times.
  String _date(DateTime? value) {
    if (value == null) return 'Time unavailable';
    final date = value.toLocal();
    return '${date.day}/${date.month}/${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  /// Keeps aliases and history readable on small screens.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final color = row.status == 'rejected' ? colors.error : colors.primary;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: colors.primary.withValues(alpha: .1),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      row.statusLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      row.isJoined
                          ? 'joined: ${_date(row.joinedAt ?? row.decidedAt)}'
                          : 'Requested ${_date(row.createdAt)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (!row.isJoined &&
                        row.status != 'pending' &&
                        row.decidedAt != null)
                      Text(
                        '${row.status == 'rejected' ? 'Decided' : 'Updated'} ${_date(row.decidedAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (opening)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

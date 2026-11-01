import 'package:flutter/material.dart';

import '../../core/widgets/loading_toast.dart';
import '../../core/widgets/page_header_style.dart';
import '../../core/widgets/section_label.dart';
import '../Model/feedback_report.dart';
import '../ModelView/feedback_inbox_view_model.dart';
import '../feedback_repository.dart';
import 'feedback_detail_page.dart';
import 'widgets/feedback_widgets.dart';

/// Presents both the administrator inbox and the hiker's own reports.
class FeedbackInboxPage extends StatefulWidget {
  /// Keeps existing callers and their role-scoped repository compatible.
  const FeedbackInboxPage({super.key, this.admin = false, this.repository});
  final bool admin;
  final FeedbackRepository? repository;

  /// Binds the inbox subscription to the page lifecycle.
  @override
  State<FeedbackInboxPage> createState() => _FeedbackInboxPageState();
}

/// Owns only the shared page layout and report navigation.
class _FeedbackInboxPageState extends State<FeedbackInboxPage> {
  late final FeedbackRepository _defaultRepository;
  late final FeedbackInboxViewModel _model;

  /// Starts the existing feedback query through its ViewModel.
  @override
  void initState() {
    super.initState();
    _defaultRepository = FeedbackRepository();
    _model = FeedbackInboxViewModel(
      repository: widget.repository ?? _defaultRepository,
      admin: widget.admin,
    )..addListener(_render);
  }

  /// Resets visible snapshots when a parent changes the selected account scope.
  @override
  void didUpdateWidget(covariant FeedbackInboxPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _model.updateInputs(
      repository: widget.repository ?? _defaultRepository,
      admin: widget.admin,
    );
  }

  /// Rebuilds after an explicit refresh.
  void _render() {
    if (mounted) setState(() {});
  }

  /// Opens the selected report with the same repository and review permissions.
  Future<void> _open(FeedbackReport report) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => FeedbackDetailPage(
        report: report,
        admin: widget.admin,
        repository: _model.repository,
      ),
    ),
  );

  /// Uses Profile's shared body header, page inset and rounded report cards.
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: FeedbackStyle.background(context),
    body: SafeArea(
      child: StreamBuilder<List<FeedbackReport>>(
        key: ValueKey(_model.revision),
        stream: _model.reports,
        builder: (context, snapshot) {
          final reports = snapshot.hasData
              ? _model.parse(snapshot.data!)
              : <FeedbackReport>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PageHeader(
                        title: widget.admin ? 'Feedback inbox' : 'My feedback',
                        subtitle: widget.admin
                            ? 'Hiker ideas and reported issues'
                            : 'Track your ideas and reported issues',
                        onBack: () => Navigator.of(context).maybePop(),
                        actions: [
                          PageHeaderAction(
                            tooltip: 'Refresh feedback',
                            icon: Icons.refresh_rounded,
                            onPressed: _model.refresh,
                            color: Theme.of(context).colorScheme.primary,
                            surface: Theme.of(context).colorScheme.surface,
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      if (snapshot.hasError)
                        FeedbackStateCard(
                          icon: Icons.cloud_off_rounded,
                          title: 'Could not load feedback',
                          message: 'Check your connection and try again.',
                          onRetry: _model.refresh,
                        )
                      else if (!snapshot.hasData)
                        const HikerCircleLoadingView(
                          message: 'Loading feedback…',
                          detail:
                              'Getting the latest reports and review statuses.',
                          padding: EdgeInsets.symmetric(vertical: 20),
                        )
                      else ...[
                        Row(
                          children: [
                            const Expanded(
                              child: SectionLabel(label: 'Recent feedback'),
                            ),
                            Text(
                              '${reports.length} ${reports.length == 1 ? 'report' : 'reports'}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (reports.isEmpty)
                          FeedbackStateCard(
                            icon: Icons.inbox_outlined,
                            title: widget.admin
                                ? 'No feedback yet'
                                : 'No reports yet',
                            message: widget.admin
                                ? 'New ideas and reported issues will appear here.'
                                : 'The feedback you send will appear here with its review status.',
                          ),
                        for (final report in reports)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: FeedbackReportTile(
                              key: ValueKey('feedback-report-${report.id}'),
                              report: report,
                              onTap: () => _open(report),
                            ),
                          ),
                        if (reports.length >= feedbackReportLimit)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text(
                              'Showing the most recent $feedbackReportLimit reports.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  /// Releases the ViewModel's presentation listeners.
  @override
  void dispose() {
    _model.removeListener(_render);
    _model.dispose();
    super.dispose();
  }
}

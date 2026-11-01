import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/widgets/loading_toast.dart';
import '../../core/widgets/page_header_style.dart';
import '../../core/widgets/section_label.dart';
import '../Model/feedback_report.dart';
import '../ModelView/feedback_detail_view_model.dart';
import '../feedback_repository.dart';
import 'widgets/feedback_widgets.dart';

/// Shows the report, protected attachment and existing administrator controls.
class FeedbackDetailPage extends StatefulWidget {
  /// Receives the selected report and the same data source used by the inbox.
  const FeedbackDetailPage({
    super.key,
    required this.report,
    this.admin = false,
    this.repository,
  });
  final FeedbackReport report;
  final bool admin;
  final FeedbackRepository? repository;

  /// Binds attachment and status state to this detail page.
  @override
  State<FeedbackDetailPage> createState() => _FeedbackDetailPageState();
}

/// Owns the detail layout while the ViewModel performs reads and updates.
class _FeedbackDetailPageState extends State<FeedbackDetailPage> {
  late final FeedbackDetailViewModel _model;

  /// Loads the selected report's screenshot once.
  @override
  void initState() {
    super.initState();
    _model = FeedbackDetailViewModel(
      report: widget.report,
      admin: widget.admin,
      repository: widget.repository ?? FeedbackRepository(),
    )..addListener(_render);
  }

  /// Rebuilds after a confirmed update or attachment retry.
  void _render() {
    if (mounted) setState(() {});
  }

  /// Keeps the message and screenshot readable below the shared page header.
  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    return Scaffold(
      backgroundColor: FeedbackStyle.background(context),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PageHeader(
                          title: 'Feedback details',
                          subtitle: 'Read the report and its review status',
                          onBack: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(height: 22),
                        const SectionLabel(label: 'Feedback'),
                        const SizedBox(height: 8),
                        FeedbackSurface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FeedbackGlyph(kind: report.kind),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          report.category,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        FeedbackStatusLabel(
                                          status: _model.status,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 28),
                              SelectableText(
                                report.message,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.copyWith(height: 1.5),
                              ),
                            ],
                          ),
                        ),
                        if (_model.screenshot != null) ...[
                          const SizedBox(height: 22),
                          const SectionLabel(label: 'Screenshot'),
                          const SizedBox(height: 8),
                          FutureBuilder<Uint8List?>(
                            future: _model.screenshot,
                            builder: _screenshot,
                          ),
                        ],
                        const SizedBox(height: 22),
                        const SectionLabel(label: 'Report details'),
                        const SizedBox(height: 8),
                        FeedbackSurface(
                          child: Column(
                            children: [
                              FeedbackInfoRow(
                                label: 'Submitted',
                                value: feedbackDisplayDate(
                                  context,
                                  report.submittedAt,
                                ),
                              ),
                              const Divider(height: 14),
                              FeedbackInfoRow(
                                label: 'Platform',
                                value: report.platformLabel,
                              ),
                            ],
                          ),
                        ),
                        if (widget.admin) ...[
                          const SizedBox(height: 22),
                          const SectionLabel(label: 'Review'),
                          const SizedBox(height: 8),
                          _reviewControls(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_model.busy)
              const HikerCircleLoadingToastOverlay(
                message: 'Updating feedback…',
                detail: 'Saving the report’s review status.',
              ),
          ],
        ),
      ),
    );
  }

  /// Keeps screenshot failures independent from reading or reviewing the report.
  Widget _screenshot(BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
    if (snapshot.hasError ||
        (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasData)) {
      return FeedbackStateCard(
        icon: Icons.broken_image_outlined,
        title: 'Screenshot unavailable',
        message: 'Try loading the attachment again.',
        onRetry: _model.retryScreenshot,
      );
    }
    if (!snapshot.hasData) {
      return const FeedbackSurface(
        child: HikerCircleLoadingView(
          compact: true,
          message: 'Loading screenshot…',
          detail: 'Getting the report’s attachment.',
          padding: EdgeInsets.symmetric(vertical: 12),
        ),
      );
    }
    return FeedbackScreenshot(
      bytes: snapshot.data!,
      onRetry: _model.retryScreenshot,
    );
  }

  /// Shows only the existing three administrator statuses, without optimistic success.
  Widget _reviewControls() => FeedbackSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Review status',
            enabled: !_model.busy,
            prefixIcon: const Icon(Icons.fact_check_outlined),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const ValueKey('feedback-review-status'),
              isExpanded: true,
              value: feedbackStatuses.contains(_model.status)
                  ? _model.status
                  : null,
              hint: const Text('Choose status'),
              items: [
                for (final status in feedbackStatuses)
                  DropdownMenuItem(value: status, child: Text(status)),
              ],
              onChanged: _model.busy
                  ? null
                  : (value) {
                      if (value != null) _model.changeStatus(value);
                    },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          FeedbackReport.statusDescription(_model.status),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        if (_model.error != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              _model.error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    ),
  );

  /// Releases listeners while allowing an already-sent backend write to finish.
  @override
  void dispose() {
    _model.removeListener(_render);
    _model.dispose();
    super.dispose();
  }
}

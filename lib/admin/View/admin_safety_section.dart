import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/widgets/caution_icon.dart';
import '../../core/widgets/colored_location_map.dart';
import '../../core/widgets/page_header_style.dart';
import '../../core/widgets/section_label.dart';
import '../../app/Data/app_settings_controller.dart';
import '../../app/Model/preferred_time_zone.dart';
import '../../trail/Model/caution_update.dart';
import '../../trail/Model/community_hazard.dart';
import '../../trail/Model/trail_hazard_categories.dart';
import '../../trail/View/caution_media.dart';
import '../Model/admin_hazard_report.dart';
import '../ModelView/admin_safety_view_model.dart';
import 'admin_ui.dart';

/// Presents the live Safety lifecycle using the app's shared admin surfaces.
class AdminSafetySection extends StatelessWidget {
  /// Receives state from the parent workspace instead of fetching in the view.
  const AdminSafetySection({super.key, required this.model});
  final AdminSafetyViewModel model;

  /// Renders tabs, lifecycle guidance and the selected report list.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final stage = model.selectedStage;
      final rows = model.visibleReports;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SafetyTabs(model: model),
          const SizedBox(height: 18),
          _SafetyGuidance(stage: stage),
          const SizedBox(height: 20),
          SectionLabel(
            label: '${stage.label} cautions',
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          if (model.loading) ...[
            const LinearProgressIndicator(minHeight: 3),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Loading safety reports…'),
            ),
          ],
          if (model.error != null) ...[
            AdminPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reports could not refresh',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(model.error!),
                  if (model.hasData)
                    const Text('Showing the last loaded records.'),
                  TextButton.icon(
                    onPressed: model.loading
                        ? null
                        : () => unawaited(model.refresh()),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (model.hasData && rows.isEmpty)
            AdminEmptyState(
              icon: model.query.isNotEmpty
                  ? Icons.search_off_rounded
                  : _stageIcon(stage),
              title: model.query.isNotEmpty
                  ? 'No matching cautions'
                  : switch (stage) {
                      AdminHazardStage.reported => 'No open reports',
                      AdminHazardStage.resolving =>
                        'No resolutions in progress',
                      AdminHazardStage.resolved => 'No closed reports yet',
                    },
              message: model.query.isNotEmpty
                  ? 'Try another trail or caution name, or clear your search.'
                  : switch (stage) {
                      AdminHazardStage.reported =>
                        'New cautions shared by hikers will appear here.',
                      AdminHazardStage.resolving =>
                        'Reports move here when a hiker proposes a resolution.',
                      AdminHazardStage.resolved =>
                        'Expired and resolved cautions remain here for reference.',
                    },
            ),
          for (final report in rows) ...[
            _SafetyReportCard(
              key: ValueKey('admin-hazard-${report.id}'),
              report: report,
              now: model.now,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      AdminHazardDetailPage(model: model, hazardId: report.id),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (model.hasMore)
            OutlinedButton.icon(
              onPressed: model.showMore,
              icon: const Icon(Icons.expand_more_rounded),
              label: const Text('Show more reports'),
            ),
        ],
      );
    },
  );
}

/// Keeps each tab reachable on small screens and with larger accessibility text.
class _SafetyTabs extends StatelessWidget {
  /// Uses totals that remain stable when the administrator searches a tab.
  const _SafetyTabs({required this.model});
  final AdminSafetyViewModel model;

  /// Builds a green selected tab with readable counts and touch targets.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.max(
        constraints.maxWidth / 3,
        100 * MediaQuery.textScalerOf(context).scale(13) / 13,
      );
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AdminUi.surface(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AdminUi.border(context)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final stage in AdminHazardStage.values)
                SizedBox(
                  width: width,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Semantics(
                      selected: model.selectedStage == stage,
                      button: true,
                      label: '${stage.label}, ${model.count(stage)} reports',
                      excludeSemantics: true,
                      child: Material(
                        color: model.selectedStage == stage
                            ? AdminUi.green(context)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          key: ValueKey('admin-safety-tab-${stage.name}'),
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => model.selectStage(stage),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${model.count(stage)}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: model.selectedStage == stage
                                        ? _selectedText(context)
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  stage.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: model.selectedStage == stage
                                        ? _selectedText(context)
                                        : AdminUi.muted(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  /// Preserves contrast with both the light and dark admin green palettes.
  Color _selectedText(BuildContext context) =>
      AdminUi.dark(context) ? const Color(0xFF102A1B) : Colors.white;
}

/// Explains the selected lifecycle stage without suggesting admin approval.
class _SafetyGuidance extends StatelessWidget {
  /// Changes the guidance along with the selected tab.
  const _SafetyGuidance({required this.stage});
  final AdminHazardStage stage;

  /// Uses the same soft green treatment as the app's preparation cards.
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AdminUi.green(context).withValues(alpha: .07),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(_stageIcon(stage), color: AdminUi.green(context), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                switch (stage) {
                  AdminHazardStage.reported => 'Shared by the hiking community',
                  AdminHazardStage.resolving =>
                    'Three hikers confirm a resolution',
                  AdminHazardStage.resolved =>
                    'Closed reports, kept for reference',
                },
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                switch (stage) {
                  AdminHazardStage.reported =>
                    'Monitor reported trail conditions and hiker evidence. Reports do not need admin approval.',
                  AdminHazardStage.resolving =>
                    'The proposing hiker counts as the first confirmation. Two other hikers must confirm before the report is resolved.',
                  AdminHazardStage.resolved =>
                    'Reports close after three hiker confirmations or when they expire. Expiry does not confirm that a trail is safe.',
                },
                style: TextStyle(
                  color: AdminUi.muted(context),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Shows one caution with its location, age and community resolution progress.
class _SafetyReportCard extends StatelessWidget {
  /// Opens a read-only detail page instead of presenting moderation actions.
  const _SafetyReportCard({
    super.key,
    required this.report,
    required this.now,
    required this.onTap,
  });
  final AdminHazardReport report;
  final DateTime now;
  final VoidCallback onTap;

  /// Keeps long names and descriptions within the card on narrow devices.
  @override
  Widget build(BuildContext context) {
    final stage = report.stageAt(now);
    return AdminPanel(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReportIcon(
                report: report,
                closed: stage == AdminHazardStage.resolved,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.type,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      report.trailName,
                      style: TextStyle(
                        color: AdminUi.muted(context),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 22),
            ],
          ),
          if (report.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              report.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              Text(
                '${report.reportCount} ${report.reportCount == 1 ? 'hiker reported' : 'hikers reported'}',
                style: TextStyle(fontSize: 12, color: AdminUi.muted(context)),
              ),
              if (report.isSerious && stage != AdminHazardStage.resolved)
                Text(
                  'Serious risk',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              if (stage == AdminHazardStage.resolved)
                Text(
                  report.statusLabel(now),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.green(context),
                  ),
                ),
            ],
          ),
          if (stage == AdminHazardStage.resolving) ...[
            const SizedBox(height: 12),
            _ResolutionProgress(report: report),
          ],
          const SizedBox(height: 10),
          Text(
            'Reported ${_formatTime(report.reportedAt)}',
            style: TextStyle(color: AdminUi.muted(context), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Reuses the condition-specific symbol and serious-risk badge used by hikers.
class _ReportIcon extends StatelessWidget {
  /// Stops the serious-risk blink for closed historical reports.
  const _ReportIcon({required this.report, required this.closed});
  final AdminHazardReport report;
  final bool closed;

  /// Gives caution icons the same rounded surface as other HikerCircle cards.
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: AdminUi.green(context).withValues(alpha: .08),
      borderRadius: BorderRadius.circular(14),
    ),
    child: CautionIcon(
      icon: trailHazardIconFor(report.type),
      size: 24,
      seriousRisk: report.isSerious && !closed,
      color: closed ? AdminUi.muted(context) : const Color(0xFFD78A20),
    ),
  );
}

/// Makes the community quorum explicit rather than showing a generic vote pill.
class _ResolutionProgress extends StatelessWidget {
  /// Displays the current cycle's confirmations only.
  const _ResolutionProgress({required this.report});
  final AdminHazardReport report;

  /// Uses a progress bar and text so the count does not depend on colour alone.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        report.resolutionCount > AdminHazardReport.resolutionTarget
            ? '${report.resolutionCount} hikers confirmed · ${AdminHazardReport.resolutionTarget} required'
            : '${report.resolutionCount} of ${AdminHazardReport.resolutionTarget} hikers confirmed',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: AdminUi.green(context),
          fontSize: 13,
        ),
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: (report.resolutionCount / AdminHazardReport.resolutionTarget)
              .clamp(0.0, 1.0),
          minHeight: 5,
          color: AdminUi.green(context),
          backgroundColor: AdminUi.green(context).withValues(alpha: .12),
        ),
      ),
    ],
  );
}

/// Shows report evidence, closure reason and live community update history.
class AdminHazardDetailPage extends StatefulWidget {
  /// Keeps the same report identity through expiry, resolution and reopening.
  const AdminHazardDetailPage({
    super.key,
    required this.model,
    required this.hazardId,
  });
  final AdminSafetyViewModel model;
  final String hazardId;

  /// Binds the evidence stream once for the lifetime of the page.
  @override
  State<AdminHazardDetailPage> createState() => _AdminHazardDetailPageState();
}

/// Owns only the detail page's stream binding and presentation lifecycle.
class _AdminHazardDetailPageState extends State<AdminHazardDetailPage> {
  late Stream<List<CautionUpdate>> _updates;

  /// Subscribes once rather than reopening a listener during every rebuild.
  @override
  void initState() {
    super.initState();
    _updates = widget.model.repository.watchUpdates(widget.hazardId);
  }

  /// Rebinds the evidence listener after a failed connection.
  void _retryUpdates() => setState(
    () => _updates = widget.model.repository.watchUpdates(widget.hazardId),
  );

  /// Uses standard navigation, section labels, evidence viewer and map controls.
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AdminUi.background(context),
    appBar: PageHeaderAppBar(
      title: const Text('Caution details'),
      backgroundColor: AdminUi.background(context),
    ),
    body: AnimatedBuilder(
      animation: widget.model,
      builder: (context, _) {
        final report = widget.model.reportById(widget.hazardId);
        if (report == null) {
          return const Padding(
            padding: EdgeInsets.all(18),
            child: AdminEmptyState(
              title: 'Report unavailable',
              message:
                  'This report has been removed or is no longer available.',
            ),
          );
        }
        final stage = report.stageAt(widget.model.now);
        final latest = report.latestEvidence;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.model.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Live updates unavailable. Showing the last loaded report.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  AdminPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ReportIcon(
                              report: report,
                              closed: stage == AdminHazardStage.resolved,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    report.type,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    report.trailName,
                                    style: TextStyle(
                                      color: AdminUi.muted(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        AdminTag(
                          label: report.statusLabel(widget.model.now),
                          icon: _stageIcon(stage),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          report.description.isEmpty
                              ? 'No description was added.'
                              : report.description,
                          style: const TextStyle(height: 1.5),
                        ),
                        const SizedBox(height: 16),
                        _ReportFact(
                          label: 'Reported',
                          value: _formatTime(report.reportedAt),
                        ),
                        _ReportFact(
                          label:
                              stage == AdminHazardStage.resolved &&
                                  !report.confirmedResolved
                              ? 'Expired'
                              : 'Report expiry',
                          value: _formatTime(report.expiresAt),
                        ),
                        if (report.confirmedResolved)
                          _ReportFact(
                            label: 'Resolved',
                            value: _formatTime(report.resolvedAt),
                          ),
                        _ReportFact(
                          label: 'Hikers reporting this caution',
                          value: '${report.reportCount}',
                        ),
                        if (stage == AdminHazardStage.resolving ||
                            report.resolutionCount > 0) ...[
                          const SizedBox(height: 14),
                          _ResolutionProgress(report: report),
                        ],
                        if (stage == AdminHazardStage.resolved &&
                            !report.confirmedResolved) ...[
                          const SizedBox(height: 12),
                          Text(
                            'This report expired. The condition may still be present.',
                            style: TextStyle(
                              color: AdminUi.muted(context),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (report.media.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const SectionLabel(
                      label: 'Report evidence',
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    CautionMediaStrip(media: report.media),
                  ],
                  if (latest.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const SectionLabel(
                      label: 'Latest reopening evidence',
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    AdminPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if ('${latest['description'] ?? ''}'
                              .trim()
                              .isNotEmpty)
                            Text(
                              '${latest['description']}',
                              style: const TextStyle(height: 1.5),
                            ),
                          if (cautionMediaFrom(latest['media']).isNotEmpty) ...[
                            const SizedBox(height: 10),
                            CautionMediaStrip(
                              media: cautionMediaFrom(latest['media']),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const SectionLabel(
                    label: 'Reported location',
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  if (report.hasLocation) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: SizedBox(
                        height: 300,
                        child: ColoredLocationMap(
                          key: ValueKey('admin-hazard-map-${report.id}'),
                          points: [
                            ColoredLocationPoint(
                              id: report.id,
                              label: report.type,
                              latitude: report.latitude!,
                              longitude: report.longitude!,
                              color: 0xFFD43C3C,
                            ),
                          ],
                          fallback: ColoredLocationPoint(
                            id: report.id,
                            label: report.type,
                            latitude: report.latitude!,
                            longitude: report.longitude!,
                            color: 0xFFD43C3C,
                          ).geometry,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${report.latitude!.toStringAsFixed(5)}, ${report.longitude!.toStringAsFixed(5)}',
                      style: TextStyle(
                        color: AdminUi.muted(context),
                        fontSize: 12,
                      ),
                    ),
                  ] else
                    AdminPanel(
                      child: Text(
                        'No location was recorded for this report.',
                        style: TextStyle(color: AdminUi.muted(context)),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const SectionLabel(
                    label: 'Latest hiker updates',
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<List<CautionUpdate>>(
                    stream: _updates,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return AdminPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Hiker updates could not load.'),
                              TextButton.icon(
                                onPressed: _retryUpdates,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final updates = snapshot.data!;
                      if (updates.isEmpty) {
                        return const AdminPanel(
                          child: Text('No additional hiker updates yet.'),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final update in updates) ...[
                            _HikerUpdateCard(
                              update: update,
                              previousCycle: update.cycle != report.cycle,
                            ),
                            const SizedBox(height: 10),
                          ],
                          Text(
                            'Showing up to 30 recent updates. Each hiker counts once per confirmation type in the current report cycle.',
                            style: TextStyle(
                              color: AdminUi.muted(context),
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Wraps report facts cleanly rather than squeezing values into a narrow row.
class _ReportFact extends StatelessWidget {
  /// Uses a small label above the recorded value for readable timestamps.
  const _ReportFact({required this.label, required this.value});
  final String label, value;

  /// Keeps date values readable at enlarged font sizes.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

/// Displays anonymous community evidence without exposing a hiker's account ID.
class _HikerUpdateCard extends StatelessWidget {
  /// Marks earlier cycles so old votes are not confused with current progress.
  const _HikerUpdateCard({required this.update, required this.previousCycle});
  final CautionUpdate update;
  final bool previousCycle;

  /// Reuses the shared photo/video viewer for each supporting update.
  @override
  Widget build(BuildContext context) => AdminPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(switch (update.action) {
          'resolve' => 'Resolution proposed',
          'confirmResolution' => 'Resolution confirmed by a hiker',
          'confirm' => 'Caution confirmed by a hiker',
          'reopen' => 'Caution reported again',
          _ => 'Hiker update',
        }, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 5),
        Text(
          _formatTime(update.createdAt),
          style: TextStyle(fontSize: 12, color: AdminUi.muted(context)),
        ),
        if (previousCycle)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Previous report cycle',
              style: TextStyle(fontSize: 12, color: AdminUi.muted(context)),
            ),
          ),
        if (update.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              update.description,
              style: const TextStyle(height: 1.5),
            ),
          ),
        if (update.media.isNotEmpty) ...[
          const SizedBox(height: 10),
          CautionMediaStrip(media: update.media),
        ],
      ],
    ),
  );
}

/// Formats report timestamps using the same selected time zone as app settings.
String _formatTime(DateTime? time) => time == null
    ? 'Time unavailable'
    : PreferredTimeZone.formatInstant(
        time,
        AppSettingsController.instance.preferredTimeZone,
      ).split(' (').first;

/// Provides a stable visual cue for each lifecycle stage.
IconData _stageIcon(AdminHazardStage stage) => switch (stage) {
  AdminHazardStage.reported => Icons.report_outlined,
  AdminHazardStage.resolving => Icons.groups_outlined,
  AdminHazardStage.resolved => Icons.task_alt_rounded,
};

part of '../../trail_caution_details_feature.dart';

/// Separates a caution's identity, evidence, resolution and hiker updates.
class _CautionReportCard extends StatelessWidget {
  /// Creates a report card from already loaded presentation state.
  const _CautionReportCard({required this.model, required this.onAction});
  final TrailCautionDetailsViewModel model;
  final ValueChanged<String> onAction;

  /// Builds a compact card without empty media gaps or floating vote controls.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final report = model.report;
    final active = model.active;
    final serious = active && !report.isResolved && report.isFatal;
    final accent = report.isResolved
        ? colors.primary
        : serious
        ? colors.error
        : colors.onSurfaceVariant;
    if (!model.available) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: const Text('This caution is no longer available.'),
      );
    }
    final evidence = report.latestEvidence;
    final evidenceNote = '${evidence['description'] ?? ''}'.trim();
    final evidenceMedia = cautionMediaFrom(evidence['media']);
    return Container(
      key: ValueKey('caution-card-${report.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: CautionIcon(
                  icon: report.isResolved
                      ? Icons.check_circle_outline_rounded
                      : trailHazardIconFor(report.type),
                  seriousRisk: serious,
                  color: report.isResolved
                      ? colors.primary
                      : Colors.orange.shade700,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.type,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      !active
                          ? 'Archived · Map display ended'
                          : report.isResolved
                          ? 'Resolved / not seen'
                          : serious
                          ? 'Serious risk · ${report.status == 'verified' ? 'Admin reviewed' : 'Community report'}'
                          : report.status == 'verified'
                          ? 'Admin reviewed'
                          : 'Community report',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _CautionCaption(
                icon: Icons.people_outline_rounded,
                text:
                    '${report.reportCount} report${report.reportCount == 1 ? '' : 's'}',
              ),
              if (report.reportedAt != null)
                _CautionCaption(
                  icon: Icons.schedule_rounded,
                  text: cautionDate(report.reportedAt!),
                ),
              if (model.isOwnReport)
                const _CautionCaption(
                  icon: Icons.person_outline_rounded,
                  text: 'Your report',
                )
              else if (model.confirmedByViewer)
                const _CautionCaption(
                  icon: Icons.check_rounded,
                  text: 'Confirmed by you',
                ),
            ],
          ),
          if (report.description.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              report.description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (report.media.isNotEmpty) ...[
            const SizedBox(height: 12),
            CautionMediaStrip(media: report.media),
          ],
          if (evidenceNote.isNotEmpty || evidenceMedia.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CautionEvidencePanel(
              title: 'Latest evidence',
              note: evidenceNote,
              media: evidenceMedia,
            ),
          ],
          if (active && report.resolutionId != null) ...[
            const SizedBox(height: 14),
            _CautionResolutionPanel(model: model, onAction: onAction),
          ],
          if (model.canConfirm ||
              model.canReportResolution ||
              model.canReopen) ...[
            const SizedBox(height: 14),
            _CautionActions(model: model, onAction: onAction),
          ],
          if (model.busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (model.error != null) ...[
            const SizedBox(height: 8),
            Text(
              cautionError(model.error!),
              style: TextStyle(color: colors.error),
            ),
          ],
          if (model.updates.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: colors.outlineVariant.withValues(alpha: .6),
            ),
            _CautionUpdates(model: model),
          ] else if (model.updatesUnavailable) ...[
            const SizedBox(height: 12),
            Text(
              'Hiker updates could not load. Try again when connected.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Keeps report counts, timestamps and ownership aligned as compact metadata.
class _CautionCaption extends StatelessWidget {
  /// Creates one icon and caption.
  const _CautionCaption({required this.icon, required this.text});
  final IconData icon;
  final String text;

  /// Wraps long captions at large text sizes without overflowing a card.
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Gives notes and media a clear grouping without reserving empty attachment space.
class _CautionEvidencePanel extends StatelessWidget {
  /// Creates a labelled evidence block.
  const _CautionEvidencePanel({
    required this.title,
    required this.note,
    required this.media,
  });
  final String title, note;
  final List<Map<String, dynamic>> media;

  /// Displays only the evidence actually attached to an update.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      if (note.isNotEmpty) ...[const SizedBox(height: 6), Text(note)],
      if (media.isNotEmpty) ...[
        const SizedBox(height: 8),
        CautionMediaStrip(media: media),
      ],
    ],
  );
}

/// Shows resolution evidence and progress in one visually connected panel.
class _CautionResolutionPanel extends StatelessWidget {
  /// Creates resolution presentation for the current report cycle.
  const _CautionResolutionPanel({required this.model, required this.onAction});
  final TrailCautionDetailsViewModel model;
  final ValueChanged<String> onAction;

  /// Hides confirmation controls when the viewer's resolution vote is counted.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final report = model.report;
    CautionUpdate? resolution;
    for (final update in model.updates) {
      if (update.cycle == report.cycle &&
          const {'resolve', 'confirmResolution'}.contains(update.action) &&
          (update.description.isNotEmpty || update.media.isNotEmpty)) {
        resolution = update;
        break;
      }
    }
    if (resolution == null) {
      for (final update in model.updates) {
        if (update.id == report.resolutionId) {
          resolution = update;
          break;
        }
      }
    }
    final remaining = math.max(0, 3 - report.resolutionCount);
    return Container(
      key: ValueKey('caution-resolution-${report.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.primary.withValues(alpha: .16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, size: 18, color: colors.primary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Resolution confirmations',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${report.resolutionCount} / 3',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (report.resolutionCount / 3).clamp(0, 1),
              minHeight: 5,
              backgroundColor: colors.primary.withValues(alpha: .12),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            report.isResolved
                ? 'Marked resolved / not seen'
                : '$remaining more confirmation${remaining == 1 ? '' : 's'} needed',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (resolution != null &&
              (resolution.description.isNotEmpty ||
                  resolution.media.isNotEmpty)) ...[
            const SizedBox(height: 12),
            _CautionEvidencePanel(
              title: resolution.uid == model.viewerUid
                  ? 'Your update'
                  : 'Hiker update',
              note: resolution.description,
              media: resolution.media,
            ),
          ],
          if (model.resolutionConfirmedByViewer) ...[
            const SizedBox(height: 10),
            const _CautionCaption(
              icon: Icons.check_circle_outline_rounded,
              text: 'Your confirmation is included.',
            ),
          ] else if (model.canConfirmResolution) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: ValueKey('confirm-resolution-${report.id}'),
              onPressed: model.busy
                  ? null
                  : () => onAction('confirmResolution'),
              icon: const Icon(Icons.thumb_up_outlined, size: 18),
              label: const Text(
                'Confirm resolved / not seen',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Labels report confirmations and evidence-backed status changes distinctly.
class _CautionActions extends StatelessWidget {
  /// Creates the actions currently allowed by the ViewModel.
  const _CautionActions({required this.model, required this.onAction});
  final TrailCautionDetailsViewModel model;
  final ValueChanged<String> onAction;

  /// Adapts action buttons to narrow cards and larger text sizes.
  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (model.canConfirm)
        OutlinedButton.icon(
          key: ValueKey('confirm-caution-${model.report.id}'),
          onPressed: model.busy ? null : () => onAction('confirm'),
          icon: const Icon(Icons.thumb_up_outlined, size: 18),
          label: const Text('Confirm caution', textAlign: TextAlign.center),
        ),
      if (model.canReportResolution)
        FilledButton.tonalIcon(
          key: ValueKey('resolve-caution-${model.report.id}'),
          onPressed: model.busy ? null : () => onAction('resolve'),
          icon: Icon(
            model.resolutionConfirmedByViewer
                ? Icons.edit_note_rounded
                : Icons.check_circle_outline_rounded,
            size: 18,
          ),
          label: Text(
            model.resolutionConfirmedByViewer
                ? 'Add resolution update'
                : 'Resolved / Not Seen',
            textAlign: TextAlign.center,
          ),
        ),
      if (model.canReopen)
        OutlinedButton.icon(
          key: ValueKey('reopen-caution-${model.report.id}'),
          onPressed: model.busy ? null : () => onAction('reopen'),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Report issue again', textAlign: TextAlign.center),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (actions.length == 1) return actions.single;
        if (constraints.maxWidth < 310 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.2) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                actions[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: actions[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Keeps the complete recent update history available without lengthening every card.
class _CautionUpdates extends StatelessWidget {
  /// Creates the collapsible history section for a report.
  const _CautionUpdates({required this.model});
  final TrailCautionDetailsViewModel model;

  /// Displays each update's action, timestamp, note and attachments when expanded.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExpansionTile(
      key: PageStorageKey('caution-updates-${model.report.id}'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 4),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(
        'Hiker updates (${model.updates.length})',
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      children: [
        for (var index = 0; index < model.updates.length; index++) ...[
          if (index > 0)
            Divider(
              height: 24,
              color: colors.outlineVariant.withValues(alpha: .6),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                const {
                      'resolve',
                      'confirmResolution',
                    }.contains(model.updates[index].action)
                    ? Icons.check_circle_outline_rounded
                    : Icons.campaign_outlined,
                size: 18,
                color: colors.primary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      cautionActionLabel(model.updates[index].action),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (model.updates[index].createdAt != null ||
                        model.updates[index].uid == model.viewerUid) ...[
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (model.updates[index].uid.isNotEmpty &&
                              model.updates[index].uid == model.viewerUid)
                            'You',
                          if (model.updates[index].createdAt != null)
                            cautionDate(model.updates[index].createdAt!),
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (model.updates[index].description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(model.updates[index].description),
                    ],
                    if (model.updates[index].media.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      CautionMediaStrip(media: model.updates[index].media),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

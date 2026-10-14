import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/community_hazard_marker.dart';
import '../../home/View/hike_start_navigation.dart';
import '../Data/trail_caution_service.dart';
import 'caution_media.dart';

class TrailCautionDetailsSheet extends StatelessWidget {
  const TrailCautionDetailsSheet({
    super.key,
    required this.reports,
    this.allowFeedback = false,
  });
  final List<CommunityHazard> reports;
  final bool allowFeedback;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: math.min(720, MediaQuery.sizeOf(context).height * .82),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (reports.length > 1)
              Text(
                '${reports.length} nearby cautions',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            if (reports.length > 1) const SizedBox(height: 12),
            for (final report in reports)
              _CautionDetail(
                report: report,
                popupHeading: reports.length == 1,
                allowFeedback: allowFeedback,
              ),
          ],
        ),
      ),
    ),
  );
}

class _CautionDetail extends StatefulWidget {
  const _CautionDetail({
    required this.report,
    required this.allowFeedback,
    this.popupHeading = false,
  });
  final CommunityHazard report;
  final bool popupHeading;
  final bool allowFeedback;
  @override
  State<_CautionDetail> createState() => _CautionDetailState();
}

class _CautionDetailState extends State<_CautionDetail> {
  Timer? expiryTimer;
  @override
  void initState() {
    super.initState();
    expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    expiryTimer?.cancel();
    super.dispose();
  }

  bool busy = false;
  String? error;
  Future<void> act(CommunityHazard report, String action) async {
    if (busy || !widget.allowFeedback) return;
    if (action == 'resolve' || action == 'reopen') {
      await showCautionEvidenceDialog(context, report, action);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final saved = await TrailCautionService().update(
        report.id,
        action,
        requestId: cautionUpdateId(),
      );
      if (mounted) {
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
    } catch (e) {
      if (mounted) setState(() => error = cautionError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: (Firebase.apps.isEmpty ? null : FirebaseFirestore.instance)
        ?.collection('hazardReports')
        .doc(widget.report.id)
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasData &&
          (!snapshot.data!.exists ||
              [
                'rejected',
                'deleted',
              ].contains(snapshot.data!.data()?['status']))) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text('This caution is no longer available.'),
        );
      }
      final report = snapshot.hasData
          ? CommunityHazard.fromMap(
                  widget.report.id,
                  snapshot.data!.data() ?? {},
                  includeExpired: true,
                ) ??
                widget.report
          : widget.report;
      final active = report.isActiveAt(DateTime.now());
      final evidence = report.latestEvidence;
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  report.isResolved
                      ? Icons.check_circle_outline_rounded
                      : Icons.warning_amber_rounded,
                  color: report.isResolved
                      ? Theme.of(context).colorScheme.primary
                      : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.popupHeading ? 'Trail caution' : report.type,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (widget.allowFeedback)
                  IconButton.filledTonal(
                    tooltip: report.isResolved
                        ? 'Report issue again with evidence'
                        : 'Upvote this issue',
                    onPressed: busy || !active
                        ? null
                        : () => act(
                            report,
                            report.isResolved ? 'reopen' : 'confirm',
                          ),
                    icon: const Icon(Icons.arrow_circle_up_rounded, size: 28),
                  ),
              ],
            ),
            if (widget.popupHeading)
              Text(
                report.type,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            Text(
              !active
                  ? 'Archived · 7-day map display ended'
                  : report.isResolved
                  ? 'Resolved / Not seen · ${report.resolutionCount} confirmations'
                  : '${report.reportCount} report${report.reportCount == 1 ? '' : 's'} · Hiker confirmations',
            ),
            if (report.reportedAt != null)
              Text(
                'Reported ${cautionDate(report.reportedAt!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (report.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(report.description),
            ],
            const SizedBox(height: 10),
            CautionMediaStrip(media: report.media),
            if (evidence.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Latest evidence',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              if ('${evidence['description'] ?? ''}'.isNotEmpty)
                Text('${evidence['description']}'),
              CautionMediaStrip(media: cautionMediaFrom(evidence['media'])),
            ],
            if (widget.allowFeedback && active && !report.isResolved) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: busy ? null : () => act(report, 'resolve'),
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Resolved / Not Seen'),
              ),
            ],
            if (active && report.resolutionId != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${report.resolutionCount} / 3 resolution confirmations',
                    ),
                  ),
                  if (widget.allowFeedback)
                    IconButton.filledTonal(
                      tooltip: 'Confirm resolved / not seen',
                      onPressed: busy
                          ? null
                          : () => act(report, 'confirmResolution'),
                      icon: const Icon(Icons.arrow_circle_up_rounded),
                    ),
                ],
              ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream:
                  (Firebase.apps.isEmpty ? null : FirebaseFirestore.instance)
                      ?.collection('hazardReports')
                      .doc(report.id)
                      .collection('updates')
                      .orderBy('createdAt', descending: true)
                      .limit(30)
                      .snapshots(),
              builder: (context, snapshot) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (snapshot.hasData && snapshot.data!.docs.isNotEmpty)
                    const Text(
                      'Hiker updates',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  for (final document
                      in snapshot.data?.docs ??
                          <QueryDocumentSnapshot<Map<String, dynamic>>>[]) ...[
                    const SizedBox(height: 10),
                    Text(
                      cautionActionLabel(
                        document.data()['action'] as String? ?? '',
                      ),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    if ('${document.data()['description'] ?? ''}'.isNotEmpty)
                      Text('${document.data()['description']}'),
                    CautionMediaStrip(
                      media: cautionMediaFrom(document.data()['media']),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

String cautionActionLabel(String action) => switch (action) {
  'resolve' => 'Reported resolved / not seen',
  'confirmResolution' => 'Confirmed resolved / not seen',
  'reopen' => 'Caution reported present again',
  _ => 'Caution confirmed',
};
String cautionUpdateId() =>
    'update_${DateTime.now().microsecondsSinceEpoch}_${math.Random.secure().nextInt(0x7fffffff).toRadixString(16)}';
String cautionDate(DateTime time) {
  final local = time.toLocal();
  return '${local.day}/${local.month}/${local.year} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

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

class _CautionEvidenceSubmission extends StatefulWidget {
  const _CautionEvidenceSubmission({
    required this.report,
    required this.action,
    required this.service,
  });
  final CommunityHazard report;
  final String action;
  final TrailCautionService service;
  @override
  State<_CautionEvidenceSubmission> createState() =>
      _CautionEvidenceSubmissionState();
}

class _CautionEvidenceSubmissionState
    extends State<_CautionEvidenceSubmission> {
  final editor = GlobalKey<CautionEvidenceEditorState>();
  late final requestId = cautionUpdateId();
  bool busy = false, confirmed = false;
  String? error;
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
      if (mounted) HikeStartNavigation.closeOwnedRoute(route);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = cautionError(e);
        });
      }
    }
  }

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
}

class TrailCautionsHistory extends StatefulWidget {
  const TrailCautionsHistory({super.key, required this.trailId});
  final String trailId;
  @override
  State<TrailCautionsHistory> createState() => _TrailCautionsHistoryState();
}

class _TrailCautionsHistoryState extends State<TrailCautionsHistory> {
  late final timer = Timer.periodic(const Duration(minutes: 1), (_) {
    if (mounted) setState(() {});
  });
  @override
  void initState() {
    super.initState();
    timer;
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Firebase.apps.isEmpty
      ? const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Trail Cautions History'),
            SizedBox(height: 8),
            Text('Sign in to view caution history.'),
          ],
        )
      : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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

List<CommunityHazard> sortTrailCautionsForHistory(
  Iterable<CommunityHazard> reports, {
  required DateTime now,
}) {
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

class TrailCautionsHistoryList extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final currentTime = now ?? DateTime.now();
    final sorted = sortTrailCautionsForHistory(reports, now: currentTime);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Trail Cautions History',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
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

class TrailCautionHistoryCard extends StatefulWidget {
  const TrailCautionHistoryCard({
    super.key,
    required this.report,
    required this.active,
    required this.archived,
  });
  final CommunityHazard report;
  final bool active, archived;
  @override
  State<TrailCautionHistoryCard> createState() =>
      _TrailCautionHistoryCardState();
}

class _TrailCautionHistoryCardState extends State<TrailCautionHistoryCard>
    with SingleTickerProviderStateMixin {
  late final pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  void syncPulse() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!pulse.isAnimating) pulse.repeat(reverse: true);
    } else {
      pulse.stop();
      pulse.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncPulse();
  }

  @override
  void didUpdateWidget(covariant TrailCautionHistoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncPulse();
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final report = widget.report;
    final radius = BorderRadius.circular(18);
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final glow = Curves.easeInOut.transform(pulse.value);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: widget.active
                ? Color.alphaBlend(
                    colors.error.withValues(alpha: .04 + glow * .05),
                    colors.surfaceContainerLow,
                  )
                : colors.surfaceContainerLow,
            border: Border.all(
              color: widget.active
                  ? colors.error.withValues(alpha: .25 + glow * .3)
                  : colors.outlineVariant.withValues(alpha: .5),
            ),
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: colors.error.withValues(alpha: .06 + glow * .13),
                      blurRadius: 8 + glow * 10,
                      spreadRadius: glow * 1.5,
                    ),
                  ]
                : const [],
          ),
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          leading: Icon(
            report.isResolved
                ? Icons.check_circle_outline_rounded
                : Icons.warning_amber_rounded,
            color: widget.active ? colors.error : colors.onSurfaceVariant,
          ),
          title: Text(
            report.type,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${widget.archived
                ? 'Archived'
                : report.isResolved
                ? 'Resolved'
                : 'Active'} · '
            '${report.reportCount} report${report.reportCount == 1 ? '' : 's'}'
            '${report.reportedAt == null ? '' : '\n${cautionDate(report.reportedAt!)}'}',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => showCommunityHazardDetails(
            context,
            CommunityHazardCluster([report]),
          ),
        ),
      ),
    );
  }
}

part of '../hazard_report_page_feature.dart';

class CautionReportHistoryPage extends StatefulWidget {
  const CautionReportHistoryPage({
    super.key,
    required this.session,
    required this.repository,
  });
  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  @override
  State<CautionReportHistoryPage> createState() =>
      _CautionReportHistoryPageState();
}

class _CautionReportHistoryPageState extends State<CautionReportHistoryPage> {
  StreamSubscription<String>? _subscription;
  List<LocalCautionReport>? _reports;
  String? _error;
  bool _retrying = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _subscription = widget.repository.cautionReportChanges
        .where((owner) => owner == widget.session.phoneNumber)
        .listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  Future<void> _load() async {
    final revision = ++_revision;
    try {
      final reports = await widget.repository.loadCautionReportHistory(
        session: widget.session,
      );
      if (mounted && revision == _revision) {
        setState(() {
          _reports = reports;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() => _error = 'Unable to load report history. Try again.');
      }
    }
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await widget.repository.flushPendingCautionReports(
        session: widget.session,
        forceRetry: true,
      );
      await _load();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Caution report history'),
      actions: [
        IconButton(
          tooltip: 'Retry pending reports',
          onPressed: _retrying ? null : _retry,
          icon: _retrying
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync_rounded),
        ),
      ],
    ),
    body: _error != null
        ? Center(
            child: TextButton(onPressed: _load, child: Text(_error!)),
          )
        : _reports == null
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(18),
              children: [
                const Text(
                  'Reports saved by this account on this phone. Pending reports retry automatically when connectivity returns.',
                ),
                const SizedBox(height: 16),
                if (_reports!.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('No caution reports yet.')),
                  ),
                for (final report in _reports!)
                  _CautionHistoryCard(report: report),
              ],
            ),
          ),
  );
}

class _CautionHistoryCard extends StatelessWidget {
  const _CautionHistoryCard({required this.report});
  final LocalCautionReport report;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pending = report.isPending;
    final statusColor = pending
        ? colors.onSurfaceVariant
        : report.isSent
        ? colors.primary
        : colors.error;
    final time = report.createdAt.toLocal();
    final label = MaterialLocalizations.of(context);
    return Card(
      key: ValueKey('caution-history-${report.reportId}'),
      color: pending
          ? Color.alphaBlend(
              colors.onSurface.withValues(alpha: .08),
              colors.surface,
            )
          : colors.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(trailHazardIconFor(report.hazardType), color: statusColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    report.hazardType,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(report.trailName),
            Text(
              '${label.formatMediumDate(time)} · ${label.formatTimeOfDay(TimeOfDay.fromDateTime(time))}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (report.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(report.description),
              ),
            if (report.mediaCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${report.mediaCount} attachment${report.mediaCount == 1 ? '' : 's'}',
                ),
              ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  pending
                      ? Icons.cloud_off_rounded
                      : report.isSent
                      ? Icons.cloud_done_rounded
                      : Icons.error_outline_rounded,
                  color: statusColor,
                  size: 19,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pending
                        ? 'Waiting for network — will retry'
                        : report.isSent
                        ? 'Sent — confirmed by server'
                        : 'Not sent — needs attention',
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (!pending && !report.isSent && report.lastError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(report.lastError),
              ),
          ],
        ),
      ),
    );
  }
}

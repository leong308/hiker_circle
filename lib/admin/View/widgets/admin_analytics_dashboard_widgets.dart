part of '../../admin_analytics_dashboard_feature.dart';

const _blue = Color(0xFF4285C4),
    _green = Color(0xFF32845D),
    _orange = Color(0xFFBD7A2C),
    _purple = Color(0xFF8066B3),
    _red = Color(0xFFBE4444);
const _palette = [_green, _blue, _orange, _purple, _red, Color(0xFF52A2A0)];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Reads only finite chart amounts.
num _n(Object? value) => value is num && value.isFinite ? value : 0;

/// Formats chart values without discarding fractional distance or timings.
String _fmt(Object? value) => value is num && value.isFinite
    ? AdminDashboardMetric.formatNumber(value, decimals: value != value.round())
    : '—';

/// Translates internal state names into administrator-facing chart labels.
String _label(Object? value) {
  final raw = value is String ? value.trim() : '';
  const names = {
    'delivery_uncertain': 'Unconfirmed',
    'no_token': 'No registered device',
    'partial': 'Some devices rejected',
    'sent': 'Accepted by FCM',
    'pending': 'Pending',
    'sending': 'Sending',
    'confirmed': 'Confirmed',
    'unconfirmed': 'Unconfirmed',
    'failed': 'Failed',
    'fresh': 'Fresh',
    'stale': 'Stale',
    'unavailable': 'Unavailable',
  };
  if (names.containsKey(raw)) return names[raw]!;
  if (raw.isEmpty) return 'Not recorded';
  return '${raw[0].toUpperCase()}${raw.substring(1).replaceAll('_', ' ')}';
}

/// A compact snapshot banner distinguishes data freshness from system availability.
class _DashboardSnapshotHeader extends StatelessWidget {
  /// Displays source coverage alongside the reporting timestamp.
  const _DashboardSnapshotHeader({
    required this.snapshot,
    required this.loading,
  });
  final AdminAnalyticsSnapshot snapshot;
  final bool loading;

  /// Uses restrained green surfaces and typography shared with the rest of HikerCircle.
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AdminUi.green(context).withValues(alpha: .07),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AdminUi.green(context).withValues(alpha: .14)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.analytics_outlined,
              color: AdminUi.green(context),
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'System performance',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Hiker activity, trail quality, safety and delivery operations.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AdminUi.muted(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Wrap(
          spacing: 14,
          runSpacing: 7,
          children: [
            _InlineStatus(
              icon: loading ? Icons.sync_rounded : Icons.schedule_rounded,
              label: loading ? 'Refreshing snapshot…' : snapshot.updatedLabel,
            ),
            _InlineStatus(
              icon: snapshot.incompleteCount == 0
                  ? Icons.fact_check_outlined
                  : Icons.info_outline_rounded,
              label:
                  '${snapshot.completeSourceCount} of ${snapshot.coverage.length} sources complete',
              warning: snapshot.incompleteCount > 0,
            ),
          ],
        ),
      ],
    ),
  );
}

/// Keeps snapshot metadata readable as the width and font size change.
class _InlineStatus extends StatelessWidget {
  /// Combines a small status symbol with a text description.
  const _InlineStatus({
    required this.icon,
    required this.label,
    this.warning = false,
  });
  final IconData icon;
  final String label;
  final bool warning;

  /// Wraps long labels without forcing a full-width status pill.
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: warning ? _orange : AdminUi.green(context)),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AdminUi.muted(context),
          ),
        ),
      ),
    ],
  );
}

/// Provides real dashboard areas without hiding analytics inside a disclosure drawer.
class _DashboardAreaTabs extends StatelessWidget {
  /// Reads selection from the ViewModel.
  const _DashboardAreaTabs({required this.model});
  final AdminDashboardViewModel model;

  /// Keeps every area reachable on phones and accessible at enlarged text sizes.
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final area in AdminDashboardArea.values)
          Semantics(
            selected: model.area == area,
            button: true,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: model.area == area
                    ? AdminUi.green(context)
                    : AdminUi.surface(context),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  key: ValueKey('dashboard-area-${area.name}'),
                  onTap: () => model.selectArea(area),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _areaIcon(area),
                          size: 17,
                          color: model.area == area
                              ? _selectedForeground(context)
                              : AdminUi.muted(context),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          area.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: model.area == area
                                ? _selectedForeground(context)
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
      ],
    ),
  );
}

/// Offers one date range for all period-scoped charts and headline metrics.
class _DashboardPeriodSelector extends StatelessWidget {
  /// Delegates calendar-window changes to the ViewModel.
  const _DashboardPeriodSelector({required this.model});
  final AdminDashboardViewModel model;

  /// Uses wrapping choices so narrow devices never clip the date range.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AdminSectionHeading(title: 'Reporting period'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 7,
        runSpacing: 4,
        children: [
          for (final period in AdminDashboardPeriod.values)
            ChoiceChip(
              key: ValueKey('analytics-period-${period.days}'),
              label: Text(period.label),
              selected: model.period == period,
              showCheckmark: false,
              onSelected: (_) => model.selectPeriod(period),
              selectedColor: AdminUi.green(context).withValues(alpha: .13),
              backgroundColor: AdminUi.surface(context),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: model.period == period
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
              side: BorderSide(
                color: model.period == period
                    ? AdminUi.green(context).withValues(alpha: .3)
                    : AdminUi.border(context),
              ),
            ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        'Period comparisons use Malaysia calendar days. Today is partial. Panels labelled current or all time keep their stated scope.',
        style: TextStyle(
          fontSize: 11,
          height: 1.5,
          color: AdminUi.muted(context),
        ),
      ),
    ],
  );
}

/// One consistent KPI card carries its scope and comparison beside the number.
class _MetricCard extends StatelessWidget {
  /// Allows management-linked metrics to share the same appearance.
  const _MetricCard({
    required this.metric,
    required this.icon,
    required this.tint,
    this.onTap,
  });
  final AdminDashboardMetric metric;
  final IconData icon;
  final Color tint;
  final VoidCallback? onTap;

  /// Retains all labels instead of truncating important metric definitions.
  @override
  Widget build(BuildContext context) {
    final comparison = metric.comparisonLabel;
    final trendColor = metric.trendMeaning > 0
        ? AdminUi.green(context)
        : metric.trendMeaning < 0
        ? Theme.of(context).colorScheme.error
        : AdminUi.muted(context);
    return AdminPanel(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: tint),
              ),
              const Spacer(),
              if (onTap != null)
                Icon(
                  Icons.arrow_outward_rounded,
                  size: 16,
                  color: AdminUi.muted(context),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              metric.formatted,
              key: ValueKey('metric-value-${metric.title}'),
              style: const TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                letterSpacing: -.7,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            metric.title,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (metric.detail.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              metric.detail,
              style: TextStyle(
                fontSize: 11,
                height: 1.45,
                color: AdminUi.muted(context),
              ),
            ),
          ],
          if (comparison != null) ...[
            const SizedBox(height: 10),
            Text(
              comparison,
              style: TextStyle(
                fontSize: 10,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: trendColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Keeps current activity compact so performance charts are reached sooner.
class _CurrentActivityPanel extends StatelessWidget {
  /// Groups the four snapshot values in one shared dashboard surface.
  const _CurrentActivityPanel({required this.children});
  final List<Widget> children;

  /// Reuses the adaptive grid for phones, tablets and enlarged text.
  @override
  Widget build(BuildContext context) => AdminPanel(
    padding: const EdgeInsets.all(4),
    child: _ResponsiveGrid(compact: true, children: children),
  );
}

/// Presents one current-state number without the height of a full trend card.
class _CurrentActivityValue extends StatelessWidget {
  /// Retains management shortcuts and the full scope in its tooltip.
  const _CurrentActivityValue({
    required this.metric,
    required this.icon,
    required this.tint,
    this.onTap,
  });
  final AdminDashboardMetric metric;
  final IconData icon;
  final Color tint;
  final VoidCallback? onTap;

  /// Uses text and icons together so colour is never the only state signal.
  @override
  Widget build(BuildContext context) => Tooltip(
    message: metric.detail,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: tint, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    metric.formatted,
                    key: ValueKey('metric-value-${metric.title}'),
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AdminUi.muted(context),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              metric.title,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Presents partial or failed snapshot state without covering useful data.
class _SnapshotNotice extends StatelessWidget {
  /// Adds a retry only when the parent has a refresh action.
  const _SnapshotNotice({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  /// Uses an inline notice rather than a full-screen blocking error.
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: _orange.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _orange.withValues(alpha: .2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, size: 18, color: _orange),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
        if (onRetry != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: onRetry,
              child: const Text('Retry statistics'),
            ),
          ),
      ],
    ),
  );
}

/// Makes the initial load and total failure states useful without fabricated counters.
class _DashboardUnavailable extends StatelessWidget {
  /// Preserves access to management tools when analytics is unavailable.
  const _DashboardUnavailable({
    required this.loading,
    required this.onRetry,
    required this.onTools,
    this.error,
  });
  final bool loading;
  final String? error;
  final VoidCallback onRetry, onTools;

  /// Uses the same panel hierarchy as the loaded dashboard.
  @override
  Widget build(BuildContext context) => AdminPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.analytics_outlined, size: 30, color: AdminUi.green(context)),
        const SizedBox(height: 14),
        Text(
          loading ? 'Analysing system activity' : 'Analysis unavailable',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          loading
              ? 'Preparing account, hiking, trail, safety and delivery metrics…'
              : error ?? 'Refresh to retrieve a system snapshot.',
          style: TextStyle(height: 1.5, color: AdminUi.muted(context)),
        ),
        if (loading) ...[
          const SizedBox(height: 18),
          const LinearProgressIndicator(minHeight: 3),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            if (!loading)
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry statistics'),
              ),
            TextButton.icon(
              onPressed: onTools,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Admin tools'),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Draws a ranked operational finding with a concrete destination.
class _AttentionRow extends StatelessWidget {
  /// Receives safe aggregate text, not raw source documents.
  const _AttentionRow({required this.issue, required this.onTap});
  final Map<String, dynamic> issue;
  final VoidCallback onTap;

  /// Keeps finding text and its count usable on small screens.
  @override
  Widget build(BuildContext context) {
    final urgent = issue['severity'] == 'urgent';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              urgent
                  ? Icons.error_outline_rounded
                  : Icons.pending_actions_rounded,
              size: 21,
              color: urgent ? Theme.of(context).colorScheme.error : _orange,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${issue['title']}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${issue['detail']}',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: AdminUi.muted(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _fmt(issue['count']),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: urgent
                    ? Theme.of(context).colorScheme.error
                    : AdminUi.green(context),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Keeps short methodology explanations readable beside the relevant metrics.
class _DefinitionLine extends StatelessWidget {
  /// Separates a term from its plain-language definition.
  const _DefinitionLine({required this.title, required this.body});
  final String title, body;

  /// Adds generous line height while avoiding large empty gaps.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: AdminUi.muted(context),
          ),
        ),
      ],
    ),
  );
}

/// Reuses a concise count row for completeness and quality checks.
class _ValueLine extends StatelessWidget {
  /// Accepts an already-scoped metric rather than calculating totals in the view.
  const _ValueLine({required this.metric});
  final AdminDashboardMetric metric;

  /// Wraps the label and keeps the figure visible.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            metric.title,
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          metric.formatted,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ],
    ),
  );
}

/// Links workload analysis to an existing protected management page.
class _ActionPanel extends StatelessWidget {
  /// Keeps the action label explicit about what will open.
  const _ActionPanel({
    required this.title,
    required this.detail,
    required this.metric,
    required this.icon,
    required this.onTap,
    required this.action,
  });
  final String title, detail, action;
  final AdminDashboardMetric metric;
  final IconData icon;
  final VoidCallback onTap;

  /// Uses the app's standard green button for administrative navigation.
  @override
  Widget build(BuildContext context) => AdminPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: AdminUi.green(context), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          detail,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: AdminUi.muted(context),
          ),
        ),
        const SizedBox(height: 8),
        _ValueLine(metric: metric),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: onTap,
          child: Text(action, textAlign: TextAlign.center),
        ),
      ],
    ),
  );
}

/// Gives methodology notes a quiet, consistent place below the data.
class _DashboardNote extends StatelessWidget {
  /// Requires a short explanation relevant to the current dashboard area.
  const _DashboardNote({required this.text});
  final String text;

  /// Avoids making explanatory text compete with headline metrics.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
    child: Text(
      text,
      style: TextStyle(
        color: AdminUi.muted(context),
        fontSize: 11,
        height: 1.6,
      ),
    ),
  );
}

/// Exposes complete, partial and unavailable sources instead of hiding sampling limits.
class _CoveragePanel extends StatelessWidget {
  /// Uses the same coverage metadata that gates metric rates and counts.
  const _CoveragePanel({required this.snapshot, this.onRefresh});
  final AdminAnalyticsSnapshot snapshot;
  final VoidCallback? onRefresh;

  /// Makes each business source and its analysed coverage inspectable.
  @override
  Widget build(BuildContext context) => AdminPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${snapshot.completeSourceCount} of ${snapshot.coverage.length} sources complete',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Complete means every available page was analysed. Exact collection counts can remain available when a detailed read is incomplete.',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: AdminUi.muted(context),
          ),
        ),
        const SizedBox(height: 12),
        for (final row in snapshot.coverage)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  row['complete'] == true
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
                  size: 18,
                  color: row['complete'] == true
                      ? AdminUi.green(context)
                      : _orange,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row['label']}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        row['complete'] == true
                            ? 'Complete · ${_fmt(row['analysed'])} analysed'
                            : row['available'] == false
                            ? 'Unavailable'
                            : 'Partial · ${_fmt(row['analysed'])} of ${_fmt(row['total'])} analysed',
                        style: TextStyle(
                          fontSize: 11,
                          color: AdminUi.muted(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (onRefresh != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh analysis'),
            ),
          ),
      ],
    ),
  );
}

/// Uses a dark foreground on the lighter green selected surface in dark mode.
Color _selectedForeground(BuildContext context) =>
    AdminUi.dark(context) ? const Color(0xFF102A1B) : Colors.white;

/// Maps analysis areas to familiar HikerCircle navigation symbols.
IconData _areaIcon(AdminDashboardArea area) => switch (area) {
  AdminDashboardArea.overview => Icons.space_dashboard_outlined,
  AdminDashboardArea.hiking => Icons.hiking_rounded,
  AdminDashboardArea.safety => Icons.shield_outlined,
  AdminDashboardArea.trails => Icons.terrain_outlined,
  AdminDashboardArea.people => Icons.people_outline_rounded,
  AdminDashboardArea.operations => Icons.monitor_heart_outlined,
};

/// Displays the responsive grid.
class _ResponsiveGrid extends StatelessWidget {
  /// Creates responsive grid.
  const _ResponsiveGrid({required this.children, this.compact = false});
  final List<Widget> children;
  final bool compact;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final cols = scale >= 1.5
          ? 1
          : compact
          ? (c.maxWidth >= 1000
                ? 4
                : c.maxWidth >= 280
                ? 2
                : 1)
          : c.maxWidth >= 760
          ? 2
          : 1;
      return Column(
        children: [
          for (var index = 0; index < children.length; index += cols)
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var offset = 0; offset < cols; offset++) ...[
                      if (offset > 0) const SizedBox(width: 12),
                      Expanded(
                        child: index + offset < children.length
                            ? children[index + offset]
                            : const SizedBox(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// Displays the timeline.
class _Timeline extends StatelessWidget {
  /// Creates timeline.
  const _Timeline({
    required this.rows,
    required this.metric,
    required this.color,
    this.emptyLabel = 'No recorded activity in this period.',
  });
  final List<Map<String, dynamic>> rows;
  final String metric;
  final Color color;
  final String emptyLabel;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty || rows.every((r) => _n(r[metric]) == 0)) {
      return SizedBox(
        height: 170,
        child: Center(child: Text(emptyLabel, textAlign: TextAlign.center)),
      );
    }
    final maximum = rows.fold<double>(
      0,
      (m, r) => math.max(m, _n(r[metric]).toDouble()),
    );
    final interval = math.max(1.0, (maximum / 4).ceilToDouble());
    final muted = AdminUi.muted(context);
    final tick = math.max(1, ((rows.length - 1) / 3).ceil());
    return Semantics(
      label:
          '$metric activity chart. ${rows.length} time buckets. Tap to inspect.',
      child: SizedBox(
        height: 205,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: math.max(1, rows.length - 1).toDouble(),
            minY: 0,
            maxY: math.max(1, maximum + interval).toDouble(),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => spots.map((s) {
                  final i = s.x.round().clamp(0, rows.length - 1);
                  return LineTooltipItem(
                    "${rows[i]['date']}\n${_fmt(s.y)} ${AdminDashboardViewModel.trendLabels[metric] ?? metric}",
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                }).toList(),
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  interval: interval,
                  getTitlesWidget: (v, m) => Text(
                    _fmt(v),
                    style: TextStyle(fontSize: 10, color: muted),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  interval: tick.toDouble(),
                  getTitlesWidget: (v, m) {
                    final i = v.round();
                    if (i < 0 || i >= rows.length) return const SizedBox();
                    final raw = rows[i]['date'].toString();
                    return Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Text(
                        raw.length == 7
                            ? _months[(int.tryParse(raw.substring(5)) ?? 1)
                                      .clamp(1, 12) -
                                  1]
                            : '${raw.substring(8)}/${raw.substring(5, 7)}',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                    );
                  },
                ),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: interval,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: AdminUi.border(context), strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var i = 0; i < rows.length; i++)
                    FlSpot(i.toDouble(), _n(rows[i][metric]).toDouble()),
                ],
                color: color,
                barWidth: 2.5,
                isCurved: false,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: .2),
                      color.withValues(alpha: .01),
                    ],
                  ),
                ),
              ),
            ],
          ),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 250),
        ),
      ),
    );
  }
}

/// Displays the bars.
class _Bars extends StatelessWidget {
  /// Creates bars.
  const _Bars({
    required this.title,
    required this.rows,
    required this.suffix,
    this.subtitle,
    this.emptyLabel = 'No records in this scope.',
    this.partial = false,
  });
  final String title, suffix;
  final String? subtitle;
  final String emptyLabel;
  final bool partial;
  final List<Map<String, dynamic>> rows;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final max = rows.fold<num>(0, (n, r) => math.max(n, _n(r['value'])));
    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeading(title: title, subtitle: subtitle),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            Text(emptyLabel, style: TextStyle(color: AdminUi.muted(context))),
          for (final (i, row) in rows.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _label(row['label']),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${partial ? '≥ ' : ''}${_fmt(row['value'])}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: max == 0 ? 0 : (_n(row['value']) / max).toDouble(),
                      minHeight: 7,
                      color: _palette[i % _palette.length],
                      backgroundColor: AdminUi.border(
                        context,
                      ).withValues(alpha: .55),
                    ),
                  ),
                ],
              ),
            ),
          Text(
            '${partial ? 'Partial counts' : 'Counts'} in $suffix',
            style: TextStyle(fontSize: 10, color: AdminUi.muted(context)),
          ),
        ],
      ),
    );
  }
}

/// Displays the donut.
class _Donut extends StatefulWidget {
  /// Creates donut.
  const _Donut({
    required this.title,
    required this.rows,
    required this.center,
    required this.unit,
    this.emptyLabel = 'No records in this scope.',
    this.partial = false,
  });
  final String title, center, unit, emptyLabel;
  final bool partial;
  final List<Map<String, dynamic>> rows;

  /// Creates the presentation state for this widget.
  @override
  State<_Donut> createState() => _DonutState();
}

/// Manages the donut presentation and lifecycle.
class _DonutState extends State<_Donut> {
  int? _selected;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final total = widget.rows.fold<num>(0, (n, r) => n + _n(r['value']));
    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeading(title: widget.title),
          const SizedBox(height: 12),
          if (total == 0)
            SizedBox(
              height: 150,
              child: Center(
                child: Text(
                  widget.emptyLabel,
                  style: TextStyle(color: AdminUi.muted(context)),
                ),
              ),
            )
          else
            SizedBox(
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      centerSpaceRadius: 58,
                      sectionsSpace: 3,
                      startDegreeOffset: -90,
                      pieTouchData: PieTouchData(
                        touchCallback: (event, response) {
                          setState(
                            () => _selected =
                                event.isInterestedForInteractions &&
                                    response
                                            ?.touchedSection
                                            ?.touchedSectionIndex !=
                                        -1
                                ? response?.touchedSection?.touchedSectionIndex
                                : null,
                          );
                        },
                      ),
                      sections: [
                        for (final (i, row) in widget.rows.indexed)
                          PieChartSectionData(
                            value: _n(row['value']).toDouble(),
                            color: _palette[i % _palette.length],
                            radius: _selected == i ? 26 : 20,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                  IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _selected != null && _selected! < widget.rows.length
                              ? _fmt(widget.rows[_selected!]['value'])
                              : widget.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          widget.unit,
                          style: TextStyle(
                            fontSize: 11,
                            color: AdminUi.muted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 14,
            runSpacing: 10,
            children: [
              for (final (i, row) in widget.rows.indexed)
                InkWell(
                  onTap: () =>
                      setState(() => _selected = _selected == i ? null : i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _palette[i % _palette.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            "${_label(row['label'])} · ${widget.partial ? '≥ ' : ''}${_fmt(row['value'])}",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: _selected == i
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

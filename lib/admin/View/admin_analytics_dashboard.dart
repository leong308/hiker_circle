// AdminAnalyticsDashboard presents backend statistics, time ranges and operational charts.
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'admin_ui.dart';

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : {};
List<Map<String, dynamic>> _rows(Object? v) => v is List
    ? v.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList()
    : [];
num _n(Object? v) => v is num && v.isFinite ? v : 0;
String _fmt(Object? value) {
  final n = _n(value);
  return n >= 10000
      ? '${(n / 1000).toStringAsFixed(1)}k'
      : n == n.round()
      ? '${n.round()}'
      : n.toStringAsFixed(1);
}

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
String _label(Object? value) {
  final text = value?.toString() ?? 'Not recorded';
  return text.isEmpty
      ? 'Not recorded'
      : '${text[0].toUpperCase()}${text.substring(1).replaceAll('_', ' ')}';
}

const _blue = Color(0xFF4C8FE8),
    _green = Color(0xFF42A781),
    _orange = Color(0xFFDF9752),
    _purple = Color(0xFF9A80DA);
const _palette = [
  _blue,
  _green,
  _orange,
  _purple,
  Color(0xFFDF7487),
  Color(0xFF6BBFC1),
];

/// Render server-computed analytics and expose refresh state without recomputing cloud totals locally.
class AdminAnalyticsDashboard extends StatefulWidget {
  const AdminAnalyticsDashboard({
    super.key,
    required this.data,
    required this.loading,
    this.error,
    required this.onRetry,
    required this.onSafety,
    required this.onCommunity,
    required this.onRewards,
    required this.onTools,
  });
  final Map<String, dynamic>? data;
  final bool loading;
  final String? error;
  final VoidCallback onRetry, onSafety, onCommunity, onRewards, onTools;
  @override
  State<AdminAnalyticsDashboard> createState() =>
      _AdminAnalyticsDashboardState();
}

class _AdminAnalyticsDashboardState extends State<AdminAnalyticsDashboard> {
  int _period = 30;
  String _growth = 'users';

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data == null) {
      return AdminPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.insights_rounded,
              color: AdminUi.green(context),
              size: 28,
            ),
            const SizedBox(height: 14),
            Text(
              widget.loading ? 'Loading overview' : 'Overview unavailable',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              widget.loading
                  ? 'Fetching the latest figures…'
                  : widget.error ?? 'Statistics are not available yet.',
              style: TextStyle(color: AdminUi.muted(context), height: 1.5),
            ),
            if (widget.loading) ...[
              const SizedBox(height: 18),
              const LinearProgressIndicator(minHeight: 3),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (!widget.loading)
                  OutlinedButton.icon(
                    onPressed: widget.onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry statistics'),
                  ),
                TextButton.icon(
                  onPressed: widget.onTools,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Admin tools'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final totals = _map(data['totals']), users = _map(data['users']);
    final hikes = _map(data['hikes']), community = _map(data['community']);
    final safety = _map(data['safety']);
    final incomplete = _map(data['coverage']).entries
        .where(
          (entry) =>
              !{'trails', 'trailRequests'}.contains(entry.key) &&
              _map(entry.value)['complete'] == false,
        )
        .map((entry) => entry.key)
        .toList();
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SnapshotSummary(
            active: _fmt(hikes['active']),
            upcoming: _fmt(hikes['upcoming']),
            updated: _snapshotTime(context, data['generatedAtMillis']),
            loading: widget.loading,
          ),
          if (widget.loading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (widget.error != null)
            _SnapshotNotice(
              message:
                  'Refresh failed. Showing the previous snapshot. ${widget.error}',
              onRetry: widget.loading ? null : widget.onRetry,
            ),
          if (incomplete.isNotEmpty)
            _SnapshotNotice(
              message:
                  'Collection totals are exact; charts and breakdowns cover the first 10,000 records in ${incomplete.join(', ')}.',
            ),
          const SizedBox(height: 18),
          AdminPanel(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AdminSectionHeading(
                  title: 'Review queue',
                  subtitle: 'Pending reports and moderation work.',
                ),
                const SizedBox(height: 8),
                _QueueRow(
                  title: 'Safety reports',
                  detail: 'Review reported hazards',
                  count: _n(safety['pendingHazards']),
                  icon: Icons.shield_outlined,
                  tint: _orange,
                  onTap: widget.onSafety,
                ),
                Divider(height: 1, color: AdminUi.border(context)),
                _QueueRow(
                  title: 'Community flags',
                  detail: 'Review flagged content',
                  count: _n(safety['pendingReviews']),
                  icon: Icons.flag_outlined,
                  tint: _purple,
                  onTap: widget.onCommunity,
                ),
                Divider(height: 1, color: AdminUi.border(context)),
                _QueueRow(
                  title: 'Open feedback',
                  detail: 'Follow up on unresolved reports',
                  count: _n(safety['openFeedback']),
                  icon: Icons.feedback_outlined,
                  tint: _blue,
                  onTap: widget.onTools,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const AdminSectionHeading(title: 'Key figures'),
          const SizedBox(height: 12),
          _ResponsiveGrid(
            compact: true,
            children: [
              _Metric(
                title: 'Registered users',
                value: _fmt(totals['users']),
                detail:
                    '${_fmt(users['recentSignIns'])} signed in · last 30 days',
                icon: Icons.people_alt_outlined,
                tint: _blue,
              ),
              _Metric(
                title: 'Completed sessions',
                value: _fmt(hikes['completed']),
                detail: '${_fmt(hikes['distanceKm'])} km recorded',
                icon: Icons.hiking_rounded,
                tint: _green,
              ),
              _Metric(
                title: 'Community posts',
                value: _fmt(totals['posts']),
                detail:
                    '${_fmt(community['likes'])} likes · ${_fmt(community['comments'])} comments',
                icon: Icons.forum_outlined,
                tint: _purple,
                onTap: widget.onCommunity,
              ),
              _Metric(
                title: 'Active hikers',
                value: _fmt(users['activeHikers30Days']),
                detail: 'Started a hike · last 30 days',
                icon: Icons.directions_walk_rounded,
                tint: _orange,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _activity(data),
          const SizedBox(height: 18),
          AdminPanel(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              key: const ValueKey('admin-more-statistics'),
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 6,
              ),
              leading: Icon(
                Icons.bar_chart_rounded,
                color: AdminUi.green(context),
              ),
              title: const Text(
                'More system breakdowns',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              subtitle: Text(
                'Hiking, community, safety and rewards',
                style: TextStyle(fontSize: 12, color: AdminUi.muted(context)),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  child: _details(data),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AdminPanel(
            onTap: widget.onTools,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  color: AdminUi.green(context),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Admin tools',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Feedback and diagnostics',
                        style: TextStyle(
                          color: AdminUi.muted(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AdminUi.muted(context),
                  size: 20,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _activity(Map<String, dynamic> data) {
    final daily = _rows(data['daily']), monthly = _rows(data['monthly']);
    final series = _period == 365
        ? monthly
        : daily.skip(math.max(0, daily.length - _period)).toList();
    final total = series.fold<num>(0, (sum, row) => sum + _n(row[_growth]));
    final label = switch (_growth) {
      'users' => total == 1 ? 'new user' : 'new users',
      'hikes' => total == 1 ? 'completed session' : 'completed sessions',
      _ => total == 1 ? 'new post' : 'new posts',
    };
    final missing = _map(
      data['unknownDates'],
    ).values.fold<num>(0, (sum, value) => sum + _n(value));
    final color = switch (_growth) {
      'users' => _blue,
      'hikes' => _green,
      _ => _purple,
    };
    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AdminSectionHeading(title: 'Growth & activity'),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final period in [30, 90, 365])
                ChoiceChip(
                  key: ValueKey('analytics-period-$period'),
                  label: Text(period == 365 ? '12 months' : '$period days'),
                  selected: _period == period,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _period = period),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: _period == period
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                  selectedColor: AdminUi.green(context).withValues(alpha: .12),
                  backgroundColor: AdminUi.background(context),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '${_fmt(total)} $label in this period',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          _Timeline(rows: series, metric: _growth, color: color),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in {
                'users': 'Users',
                'hikes': 'Hikes',
                'posts': 'Posts',
              }.entries)
                TextButton.icon(
                  onPressed: () => setState(() => _growth = entry.key),
                  icon: Icon(
                    _growth == entry.key
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 14,
                  ),
                  label: Text(entry.value),
                  style: TextButton.styleFrom(
                    foregroundColor: _growth == entry.key
                        ? color
                        : AdminUi.muted(context),
                    textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 12,
                      fontWeight: _growth == entry.key
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
            ],
          ),
          if (missing > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${_fmt(missing)} records have missing or future dates and are excluded from timelines.',
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: AdminUi.muted(context),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Tap the chart to inspect a date. Team participants count as separate hiker sessions.',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: AdminUi.muted(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _details(Map<String, dynamic> data) {
    final totals = _map(data['totals']), hikes = _map(data['hikes']);
    final users = _map(data['users']), safety = _map(data['safety']);
    final community = _map(data['community']), rewards = _map(data['rewards']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.all(6),
          child: AdminSectionHeading(title: 'Hiking activity'),
        ),
        const SizedBox(height: 8),
        _ResponsiveGrid(
          compact: true,
          children: [
            _Metric(
              title: 'Hiking hours',
              value: _fmt(hikes['hours']),
              detail: 'Completed sessions · all time',
              icon: Icons.timer_outlined,
              tint: _green,
            ),
            _Metric(
              title: 'Average distance',
              value: '${_fmt(hikes['averageDistanceKm'])} km',
              detail: 'Per completed hiker session',
              icon: Icons.straighten_rounded,
              tint: _blue,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ResponsiveGrid(
          children: [
            _Donut(
              title: 'Session outcomes',
              rows: _rows(hikes['byStatus']),
              center: _fmt(totals['hikeSessions']),
              unit: 'sessions',
            ),
            _Donut(
              title: 'Hike types',
              rows: _rows(hikes['byType']),
              center: _fmt(totals['hikeSessions']),
              unit: 'sessions',
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.all(6),
          child: AdminSectionHeading(title: 'Community & safety'),
        ),
        const SizedBox(height: 8),
        _ResponsiveGrid(
          children: [
            _Donut(
              title: 'Community visibility',
              rows: _rows(community['byVisibility']),
              center: _fmt(totals['posts']),
              unit: 'posts',
            ),
            _Bars(
              title: 'Hazard severity',
              rows: _rows(safety['bySeverity']),
              suffix: 'reports',
            ),
            _Bars(
              title: 'Hazard review status',
              rows: _rows(safety['byHazardStatus']),
              suffix: 'reports',
            ),
            _Bars(
              title: 'Hazard types',
              rows: _rows(safety['byHazardType']),
              suffix: 'reports',
            ),
            _Bars(
              title: 'Feedback status',
              rows: _rows(safety['byFeedbackStatus']),
              suffix: 'reports',
            ),
            _Bars(
              title: 'Feedback categories',
              rows: _rows(safety['byFeedbackCategory']),
              suffix: 'reports',
            ),
            _Bars(
              title: 'SOS alert status',
              rows: _rows(safety['bySosStatus']),
              suffix: 'alerts',
              subtitle:
                  'Recorded states, rather than a live safety assessment.',
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.all(6),
          child: AdminSectionHeading(title: 'Accounts & rewards'),
        ),
        const SizedBox(height: 8),
        _Metric(
          title: 'Achievement awards',
          value: _fmt(totals['achievementAwards']),
          detail: '${_fmt(totals['achievements'])} reward definitions',
          icon: Icons.emoji_events_outlined,
          tint: _purple,
          onTap: widget.onRewards,
        ),
        const SizedBox(height: 12),
        _ResponsiveGrid(
          children: [
            _Bars(
              title: 'Account signals',
              subtitle: 'These groups may overlap.',
              suffix: 'users',
              rows: [
                {
                  'label': 'Administrators',
                  'value': users['administrators'] ?? 0,
                },
                {'label': 'Disabled accounts', 'value': users['disabled'] ?? 0},
                {
                  'label': 'Signed in within 30 days',
                  'value': users['recentSignIns'] ?? 0,
                },
              ],
            ),
            _Bars(
              title: 'Reward definitions',
              suffix: 'definitions',
              rows: [
                {'label': 'Active', 'value': rewards['active'] ?? 0},
                {'label': 'Archived', 'value': rewards['inactive'] ?? 0},
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'All-time totals reflect current records. Deleted records are not reconstructed. Engagement uses stored like/comment counters; sign-ins represent the latest recorded sign-in, not every app visit.',
          style: TextStyle(
            color: AdminUi.muted(context),
            fontSize: 11,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _SnapshotSummary extends StatelessWidget {
  const _SnapshotSummary({
    required this.active,
    required this.upcoming,
    required this.updated,
    required this.loading,
  });
  final String active, upcoming, updated;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final dark = AdminUi.dark(context);
    final foreground = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [const Color(0xFF203D30), const Color(0xFF192B25)]
              : [const Color(0xFFE6F2E9), const Color(0xFFF2F7F3)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AdminUi.green(context).withValues(alpha: .12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Activity snapshot',
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            loading ? 'Refreshing…' : 'Updated $updated · MYT',
            style: TextStyle(
              color: AdminUi.muted(context),
              fontSize: 11,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SnapshotValue(
                  value: active,
                  label: 'Active sessions',
                  icon: Icons.hiking_rounded,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _SnapshotValue(
                  value: upcoming,
                  label: 'Upcoming hikes',
                  icon: Icons.event_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SnapshotValue extends StatelessWidget {
  const _SnapshotValue({
    required this.value,
    required this.label,
    required this.icon,
  });
  final String value, label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, color: AdminUi.green(context), size: 19),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 3),
      Text(
        label,
        style: TextStyle(
          color: AdminUi.muted(context),
          fontSize: 12,
          height: 1.4,
        ),
      ),
    ],
  );
}

class _SnapshotNotice extends StatelessWidget {
  const _SnapshotNotice({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _orange.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _orange.withValues(alpha: .25)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: _orange, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
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

String _snapshotTime(BuildContext context, Object? value) {
  if (value is! num) return 'unavailable';
  final date = DateTime.fromMillisecondsSinceEpoch(
    value.toInt(),
    isUtc: true,
  ).add(const Duration(hours: 8));
  return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.children, this.compact = false});
  final List<Widget> children;
  final bool compact;
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

class _Metric extends StatelessWidget {
  const _Metric({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    required this.tint,
    this.onTap,
  });
  final String title, value, detail;
  final IconData icon;
  final Color tint;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => AdminPanel(
    onTap: onTap,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: tint, size: 18),
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
        Text(
          value,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            height: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          detail,
          style: TextStyle(
            fontSize: 11,
            color: AdminUi.muted(context),
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.rows,
    required this.metric,
    required this.color,
  });
  final List<Map<String, dynamic>> rows;
  final String metric;
  final Color color;
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty || rows.every((r) => _n(r[metric]) == 0)) {
      return const SizedBox(
        height: 170,
        child: Center(child: Text('No recorded activity in this period.')),
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
                    '${rows[i]['date']}\n${s.y.toInt()} $metric',
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
          duration: const Duration(milliseconds: 400),
        ),
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({
    required this.title,
    required this.rows,
    required this.suffix,
    this.subtitle,
  });
  final String title, suffix;
  final String? subtitle;
  final List<Map<String, dynamic>> rows;
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
            Text(
              'No records yet.',
              style: TextStyle(color: AdminUi.muted(context)),
            ),
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
                        _fmt(row['value']),
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
            'Counts in $suffix',
            style: TextStyle(fontSize: 10, color: AdminUi.muted(context)),
          ),
        ],
      ),
    );
  }
}

class _Donut extends StatefulWidget {
  const _Donut({
    required this.title,
    required this.rows,
    required this.center,
    required this.unit,
  });
  final String title, center, unit;
  final List<Map<String, dynamic>> rows;
  @override
  State<_Donut> createState() => _DonutState();
}

class _DonutState extends State<_Donut> {
  int? _selected;
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
                  'No records yet.',
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
                            '${_label(row['label'])} · ${_fmt(row['value'])}',
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

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.title,
    required this.detail,
    required this.count,
    required this.icon,
    required this.tint,
    required this.onTap,
  });
  final String title, detail;
  final num count;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: tint, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: AdminUi.muted(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            constraints: const BoxConstraints(minWidth: 30),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: count > 0
                  ? tint.withValues(alpha: .12)
                  : AdminUi.background(context),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              _fmt(count),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AdminUi.muted(context),
          ),
        ],
      ),
    ),
  );
}

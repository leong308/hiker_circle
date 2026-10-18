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
    required this.onTrails,
    this.onTrailRequests,
    required this.onSafety,
    required this.onCommunity,
    required this.onRewards,
    required this.onTools,
  });
  final Map<String, dynamic>? data;
  final bool loading;
  final String? error;
  final VoidCallback? onTrailRequests;
  final VoidCallback onRetry,
      onTrails,
      onSafety,
      onCommunity,
      onRewards,
      onTools;
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
            const Text(
              'System analytics',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (widget.loading) const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 12),
            Text(
              widget.loading
                  ? 'Building your Firestore statistics…'
                  : widget.error ?? 'Statistics are not available yet.',
            ),
            if (!widget.loading)
              TextButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry statistics'),
              ),
            TextButton.icon(
              onPressed: widget.onTools,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Admin tools'),
            ),
          ],
        ),
      );
    }
    final totals = _map(data['totals']),
        users = _map(data['users']),
        trails = _map(data['trails']);
    final hikes = _map(data['hikes']),
        community = _map(data['community']),
        safety = _map(data['safety']);
    final daily = _rows(data['daily']), monthly = _rows(data['monthly']);
    final series = _period == 365
        ? monthly
        : daily.skip(math.max(0, daily.length - _period)).toList();
    final activityTotal = series.fold<num>(0, (n, r) => n + _n(r[_growth]));
    final activityLabel = _growth == 'users'
        ? (activityTotal == 1 ? 'new user' : 'new users')
        : _growth == 'hikes'
        ? (activityTotal == 1 ? 'completed session' : 'completed sessions')
        : (activityTotal == 1 ? 'new post' : 'new posts');
    final coverage = _map(data['coverage']);
    final incomplete = coverage.entries
        .where((e) => _map(e.value)['complete'] == false)
        .map((e) => e.key)
        .toList();
    final missing = _map(
      data['unknownDates'],
    ).values.fold<num>(0, (sum, n) => sum + _n(n));
    final pending = _n(safety['pendingHazards']).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: AdminUi.dark(context)
                  ? [const Color(0xFF233B32), const Color(0xFF192E32)]
                  : [const Color(0xFFE5F2EA), const Color(0xFFEAF1FA)],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The bigger picture',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 7),
              Text(
                'People, places and progress across HikerCircle.',
                style: TextStyle(color: AdminUi.muted(context), height: 1.4),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  const AdminTag(
                    label: 'Firestore statistics',
                    icon: Icons.cloud_done_outlined,
                  ),
                  AdminTag(
                    label: '${_fmt(hikes['active'])} hikers on a session',
                    color: AdminUi.blue(context),
                    icon: Icons.hiking_rounded,
                  ),
                  AdminTag(
                    label: '${_fmt(hikes['upcoming'])} upcoming hikes',
                    color: AdminUi.green(context),
                    icon: Icons.event_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Snapshot ${_snapshotTime(context, data['generatedAtMillis'])} · Malaysia time',
                style: TextStyle(fontSize: 11, color: AdminUi.muted(context)),
              ),
            ],
          ),
        ),
        if (widget.loading)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (widget.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Refresh failed. Showing the previous snapshot. ${widget.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (incomplete.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Collection totals are exact; charts and breakdowns cover the first 10,000 records in ${incomplete.join(', ')}.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
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
              title: 'Trail library',
              value: _fmt(totals['trails']),
              detail:
                  '${_fmt(trails['verified'])} verified · ${_fmt(trails['totalDistanceKm'])} km',
              icon: Icons.route_rounded,
              tint: _green,
              onTap: widget.onTrails,
            ),
            _Metric(
              title: 'Completed sessions',
              value: _fmt(hikes['completed']),
              detail: '${_fmt(hikes['distanceKm'])} km recorded',
              icon: Icons.hiking_rounded,
              tint: _orange,
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
          ],
        ),
        const SizedBox(height: 22),
        AdminPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AdminSectionHeading(
                title: 'Growth & activity',
                subtitle:
                    'New registrations, completed hiker sessions and posts.',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in [30, 90, 365])
                    ChoiceChip(
                      key: ValueKey('analytics-period-$p'),
                      label: Text(p == 365 ? '12 months' : '$p days'),
                      selected: _period == p,
                      onSelected: (_) => setState(() => _period = p),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in {
                    'users': 'Users',
                    'hikes': 'Hikes',
                    'posts': 'Posts',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _growth == entry.key,
                      onSelected: (_) => setState(() => _growth = entry.key),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '${_fmt(activityTotal)} $activityLabel in this period',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              _Timeline(
                rows: series,
                metric: _growth,
                color: _growth == 'users'
                    ? _blue
                    : _growth == 'hikes'
                    ? _green
                    : _purple,
              ),
              if (missing > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '${_fmt(missing)} records have missing or future dates and are excluded from timelines.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AdminUi.muted(context),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Tap or drag the chart to inspect a date. Team participants count as separate hiker sessions.',
                style: TextStyle(fontSize: 11, color: AdminUi.muted(context)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const AdminSectionHeading(
          title: 'Trail landscape',
          subtitle:
              'Where routes are available and how the library is maintained.',
        ),
        const SizedBox(height: 12),
        _ResponsiveGrid(
          children: [
            _Bars(
              title: 'Coverage by state',
              rows: _rows(trails['byState']),
              suffix: 'trails',
              allRows: true,
            ),
            _Donut(
              title: 'Route distances',
              rows: _rows(trails['byLength']),
              center: _fmt(totals['trails']),
              unit: 'trails',
            ),
            _Bars(
              title: 'Difficulty',
              rows: _rows(trails['byDifficulty']),
              suffix: 'trails',
              subtitle: 'Unrated trails are shown as not recorded.',
            ),
            AdminPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AdminSectionHeading(title: 'Library quality'),
                  const SizedBox(height: 16),
                  _Progress(
                    label: 'Verified trails',
                    value: _n(trails['verified']),
                    total: _n(totals['trails']),
                    color: _green,
                  ),
                  _Progress(
                    label: 'Stored route geometry',
                    value: _n(trails['routeStored']),
                    total: _n(totals['trails']),
                    color: _blue,
                  ),
                  _Progress(
                    label: 'Offline maps available',
                    value: _n(trails['offlineAvailable']),
                    total: _n(totals['trails']),
                    color: _purple,
                  ),
                  TextButton.icon(
                    onPressed: widget.onTrails,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text('Manage trails'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const AdminSectionHeading(
          title: 'Hiking activity',
          subtitle: 'Recorded sessions and completed-route engagement.',
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
            _Bars(
              title: 'Most hiked trails',
              rows: _rows(hikes['popularTrails']),
              suffix: 'completions',
              subtitle: 'Ranked by completed hiker sessions.',
            ),
          ],
        ),
        const SizedBox(height: 12),
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
            _Metric(
              title: 'Active hikers',
              value: _fmt(users['activeHikers30Days']),
              detail: 'Distinct users starting a hike in 30 days',
              icon: Icons.directions_walk_rounded,
              tint: _orange,
            ),
            _Metric(
              title: 'Achievement awards',
              value: _fmt(totals['achievementAwards']),
              detail: '${_fmt(totals['achievements'])} reward definitions',
              icon: Icons.emoji_events_outlined,
              tint: _purple,
              onTap: widget.onRewards,
            ),
          ],
        ),
        const SizedBox(height: 22),
        const AdminSectionHeading(
          title: 'Community & operations',
          subtitle: 'Visibility, safety reports and items needing attention.',
        ),
        const SizedBox(height: 12),
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
              title: 'Feedback status',
              rows: _rows(safety['byFeedbackStatus']),
              suffix: 'reports',
            ),
            _Bars(
              title: 'SOS alert status',
              rows: _rows(safety['bySosStatus']),
              suffix: 'alerts',
              subtitle: 'Recorded alert states; not a live safety assessment.',
            ),
          ],
        ),
        const SizedBox(height: 12),
        AdminPanel(
          padding: EdgeInsets.zero,
          child: ExpansionTile(
            key: const ValueKey('admin-more-statistics'),
            shape: const Border(),
            collapsedShape: const Border(),
            title: const Text(
              'More system breakdowns',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Accounts, hike types, hazards and reward rules',
              style: TextStyle(fontSize: 12),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                child: _ResponsiveGrid(
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
                        {
                          'label': 'Disabled accounts',
                          'value': users['disabled'] ?? 0,
                        },
                        {
                          'label': 'Signed in within 30 days',
                          'value': users['recentSignIns'] ?? 0,
                        },
                      ],
                    ),
                    _Donut(
                      title: 'Hike types',
                      rows: _rows(hikes['byType']),
                      center: _fmt(totals['hikeSessions']),
                      unit: 'sessions',
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
                      title: 'Feedback categories',
                      rows: _rows(safety['byFeedbackCategory']),
                      suffix: 'reports',
                    ),
                    _Bars(
                      title: 'Reward definitions',
                      rows: [
                        {
                          'label': 'Active',
                          'value': _map(data['rewards'])['active'] ?? 0,
                        },
                        {
                          'label': 'Archived',
                          'value': _map(data['rewards'])['inactive'] ?? 0,
                        },
                      ],
                      suffix: 'definitions',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AdminPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminSectionHeading(title: 'Review queue'),
              const SizedBox(height: 12),
              _QueueRow(
                label:
                    '${_fmt(safety['pendingTrailRequests'])} recorded trails awaiting approval',
                icon: Icons.add_road_rounded,
                onTap: widget.onTrailRequests ?? widget.onTrails,
              ),
              _QueueRow(
                label:
                    '$pending safety ${pending == 1 ? 'report needs' : 'reports need'} review',
                icon: Icons.shield_outlined,
                onTap: widget.onSafety,
              ),
              _QueueRow(
                label:
                    '${_fmt(safety['pendingReviews'])} community flags awaiting review',
                icon: Icons.flag_outlined,
                onTap: widget.onCommunity,
              ),
              _QueueRow(
                label:
                    '${_fmt(safety['openFeedback'])} feedback reports unresolved',
                icon: Icons.feedback_outlined,
                onTap: widget.onTools,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AdminPanel(
          onTap: widget.onTools,
          child: Row(
            children: [
              const Icon(Icons.tune_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Admin tools',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Feedback, button debugging and data diagnostics',
                      style: TextStyle(
                        color: AdminUi.muted(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'All-time totals reflect current Firestore records. Deleted records are not reconstructed. Engagement uses stored like/comment counters; sign-ins represent the latest recorded sign-in, not every app visit.',
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
                : c.maxWidth >= 340
                ? 2
                : 1)
          : c.maxWidth >= 760
          ? 2
          : 1;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children)
            SizedBox(
              width: (c.maxWidth - (cols - 1) * 12) / cols,
              child: child,
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: tint, size: 22),
        const SizedBox(height: 14),
        Text(
          value,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
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

class _Bars extends StatefulWidget {
  const _Bars({
    required this.title,
    required this.rows,
    required this.suffix,
    this.subtitle,
    this.allRows = false,
  });
  final String title, suffix;
  final String? subtitle;
  final List<Map<String, dynamic>> rows;
  final bool allRows;
  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final max = widget.rows.fold<num>(0, (n, r) => math.max(n, _n(r['value'])));
    final shown = widget.allRows && !_expanded
        ? widget.rows.take(6)
        : widget.rows;
    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeading(title: widget.title, subtitle: widget.subtitle),
          const SizedBox(height: 16),
          if (widget.rows.isEmpty)
            Text(
              'No records yet.',
              style: TextStyle(color: AdminUi.muted(context)),
            ),
          for (final (i, row) in shown.indexed)
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
          if (widget.allRows && widget.rows.length > 6)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded
                    ? 'Show fewer states'
                    : 'View all ${widget.rows.length} states',
              ),
            ),
          Text(
            'Counts in ${widget.suffix}',
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

class _Progress extends StatelessWidget {
  const _Progress({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });
  final String label;
  final num value, total;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
            const SizedBox(width: 8),
            Text(
              '${_fmt(value)}/${_fmt(total)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: total > 0 ? (value / total).clamp(0, 1).toDouble() : 0,
            color: color,
            backgroundColor: AdminUi.border(context),
            minHeight: 7,
          ),
        ),
      ],
    ),
  );
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: AdminUi.green(context)),
    title: Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

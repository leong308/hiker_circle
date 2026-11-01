part of '../admin_analytics_dashboard_feature.dart';

/// Presents system-wide analysis from one protected aggregate snapshot.
class AdminAnalyticsDashboard extends StatefulWidget {
  /// Keeps management navigation separate from analytics selection.
  const AdminAnalyticsDashboard({
    super.key,
    required this.data,
    required this.loading,
    this.error,
    required this.onRetry,
    required this.onSafety,
    required this.onTools,
    this.onTrailRequests,
    this.onFeedback,
  });
  final Map<String, dynamic>? data;
  final bool loading;
  final String? error;
  final VoidCallback onRetry, onSafety, onTools;
  final VoidCallback? onTrailRequests, onFeedback;

  /// Binds the dashboard's presentation lifecycle to its ViewModel.
  @override
  State<AdminAnalyticsDashboard> createState() =>
      _AdminAnalyticsDashboardState();
}

/// Owns widget bindings while the ViewModel handles filters and metric semantics.
class _AdminAnalyticsDashboardState extends State<AdminAnalyticsDashboard> {
  late final _model = AdminDashboardViewModel(widget.data);

  /// Preserves selections when a refreshed server snapshot arrives.
  @override
  void didUpdateWidget(covariant AdminAnalyticsDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) _model.updateData(widget.data);
  }

  /// Releases selection listeners when the Overview workspace closes.
  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  /// Renders the selected analysis area with consistent global scope controls.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _model,
    builder: (context, _) {
      final snapshot = _model.snapshot;
      if (snapshot == null) {
        return _DashboardUnavailable(
          loading: widget.loading,
          error: widget.error,
          onRetry: widget.onRetry,
          onTools: widget.onTools,
        );
      }
      return Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DashboardSnapshotHeader(
              snapshot: snapshot,
              loading: widget.loading,
            ),
            if (widget.loading)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (widget.error != null)
              _SnapshotNotice(
                message:
                    'Refresh could not finish. The previous snapshot remains visible.',
                onRetry: widget.loading ? null : widget.onRetry,
              ),
            if (snapshot.incompleteCount > 0)
              _SnapshotNotice(
                message:
                    '${snapshot.incompleteCount} data sources are incomplete. Counts marked ≥ are partial; rates need complete data. See Operations for coverage.',
              ),
            if (!snapshot.hasExpandedAnalysis)
              const _SnapshotNotice(
                message:
                    'Some detailed analysis is unavailable in this snapshot. Refresh to check for an updated analysis.',
              ),
            const SizedBox(height: 20),
            _DashboardAreaTabs(model: _model),
            const SizedBox(height: 18),
            if (_model.supportsPeriod) ...[
              _DashboardPeriodSelector(model: _model),
              const SizedBox(height: 20),
            ],
            ...switch (_model.area) {
              AdminDashboardArea.overview => _overview(snapshot),
              AdminDashboardArea.hiking => _hiking(snapshot),
              AdminDashboardArea.safety => _safety(snapshot),
              AdminDashboardArea.trails => _trails(snapshot),
              AdminDashboardArea.people => _people(snapshot),
              AdminDashboardArea.operations => _operations(snapshot),
            },
            const SizedBox(height: 20),
            Text(
              'Snapshot analysis · Malaysia time. Team members count as separate hiker sessions. Current-state panels and lifetime totals are labelled separately from the selected period.',
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: AdminUi.muted(context),
              ),
            ),
          ],
        ),
      );
    },
  );

  /// Gives the administrator a concise operating picture before detailed charts.
  List<Widget> _overview(AdminAnalyticsSnapshot snapshot) => [
    const AdminSectionHeading(
      title: 'Current activity',
      subtitle: 'Latest recorded state at the snapshot time',
    ),
    const SizedBox(height: 10),
    _CurrentActivityPanel(
      children: [
        _CurrentActivityValue(
          metric: _model.metric('Active hiker sessions', 'hikes.active', [
            'hikeSessions',
          ], 'Current recorded sessions'),
          icon: Icons.hiking_rounded,
          tint: _green,
        ),
        _CurrentActivityValue(
          metric: _model.metric('Active team hikes', 'teams.active', [
            'teamHikeSessions',
          ], 'One record per team'),
          icon: Icons.groups_outlined,
          tint: _blue,
        ),
        _CurrentActivityValue(
          metric: _model.metric('Upcoming plans', 'plans.upcoming', [
            'upcomingHikes',
            'teamHikeSessions',
          ], 'Future scheduled departures'),
          icon: Icons.event_outlined,
          tint: _purple,
        ),
        _CurrentActivityValue(
          metric: _model.metric(
            'Open trail cautions',
            'safety.pendingHazards',
            ['hazardReports'],
            'Reported + resolving',
          ),
          icon: Icons.shield_outlined,
          tint: _orange,
          onTap: widget.onSafety,
        ),
      ],
    ),
    const SizedBox(height: 24),
    const AdminSectionHeading(
      title: 'Period performance',
      subtitle: 'Compared with the preceding calendar period',
    ),
    const SizedBox(height: 10),
    _ResponsiveGrid(
      compact: true,
      children: [
        _MetricCard(
          metric: _model.periodMetric('Completed hikes', 'completedHikes', [
            'hikeSessions',
          ], higherIsBetter: true),
          icon: Icons.task_alt_rounded,
          tint: _green,
        ),
        _MetricCard(
          metric: _model.periodMetric('New accounts', 'newUsers', [
            'users',
          ], higherIsBetter: true),
          icon: Icons.person_add_alt_1_rounded,
          tint: _blue,
        ),
        _MetricCard(
          metric: _model.periodMetric(
            'Distance recorded',
            'distanceKm',
            ['hikeSessions'],
            unit: 'km',
            higherIsBetter: true,
          ),
          icon: Icons.route_outlined,
          tint: _purple,
        ),
        _MetricCard(
          metric: _model.periodMetric(
            'Completion rate',
            'completionRate',
            ['hikeSessions'],
            unit: '%',
            higherIsBetter: true,
          ),
          icon: Icons.flag_outlined,
          tint: _green,
        ),
      ],
    ),
    const SizedBox(height: 18),
    _trendPanel(),
    const SizedBox(height: 18),
    _attention(snapshot),
    const SizedBox(height: 18),
    _ResponsiveGrid(
      children: [
        _Donut(
          title: 'Period hike outcomes',
          rows: _model.periodOutcomes,
          center: _model.periodEndedLabel,
          unit: 'ended',
          emptyLabel: _model.emptyLabel(['hikeSessions']),
          partial: _model.partial(['hikeSessions']),
        ),
        _bars(
          'Current hazard lifecycle',
          'safety.byHazardLifecycle',
          ['hazardReports'],
          'reports',
          subtitle:
              'Includes expiry; expiry does not confirm that a trail is safe.',
        ),
      ],
    ),
    const SizedBox(height: 24),
    const AdminSectionHeading(
      title: 'System footprint',
      subtitle: 'All current records · lifetime totals',
    ),
    const SizedBox(height: 10),
    _ResponsiveGrid(
      compact: true,
      children: [
        _MetricCard(
          metric: _model.metric(
            'Registered accounts',
            'totals.users',
            ['users'],
            'Current account records',
            exactTotal: true,
          ),
          icon: Icons.people_outline_rounded,
          tint: _blue,
        ),
        _MetricCard(
          metric: _model.metric(
            'Trail catalogue',
            'totals.trails',
            ['trails'],
            'Published trail records',
            exactTotal: true,
          ),
          icon: Icons.terrain_outlined,
          tint: _green,
        ),
        _MetricCard(
          metric: _model.metric('Completed sessions', 'hikes.completed', [
            'hikeSessions',
          ], 'All recorded completions'),
          icon: Icons.check_circle_outline_rounded,
          tint: _purple,
        ),
        _MetricCard(
          metric: _model.metric(
            'Achievement awards',
            'totals.achievementAwards',
            ['userAchievements'],
            'Unlocked awards · all time',
          ),
          icon: Icons.emoji_events_outlined,
          tint: _orange,
        ),
      ],
    ),
  ];

  /// Separates hiker activity, shared team sessions and scheduled plan outcomes.
  List<Widget> _hiking(AdminAnalyticsSnapshot snapshot) => [
    const AdminSectionHeading(
      title: 'Hiking performance',
      subtitle: 'Selected reporting period',
    ),
    const SizedBox(height: 10),
    _ResponsiveGrid(
      compact: true,
      children: [
        _MetricCard(
          metric: _model.periodMetric('Hikes started', 'startedHikes', [
            'hikeSessions',
          ], higherIsBetter: true),
          icon: Icons.play_circle_outline_rounded,
          tint: _green,
        ),
        _MetricCard(
          metric: _model.periodMetric('Completed hikes', 'completedHikes', [
            'hikeSessions',
          ], higherIsBetter: true),
          icon: Icons.flag_outlined,
          tint: _blue,
        ),
        _MetricCard(
          metric: _model.periodMetric('Distinct hikers', 'activeHikers', [
            'hikeSessions',
          ], higherIsBetter: true),
          icon: Icons.people_outline_rounded,
          tint: _purple,
        ),
        _MetricCard(
          metric: _model.periodMetric('Repeat hikers', 'repeatHikers', [
            'hikeSessions',
          ], higherIsBetter: true),
          icon: Icons.repeat_rounded,
          tint: _orange,
        ),
      ],
    ),
    const SizedBox(height: 18),
    _trendPanel(),
    const SizedBox(height: 18),
    _ResponsiveGrid(
      children: [
        _Donut(
          title: 'Ended session outcomes',
          rows: _model.periodOutcomes,
          center: _model.periodEndedLabel,
          unit: 'ended',
          emptyLabel: _model.emptyLabel(['hikeSessions']),
          partial: _model.partial(['hikeSessions']),
        ),
        _bars(
          'Completed hike types',
          'windows.${_model.period.days}.current.hikeTypes',
          ['hikeSessions'],
          'hiker sessions',
          subtitle: 'Selected period · completed sessions',
        ),
      ],
    ),
    const SizedBox(height: 18),
    _ResponsiveGrid(
      compact: true,
      children: [
        _MetricCard(
          metric: _model.periodMetric('Distance recorded', 'distanceKm', [
            'hikeSessions',
          ], unit: 'km'),
          icon: Icons.route_outlined,
          tint: _green,
        ),
        _MetricCard(
          metric: _model.periodMetric('Hiking time', 'hours', [
            'hikeSessions',
          ], unit: 'h'),
          icon: Icons.timer_outlined,
          tint: _blue,
        ),
        _MetricCard(
          metric: _model.periodMetric(
            'Average hike distance',
            'averageDistanceKm',
            ['hikeSessions'],
            unit: 'km',
          ),
          icon: Icons.straighten_rounded,
          tint: _purple,
        ),
        _MetricCard(
          metric: _model.periodMetric('Average hike duration', 'averageHours', [
            'hikeSessions',
          ], unit: 'h'),
          icon: Icons.schedule_rounded,
          tint: _orange,
        ),
      ],
    ),
    const SizedBox(height: 24),
    _DashboardNote(text: _model.measurementCoverageLabel),
    const SizedBox(height: 12),
    const AdminSectionHeading(
      title: 'Plans & team participation',
      subtitle: 'Current recorded state · all plans and team records',
    ),
    const SizedBox(height: 10),
    _ResponsiveGrid(
      children: [
        _bars(
          'Scheduled plan outcomes',
          'plans.byStatus',
          ['upcomingHikes', 'teamHikeSessions'],
          'plans',
          subtitle:
              'Expired after the 15-minute start window; started team plans are excluded.',
        ),
        _bars(
          'Team hike phases',
          'teams.byPhase',
          ['teamHikeSessions'],
          'teams',
          subtitle: 'One team session, regardless of participant count.',
        ),
        _bars(
          'Hike join requests',
          'joining.byStatus',
          ['upcomingHikeJoinRequests'],
          'requests',
          subtitle: 'Latest decision for each recorded request.',
        ),
        _bars(
          'Most hiked trails',
          'hikes.popularTrails',
          ['hikeSessions', 'trails'],
          'completed hiker sessions',
          subtitle:
              'All time · top eight · unlisted locations remain anonymous.',
        ),
      ],
    ),
    const SizedBox(height: 12),
    _DashboardNote(
      text:
          'Distinct hikers started at least one session in the selected period. Repeat hikers started at least two. Completion rate uses completed and abandoned sessions with recorded end dates; active sessions are excluded.',
    ),
  ];

  /// Distinguishes hazard resolution, SOS events and provider acknowledgement.
  List<Widget> _safety(AdminAnalyticsSnapshot snapshot) => [
    const AdminSectionHeading(
      title: 'Current trail safety',
      subtitle: 'Reported and resolving cautions at snapshot time',
    ),
    const SizedBox(height: 10),
    _ResponsiveGrid(
      compact: true,
      children: [
        _MetricCard(
          metric: _model.metric('Open cautions', 'safety.pendingHazards', [
            'hazardReports',
          ], 'Reported + resolving'),
          icon: Icons.shield_outlined,
          tint: _orange,
          onTap: widget.onSafety,
        ),
        _MetricCard(
          metric: _model.metric(
            'Serious open cautions',
            'safety.criticalOpen',
            ['hazardReports'],
            'Current serious-risk reports',
          ),
          icon: Icons.warning_amber_rounded,
          tint: _red,
          onTap: widget.onSafety,
        ),
        _MetricCard(
          metric: _model.metric(
            'Resolving reports',
            'safety.resolvingHazards',
            ['hazardReports'],
            'Awaiting three distinct hikers',
          ),
          icon: Icons.groups_outlined,
          tint: _blue,
          onTap: widget.onSafety,
        ),
        _MetricCard(
          metric: _model.metric(
            'Median time to resolution',
            'safety.medianResolutionHours',
            ['hazardReports'],
            'All time · recorded resolution timings',
            unit: 'h',
            requireComplete: true,
          ),
          icon: Icons.timelapse_rounded,
          tint: _green,
        ),
      ],
    ),
    const SizedBox(height: 18),
    _ResponsiveGrid(
      children: [
        _bars('Open caution types', 'safety.byOpenHazardType', [
          'hazardReports',
        ], 'current reports'),
        _bars(
          'Hazard lifecycle',
          'safety.byHazardLifecycle',
          ['hazardReports'],
          'reports',
          subtitle:
              'All retained reports · expired reports are included under Resolved.',
        ),
      ],
    ),
    const SizedBox(height: 24),
    const AdminSectionHeading(
      title: 'SOS & contact confirmations',
      subtitle: 'Selected period · test dispatches excluded',
    ),
    const SizedBox(height: 10),
    _ResponsiveGrid(
      compact: true,
      children: [
        _MetricCard(
          metric: _model.periodMetric('SOS alerts recorded', 'sosAlerts', [
            'sosAlerts',
          ]),
          icon: Icons.sos_rounded,
          tint: _red,
        ),
        _MetricCard(
          metric: _model.periodMetric('New hazard reports', 'hazards', [
            'hazardReports',
          ]),
          icon: Icons.report_outlined,
          tint: _orange,
        ),
        _MetricCard(
          metric: _model.periodMetric(
            'Contacts confirmed',
            'contactConfirmed',
            ['sosWhatsAppDispatches'],
          ),
          icon: Icons.mark_chat_read_outlined,
          tint: _green,
        ),
        _MetricCard(
          metric: _model.periodMetric(
            'Contact confirmation rate',
            'contactConfirmationRate',
            ['sosWhatsAppDispatches'],
            unit: '%',
            higherIsBetter: true,
          ),
          icon: Icons.verified_outlined,
          tint: _blue,
        ),
      ],
    ),
    const SizedBox(height: 18),
    _ResponsiveGrid(
      children: [
        _Bars(
          title: 'SOS contact outcomes',
          rows: snapshot.hasSources(['sosWhatsAppDispatches'])
              ? _model.periodContacts
              : const [],
          suffix: 'contacts',
          subtitle:
              'Latest known outcome for contacts dispatched in this period.',
          emptyLabel: _model.emptyLabel(['sosWhatsAppDispatches']),
          partial: _model.partial(['sosWhatsAppDispatches']),
        ),
        AdminPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminSectionHeading(title: 'How to read these results'),
              const SizedBox(height: 14),
              const _DefinitionLine(
                title: 'Confirmed',
                body:
                    'The provider acknowledged the dispatch. This does not confirm delivery to the contact, a reply or a rescue response.',
              ),
              const _DefinitionLine(
                title: 'Unconfirmed',
                body:
                    'No acknowledgement arrived within 15 seconds. Late confirmations can still update the result.',
              ),
              const _DefinitionLine(
                title: 'Failed',
                body:
                    'A known dispatch failure. Only eligible failed contacts can be retried.',
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: widget.onSafety,
                icon: const Icon(Icons.shield_outlined),
                label: const Text('Open trail Safety'),
              ),
            ],
          ),
        ),
      ],
    ),
    const SizedBox(height: 18),
    _ResponsiveGrid(
      compact: true,
      children: [
        _MetricCard(
          metric: _model.metric(
            'Unconfirmed contacts · 24h',
            'contacts.recentUnconfirmed',
            ['sosWhatsAppDispatches'],
            'Latest known outcomes · last 24 hours',
          ),
          icon: Icons.pending_outlined,
          tint: _orange,
        ),
        _MetricCard(
          metric: _model.metric(
            'Failed contacts · 24h',
            'contacts.recentFailed',
            ['sosWhatsAppDispatches'],
            'Known failures · last 24 hours',
          ),
          icon: Icons.error_outline_rounded,
          tint: _red,
        ),
        _MetricCard(
          metric: _model.metric(
            'Confirmed resolutions',
            'safety.confirmedResolutions',
            ['hazardReports'],
            'Three hikers confirmed · all time',
          ),
          icon: Icons.task_alt_rounded,
          tint: _green,
        ),
        _MetricCard(
          metric: _model.metric(
            'Expired reports',
            'safety.expiredHazards',
            ['hazardReports'],
            'Expired without confirmed resolution',
          ),
          icon: Icons.history_rounded,
          tint: _blue,
        ),
      ],
    ),
    const SizedBox(height: 12),
    const _DashboardNote(
      text:
          'Weather cautions expire after 24 hours for critical risks or 12 hours otherwise. Other trail reports keep their seven-day lifetime. Expiry is not proof that a condition is safe.',
    ),
  ];

  /// Analyses catalogue quality and coverage without exposing private hike locations.
  List<Widget> _trails(AdminAnalyticsSnapshot snapshot) => [
    const AdminSectionHeading(
      title: 'Trail catalogue quality',
      subtitle: 'Current catalogue · all records',
    ),
    const SizedBox(height: 10),
    _ResponsiveGrid(
      compact: true,
      children: [
        _MetricCard(
          metric: _model.metric(
            'Published trails',
            'totals.trails',
            ['trails'],
            'Current catalogue records',
            exactTotal: true,
          ),
          icon: Icons.terrain_outlined,
          tint: _green,
        ),
        _MetricCard(
          metric: _model.ratio(
            'Stored route coverage',
            'trails.routeStored',
            'trails.analysedCount',
            ['trails'],
            'Trails with stored route geometry',
          ),
          icon: Icons.route_outlined,
          tint: _blue,
        ),
        _MetricCard(
          metric: _model.metric(
            'Hiker rating average',
            'trails.averageRating',
            ['trails'],
            'Weighted by available rating records',
            requireComplete: true,
          ),
          icon: Icons.star_outline_rounded,
          tint: _orange,
        ),
        _MetricCard(
          metric: _model.ratio(
            'Fresh trailhead forecasts',
            'trails.freshForecasts',
            'trails.analysedCount',
            ['trails'],
            'Forecasts younger than three hours',
          ),
          icon: Icons.cloud_outlined,
          tint: _purple,
        ),
      ],
    ),
    const SizedBox(height: 18),
    _ResponsiveGrid(
      children: [
        _bars('Trails by state', 'trails.byState', ['trails'], 'trails'),
        _bars('Trail difficulty', 'trails.byDifficulty', ['trails'], 'trails'),
        _bars('Trail length', 'trails.byLength', ['trails'], 'trails'),
        AdminPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminSectionHeading(title: 'Catalogue completeness'),
              const SizedBox(height: 14),
              _ValueLine(
                metric: _model.metric(
                  'Missing map coordinates',
                  'trails.missingLocation',
                  ['trails'],
                  '',
                ),
              ),
              _ValueLine(
                metric: _model.metric(
                  'Missing trail distance',
                  'trails.missingDistance',
                  ['trails'],
                  '',
                ),
              ),
              _ValueLine(
                metric: _model.metric(
                  'Missing cover image',
                  'trails.missingCover',
                  ['trails'],
                  '',
                ),
              ),
              _ValueLine(
                metric: _model.metric(
                  'Offline maps available',
                  'trails.offlineAvailable',
                  ['trails'],
                  '',
                ),
              ),
              _ValueLine(
                metric: _model.metric(
                  'Verified trail records',
                  'trails.verified',
                  ['trails'],
                  '',
                ),
              ),
              _ValueLine(
                metric: _model.metric(
                  'Ratings recorded',
                  'trails.ratingCount',
                  ['trails'],
                  '',
                ),
              ),
            ],
          ),
        ),
      ],
    ),
    const SizedBox(height: 18),
    _ActionPanel(
      title: 'Trail submissions',
      detail: 'Review recorded trails before adding them to the catalogue.',
      metric: _model.metric(
        'Pending review',
        'feedback.pendingTrailRequests',
        ['trailRequests'],
        'Current submitted requests',
      ),
      icon: Icons.add_location_alt_outlined,
      onTap: widget.onTrailRequests ?? widget.onTools,
      action: 'Review trail submissions',
    ),
    const SizedBox(height: 12),
    const _DashboardNote(
      text:
          'A stale forecast normally refreshes when it is requested. It is not evidence of a provider outage. Stored route coverage uses saved geometry metadata, not whether a map was opened.',
    ),
  ];

  /// Shows account adoption and recognition alongside aggregate community engagement.
  List<Widget> _people(AdminAnalyticsSnapshot snapshot) => [
    const AdminSectionHeading(
      title: 'People & participation',
      subtitle: 'Accounts and recorded hiking engagement',
    ),
    const SizedBox(height: 10),
    _ResponsiveGrid(
      compact: true,
      children: [
        _MetricCard(
          metric: _model.periodMetric('New accounts', 'newUsers', [
            'users',
          ], higherIsBetter: true),
          icon: Icons.person_add_alt_1_outlined,
          tint: _blue,
        ),
        _MetricCard(
          metric: _model.metric(
            'Accounts that started a hike',
            'users.activated',
            ['users', 'hikeSessions'],
            'Current accounts · any recorded start',
          ),
          icon: Icons.hiking_rounded,
          tint: _green,
        ),
        _MetricCard(
          metric: _model.metric(
            'Hiking activation',
            'users.activationRate',
            ['users', 'hikeSessions'],
            'Current accounts with a recorded hike start',
            unit: '%',
          ),
          icon: Icons.insights_outlined,
          tint: _purple,
        ),
        _MetricCard(
          metric: _model.metric(
            'Recent sign-ins',
            'users.recentSignIns',
            ['users'],
            'Latest recorded sign-in within 30 days',
          ),
          icon: Icons.login_rounded,
          tint: _orange,
        ),
      ],
    ),
    const SizedBox(height: 18),
    _trendPanel(),
    const SizedBox(height: 18),
    _ResponsiveGrid(
      children: [
        _bars(
          'Account availability',
          'users.byStatus',
          ['users'],
          'accounts',
          subtitle:
              'Administrators remain part of the enabled or disabled account totals.',
        ),
        _Bars(
          title: 'Achievement definitions',
          rows: _model.definitionRows,
          suffix: 'definitions',
          emptyLabel: _model.emptyLabel(['achievements']),
          partial: _model.partial(['achievements']),
        ),
      ],
    ),
    const SizedBox(height: 24),
    const AdminSectionHeading(
      title: 'Rewards & recognition',
      subtitle: 'Unlocked awards and the rules currently stored',
    ),
    const SizedBox(height: 10),
    _ResponsiveGrid(
      compact: true,
      children: [
        _MetricCard(
          metric: _model.periodMetric('Awards unlocked', 'awards', [
            'userAchievements',
          ], higherIsBetter: true),
          icon: Icons.emoji_events_outlined,
          tint: _orange,
        ),
        _MetricCard(
          metric: _model.metric(
            'Hikers with awards',
            'rewards.recipients',
            ['userAchievements'],
            'Distinct award recipients · all time',
          ),
          icon: Icons.workspace_premium_outlined,
          tint: _purple,
        ),
        _MetricCard(
          metric: _model.metric(
            'Active achievement rules',
            'rewards.active',
            ['achievements'],
            'Currently available definitions',
          ),
          icon: Icons.rule_outlined,
          tint: _green,
        ),
        _MetricCard(
          metric: _model.metric(
            'Archived achievement rules',
            'rewards.inactive',
            ['achievements'],
            'Inactive definitions kept for reference',
          ),
          icon: Icons.archive_outlined,
          tint: _blue,
        ),
      ],
    ),
    const SizedBox(height: 18),
    _bars(
      'Hiking participation funnel',
      'users.hikingFunnel',
      ['users', 'hikeSessions'],
      'current accounts',
      subtitle:
          'Current accounts with a recorded start and completion; each account counts once.',
    ),
    const SizedBox(height: 18),
    _bars(
      'Most awarded achievements',
      'rewards.topAwards',
      ['userAchievements', 'achievements'],
      'unlocked awards',
      subtitle: 'All time · top eight · archived awards stay in history.',
    ),
    const SizedBox(height: 24),
    const AdminSectionHeading(
      title: 'Community engagement',
      subtitle: 'Aggregate current post records · no personal content',
    ),
    const SizedBox(height: 10),
    _ResponsiveGrid(
      compact: true,
      children: [
        _MetricCard(
          metric: _model.periodMetric('New community posts', 'posts', [
            'communityPosts',
          ]),
          icon: Icons.article_outlined,
          tint: _blue,
        ),
        _MetricCard(
          metric: _model.metric(
            'Recorded likes',
            'content.likes',
            ['communityPosts'],
            'Current stored post counters · all time',
          ),
          icon: Icons.favorite_border_rounded,
          tint: _purple,
        ),
        _MetricCard(
          metric: _model.metric(
            'Recorded comments',
            'content.comments',
            ['communityPosts'],
            'Current stored post counters · all time',
          ),
          icon: Icons.chat_bubble_outline_rounded,
          tint: _green,
        ),
        _MetricCard(
          metric: _model.metric(
            'Administrator accounts',
            'users.administrators',
            ['users'],
            'Current protected admin roles',
          ),
          icon: Icons.admin_panel_settings_outlined,
          tint: _orange,
        ),
      ],
    ),
    const SizedBox(height: 12),
    const _DashboardNote(
      text:
          'Recent sign-ins count the latest stored sign-in for each account, not app visits or a full login history. Archived achievements remain part of historical awards. Deleted records are not reconstructed.',
    ),
  ];

  /// Presents recorded delivery work and source coverage, not inferred infrastructure uptime.
  List<Widget> _operations(AdminAnalyticsSnapshot snapshot) => [
    const AdminSectionHeading(
      title: 'Notification operations',
      subtitle: 'Current job states · all retained notification records',
    ),
    const SizedBox(height: 10),
    _ResponsiveGrid(
      compact: true,
      children: [
        _MetricCard(
          metric: _model.metric(
            'Overdue notification jobs',
            'operations.notifications.overdue',
            ['fcmOutbox'],
            'Due jobs pending longer than five minutes',
          ),
          icon: Icons.pending_actions_rounded,
          tint: _orange,
        ),
        _MetricCard(
          metric: _model.metric(
            'Unconfirmed jobs',
            'operations.notifications.unconfirmed',
            ['fcmOutbox'],
            'Outbound result could not be confirmed',
          ),
          icon: Icons.help_outline_rounded,
          tint: _orange,
        ),
        _MetricCard(
          metric: _model.metric(
            'FCM device acceptance',
            'operations.notifications.deviceAcceptanceRate',
            ['fcmOutbox'],
            'Known accepted / accepted + rejected attempts',
            unit: '%',
          ),
          icon: Icons.notifications_active_outlined,
          tint: _green,
        ),
        _MetricCard(
          metric: _model.metric(
            'Median processing time',
            'operations.notifications.medianProcessingSeconds',
            ['fcmOutbox'],
            'Recorded creation-to-processing timings',
            unit: 's',
            requireComplete: true,
          ),
          icon: Icons.av_timer_rounded,
          tint: _blue,
        ),
      ],
    ),
    const SizedBox(height: 18),
    _ResponsiveGrid(
      children: [
        _bars(
          'Notification job outcomes',
          'operations.notifications.byStatus',
          ['fcmOutbox'],
          'jobs',
          subtitle:
              'Sent means accepted by FCM, not delivered to or read by a hiker.',
        ),
        _bars('Notification categories', 'operations.notifications.byType', [
          'fcmOutbox',
        ], 'jobs'),
      ],
    ),
    const SizedBox(height: 24),
    const AdminSectionHeading(
      title: 'Forecast cache & location sharing',
      subtitle: 'Latest stored state · three-hour forecast freshness',
    ),
    const SizedBox(height: 10),
    _ResponsiveGrid(
      compact: true,
      children: [
        _MetricCard(
          metric: _model.metric(
            'Fresh shared forecasts',
            'operations.weather.fresh',
            ['trailWeatherCache'],
            'Cache entries younger than three hours',
          ),
          icon: Icons.cloud_done_outlined,
          tint: _green,
        ),
        _MetricCard(
          metric: _model.metric(
            'Weather retry cooldowns',
            'operations.weather.retryCooldown',
            ['trailWeatherCache'],
            'Current provider retry cooldowns',
          ),
          icon: Icons.cloud_sync_outlined,
          tint: _orange,
        ),
        _MetricCard(
          metric: _model.metric(
            'Fresh checkpoint forecasts',
            'operations.checkpointForecasts.fresh',
            ['checkpointWeather'],
            'Shared saved checkpoint forecasts',
          ),
          icon: Icons.location_on_outlined,
          tint: _blue,
        ),
        _MetricCard(
          metric: _model.metric(
            'Active location shares',
            'operations.activeShares',
            ['live_location_shares'],
            'Enabled shares that have not expired',
          ),
          icon: Icons.share_location_rounded,
          tint: _purple,
        ),
      ],
    ),
    const SizedBox(height: 18),
    _ResponsiveGrid(
      children: [
        _bars(
          'Shared forecast freshness',
          'operations.weather.byFreshness',
          ['trailWeatherCache'],
          'cache entries',
          subtitle:
              'Stale entries refresh on demand; this is not an uptime monitor.',
        ),
        _bars(
          'Checkpoint forecast freshness',
          'operations.checkpointForecasts.byFreshness',
          ['checkpointWeather'],
          'checkpoint forecasts',
        ),
      ],
    ),
    const SizedBox(height: 24),
    const AdminSectionHeading(
      title: 'Administrative workload',
      subtitle: 'Current queues that need follow-up',
    ),
    const SizedBox(height: 10),
    _ResponsiveGrid(
      children: [
        _ActionPanel(
          title: 'Hiker feedback',
          detail: 'Follow up on unresolved feedback and support requests.',
          metric: _model.metric('Open feedback', 'feedback.open', [
            'appFeedback',
          ], ''),
          icon: Icons.feedback_outlined,
          onTap: widget.onFeedback ?? widget.onTools,
          action: 'Open feedback inbox',
        ),
        _ActionPanel(
          title: 'Trail submissions',
          detail: 'Review recorded trails awaiting publication.',
          metric: _model.metric(
            'Pending review',
            'feedback.pendingTrailRequests',
            ['trailRequests'],
            '',
          ),
          icon: Icons.add_location_alt_outlined,
          onTap: widget.onTrailRequests ?? widget.onTools,
          action: 'Review trail submissions',
        ),
      ],
    ),
    const SizedBox(height: 24),
    _ResponsiveGrid(
      children: [
        _bars('Feedback outcomes', 'feedback.byStatus', [
          'appFeedback',
        ], 'reports'),
        _bars('Feedback categories', 'feedback.byCategory', [
          'appFeedback',
        ], 'reports'),
      ],
    ),
    const SizedBox(height: 24),
    const AdminSectionHeading(
      title: 'Analysis coverage',
      subtitle: 'What this snapshot can reliably describe',
    ),
    const SizedBox(height: 10),
    _CoveragePanel(
      snapshot: snapshot,
      onRefresh: widget.loading ? null : widget.onRetry,
    ),
    const SizedBox(height: 18),
    _Bars(
      title: 'Activity date exclusions',
      rows: _model.dateIssues,
      suffix: 'events',
      subtitle:
          'Missing dates or event times after this snapshot are excluded from period metrics.',
      emptyLabel: snapshot.hasExpandedAnalysis
          ? 'No date exclusions in the analysed activity.'
          : 'Date quality analysis is unavailable.',
    ),
    const SizedBox(height: 12),
    const _DashboardNote(
      text:
          'These figures describe stored application work. They do not measure server uptime, app crashes, network availability, message reads or rescue response. Sources are collected independently; the snapshot is not an atomic live view.',
    ),
  ];

  /// Plots only valid buckets for the selected source and reporting period.
  Widget _trendPanel() => AdminPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminSectionHeading(title: 'Activity trend'),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          key: ValueKey('dashboard-trend-${_model.trendMetric}'),
          initialValue: _model.trendMetric,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Measure',
            prefixIcon: Icon(Icons.show_chart_rounded),
            border: OutlineInputBorder(),
          ),
          items: [
            for (final entry in AdminDashboardViewModel.trendLabels.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (value) {
            if (value != null) _model.selectTrend(value);
          },
        ),
        const SizedBox(height: 18),
        _Timeline(
          rows: _model.trendRows,
          metric: _model.trendMetric,
          color: _model.trendMetric == 'sosAlerts' ? _red : _green,
          emptyLabel: _model.emptyLabel([
            AdminDashboardViewModel.trendSources[_model.trendMetric]!,
          ]),
        ),
        const SizedBox(height: 8),
        Text(
          '${_model.trendLabel} · ${_model.periodHint}',
          style: TextStyle(fontSize: 11, color: AdminUi.muted(context)),
        ),
        const SizedBox(height: 6),
        Text(
          'Tap a point to inspect its value. Missing and future-dated events are excluded.',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: AdminUi.muted(context),
          ),
        ),
      ],
    ),
  );

  /// Routes each finding to the relevant analysis or management destination.
  Widget _attention(AdminAnalyticsSnapshot snapshot) => AdminPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminSectionHeading(
          title: 'Needs attention',
          subtitle: 'Recorded findings at snapshot time',
        ),
        const SizedBox(height: 8),
        if (snapshot.rows('attention').isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              snapshot.incompleteCount > 0
                  ? 'No findings in the available sources. Review incomplete coverage in Operations.'
                  : 'No outstanding findings in the monitored queues.',
              style: TextStyle(color: AdminUi.muted(context), height: 1.5),
            ),
          ),
        for (final issue in snapshot.rows('attention'))
          _AttentionRow(
            issue: issue,
            onTap: () {
              final key = '${issue['key']}';
              if (key.startsWith('sos-')) {
                _model.selectArea(AdminDashboardArea.safety);
              } else if (key == 'critical-hazards') {
                widget.onSafety();
              } else if (key == 'trail-requests') {
                (widget.onTrailRequests ?? widget.onTools)();
              } else if (key == 'feedback') {
                (widget.onFeedback ?? widget.onTools)();
              } else {
                _model.selectArea(AdminDashboardArea.operations);
              }
            },
          ),
      ],
    ),
  );

  /// Adds a source-aware empty state to standard ranked bar panels.
  Widget _bars(
    String title,
    String path,
    List<String> sources,
    String suffix, {
    String? subtitle,
  }) => _Bars(
    title: title,
    rows: _model.rows(path, sources),
    suffix: suffix,
    subtitle: subtitle,
    emptyLabel: _model.emptyLabel(sources),
    partial: _model.partial(sources),
  );
}

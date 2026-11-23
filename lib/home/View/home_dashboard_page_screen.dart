part of '../home_dashboard_page_feature.dart';

/// Displays the home dashboard page.
class HomeDashboardPage extends StatelessWidget {
  /// Creates home dashboard page.
  const HomeDashboardPage({
    super.key,
    required this.phoneNumber,
    this.myUpcomingHikes = const [],
    required this.plannedHike,
    required this.trails,
    required this.isLoadingTrails,
    required this.activeHike,
    required this.isVisible,
    required this.onStartHike,
    required this.onFindHike,
    required this.onOpenTrailDetail,
    this.onTapUpcomingHike,
    this.onDeleteUpcomingHike,
    this.onAddTrailByAdmin,
    this.onReviewTrailRequestsByAdmin,
    this.onEditTrailByAdmin,
    this.onDeleteTrailByAdmin,
    required this.onActiveHikeChanged,
    this.onPlannedHikeChanged,
    required this.onCheckInRequested,
    required this.onPingTeamMember,
    required this.onEndHike,
    required this.fallStillnessSnapshot,
    required this.onCancelFallStillnessSos,
  });

  final String phoneNumber;
  final List<UpcomingHike> myUpcomingHikes;
  final PlannedHike? plannedHike;
  final List<Trail> trails;
  final bool isLoadingTrails;
  final ActiveHikeSession? activeHike;
  final bool isVisible;
  final Future<void> Function(Trail? trail) onStartHike;
  final VoidCallback onFindHike;
  final ValueChanged<Trail> onOpenTrailDetail;
  final Future<void> Function(UpcomingHike)? onTapUpcomingHike;
  final Future<void> Function(UpcomingHike)? onDeleteUpcomingHike;
  final VoidCallback? onAddTrailByAdmin;
  final VoidCallback? onReviewTrailRequestsByAdmin;
  final Future<void> Function(Trail trail)? onEditTrailByAdmin;
  final Future<void> Function(Trail trail)? onDeleteTrailByAdmin;
  final ValueChanged<ActiveHikeSession> onActiveHikeChanged;
  final Future<void> Function(PlannedHike)? onPlannedHikeChanged;
  final Future<ActiveHikeSession> Function(ActiveHikeSession activeHike)
  onCheckInRequested;
  final Future<TeamHikeSession?> Function(String phoneNumber) onPingTeamMember;
  final VoidCallback onEndHike;
  final FallStillnessMonitorSnapshot fallStillnessSnapshot;
  final VoidCallback onCancelFallStillnessSos;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final active = activeHike;
    final planned = plannedHike;

    return ColoredBox(
      color: _HomeColors.backgroundFor(context),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 112),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: active == null
                  ? planned == null
                        ? _TrailDiscoveryDashboard(
                            myUpcomingHikes: myUpcomingHikes,
                            isVisible: isVisible,
                            phoneNumber: phoneNumber,
                            trails: trails,
                            isLoadingTrails: isLoadingTrails,
                            onStartHike: () =>
                                unawaited(_startHikeFromDashboard(context)),
                            onFindHike: onFindHike,
                            onOpenTrailDetail: onOpenTrailDetail,
                            onTapUpcomingHike: onTapUpcomingHike,
                            onDeleteUpcomingHike: onDeleteUpcomingHike,
                            onAddTrailByAdmin: onAddTrailByAdmin,
                            onReviewTrailRequestsByAdmin:
                                onReviewTrailRequestsByAdmin,
                            onEditTrailByAdmin: onEditTrailByAdmin,
                            onDeleteTrailByAdmin: onDeleteTrailByAdmin,
                          )
                        : _PreparationDashboard(
                            myUpcomingHikes: myUpcomingHikes,
                            isVisible: isVisible,
                            phoneNumber: phoneNumber,
                            plannedHike: planned,
                            trails: trails,
                            isLoadingTrails: isLoadingTrails,
                            // Creating a new hike must never inherit or start
                            // the next scheduled hike shown below. Scheduled
                            // hikes have their own preparation/details flow.
                            onStartHike: () =>
                                unawaited(_startHikeFromDashboard(context)),
                            onFindHike: onFindHike,
                            onOpenTrailDetail: onOpenTrailDetail,
                            onTapUpcomingHike: onTapUpcomingHike,
                            onDeleteUpcomingHike: onDeleteUpcomingHike,
                            onAddTrailByAdmin: onAddTrailByAdmin,
                            onReviewTrailRequestsByAdmin:
                                onReviewTrailRequestsByAdmin,
                            onEditTrailByAdmin: onEditTrailByAdmin,
                            onDeleteTrailByAdmin: onDeleteTrailByAdmin,
                          )
                  : _ActiveHikeDashboard(
                      currentPhoneNumber: phoneNumber,
                      activeHike: active,
                      isVisible: isVisible,
                      fallStillnessSnapshot: fallStillnessSnapshot,
                      onCheckIn: () => unawaited(_checkIn(context, active)),
                      onPingTeamMember: onPingTeamMember,
                      onEndHike: () => unawaited(_confirmEndHike(context)),
                      onCancelFallStillnessSos: onCancelFallStillnessSos,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// Starts hike from dashboard.
  Future<void> _startHikeFromDashboard(BuildContext context) async {
    await _requestStartHike(context, null);
  }

  /// Computes request start hike.
  Future<void> _requestStartHike(BuildContext context, Trail? trail) async {
    try {
      await onStartHike(trail);
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to start this hike right now.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  /// Checks in.
  Future<void> _checkIn(BuildContext context, ActiveHikeSession active) async {
    try {
      final updatedHike = await onCheckInRequested(active);
      onActiveHikeChanged(updatedHike);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Check-in saved locally and queued for sync.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to save a check-in right now.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  /// Confirm the end-hike action before delegating final persistence to the owning home page.
  Future<void> _confirmEndHike(BuildContext context) async {
    final shouldEnd = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('End hike session?'),
          content: const Text(
            'Your local trail points and queued updates will remain on this phone for sync.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('End Hike'),
            ),
          ],
        );
      },
    );

    if (shouldEnd == true && context.mounted) {
      onEndHike();
    }
  }
}

/// Displays the preparation dashboard.
class _PreparationDashboard extends StatelessWidget {
  /// Creates preparation dashboard.
  const _PreparationDashboard({
    this.myUpcomingHikes = const [],
    required this.isVisible,
    required this.phoneNumber,
    required this.plannedHike,
    required this.trails,
    required this.isLoadingTrails,
    required this.onStartHike,
    required this.onFindHike,
    required this.onOpenTrailDetail,
    this.onTapUpcomingHike,
    this.onDeleteUpcomingHike,
    this.onAddTrailByAdmin,
    this.onReviewTrailRequestsByAdmin,
    this.onEditTrailByAdmin,
    this.onDeleteTrailByAdmin,
  });

  final List<UpcomingHike> myUpcomingHikes;
  final bool isVisible;
  final String phoneNumber;
  final PlannedHike plannedHike;
  final List<Trail> trails;
  final bool isLoadingTrails;
  final VoidCallback onStartHike;
  final VoidCallback onFindHike;
  final ValueChanged<Trail> onOpenTrailDetail;
  final Future<void> Function(UpcomingHike)? onTapUpcomingHike;
  final Future<void> Function(UpcomingHike)? onDeleteUpcomingHike;
  final VoidCallback? onAddTrailByAdmin;
  final VoidCallback? onReviewTrailRequestsByAdmin;
  final Future<void> Function(Trail trail)? onEditTrailByAdmin;
  final Future<void> Function(Trail trail)? onDeleteTrailByAdmin;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final hazards = plannedHike.trail.hazards;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _HomeDashboardHeader(
          title: 'Home',
          subtitle: 'Your hikes, preparation and trail discoveries.',
        ),
        const SizedBox(height: 16),
        _StartHikeActions(onStartHike: onStartHike, onFindHike: onFindHike),
        if (myUpcomingHikes.isNotEmpty) ...[
          const SizedBox(height: 22),
          _MyUpcomingHikesSection(
            hikes: myUpcomingHikes,
            trails: trails,
            plannedHike: plannedHike,
            isVisible: isVisible,
            phoneNumber: phoneNumber,
            onTapHike: onTapUpcomingHike,
            onDeleteHike: onDeleteUpcomingHike,
          ),
        ],
        const SizedBox(height: 22),
        _BestMatchesSection(
          trails: trails,
          isLoading: isLoadingTrails,
          onOpenTrail: onOpenTrailDetail,
          onAddTrailByAdmin: onAddTrailByAdmin,
          onReviewTrailRequestsByAdmin: onReviewTrailRequestsByAdmin,
          onEditTrailByAdmin: onEditTrailByAdmin,
          onDeleteTrailByAdmin: onDeleteTrailByAdmin,
        ),
        if (myUpcomingHikes.isEmpty &&
            plannedHike.missingPreparationItems.isNotEmpty) ...[
          const SizedBox(height: 14),
          _PreparationWarning(
            plannedHike: plannedHike,
            missingItems: plannedHike.missingPreparationItems,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) =>
                    _PreparationReminderPage(plannedHike: plannedHike),
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        SectionLabel(label: 'Recent Hazards on This Trail'),
        const SizedBox(height: 8),
        if (hazards.isEmpty)
          const _EmptyState(
            message: 'No recent hazards reported for this trail.',
          )
        else
          for (final hazard in hazards) ...[
            _HazardRow(
              trail: plannedHike.trail,
              hazard: hazard,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => _HazardDetailPage(
                    trail: plannedHike.trail,
                    hazard: hazard,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

/// Displays the trail discovery dashboard.
class _TrailDiscoveryDashboard extends StatelessWidget {
  /// Creates trail discovery dashboard.
  const _TrailDiscoveryDashboard({
    this.myUpcomingHikes = const [],
    required this.isVisible,
    required this.phoneNumber,
    required this.trails,
    required this.isLoadingTrails,
    required this.onStartHike,
    required this.onFindHike,
    required this.onOpenTrailDetail,
    this.onTapUpcomingHike,
    this.onDeleteUpcomingHike,
    this.onAddTrailByAdmin,
    this.onReviewTrailRequestsByAdmin,
    this.onEditTrailByAdmin,
    this.onDeleteTrailByAdmin,
  });

  final List<UpcomingHike> myUpcomingHikes;
  final bool isVisible;
  final String phoneNumber;
  final List<Trail> trails;
  final bool isLoadingTrails;
  final VoidCallback onStartHike;
  final VoidCallback onFindHike;
  final ValueChanged<Trail> onOpenTrailDetail;
  final Future<void> Function(UpcomingHike)? onTapUpcomingHike;
  final Future<void> Function(UpcomingHike)? onDeleteUpcomingHike;
  final VoidCallback? onAddTrailByAdmin;
  final VoidCallback? onReviewTrailRequestsByAdmin;
  final Future<void> Function(Trail trail)? onEditTrailByAdmin;
  final Future<void> Function(Trail trail)? onDeleteTrailByAdmin;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _HomeDashboardHeader(
          title: 'Home',
          subtitle: 'Find a trail and plan your next adventure.',
        ),
        const SizedBox(height: 16),
        _StartHikeActions(onStartHike: onStartHike, onFindHike: onFindHike),
        if (myUpcomingHikes.isNotEmpty) ...[
          const SizedBox(height: 22),
          _MyUpcomingHikesSection(
            hikes: myUpcomingHikes,
            trails: trails,
            isVisible: isVisible,
            phoneNumber: phoneNumber,
            onTapHike: onTapUpcomingHike,
            onDeleteHike: onDeleteUpcomingHike,
          ),
        ],
        const SizedBox(height: 22),
        _BestMatchesSection(
          trails: trails,
          isLoading: isLoadingTrails,
          onOpenTrail: onOpenTrailDetail,
          onAddTrailByAdmin: onAddTrailByAdmin,
          onReviewTrailRequestsByAdmin: onReviewTrailRequestsByAdmin,
          onEditTrailByAdmin: onEditTrailByAdmin,
          onDeleteTrailByAdmin: onDeleteTrailByAdmin,
        ),
      ],
    );
  }
}

/// Defines the trail filter mode choices.
enum _TrailFilterMode { all, nearest, state }

/// Displays the home swipe action background.
class _HomeSwipeActionBackground extends StatelessWidget {
  /// Creates home swipe action background.
  const _HomeSwipeActionBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final isLeft = alignment == Alignment.centerLeft;

    return Container(
      color: color,
      alignment: alignment,
      padding: EdgeInsets.only(left: isLeft ? 18 : 0, right: isLeft ? 0 : 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: isLeft
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the best match trail cover.
class _BestMatchTrailCover extends StatelessWidget {
  /// Creates best match trail cover.
  const _BestMatchTrailCover({required this.trail, this.expanded = false});

  final Trail trail;
  final bool expanded;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final fallbackColor = Color(trail.coverColorValue);
    final url = trail.coverImageUrls.isNotEmpty
        ? trail.coverImageUrls.first
        : '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: expanded ? double.infinity : 96,
        height: expanded ? null : 96,
        child: url.trim().isEmpty
            ? _TrailCoverFallback(color: fallbackColor)
            : CachedTrailImage(
                imageUrl: url,
                fit: BoxFit.cover,
                width: expanded ? null : 96,
                height: expanded ? null : 96,
                semanticLabel: '${trail.name} trail cover',
                loadingBuilder: (context) => Stack(
                  fit: StackFit.expand,
                  children: [
                    _TrailCoverFallback(color: fallbackColor),
                    const Center(
                      child: HikerCircleMinorLoadingIndicator(size: 28),
                    ),
                  ],
                ),
                fallbackBuilder: (context) =>
                    _TrailCoverFallback(color: fallbackColor),
              ),
      ),
    );
  }
}

/// Displays the trail cover fallback.
class _TrailCoverFallback extends StatelessWidget {
  /// Creates trail cover fallback.
  const _TrailCoverFallback({required this.color});

  final Color color;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, Color.lerp(color, Colors.black, 0.25)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.landscape_rounded, color: Colors.white, size: 32),
      ),
    );
  }
}

/// Displays the best matches loading.
class _BestMatchesLoading extends StatelessWidget {
  /// Creates best matches loading.
  const _BestMatchesLoading();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return const _InsetGroup(
      child: HikerCircleLoadingView(
        message: 'Loading recommended trails…',
        detail: 'Finding routes that match your hike plans.',
        compact: true,
        padding: EdgeInsets.all(14),
      ),
    );
  }
}

/// Displays the start hike actions.
class _StartHikeActions extends StatelessWidget {
  /// Creates start hike actions.
  const _StartHikeActions({
    required this.onStartHike,
    required this.onFindHike,
  });

  final VoidCallback onStartHike;
  final VoidCallback onFindHike;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onStartHike,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Create Hike'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onFindHike,
            icon: const Icon(Icons.explore_rounded),
            label: const Text('Find a Hike'),
          ),
        ),
      ],
    );
  }
}

/// Displays the preparation warning.
class _PreparationWarning extends StatelessWidget {
  /// Creates preparation warning.
  const _PreparationWarning({
    required this.plannedHike,
    required this.missingItems,
    required this.onTap,
  });

  final PlannedHike plannedHike;
  final List<String> missingItems;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Glyph(
                  icon: Icons.warning_amber_rounded,
                  color: _HomeColors.orange,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Preparation reminder',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: _HomeColors.textFor(context),
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                            ),
                          ),
                          _StatusPill(
                            label: '${plannedHike.preparationPercent}%',
                            color: _HomeColors.orange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${missingItems.length} item${missingItems.length == 1 ? '' : 's'} need attention before ${plannedHike.trail.name}. Tap to review the full prep list.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _HomeColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: plannedHike.preparationPercent / 100,
                          minHeight: 5,
                          color: _HomeColors.orange,
                          backgroundColor: _HomeColors.orange.withValues(
                            alpha: 0.18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  CupertinoIcons.chevron_forward,
                  color: _HomeColors.secondaryTextFor(context),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the preparation reminder page.
class _PreparationReminderPage extends StatelessWidget {
  /// Creates preparation reminder page.
  const _PreparationReminderPage({required this.plannedHike});

  final PlannedHike plannedHike;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final missingItems = plannedHike.missingPreparationItems;
    final readyItems = [
      if (plannedHike.weatherCached) 'Weather forecast cached',
      if (plannedHike.emergencyContactsSelected) 'SOS contact list ready',
      if (plannedHike.hasKnownBatteryLevel &&
          plannedHike.phoneBatteryLevel >= 60)
        'Battery above 60%',
      if (plannedHike.liveLocationConfigured) 'Live sharing configured',
    ];

    return Scaffold(
      backgroundColor: _HomeColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(
                    title: 'Preparation',
                    subtitle: plannedHike.trail.name,
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const _Glyph(icon: Icons.task_alt_rounded),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Gear checklist ${plannedHike.checklistCompleted}/${plannedHike.checklistTotal}',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        color: _HomeColors.textFor(context),
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0,
                                      ),
                                ),
                              ),
                              _StatusPill(
                                label: '${missingItems.length} todo',
                                color: missingItems.isEmpty
                                    ? _HomeColors.green
                                    : _HomeColors.orange,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: plannedHike.preparationPercent / 100,
                              minHeight: 8,
                              color: _HomeColors.green,
                              backgroundColor: _HomeColors.green.withValues(
                                alpha: 0.14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _InfoLine(
                            label: 'Departure',
                            value:
                                '${_formatDate(plannedHike.plannedStartTime)} | ${_formatTime(plannedHike.plannedStartTime)}',
                          ),
                          _InfoLine(
                            label: 'Estimated return',
                            value: _formatTime(plannedHike.expectedReturnTime),
                          ),
                          _InfoLine(
                            label: 'Phone battery',
                            value: plannedHike.hasKnownBatteryLevel
                                ? '${plannedHike.phoneBatteryLevel}%'
                                : 'Unavailable',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SectionLabel(label: 'Needs Attention'),
                  const SizedBox(height: 8),
                  if (missingItems.isEmpty)
                    const _EmptyState(
                      message: 'No outstanding preparation items.',
                    )
                  else
                    for (final item in missingItems) ...[
                      _ChecklistInsightRow(
                        icon: Icons.error_outline_rounded,
                        color: _HomeColors.orange,
                        title: item,
                        subtitle: _preparationAdvice(item),
                      ),
                      const SizedBox(height: 8),
                    ],
                  const SizedBox(height: 14),
                  SectionLabel(label: 'Already Ready'),
                  const SizedBox(height: 8),
                  if (readyItems.isEmpty)
                    const _EmptyState(message: 'No ready items yet.')
                  else
                    for (final item in readyItems) ...[
                      _ChecklistInsightRow(
                        icon: Icons.check_circle_rounded,
                        color: _HomeColors.green,
                        title: item,
                        subtitle: 'This will be included in your hike plan.',
                      ),
                      const SizedBox(height: 8),
                    ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the hazard detail page.
class _HazardDetailPage extends StatelessWidget {
  /// Creates hazard detail page.
  const _HazardDetailPage({required this.trail, required this.hazard});

  final Trail trail;
  final TrailHazard hazard;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final severityColor = _severityColor(hazard.severity);

    return Scaffold(
      backgroundColor: _HomeColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(
                    title: 'Hazard Detail',
                    subtitle: trail.name,
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _Glyph(
                                icon: Icons.report_problem_rounded,
                                color: severityColor,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  hazard.type,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        color: _HomeColors.textFor(context),
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0,
                                      ),
                                ),
                              ),
                              _StatusPill(
                                label: hazard.severity,
                                color: severityColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            hazard.description,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: _HomeColors.textFor(context),
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 14),
                          _InfoLine(
                            label: 'Location',
                            value: hazard.locationLabel,
                          ),
                          _InfoLine(
                            label: 'Reported',
                            value:
                                '${_formatDate(hazard.reportedAt)} | ${_formatTime(hazard.reportedAt)}',
                          ),
                          _InfoLine(
                            label: 'Trail',
                            value: [
                              trail.distanceLabel,
                              if (trail.hasCommunityDifficulty)
                                trail.difficulty,
                            ].join(' - '),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SectionLabel(label: 'Recommended Action'),
                  const SizedBox(height: 8),
                  _ChecklistInsightRow(
                    icon: Icons.route_rounded,
                    color: _HomeColors.blue,
                    title: 'Plan a slower segment',
                    subtitle:
                        'Expect slower movement around ${hazard.locationLabel}. Keep the group together and avoid rushing through the affected section.',
                  ),
                  const SizedBox(height: 8),
                  _ChecklistInsightRow(
                    icon: Icons.update_rounded,
                    color: _HomeColors.green,
                    title: 'Re-check before departure',
                    subtitle:
                        'Refresh the trail detail before departure to review the latest hazard reports and route notes.',
                  ),
                  const SizedBox(height: 8),
                  _ChecklistInsightRow(
                    icon: Icons.warning_amber_rounded,
                    color: _HomeColors.orange,
                    title: 'Escalate if conditions worsen',
                    subtitle:
                        'Use SOS only for urgent danger or injury. For non-urgent trail notes, report the hazard from the trail detail page.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the active hike dashboard.
class _ActiveHikeDashboard extends StatelessWidget {
  /// Creates active hike dashboard.
  const _ActiveHikeDashboard({
    required this.activeHike,
    required this.currentPhoneNumber,
    required this.isVisible,
    required this.fallStillnessSnapshot,
    required this.onCheckIn,
    required this.onPingTeamMember,
    required this.onEndHike,
    required this.onCancelFallStillnessSos,
  });

  final ActiveHikeSession activeHike;
  final String currentPhoneNumber;
  final bool isVisible;
  final FallStillnessMonitorSnapshot fallStillnessSnapshot;
  final VoidCallback onCheckIn;
  final Future<TeamHikeSession?> Function(String phoneNumber) onPingTeamMember;
  final VoidCallback onEndHike;
  final VoidCallback onCancelFallStillnessSos;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActiveHeader(activeHike: activeHike),
        const SizedBox(height: 16),
        _ActiveMetrics(
          startedAt: activeHike.startedAt,
          isVisible: isVisible,
          expectedReturn: activeHike.draft.expectedReturnTime,
          batteryLevel: activeHike.batteryLevel,
          batteryLevelKnown: activeHike.hasKnownBatteryLevel,
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: onEndHike,
          icon: const Icon(Icons.stop_circle_rounded),
          label: const Text('End Hike Session'),
        ),
        const SizedBox(height: 14),
        _ConnectionStatusCard(queuedUpdates: activeHike.queuedUpdates),
        const SizedBox(height: 14),
        _MiniMapCard(
          activeHike: activeHike,
          currentPhoneNumber: currentPhoneNumber,
        ),
        const SizedBox(height: 14),
        const SizedBox(height: 22),
        SectionLabel(label: 'Safety Monitoring'),
        const SizedBox(height: 8),
        _MonitoringCard(
          activeHike: activeHike,
          fallStillnessSnapshot: fallStillnessSnapshot,
          onCancelFallStillnessSos: onCancelFallStillnessSos,
        ),
        const SizedBox(height: 22),
        SectionLabel(label: 'Shared With'),
        const SizedBox(height: 8),
        _SharedWithCard(activeHike: activeHike),
        const SizedBox(height: 22),
        SectionLabel(label: 'Team Snapshot'),
        const SizedBox(height: 8),
        _TeamSnapshotCard(
          activeHike: activeHike,
          currentPhoneNumber: currentPhoneNumber,
          onPingTeamMember: onPingTeamMember,
        ),
      ],
    );
  }
}

/// Displays the active metrics.
class _ActiveMetrics extends StatelessWidget {
  /// Creates active metrics.
  const _ActiveMetrics({
    required this.startedAt,
    required this.isVisible,
    required this.expectedReturn,
    required this.batteryLevel,
    required this.batteryLevelKnown,
  });

  final DateTime startedAt;
  final bool isVisible;
  final DateTime expectedReturn;
  final int batteryLevel;
  final bool batteryLevelKnown;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 74),
        child: IntrinsicHeight(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: _ElapsedMetricCell(
                    startedAt: startedAt,
                    isVisible: isVisible,
                  ),
                ),
                const _VerticalSeparator(),
                Expanded(
                  child: _MetricCell(
                    label: 'Estimated Return',
                    value: _formatTime(expectedReturn),
                  ),
                ),
                const _VerticalSeparator(),
                Expanded(
                  child: _MetricCell(
                    label: 'Battery',
                    value: batteryLevelKnown ? '$batteryLevel%' : 'Unknown',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the metric cell.
class _MetricCell extends StatelessWidget {
  /// Creates metric cell.
  const _MetricCell({required this.label, required this.value});

  final String label;
  final String value;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: _HomeColors.textFor(context),
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: _HomeColors.secondaryTextFor(context),
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

/// Displays the elapsed metric cell.
class _ElapsedMetricCell extends StatefulWidget {
  /// Creates elapsed metric cell.
  const _ElapsedMetricCell({required this.startedAt, required this.isVisible});

  final DateTime startedAt;
  final bool isVisible;

  /// Creates the presentation state for this widget.
  @override
  State<_ElapsedMetricCell> createState() => _ElapsedMetricCellState();
}

/// Manages the elapsed metric cell presentation and lifecycle.
class _ElapsedMetricCellState extends State<_ElapsedMetricCell>
    with WidgetsBindingObserver {
  Timer? _timer;
  AppLifecycleState _lifecycleState =
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;

  /// Returns should tick.
  bool get _shouldTick {
    return widget.isVisible && _lifecycleState == AppLifecycleState.resumed;
  }

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncTimer();
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant _ElapsedMetricCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible != widget.isVisible ||
        oldWidget.startedAt != widget.startedAt) {
      _syncTimer();
      if (mounted) {
        setState(() {});
      }
    }
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncTimer();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  /// Synchronizes timer.
  void _syncTimer() {
    if (!_shouldTick) {
      _timer?.cancel();
      _timer = null;
      return;
    }

    if (_timer?.isActive == true) {
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _MetricCell(
      label: 'Elapsed Time',
      value: _formatElapsed(DateTime.now().difference(widget.startedAt)),
    );
  }
}

/// Displays the info line.
class _InfoLine extends StatelessWidget {
  /// Creates info line.
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _HomeColors.secondaryTextFor(context),
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _HomeColors.textFor(context),
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the glyph.
class _Glyph extends StatelessWidget {
  /// Creates glyph.
  const _Glyph({required this.icon, this.color = _HomeColors.green});

  final IconData icon;
  final Color color;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

/// Displays the inset group.
class _InsetGroup extends StatelessWidget {
  /// Creates inset group.
  const _InsetGroup({required this.child});

  final Widget child;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _HomeColors.surfaceFor(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }
}

/// Displays the horizontal separator.
class _HorizontalSeparator extends StatelessWidget {
  /// Creates horizontal separator.
  const _HorizontalSeparator();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.7,
      color: _HomeColors.separatorFor(context),
    );
  }
}

/// Displays the vertical separator.
class _VerticalSeparator extends StatelessWidget {
  /// Creates vertical separator.
  const _VerticalSeparator();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: VerticalDivider(
        width: 1,
        thickness: 0.7,
        color: _HomeColors.separatorFor(context),
      ),
    );
  }
}

/// Formats date.
String _formatDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

/// Formats time.
String _formatTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

/// Formats elapsed.
String _formatElapsed(Duration elapsed) {
  final hours = elapsed.inHours.toString().padLeft(2, '0');
  final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

/// Formats relative date.
String _formatRelativeDate(DateTime dateTime) {
  final now = DateTime.now();
  final difference = now.difference(dateTime.toLocal());
  if (difference.inDays <= 0) {
    return 'today';
  }
  if (difference.inDays == 1) {
    return 'yesterday';
  }
  return '${difference.inDays} days ago';
}

/// Computes same phone number.
bool _samePhoneNumber(String first, String second) {
  final firstKey = first.replaceAll(RegExp(r'[^0-9]'), '');
  final secondKey = second.replaceAll(RegExp(r'[^0-9]'), '');
  return firstKey.isNotEmpty && firstKey == secondKey;
}

/// Computes preparation advice.
String _preparationAdvice(String item) {
  if (item.contains('map')) {
    return 'Open the trail detail later and cache the route before leaving coverage.';
  }
  if (item.contains('Weather')) {
    return 'Refresh the forecast and agree on a turn-back point before departure.';
  }
  if (item.contains('contact')) {
    return 'Use SOS settings to choose who receives alerts during the hike.';
  }
  if (item.contains('battery')) {
    return 'Charge above 60% and bring a power bank for tracking and SOS.';
  }
  if (item.contains('checklist')) {
    return 'Review water, light, rain cover, and first-aid items before starting.';
  }
  if (item.contains('Live location')) {
    return 'Choose who can follow the hike when network coverage is available.';
  }
  return 'Review this item before starting the hike.';
}

/// Computes severity color.
Color _severityColor(String severity) {
  return switch (severity.toLowerCase()) {
    'high' || 'fatal' => _HomeColors.red,
    'moderate' => _HomeColors.orange,
    _ => _HomeColors.green,
  };
}

/// Represents home colors.
abstract final class _HomeColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color orange = Color(0xFFF59E0B);
  static const Color blue = Color(0xFF2563EB);
  static const Color red = Color(0xFFE11D48);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);

  /// Checks whether dark.
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Computes background for.
  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  /// Computes surface for.
  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  /// Computes separator for.
  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  /// Computes text for.
  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  /// Computes secondary text for.
  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;
}

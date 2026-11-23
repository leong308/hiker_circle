part of '../../home_dashboard_page_feature.dart';

/// Displays the home dashboard header.
class _HomeDashboardHeader extends StatelessWidget {
  /// Creates home dashboard header.
  const _HomeDashboardHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PageHeaderStyle.title(context, _HomeColors.textFor(context)),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: PageHeaderStyle.subtitle(
              context,
              _HomeColors.secondaryTextFor(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the best matches section.
class _BestMatchesSection extends StatefulWidget {
  /// Creates best matches section.
  const _BestMatchesSection({
    required this.trails,
    required this.isLoading,
    required this.onOpenTrail,
    this.onAddTrailByAdmin,
    this.onReviewTrailRequestsByAdmin,
    this.onEditTrailByAdmin,
    this.onDeleteTrailByAdmin,
  });

  final List<Trail> trails;
  final bool isLoading;
  final ValueChanged<Trail> onOpenTrail;
  final VoidCallback? onAddTrailByAdmin;
  final VoidCallback? onReviewTrailRequestsByAdmin;
  final Future<void> Function(Trail trail)? onEditTrailByAdmin;
  final Future<void> Function(Trail trail)? onDeleteTrailByAdmin;

  /// Creates the presentation state for this widget.
  @override
  State<_BestMatchesSection> createState() => _BestMatchesSectionState();
}

/// Manages the best matches section presentation and lifecycle.
class _BestMatchesSectionState extends State<_BestMatchesSection>
    with WidgetsBindingObserver {
  late final _BestMatchesSectionStateViewModel _screenModel;

  /// Returns filter mode.
  _TrailFilterMode get _filterMode => _screenModel.stateFilterMode;

  /// Updates filter mode.
  set _filterMode(_TrailFilterMode value) =>
      _screenModel.stateFilterMode = value;

  /// Returns region.
  WorldwideRegion? get _region => _screenModel.stateRegion;

  /// Updates region.
  set _region(WorldwideRegion? value) => _screenModel.stateRegion = value;

  /// Returns nearest radius km.
  double get _nearestRadiusKm => _screenModel.stateNearestRadiusKm;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  final _travelDistances = MapboxTravelDistanceService();
  Map<String, double?> _roadDistancesKm = {};
  bool _isRouting = false;
  int _distanceGeneration = 0;

  SosTriggerLocation? _userLocation;
  bool _isLocating = false;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _BestMatchesSectionStateViewModel(
      effectChooseRadius: _chooseRadius,
      effectUseNearest: _useNearest,
    )..addListener(_renderScreenModel);

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_useNearest()),
    );
  }

  /// Delegates destinations to the ViewModel.
  List<TravelDestination> _destinations(List<Trail> trails) =>
      _screenModel.commandDestinations(trails);

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant _BestMatchesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_destinations(oldWidget.trails).toString() !=
        _destinations(widget.trails).toString()) {
      unawaited(_refreshRoadDistances());
    }
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_useNearest(select: false));
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _distanceGeneration++;

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Discard an older travel-distance response after a newer location/filter refresh has started.
  Future<void> _refreshRoadDistances() async {
    final location = _userLocation;
    if (location == null) return;
    final generation = ++_distanceGeneration;
    setState(() {
      _isRouting = true;
      _roadDistancesKm = {};
    });
    final distances = await _travelDistances.distancesKm(
      latitude: location.latitude,
      longitude: location.longitude,
      destinations: _destinations(widget.trails),
    );
    if (!mounted || generation != _distanceGeneration) return;
    setState(() {
      _roadDistancesKm = distances;
      _isRouting = false;
    });
  }

  /// Delegates matches region to the ViewModel.
  bool _matchesRegion(Trail trail) => _screenModel.commandMatchesRegion(trail);

  /// Computes use nearest.
  Future<void> _useNearest({bool select = true}) async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final snapshots = LocationSnapshotService.instance;
      final location = await snapshots.refresh() ?? snapshots.latestLocation;
      if (!mounted) return;
      if (location == null) {
        if (Scaffold.maybeOf(context) == null) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Current location is unavailable. Enable location and try Nearest again.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }
      setState(() {
        _userLocation = location;
        if (select) _filterMode = _TrailFilterMode.nearest;
      });
      await _refreshRoadDistances();
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  /// Computes choose region.
  Future<void> _chooseRegion() async {
    final selected = await WorldwideRegionPicker.show(
      context,
      initialCountry: _region?.country ?? 'Malaysia',
      initialState: _region?.state ?? '',
      countryCodeFilter: 'MY',
    );
    if (!mounted || selected == null) return;
    setState(() {
      _region = selected;
      _filterMode = _TrailFilterMode.state;
    });
  }

  /// Computes choose radius.
  Future<double?> _chooseRadius() async {
    const values = <double>[5, 10, 25, 50, 100, 250, 500];
    var index = values.indexOf(_nearestRadiusKm);
    if (index < 0) index = 3;
    final selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: _HomeColors.surfaceFor(context),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: 300,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Nearest distance',
                        style: Theme.of(sheetContext).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    CupertinoButton(
                      child: const Text('Done'),
                      onPressed: () =>
                          Navigator.of(sheetContext).pop(values[index]),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoPicker(
                  itemExtent: 48,
                  scrollController: FixedExtentScrollController(
                    initialItem: index,
                  ),
                  onSelectedItemChanged: (value) => index = value,
                  children: [
                    for (final value in values)
                      Center(child: Text('Within ${value.toInt()} km')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return selected;
  }

  /// Delegates choose nearest to the ViewModel.
  Future<void> _chooseNearest() => _screenModel.commandChooseNearest();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final filteredTrails = widget.trails.where(_matchesRegion).toList();
    final location = _userLocation;
    if (_filterMode == _TrailFilterMode.nearest &&
        location != null &&
        !_isRouting) {
      filteredTrails.removeWhere(
        (trail) =>
            (_roadDistancesKm[trail.trailId] ?? double.infinity) >
            _nearestRadiusKm,
      );
      filteredTrails.sort(
        (a, b) => (_roadDistancesKm[a.trailId] ?? double.infinity).compareTo(
          _roadDistancesKm[b.trailId] ?? double.infinity,
        ),
      );
    } else {
      filteredTrails.sort((a, b) => b.ratingAverage.compareTo(a.ratingAverage));
    }
    final visibleTrails = filteredTrails;
    return TrailCardViewBuilder(
      builder: (context, cardView, onToggleView) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BestMatchesHeader(
            onAddTrailByAdmin: widget.onAddTrailByAdmin,
            view: cardView,
            onToggleView: onToggleView,
          ),
          const SizedBox(height: 8),
          Material(
            type: MaterialType.transparency,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filterMode == _TrailFilterMode.all,
                  onSelected: (_) =>
                      setState(() => _filterMode = _TrailFilterMode.all),
                ),
                ChoiceChip(
                  avatar: _isLocating
                      ? const Icon(Icons.location_searching_rounded, size: 17)
                      : const Icon(Icons.near_me_rounded, size: 17),
                  label: Text('Nearest · ${_nearestRadiusKm.toInt()} km'),
                  selected: _filterMode == _TrailFilterMode.nearest,
                  onSelected: (_) => unawaited(_chooseNearest()),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.public_rounded, size: 17),
                  label: Text(
                    _region == null ? 'State' : 'State · ${_region!.state}',
                  ),
                  selected: _filterMode == _TrailFilterMode.state,
                  onSelected: (_) => unawaited(_chooseRegion()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_isRouting) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
          ],
          if (widget.onReviewTrailRequestsByAdmin != null) ...[
            AdminPanel(
              key: const ValueKey('home-undiscovered-trail-requests'),
              onTap: widget.onReviewTrailRequestsByAdmin,
              child: const Row(
                children: [
                  Icon(Icons.add_road_rounded),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Review undiscovered trail requests',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (widget.isLoading && visibleTrails.isEmpty)
            const _BestMatchesLoading()
          else if (visibleTrails.isEmpty)
            _EmptyState(
              message: _filterMode != _TrailFilterMode.state || _region == null
                  ? (_filterMode == _TrailFilterMode.nearest && location != null
                        ? nearestTrailsEmptyMessage(
                            radiusKm: _nearestRadiusKm.toInt(),
                            drivingDistancesKm: widget.trails.map(
                              (trail) => _roadDistancesKm[trail.trailId],
                            ),
                          )
                        : 'No trails are available yet. Check again later.')
                  : 'No trails match ${_region!.state}, ${_region!.country}. Try another state.',
            )
          else
            TrailCardCollection(
              view: cardView,
              itemCount: visibleTrails.length,
              itemBuilder: (context, index) {
                final trail = visibleTrails[index];
                return _BestMatchTrailCard(
                  key: ValueKey(trail.trailId),
                  trail: trail,
                  grid: cardView == TrailCardView.grid,
                  nearbyDistanceKm: _roadDistancesKm[trail.trailId],
                  onTap: () => widget.onOpenTrail(trail),
                  onEditTrail: widget.onEditTrailByAdmin == null
                      ? null
                      : () => widget.onEditTrailByAdmin!(trail),
                  onDeleteTrail: widget.onDeleteTrailByAdmin == null
                      ? null
                      : () => widget.onDeleteTrailByAdmin!(trail),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Displays the best matches header.
class _BestMatchesHeader extends StatelessWidget {
  /// Creates best matches header.
  const _BestMatchesHeader({
    this.onAddTrailByAdmin,
    required this.view,
    required this.onToggleView,
  });

  final VoidCallback? onAddTrailByAdmin;
  final TrailCardView view;
  final VoidCallback onToggleView;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: SectionLabel(label: 'Hiking Trails')),
        if (onAddTrailByAdmin != null)
          Tooltip(
            message: 'Add trail',
            child: CupertinoButton(
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              onPressed: onAddTrailByAdmin,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _HomeColors.green.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _HomeColors.green.withValues(alpha: 0.28),
                  ),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: _HomeColors.green,
                  size: 22,
                ),
              ),
            ),
          ),
        if (onAddTrailByAdmin != null) const SizedBox(width: 6),
        TrailViewToggle(
          key: const ValueKey('trail-view-toggle'),
          view: view,
          onPressed: onToggleView,
        ),
      ],
    );
  }
}

/// Displays the best match trail card.
class _BestMatchTrailCard extends StatelessWidget {
  /// Creates best match trail card.
  const _BestMatchTrailCard({
    super.key,
    required this.trail,
    required this.onTap,
    this.grid = false,
    this.nearbyDistanceKm,
    this.onEditTrail,
    this.onDeleteTrail,
  });

  final Trail trail;
  final VoidCallback onTap;
  final bool grid;
  final double? nearbyDistanceKm;
  final Future<void> Function()? onEditTrail;
  final Future<void> Function()? onDeleteTrail;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          trail.name,
          maxLines: grid ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: _HomeColors.textFor(context),
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          trail.locationLabel,
          maxLines: grid ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _HomeColors.secondaryTextFor(context),
          ),
        ),
        const SizedBox(height: 8),
        TrailCardMetrics(
          distanceLabel: trail.distanceLabel,
          durationLabel: trail.durationLabel,
          grid: grid,
          nearbyDistanceKm: nearbyDistanceKm,
          color: _HomeColors.secondaryTextFor(context),
        ),
        const SizedBox(height: 8),
        TrailCardRating(trail: trail),
      ],
    );
    final card = _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: grid
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: _BestMatchTrailCover(
                          trail: trail,
                          expanded: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      details,
                    ],
                  )
                : Row(
                    children: [
                      _BestMatchTrailCover(trail: trail),
                      const SizedBox(width: 12),
                      Expanded(child: details),
                      const SizedBox(width: 8),
                      Icon(
                        CupertinoIcons.chevron_forward,
                        color: _HomeColors.secondaryTextFor(context),
                        size: 17,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    if (onEditTrail == null || onDeleteTrail == null) {
      return card;
    }

    return Dismissible(
      key: ValueKey('home-trail-${trail.trailId}-${trail.name}'),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await onEditTrail?.call();
          return false;
        }

        await onDeleteTrail?.call();
        return false;
      },
      background: const _HomeSwipeActionBackground(
        alignment: Alignment.centerLeft,
        color: _HomeColors.green,
        icon: Icons.edit_rounded,
        label: 'Edit',
      ),
      secondaryBackground: const _HomeSwipeActionBackground(
        alignment: Alignment.centerRight,
        color: _HomeColors.red,
        icon: Icons.delete_rounded,
        label: 'Delete',
      ),
      child: card,
    );
  }
}

/// Displays the hazard row.
class _HazardRow extends StatelessWidget {
  /// Creates hazard row.
  const _HazardRow({
    required this.trail,
    required this.hazard,
    required this.onTap,
  });

  final Trail trail;
  final TrailHazard hazard;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final severityColor = _severityColor(hazard.severity);

    return _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Glyph(
                  icon: Icons.report_problem_rounded,
                  color: severityColor,
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
                              hazard.type,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: _HomeColors.textFor(context),
                                    fontWeight: FontWeight.w700,
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
                      const SizedBox(height: 4),
                      Text(
                        '${trail.name} - ${hazard.locationLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _HomeColors.secondaryTextFor(context),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        hazard.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _HomeColors.textFor(context),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Reported ${_formatRelativeDate(hazard.reportedAt)} - Tap for route impact and advice',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _HomeColors.secondaryTextFor(context),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
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

/// Displays the checklist insight row.
class _ChecklistInsightRow extends StatelessWidget {
  /// Creates checklist insight row.
  const _ChecklistInsightRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(icon: icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _HomeColors.textFor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _HomeColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the detail header.
class _DetailHeader extends StatelessWidget {
  /// Creates detail header.
  const _DetailHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) =>
      PageHeader(title: title, subtitle: subtitle, onBack: onBack);
}

/// Displays the active header.
class _ActiveHeader extends StatelessWidget {
  /// Creates active header.
  const _ActiveHeader({required this.activeHike});

  final ActiveHikeSession activeHike;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ACTIVE HIKE',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: _HomeColors.green,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              Text(
                activeHike.trail.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PageHeaderStyle.title(
                  context,
                  _HomeColors.textFor(context),
                ),
              ),
            ],
          ),
        ),
        const _StatusPill(label: 'Tracking', color: _HomeColors.green),
      ],
    );
  }
}

/// Displays the connection status card.
class _ConnectionStatusCard extends StatelessWidget {
  /// Creates connection status card.
  const _ConnectionStatusCard({required this.queuedUpdates});

  final int queuedUpdates;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(
              icon: queuedUpdates > 0
                  ? Icons.sync_problem_rounded
                  : Icons.save_rounded,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                queuedUpdates > 0
                    ? '$queuedUpdates location update${queuedUpdates == 1 ? '' : 's'} are stored on this phone and waiting to sync. Keep HikerCircle active; mobile OS suspension can pause new samples.'
                    : 'No location updates are waiting to sync. Keep HikerCircle active for continuous route and safety checks.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _HomeColors.textFor(context),
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the mini map card.
class _MiniMapCard extends StatelessWidget {
  /// Creates mini map card.
  const _MiniMapCard({
    required this.activeHike,
    required this.currentPhoneNumber,
  });

  final ActiveHikeSession activeHike;
  final String currentPhoneNumber;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 190,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ActiveTrackingMapView(
                  activeHike: activeHike,
                  teamHikeSession: activeHike.teamHikeSession,
                  interactive: false,
                  currentPhoneNumber: currentPhoneNumber,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _InfoLine(
                    label: 'GPS Points',
                    value: '${activeHike.routePointCount}',
                  ),
                ),
                Expanded(
                  child: _InfoLine(
                    label: 'Distance',
                    value:
                        '${activeHike.recordedDistanceKm.toStringAsFixed(2)} km',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the monitoring card.
class _MonitoringCard extends StatelessWidget {
  /// Creates monitoring card.
  const _MonitoringCard({
    required this.activeHike,
    required this.fallStillnessSnapshot,
    required this.onCancelFallStillnessSos,
  });

  final ActiveHikeSession activeHike;
  final FallStillnessMonitorSnapshot fallStillnessSnapshot;
  final VoidCallback onCancelFallStillnessSos;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final settings = activeHike.draft.fallDetectionSettings;
    final fallDetectionValue = activeHike.draft.fallDetectionEnabled
        ? fallStillnessSnapshot.status.label
        : 'Off';
    final latestLocationAt = activeHike.latestLocation?.capturedAt.toUtc();
    final latestLocationAge = latestLocationAt == null
        ? null
        : DateTime.now().toUtc().difference(latestLocationAt);
    final sessionStatus = latestLocationAge == null
        ? 'Waiting for GPS'
        : latestLocationAge < const Duration(minutes: -1) ||
              latestLocationAge > const Duration(minutes: 2)
        ? 'GPS paused or stale'
        : 'Recording (app active)';

    return _InsetGroup(
      child: Column(
        children: [
          _StatusRow(label: 'Session Status', value: sessionStatus),
          const _HorizontalSeparator(),
          _StatusRow(label: 'Fall Detection', value: fallDetectionValue),
          if (activeHike.draft.fallDetectionEnabled) ...[
            const _HorizontalSeparator(),
            _StatusRow(
              label: 'Sensor Sensitivity',
              value:
                  '${settings.sensitivityLabel} (${settings.sensorSensitivity.round()}/10)',
            ),
            const _HorizontalSeparator(),
            _StatusRow(
              label: 'Fall Response Time',
              value: settings.responseCountdownDurationLabel,
            ),
            const _HorizontalSeparator(),
            _StatusRow(
              label: 'Longest Rest Time',
              value: settings.longestRestDurationLabel,
            ),
          ],
          if (fallStillnessSnapshot.status ==
              FallStillnessMonitorStatus.verifyingStillness) ...[
            const _HorizontalSeparator(),
            _StatusRow(
              label: 'Stillness Check',
              value: _stillnessCheckValue(fallStillnessSnapshot),
            ),
          ],
          if (fallStillnessSnapshot.status ==
              FallStillnessMonitorStatus.awaitingResponse) ...[
            const _HorizontalSeparator(),
            _FallStillnessCountdownRow(
              snapshot: fallStillnessSnapshot,
              onCancel: onCancelFallStillnessSos,
            ),
          ],
          if (fallStillnessSnapshot.status ==
              FallStillnessMonitorStatus.unavailable) ...[
            const _HorizontalSeparator(),
            _StatusRow(
              label: 'Sensor Status',
              value: fallStillnessSnapshot.message ?? 'Unavailable',
            ),
          ],
          const _HorizontalSeparator(),
          _StatusRow(
            label: 'Footprint interval',
            value: _recordingIntervalLabel(
              activeHike.draft.locationRecordingInterval,
            ),
          ),
          const _HorizontalSeparator(),
          _StatusRow(
            label: 'Queued Updates',
            value: activeHike.queuedUpdates == 0
                ? 'None waiting'
                : '${activeHike.queuedUpdates} waiting to sync',
          ),
          const _HorizontalSeparator(),
          _StatusRow(
            label: 'Local GPS',
            value: _recordingIntervalLabel(
              activeHike.draft.locationRecordingInterval,
            ),
          ),
        ],
      ),
    );
  }

  /// Computes stillness check value.
  String _stillnessCheckValue(FallStillnessMonitorSnapshot snapshot) {
    final seconds = snapshot.secondsRemaining;
    final suffix = snapshot.isBackpackTrapLikely ? ' extended' : '';
    if (seconds == null) {
      return 'Verifying$suffix';
    }
    return '$seconds sec$suffix';
  }

  /// Computes recording interval label.
  String _recordingIntervalLabel(Duration interval) {
    final totalSeconds = interval.inSeconds;
    if (totalSeconds <= 0) {
      return 'Not configured';
    }
    if (totalSeconds < Duration.secondsPerMinute) {
      return 'Every $totalSeconds sec';
    }

    final minutes = totalSeconds ~/ Duration.secondsPerMinute;
    final seconds = totalSeconds % Duration.secondsPerMinute;
    if (seconds == 0) {
      return 'Every $minutes min';
    }
    return 'Every $minutes min $seconds sec';
  }
}

/// Displays the fall stillness countdown row.
class _FallStillnessCountdownRow extends StatelessWidget {
  /// Creates fall stillness countdown row.
  const _FallStillnessCountdownRow({
    required this.snapshot,
    required this.onCancel,
  });

  final FallStillnessMonitorSnapshot snapshot;
  final VoidCallback onCancel;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final seconds = snapshot.secondsRemaining ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _Glyph(icon: Icons.health_and_safety_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  snapshot.isProlongedStillnessDetection
                      ? 'Prolonged stillness detected. SOS in $seconds seconds.'
                      : 'Possible fall detected. SOS in $seconds seconds.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _HomeColors.red,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: _countdownProgress(snapshot),
            minHeight: 3,
            color: _HomeColors.red,
            backgroundColor: _HomeColors.red.withValues(alpha: 0.14),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.touch_app_rounded),
            label: const Text('I am OK - Cancel SOS'),
          ),
        ],
      ),
    );
  }

  /// Computes countdown progress.
  double? _countdownProgress(FallStillnessMonitorSnapshot snapshot) {
    final settings = snapshot.settings;
    final remaining = snapshot.secondsRemaining;
    if (settings == null || remaining == null) {
      return null;
    }

    final totalDurationSeconds = settings.fallResponseDuration.inSeconds;
    if (totalDurationSeconds <= 0) {
      return null;
    }

    return 1 - (remaining / totalDurationSeconds).clamp(0, 1).toDouble();
  }
}

/// Displays the shared with card.
class _SharedWithCard extends StatelessWidget {
  /// Creates shared with card.
  const _SharedWithCard({required this.activeHike});

  final ActiveHikeSession activeHike;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final contacts = {
      for (final name in activeHike.draft.emergencyContactNames)
        if (name.trim().isNotEmpty) name.trim(),
    }.toList();
    final teamParticipantCount =
        activeHike.teamHikeSession?.participants.length;

    return _InsetGroup(
      child: Column(
        children: [
          _StatusRow(
            label: 'Live Location',
            value: activeHike.draft.shareLiveLocation ? 'Enabled' : 'Off',
          ),
          const _HorizontalSeparator(),
          _StatusRow(
            label: 'Emergency Contacts',
            value: contacts.isEmpty ? 'None selected' : contacts.join(', '),
          ),
          if (teamParticipantCount != null) ...[
            const _HorizontalSeparator(),
            _StatusRow(
              label: 'Team Session',
              value:
                  '$teamParticipantCount participant${teamParticipantCount == 1 ? '' : 's'}',
            ),
          ],
        ],
      ),
    );
  }
}

/// Displays the team snapshot card.
class _TeamSnapshotCard extends StatefulWidget {
  /// Creates team snapshot card.
  const _TeamSnapshotCard({
    required this.activeHike,
    required this.currentPhoneNumber,
    required this.onPingTeamMember,
  });

  final ActiveHikeSession activeHike;
  final String currentPhoneNumber;
  final Future<TeamHikeSession?> Function(String phoneNumber) onPingTeamMember;

  /// Creates the presentation state for this widget.
  @override
  State<_TeamSnapshotCard> createState() => _TeamSnapshotCardState();
}

/// Manages the team snapshot card presentation and lifecycle.
class _TeamSnapshotCardState extends State<_TeamSnapshotCard> {
  String _pingingPhoneNumber = '';
  HikerCircleLoadingDialogRoute? _pingLoadingRoute;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final teamSession = widget.activeHike.teamHikeSession;
    if (widget.activeHike.draft.hikeType != HikeType.team) {
      return const _InsetGroup(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text('Start a team hike to see teammate positions.'),
        ),
      );
    }

    if (teamSession == null) {
      return const _InsetGroup(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text('Waiting for live team status...'),
        ),
      );
    }

    final leader = teamSession.leader;
    return _InsetGroup(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                const _Glyph(icon: Icons.groups_2_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Team live status',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _HomeColors.textFor(context),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                      ),
                      Text(
                        leader == null
                            ? teamSession.phase.label
                            : '${leader.buddy.shortName} is currently leading',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _HomeColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(
                  label: teamSession.phase.label,
                  color: _HomeColors.green,
                ),
              ],
            ),
          ),
          const _HorizontalSeparator(),
          for (
            var index = 0;
            index < teamSession.participants.length;
            index++
          ) ...[
            _TeamParticipantRow(
              participant: teamSession.participants[index],
              isSelf: _samePhoneNumber(
                teamSession.participants[index].phoneNumber,
                widget.currentPhoneNumber,
              ),
              isPinging: _samePhoneNumber(
                teamSession.participants[index].phoneNumber,
                _pingingPhoneNumber,
              ),
              onPing: () => _ping(teamSession.participants[index]),
            ),
            if (index != teamSession.participants.length - 1)
              const _HorizontalSeparator(),
          ],
        ],
      ),
    );
  }

  /// Computes ping.
  Future<void> _ping(TeamHikeParticipant participant) async {
    if (_pingingPhoneNumber.isNotEmpty || !participant.canBePinged) {
      return;
    }
    setState(() {
      _pingingPhoneNumber = participant.phoneNumber;
    });
    unawaited(_presentPingEffect1());
    try {
      final updatedSession = await widget
          .onPingTeamMember(participant.phoneNumber)
          .timeout(const Duration(seconds: 30));
      if (!mounted) {
        return;
      }
      if (updatedSession == null) {
        throw StateError('The team session did not accept the ping.');
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Ping sent to ${participant.buddy.shortName}.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to send the safety ping right now.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      _presentPingEffect2();
      if (mounted) {
        setState(() {
          _pingingPhoneNumber = '';
        });
      }
    }
  }

  /// Uses the same bounded modal treatment as other loading operations.
  Future<void> _presentPingEffect1() {
    final route = HikerCircleLoadingDialogRoute(
      context: context,
      compact: true,
      message: 'Sending safety ping…',
      detail: 'Sending a check-in request to your teammate.',
    );
    _pingLoadingRoute = route;
    return Navigator.of(context, rootNavigator: true).push<void>(route);
  }

  /// Closes only this ping's loader; late completion cannot dismiss another route.
  void _presentPingEffect2() {
    _pingLoadingRoute?.close();
    _pingLoadingRoute = null;
  }

  /// Removes an outstanding loader if the containing team card goes away.
  @override
  void dispose() {
    final loading = _pingLoadingRoute;
    WidgetsBinding.instance.addPostFrameCallback((_) => loading?.close());
    super.dispose();
  }
}

/// Displays the team participant row.
class _TeamParticipantRow extends StatelessWidget {
  /// Creates team participant row.
  const _TeamParticipantRow({
    required this.participant,
    required this.isSelf,
    required this.isPinging,
    required this.onPing,
  });

  final TeamHikeParticipant participant;
  final bool isSelf;
  final bool isPinging;
  final VoidCallback onPing;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final isEnded = participant.status == TeamHikeParticipantStatus.ended;
    final color = participant.isLeader ? _HomeColors.orange : _HomeColors.green;
    final avatarColor = Color(participant.buddy.avatarColorValue);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isEnded
                      ? avatarColor.withValues(alpha: 0.35)
                      : avatarColor,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  participant.buddy.shortName.substring(0, 1).toUpperCase(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isEnded
                        ? Colors.white.withValues(alpha: 0.45)
                        : Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (participant.isLeader && !isEnded)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _HomeColors.orange,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _HomeColors.surfaceFor(context),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.flag_rounded,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isSelf ? 'You' : participant.buddy.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isEnded
                              ? _HomeColors.secondaryTextFor(context)
                              : _HomeColors.textFor(context),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                          decoration: isEnded
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    if (participant.isLeader && !isEnded) ...[
                      const SizedBox(width: 6),
                      _StatusPill(label: 'Leader', color: color),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${participant.status.label} - ${(participant.progressMeters / 1000).toStringAsFixed(2)} km - ${participant.responseLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isEnded
                        ? _HomeColors.secondaryTextFor(
                            context,
                          ).withValues(alpha: 0.5)
                        : _HomeColors.secondaryTextFor(context),
                    letterSpacing: 0,
                    decoration: isEnded ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!isSelf)
            Tooltip(
              message: isEnded
                  ? 'Buddy has ended their hike'
                  : participant.canBePinged
                  ? 'Ping for OK response'
                  : 'Buddy has not joined yet',
              child: OutlinedButton(
                onPressed: participant.canBePinged && !isPinging
                    ? onPing
                    : null,
                child: const Text('Ping'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Displays the status row.
class _StatusRow extends StatelessWidget {
  /// Creates status row.
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _HomeColors.textFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _HomeColors.secondaryTextFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the my upcoming hikes section.
class _MyUpcomingHikesSection extends StatefulWidget {
  /// Creates my upcoming hikes section.
  const _MyUpcomingHikesSection({
    required this.hikes,
    required this.trails,
    required this.isVisible,
    this.plannedHike,
    required this.phoneNumber,
    this.onTapHike,
    this.onDeleteHike,
  });

  final List<UpcomingHike> hikes;
  final List<Trail> trails;
  final bool isVisible;
  final PlannedHike? plannedHike;
  final String phoneNumber;
  final Future<void> Function(UpcomingHike)? onTapHike;
  final Future<void> Function(UpcomingHike)? onDeleteHike;

  /// Creates the presentation state for this widget.
  @override
  State<_MyUpcomingHikesSection> createState() =>
      _MyUpcomingHikesSectionState();
}

/// Manages the my upcoming hikes section presentation and lifecycle.
class _MyUpcomingHikesSectionState extends State<_MyUpcomingHikesSection> {
  late final _MyUpcomingHikesSectionStateViewModel _screenModel;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  final _controller = ScrollController(keepScrollOffset: false);
  List<UpcomingHike> _hikes = const [];
  int _index = 0;
  double _pageWidth = 0;
  int _alignmentRevision = 0;
  bool _alignmentPending = false;

  /// Delegates ordered hikes to the ViewModel.
  List<UpcomingHike> _orderedHikes() => _screenModel.commandOrderedHikes();

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _MyUpcomingHikesSectionStateViewModel(
      readHikes: () => widget.hikes,
    )..addListener(_renderScreenModel);

    _hikes = _orderedHikes();
    _controller.addListener(_onScroll);
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant _MyUpcomingHikesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ordered = _orderedHikes();
    final changedOrder = !listEquals(
      _hikes.map((hike) => hike.id).toList(),
      ordered.map((hike) => hike.id).toList(),
    );
    _hikes = ordered;
    if (changedOrder || (!oldWidget.isVisible && widget.isVisible)) {
      _index = 0;
      _alignAfterLayout();
    }
  }

  /// Computes align after layout.
  void _alignAfterLayout() {
    final revision = ++_alignmentRevision;
    _alignmentPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _alignmentRevision) return;
      if (_controller.hasClients) {
        _controller.jumpTo(_index * _pageWidth);
      }
      _alignmentPending = false;
    });
  }

  /// Computes on scroll.
  void _onScroll() {
    if (_alignmentPending || _pageWidth <= 0 || _hikes.isEmpty) return;
    final page = (_controller.offset / _pageWidth).round().clamp(
      0,
      _hikes.length - 1,
    );
    if (page != _index) setState(() => _index = page);
  }

  /// Computes go to.
  void _goTo(int index) {
    if (!_controller.hasClients) return;
    final target = index * _pageWidth;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpTo(target);
    } else {
      unawaited(
        _controller.animateTo(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _controller.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Computes card.
  Widget _card(UpcomingHike hike, int index) {
    final plan = widget.plannedHike?.upcomingHikeId == hike.id
        ? widget.plannedHike
        : null;
    final trail =
        plan?.trail ??
        widget.trails
            .where((trail) => trail.trailId == hike.trailId)
            .firstOrNull;
    return ExcludeSemantics(
      excluding: index != _index,
      child: ExcludeFocus(
        excluding: index != _index,
        child: NextHikeBriefing(
          key: ValueKey(hike.id),
          hike: hike,
          isNextHike: index == 0,
          phoneNumber: widget.phoneNumber,
          plannedHike: plan,
          onDelete:
              widget.onDeleteHike == null ||
                  index != _index ||
                  !widget.isVisible ||
                  !hike.isParticipant(widget.phoneNumber)
              ? null
              : () => widget.onDeleteHike!(hike),
          trail: trail,
          isVisible: widget.isVisible && index == _index,
          onReview: widget.onTapHike != null
              ? () => widget.onTapHike!(hike)
              : plan == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _PreparationReminderPage(plannedHike: plan),
                  ),
                ),
        ),
      ),
    );
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (_hikes.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_pageWidth != constraints.maxWidth) {
          _pageWidth = constraints.maxWidth;
          _alignAfterLayout();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A horizontal viewport lets the cards keep their natural height,
            // including large text, while PageScrollPhysics snaps one hike at a time.
            SingleChildScrollView(
              key: const ValueKey('upcoming-hike-carousel'),
              controller: _controller,
              scrollDirection: Axis.horizontal,
              reverse: Directionality.of(context) == TextDirection.rtl,
              physics: const PageScrollPhysics(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                textDirection: TextDirection.ltr,
                children: [
                  for (var i = 0; i < _hikes.length; i++)
                    SizedBox(
                      key: ValueKey('upcoming-hike-card-${_hikes[i].id}'),
                      width: _pageWidth,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: _hikes.length > 1 ? 4 : 0,
                        ),
                        child: _card(_hikes[i], i),
                      ),
                    ),
                ],
              ),
            ),
            if (_hikes.length > 1) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous hike',
                    onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Text(
                      '${_index + 1} of ${_hikes.length} hikes',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next upcoming hike',
                    onPressed: _index < _hikes.length - 1
                        ? () => _goTo(_index + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Displays the empty state.
class _EmptyState extends StatelessWidget {
  /// Creates empty state.
  const _EmptyState({required this.message});

  final String message;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Center(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _HomeColors.secondaryTextFor(context),
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the status pill.
class _StatusPill extends StatelessWidget {
  /// Creates status pill.
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

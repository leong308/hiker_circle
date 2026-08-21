import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../trail/Model/trail_models.dart';
import '../../sos/Data/location_snapshot_service.dart';
import '../../sos/Model/sos_models.dart';
import '../Model/hike_session_models.dart';
import '../ModelView/fall_stillness_monitor.dart';
import 'active_tracking_map_view.dart';
import 'gear_checklist_page.dart';

class HomeDashboardPage extends StatelessWidget {
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
    this.onAddTrailByAdmin,
    this.onEditTrailByAdmin,
    this.onDeleteTrailByAdmin,
    required this.onActiveHikeChanged,
    this.onPlannedHikeChanged,
    required this.onCheckInRequested,
    required this.onPinLocationRequested,
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
  final void Function(UpcomingHike)? onTapUpcomingHike;
  final VoidCallback? onAddTrailByAdmin;
  final Future<void> Function(Trail trail)? onEditTrailByAdmin;
  final Future<void> Function(Trail trail)? onDeleteTrailByAdmin;
  final ValueChanged<ActiveHikeSession> onActiveHikeChanged;
  final Future<void> Function(PlannedHike)? onPlannedHikeChanged;
  final Future<ActiveHikeSession> Function(ActiveHikeSession activeHike)
  onCheckInRequested;
  final Future<PinLocationResult> Function(ActiveHikeSession activeHike)
  onPinLocationRequested;
  final Future<TeamHikeSession?> Function(String phoneNumber) onPingTeamMember;
  final VoidCallback onEndHike;
  final FallStillnessMonitorSnapshot fallStillnessSnapshot;
  final VoidCallback onCancelFallStillnessSos;

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
                            phoneNumber: phoneNumber,
                            trails: trails,
                            isLoadingTrails: isLoadingTrails,
                            onStartHike: () =>
                                unawaited(_startHikeFromDashboard(context)),
                            onFindHike: onFindHike,
                            onOpenTrailDetail: onOpenTrailDetail,
                            onTapUpcomingHike: onTapUpcomingHike,
                            onAddTrailByAdmin: onAddTrailByAdmin,
                            onEditTrailByAdmin: onEditTrailByAdmin,
                            onDeleteTrailByAdmin: onDeleteTrailByAdmin,
                          )
                        : _PreparationDashboard(
                            myUpcomingHikes: myUpcomingHikes,
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
                            onAddTrailByAdmin: onAddTrailByAdmin,
                            onEditTrailByAdmin: onEditTrailByAdmin,
                            onDeleteTrailByAdmin: onDeleteTrailByAdmin,
                            onPlannedHikeChanged: onPlannedHikeChanged,
                          )
                  : _ActiveHikeDashboard(
                      currentPhoneNumber: phoneNumber,
                      activeHike: active,
                      isVisible: isVisible,
                      fallStillnessSnapshot: fallStillnessSnapshot,
                      onCheckIn: () => unawaited(_checkIn(context, active)),
                      onPinLocation: () =>
                          unawaited(_pinLocation(context, active)),
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

  Future<void> _startHikeFromDashboard(BuildContext context) async {
    if (trails.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              isLoadingTrails
                  ? 'Trails are still loading. Try again shortly.'
                  : 'No trails are available to start yet.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    await _requestStartHike(context, null);
  }

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

  Future<void> _pinLocation(
    BuildContext context,
    ActiveHikeSession active,
  ) async {
    try {
      final result = await onPinLocationRequested(active);
      onActiveHikeChanged(result.hike);
      if (!context.mounted) {
        return;
      }
      final message = switch (result.status) {
        PinLocationStatus.pinned => 'Current GPS location pinned on the map.',
        PinLocationStatus.duplicate =>
          'This location is already pinned before.',
        PinLocationStatus.unavailable =>
          'GPS is unavailable, so no pin was added.',
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to pin the current location right now.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

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

class _PreparationDashboard extends StatelessWidget {
  const _PreparationDashboard({
    this.myUpcomingHikes = const [],
    required this.phoneNumber,
    required this.plannedHike,
    required this.trails,
    required this.isLoadingTrails,
    required this.onStartHike,
    required this.onFindHike,
    required this.onOpenTrailDetail,
    this.onTapUpcomingHike,
    this.onAddTrailByAdmin,
    this.onEditTrailByAdmin,
    this.onDeleteTrailByAdmin,
    this.onPlannedHikeChanged,
  });

  final List<UpcomingHike> myUpcomingHikes;
  final String phoneNumber;
  final PlannedHike plannedHike;
  final List<Trail> trails;
  final bool isLoadingTrails;
  final VoidCallback onStartHike;
  final VoidCallback onFindHike;
  final ValueChanged<Trail> onOpenTrailDetail;
  final void Function(UpcomingHike)? onTapUpcomingHike;
  final VoidCallback? onAddTrailByAdmin;
  final Future<void> Function(Trail trail)? onEditTrailByAdmin;
  final Future<void> Function(Trail trail)? onDeleteTrailByAdmin;
  final Future<void> Function(PlannedHike)? onPlannedHikeChanged;

  @override
  Widget build(BuildContext context) {
    final hazards = plannedHike.trail.hazards;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _HomeDashboardHeader(
          title: 'Hike Plan Ready',
          subtitle: 'Review your route, preparation, and nearby trail options.',
        ),
        const SizedBox(height: 16),
        _StartHikeActions(onStartHike: onStartHike, onFindHike: onFindHike),
        const SizedBox(height: 18),
        _UpcomingHikeCard(
          plannedHike: plannedHike,
          onContinuePreparation: () => unawaited(_openChecklist(context)),
          onOpenTrail: () => onOpenTrailDetail(plannedHike.trail),
        ),
        if (myUpcomingHikes.isNotEmpty) ...[
          const SizedBox(height: 22),
          _MyUpcomingHikesSection(
            hikes: myUpcomingHikes,
            phoneNumber: phoneNumber,
            onTapHike: onTapUpcomingHike,
          ),
        ],
        const SizedBox(height: 22),
        _BestMatchesSection(
          trails: trails,
          isLoading: isLoadingTrails,
          onOpenTrail: onOpenTrailDetail,
          onAddTrailByAdmin: onAddTrailByAdmin,
          onEditTrailByAdmin: onEditTrailByAdmin,
          onDeleteTrailByAdmin: onDeleteTrailByAdmin,
        ),
        if (plannedHike.missingPreparationItems.isNotEmpty) ...[
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
        _SectionTitle(label: 'Recent Hazards on This Trail'),
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

  Future<void> _openChecklist(BuildContext context) async {
    final completedItems = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute<Set<String>>(
        builder: (context) => GearChecklistPage(plannedHike: plannedHike),
      ),
    );
    if (completedItems == null || !context.mounted) {
      return;
    }
    await onPlannedHikeChanged?.call(
      plannedHike.copyWith(
        completedChecklistItems: completedItems,
        checklistCompleted: completedItems.length,
        checklistTotal: GearChecklistPage.checklistItemCount,
      ),
    );
  }
}

class _TrailDiscoveryDashboard extends StatelessWidget {
  const _TrailDiscoveryDashboard({
    this.myUpcomingHikes = const [],
    required this.phoneNumber,
    required this.trails,
    required this.isLoadingTrails,
    required this.onStartHike,
    required this.onFindHike,
    required this.onOpenTrailDetail,
    this.onTapUpcomingHike,
    this.onAddTrailByAdmin,
    this.onEditTrailByAdmin,
    this.onDeleteTrailByAdmin,
  });

  final List<UpcomingHike> myUpcomingHikes;
  final String phoneNumber;
  final List<Trail> trails;
  final bool isLoadingTrails;
  final VoidCallback onStartHike;
  final VoidCallback onFindHike;
  final ValueChanged<Trail> onOpenTrailDetail;
  final void Function(UpcomingHike)? onTapUpcomingHike;
  final VoidCallback? onAddTrailByAdmin;
  final Future<void> Function(Trail trail)? onEditTrailByAdmin;
  final Future<void> Function(Trail trail)? onDeleteTrailByAdmin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _HomeDashboardHeader(
          title: 'Plan Your Hike',
          subtitle: 'Start a solo session or choose a trail from Best Matches.',
        ),
        const SizedBox(height: 16),
        _StartHikeActions(onStartHike: onStartHike, onFindHike: onFindHike),
        if (myUpcomingHikes.isNotEmpty) ...[
          const SizedBox(height: 22),
          _MyUpcomingHikesSection(
            hikes: myUpcomingHikes,
            phoneNumber: phoneNumber,
            onTapHike: onTapUpcomingHike,
          ),
        ],
        const SizedBox(height: 22),
        _BestMatchesSection(
          trails: trails,
          isLoading: isLoadingTrails,
          onOpenTrail: onOpenTrailDetail,
          onAddTrailByAdmin: onAddTrailByAdmin,
          onEditTrailByAdmin: onEditTrailByAdmin,
          onDeleteTrailByAdmin: onDeleteTrailByAdmin,
        ),
      ],
    );
  }
}

class _HomeDashboardHeader extends StatelessWidget {
  const _HomeDashboardHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

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
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: _HomeColors.textFor(context),
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _HomeColors.secondaryTextFor(context),
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

enum _BestMatchSort { recommended, nearest }

enum _TrailRegionKind { country, state }

class _TrailRegionFilter {
  const _TrailRegionFilter({required this.kind, required this.value});

  final _TrailRegionKind kind;
  final String value;

  String get label => switch (kind) {
    _TrailRegionKind.country => value,
    _TrailRegionKind.state => value,
  };
}

class _BestMatchesSection extends StatefulWidget {
  const _BestMatchesSection({
    required this.trails,
    required this.isLoading,
    required this.onOpenTrail,
    this.onAddTrailByAdmin,
    this.onEditTrailByAdmin,
    this.onDeleteTrailByAdmin,
  });

  final List<Trail> trails;
  final bool isLoading;
  final ValueChanged<Trail> onOpenTrail;
  final VoidCallback? onAddTrailByAdmin;
  final Future<void> Function(Trail trail)? onEditTrailByAdmin;
  final Future<void> Function(Trail trail)? onDeleteTrailByAdmin;

  @override
  State<_BestMatchesSection> createState() => _BestMatchesSectionState();
}

class _BestMatchesSectionState extends State<_BestMatchesSection> {
  _BestMatchSort _sort = _BestMatchSort.recommended;
  _TrailRegionFilter? _region;
  SosTriggerLocation? _userLocation;
  bool _isLocating = false;

  List<_TrailRegionFilter> get _regionOptions {
    final countries = <String>{};
    final states = <String>{};
    for (final trail in widget.trails) {
      final country = trail.country.trim();
      final state = trail.state.trim();
      if (country.isNotEmpty) countries.add(country);
      if (state.isNotEmpty) states.add(state);
    }
    final sortedCountries = countries.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final sortedStates = states.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [
      for (final value in sortedCountries)
        _TrailRegionFilter(kind: _TrailRegionKind.country, value: value),
      for (final value in sortedStates)
        _TrailRegionFilter(kind: _TrailRegionKind.state, value: value),
    ];
  }

  bool _matchesRegion(Trail trail) {
    final region = _region;
    if (region == null) return true;
    return switch (region.kind) {
      _TrailRegionKind.country =>
        trail.country.trim().toLowerCase() == region.value.toLowerCase(),
      _TrailRegionKind.state =>
        trail.state.trim().toLowerCase() == region.value.toLowerCase(),
    };
  }

  Future<void> _useNearest() async {
    if (_isLocating) return;
    if (_userLocation != null) {
      setState(() => _sort = _BestMatchSort.nearest);
      return;
    }
    setState(() => _isLocating = true);
    try {
      final snapshots = LocationSnapshotService.instance;
      final location = await snapshots.refresh() ?? snapshots.latestLocation;
      if (!mounted) return;
      if (location == null) {
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
        _sort = _BestMatchSort.nearest;
      });
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _chooseRegion() async {
    final options = _regionOptions;
    final selected = await showModalBottomSheet<_TrailRegionFilter?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: _HomeColors.surfaceFor(context),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
                child: Text(
                  'Filter by region',
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                    color: _HomeColors.textFor(sheetContext),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.public_rounded),
                title: const Text('All regions'),
                trailing: _region == null
                    ? const Icon(Icons.check_rounded, color: _HomeColors.green)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(
                  const _TrailRegionFilter(
                    kind: _TrailRegionKind.country,
                    value: '',
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: options.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Region information is not available for these trails yet.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final option = options[index];
                          final selected =
                              _region?.kind == option.kind &&
                              _region?.value == option.value;
                          return ListTile(
                            leading: Icon(
                              option.kind == _TrailRegionKind.country
                                  ? Icons.public_rounded
                                  : Icons.map_outlined,
                            ),
                            title: Text(option.value),
                            subtitle: Text(
                              option.kind == _TrailRegionKind.country
                                  ? 'Country'
                                  : 'State or region',
                            ),
                            trailing: selected
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: _HomeColors.green,
                                  )
                                : null,
                            onTap: () => Navigator.of(sheetContext).pop(option),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _region = selected.value.isEmpty ? null : selected);
  }

  @override
  Widget build(BuildContext context) {
    final filteredTrails = widget.trails.where(_matchesRegion).toList();
    final location = _userLocation;
    if (_sort == _BestMatchSort.nearest && location != null) {
      filteredTrails.sort(
        (a, b) => _distanceFromTrail(
          a,
          location,
        ).compareTo(_distanceFromTrail(b, location)),
      );
    }
    final visibleTrails = filteredTrails.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BestMatchesHeader(
          onAddTrailByAdmin: widget.onAddTrailByAdmin,
          hasActiveFilter: _sort == _BestMatchSort.nearest || _region != null,
        ),
        const SizedBox(height: 8),
        Material(
          type: MaterialType.transparency,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Recommended'),
                selected: _sort == _BestMatchSort.recommended,
                onSelected: (_) =>
                    setState(() => _sort = _BestMatchSort.recommended),
              ),
              ChoiceChip(
                avatar: _isLocating
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.near_me_rounded, size: 17),
                label: const Text('Nearest'),
                selected: _sort == _BestMatchSort.nearest,
                onSelected: (_) => unawaited(_useNearest()),
              ),
              ActionChip(
                avatar: const Icon(Icons.public_rounded, size: 17),
                label: Text(_region?.label ?? 'Region'),
                onPressed: _chooseRegion,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (widget.isLoading && visibleTrails.isEmpty)
          const _BestMatchesLoading()
        else if (visibleTrails.isEmpty)
          _EmptyState(
            message: _region == null
                ? 'No trails are available yet. Check again later.'
                : 'No trails match ${_region!.label}. Try another region.',
          )
        else
          for (final trail in visibleTrails) ...[
            _BestMatchTrailCard(
              trail: trail,
              nearbyDistanceKm: location == null
                  ? null
                  : _distanceFromTrail(trail, location),
              onTap: () => widget.onOpenTrail(trail),
              onEditTrail: widget.onEditTrailByAdmin == null
                  ? null
                  : () => widget.onEditTrailByAdmin!(trail),
              onDeleteTrail: widget.onDeleteTrailByAdmin == null
                  ? null
                  : () => widget.onDeleteTrailByAdmin!(trail),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  double _distanceFromTrail(Trail trail, SosTriggerLocation location) {
    if (!trail.latitude.isFinite ||
        !trail.longitude.isFinite ||
        trail.latitude < -90 ||
        trail.latitude > 90 ||
        trail.longitude < -180 ||
        trail.longitude > 180) {
      return double.infinity;
    }
    const earthRadiusKm = 6371.0;
    double radians(double degrees) => degrees * math.pi / 180;
    final latitudeDelta = radians(trail.latitude - location.latitude);
    final longitudeDelta = radians(trail.longitude - location.longitude);
    final value =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(radians(location.latitude)) *
            math.cos(radians(trail.latitude)) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    return earthRadiusKm * 2 * math.asin(math.sqrt(value.clamp(0.0, 1.0)));
  }
}

class _BestMatchesHeader extends StatelessWidget {
  const _BestMatchesHeader({
    this.onAddTrailByAdmin,
    required this.hasActiveFilter,
  });

  final VoidCallback? onAddTrailByAdmin;
  final bool hasActiveFilter;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: _SectionTitle(label: 'Best Matches')),
        if (hasActiveFilter)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(
              Icons.filter_alt_rounded,
              size: 18,
              color: _HomeColors.green,
            ),
          ),
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
      ],
    );
  }
}

class _BestMatchTrailCard extends StatelessWidget {
  const _BestMatchTrailCard({
    required this.trail,
    required this.onTap,
    this.nearbyDistanceKm,
    this.onEditTrail,
    this.onDeleteTrail,
  });

  final Trail trail;
  final VoidCallback onTap;
  final double? nearbyDistanceKm;
  final Future<void> Function()? onEditTrail;
  final Future<void> Function()? onDeleteTrail;

  @override
  Widget build(BuildContext context) {
    final card = _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _BestMatchTrailCover(trail: trail),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trail.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _HomeColors.textFor(context),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        trail.locationLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _HomeColors.secondaryTextFor(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 5,
                        children: [
                          _TrailMeta(
                            icon: Icons.route_rounded,
                            label: trail.distanceLabel,
                          ),
                          if (nearbyDistanceKm != null &&
                              nearbyDistanceKm!.isFinite)
                            _TrailMeta(
                              icon: Icons.near_me_rounded,
                              label: nearbyDistanceKm! < 1
                                  ? '${(nearbyDistanceKm! * 1000).round()} m away'
                                  : '${nearbyDistanceKm!.toStringAsFixed(1)} km away',
                            ),
                          _TrailMeta(
                            icon: Icons.signal_cellular_alt_rounded,
                            label: trail.difficulty,
                          ),
                          _TrailMeta(
                            icon: CupertinoIcons.clock_fill,
                            label: trail.durationLabel,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFF59E0B),
                            size: 18,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            trail.ratingAverage.toStringAsFixed(1),
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: _HomeColors.textFor(context),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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

class _HomeSwipeActionBackground extends StatelessWidget {
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

class _BestMatchTrailCover extends StatelessWidget {
  const _BestMatchTrailCover({required this.trail});

  final Trail trail;

  @override
  Widget build(BuildContext context) {
    final fallbackColor = Color(trail.coverColorValue);
    final url = trail.coverImageUrls.isNotEmpty
        ? trail.coverImageUrls.first
        : '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 96,
        height: 96,
        child: url.trim().isEmpty
            ? _TrailCoverFallback(color: fallbackColor)
            : Image.network(
                url.trim(),
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return _TrailCoverFallback(color: fallbackColor);
                },
                errorBuilder: (context, error, stackTrace) {
                  return _TrailCoverFallback(color: fallbackColor);
                },
              ),
      ),
    );
  }
}

class _TrailCoverFallback extends StatelessWidget {
  const _TrailCoverFallback({required this.color});

  final Color color;

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

class _TrailMeta extends StatelessWidget {
  const _TrailMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _HomeColors.secondaryTextFor(context)),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _HomeColors.secondaryTextFor(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _BestMatchesLoading extends StatelessWidget {
  const _BestMatchesLoading();

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Loading trails...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _HomeColors.secondaryTextFor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartHikeActions extends StatelessWidget {
  const _StartHikeActions({
    required this.onStartHike,
    required this.onFindHike,
  });

  final VoidCallback onStartHike;
  final VoidCallback onFindHike;

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

class _UpcomingHikeCard extends StatelessWidget {
  const _UpcomingHikeCard({
    required this.plannedHike,
    required this.onContinuePreparation,
    required this.onOpenTrail,
  });

  final PlannedHike plannedHike;
  final VoidCallback onContinuePreparation;
  final VoidCallback onOpenTrail;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _Glyph(icon: Icons.event_available_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upcoming Hike',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: _HomeColors.secondaryTextFor(context),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                            ),
                      ),
                      Text(
                        plannedHike.trail.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _HomeColors.textFor(context),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'View trail',
                  onPressed: onOpenTrail,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoLine(
              label: 'Departure',
              value:
                  '${_formatDate(plannedHike.plannedStartTime)} | ${_formatTime(plannedHike.plannedStartTime)}',
            ),
            _InfoLine(
              label: 'Expected Return',
              value: _formatTime(plannedHike.expectedReturnTime),
            ),
            _InfoLine(
              label: 'Weather Preview',
              value: plannedHike.trail.weather.summary,
            ),
            _InfoLine(
              label: 'Emergency Contacts',
              value: plannedHike.emergencyContactsSelected
                  ? 'Configured'
                  : 'None selected',
            ),
            _InfoLine(
              label: 'Checklist',
              value:
                  '${plannedHike.checklistCompleted} / ${plannedHike.checklistTotal} Completed',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onContinuePreparation,
              icon: const Icon(Icons.task_alt_rounded),
              label: const Text('Continue Preparation'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreparationWarning extends StatelessWidget {
  const _PreparationWarning({
    required this.plannedHike,
    required this.missingItems,
    required this.onTap,
  });

  final PlannedHike plannedHike;
  final List<String> missingItems;
  final VoidCallback onTap;

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

class _HazardRow extends StatelessWidget {
  const _HazardRow({
    required this.trail,
    required this.hazard,
    required this.onTap,
  });

  final Trail trail;
  final TrailHazard hazard;
  final VoidCallback onTap;

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

class _PreparationReminderPage extends StatelessWidget {
  const _PreparationReminderPage({required this.plannedHike});

  final PlannedHike plannedHike;

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
                                  '${plannedHike.preparationPercent}% ready',
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
                            label: 'Expected return',
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
                  _SectionTitle(label: 'Needs Attention'),
                  const SizedBox(height: 8),
                  if (missingItems.isEmpty)
                    const _EmptyState(message: 'Everything looks ready.')
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
                  _SectionTitle(label: 'Already Ready'),
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

class _HazardDetailPage extends StatelessWidget {
  const _HazardDetailPage({required this.trail, required this.hazard});

  final Trail trail;
  final TrailHazard hazard;

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
                            value:
                                '${trail.distanceLabel} - ${trail.difficulty}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _SectionTitle(label: 'Recommended Action'),
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

class _ChecklistInsightRow extends StatelessWidget {
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

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Tooltip(
          message: 'Back',
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(36),
            onPressed: onBack,
            child: const _CircleIcon(icon: CupertinoIcons.chevron_back),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _HomeColors.textFor(context),
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _HomeColors.secondaryTextFor(context),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActiveHikeDashboard extends StatelessWidget {
  const _ActiveHikeDashboard({
    required this.activeHike,
    required this.currentPhoneNumber,
    required this.isVisible,
    required this.fallStillnessSnapshot,
    required this.onCheckIn,
    required this.onPinLocation,
    required this.onPingTeamMember,
    required this.onEndHike,
    required this.onCancelFallStillnessSos,
  });

  final ActiveHikeSession activeHike;
  final String currentPhoneNumber;
  final bool isVisible;
  final FallStillnessMonitorSnapshot fallStillnessSnapshot;
  final VoidCallback onCheckIn;
  final VoidCallback onPinLocation;
  final Future<TeamHikeSession?> Function(String phoneNumber) onPingTeamMember;
  final VoidCallback onEndHike;
  final VoidCallback onCancelFallStillnessSos;

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
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onCheckIn,
                icon: const Icon(Icons.verified_user_rounded),
                label: const Text('Check In Now'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPinLocation,
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Pin Location'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _SectionTitle(label: 'Safety Monitoring'),
        const SizedBox(height: 8),
        _MonitoringCard(
          activeHike: activeHike,
          fallStillnessSnapshot: fallStillnessSnapshot,
          onCancelFallStillnessSos: onCancelFallStillnessSos,
        ),
        const SizedBox(height: 22),
        _SectionTitle(label: 'Shared With'),
        const SizedBox(height: 8),
        _SharedWithCard(activeHike: activeHike),
        const SizedBox(height: 22),
        _SectionTitle(label: 'Team Snapshot'),
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

class _ActiveHeader extends StatelessWidget {
  const _ActiveHeader({required this.activeHike});

  final ActiveHikeSession activeHike;

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
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _HomeColors.textFor(context),
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
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

class _ActiveMetrics extends StatelessWidget {
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
                    label: 'Expected Return',
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

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.label, required this.value});

  final String label;
  final String value;

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

class _ElapsedMetricCell extends StatefulWidget {
  const _ElapsedMetricCell({required this.startedAt, required this.isVisible});

  final DateTime startedAt;
  final bool isVisible;

  @override
  State<_ElapsedMetricCell> createState() => _ElapsedMetricCellState();
}

class _ElapsedMetricCellState extends State<_ElapsedMetricCell>
    with WidgetsBindingObserver {
  Timer? _timer;
  AppLifecycleState _lifecycleState =
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;

  bool get _shouldTick {
    return widget.isVisible && _lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncTimer();
  }

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    return _MetricCell(
      label: 'Elapsed Time',
      value: _formatElapsed(DateTime.now().difference(widget.startedAt)),
    );
  }
}

class _ConnectionStatusCard extends StatelessWidget {
  const _ConnectionStatusCard({required this.queuedUpdates});

  final int queuedUpdates;

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

class _MiniMapCard extends StatelessWidget {
  const _MiniMapCard({
    required this.activeHike,
    required this.currentPhoneNumber,
  });

  final ActiveHikeSession activeHike;
  final String currentPhoneNumber;

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
            _InfoLine(
              label: 'Manual Pins',
              value: '${activeHike.manualPinLocations.length} saved',
            ),
          ],
        ),
      ),
    );
  }
}

class _MonitoringCard extends StatelessWidget {
  const _MonitoringCard({
    required this.activeHike,
    required this.fallStillnessSnapshot,
    required this.onCancelFallStillnessSos,
  });

  final ActiveHikeSession activeHike;
  final FallStillnessMonitorSnapshot fallStillnessSnapshot;
  final VoidCallback onCancelFallStillnessSos;

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
            label: 'Location Recording',
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
          _StatusRow(label: 'Check-Ins', value: '${activeHike.checkIns} saved'),
        ],
      ),
    );
  }

  String _stillnessCheckValue(FallStillnessMonitorSnapshot snapshot) {
    final seconds = snapshot.secondsRemaining;
    final suffix = snapshot.isBackpackTrapLikely ? ' extended' : '';
    if (seconds == null) {
      return 'Verifying$suffix';
    }
    return '$seconds sec$suffix';
  }

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

class _FallStillnessCountdownRow extends StatelessWidget {
  const _FallStillnessCountdownRow({
    required this.snapshot,
    required this.onCancel,
  });

  final FallStillnessMonitorSnapshot snapshot;
  final VoidCallback onCancel;

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

class _SharedWithCard extends StatelessWidget {
  const _SharedWithCard({required this.activeHike});

  final ActiveHikeSession activeHike;

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

class _TeamSnapshotCard extends StatefulWidget {
  const _TeamSnapshotCard({
    required this.activeHike,
    required this.currentPhoneNumber,
    required this.onPingTeamMember,
  });

  final ActiveHikeSession activeHike;
  final String currentPhoneNumber;
  final Future<TeamHikeSession?> Function(String phoneNumber) onPingTeamMember;

  @override
  State<_TeamSnapshotCard> createState() => _TeamSnapshotCardState();
}

class _TeamSnapshotCardState extends State<_TeamSnapshotCard> {
  String _pingingPhoneNumber = '';

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

  Future<void> _ping(TeamHikeParticipant participant) async {
    if (_pingingPhoneNumber.isNotEmpty || !participant.canBePinged) {
      return;
    }
    setState(() {
      _pingingPhoneNumber = participant.phoneNumber;
    });
    try {
      final updatedSession = await widget.onPingTeamMember(
        participant.phoneNumber,
      );
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
      if (mounted) {
        setState(() {
          _pingingPhoneNumber = '';
        });
      }
    }
  }
}

class _TeamParticipantRow extends StatelessWidget {
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
                child: isPinging
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Ping'),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

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

class _MyUpcomingHikesSection extends StatelessWidget {
  const _MyUpcomingHikesSection({
    required this.hikes,
    required this.phoneNumber,
    this.onTapHike,
  });

  final List<UpcomingHike> hikes;
  final String phoneNumber;
  final void Function(UpcomingHike)? onTapHike;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(label: 'My Upcoming Hike${hikes.length == 1 ? '' : 's'}'),
        const SizedBox(height: 8),
        for (final hike in hikes) ...[
          GestureDetector(
            onTap: onTapHike != null ? () => onTapHike!(hike) : null,
            child: _InsetGroup(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const _Glyph(icon: Icons.event_available_rounded),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hike.trailName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: _HomeColors.textFor(context),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                hike.startPointName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: _HomeColors.secondaryTextFor(
                                        context,
                                      ),
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: (hike.creatorPhone == phoneNumber)
                                ? _HomeColors.green.withValues(alpha: 0.12)
                                : _HomeColors.secondaryTextFor(
                                    context,
                                  ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            hike.creatorPhone == phoneNumber
                                ? 'Creator'
                                : 'Joined',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _InfoLine(
                      label: 'Departure',
                      value:
                          '${_formatDate(hike.departureTime)} | ${_formatTime(hike.departureTime)}',
                    ),
                    _InfoLine(
                      label: 'Expected Return',
                      value: _formatTime(hike.expectedReturnTime),
                    ),
                    _InfoLine(
                      label: 'Trail',
                      value:
                          '${hike.distanceKm.toStringAsFixed(1)} km · ${hike.difficulty} · ${[hike.area, hike.state, hike.country].where((part) => part.trim().isNotEmpty).join(', ')}',
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _HomeColors.secondaryTextFor(context),
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

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

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _HomeColors.surfaceFor(context),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: _HomeColors.green, size: 19),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, this.color = _HomeColors.green});

  final IconData icon;
  final Color color;

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

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});

  final Widget child;

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

class _HorizontalSeparator extends StatelessWidget {
  const _HorizontalSeparator();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.7,
      color: _HomeColors.separatorFor(context),
    );
  }
}

class _VerticalSeparator extends StatelessWidget {
  const _VerticalSeparator();

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

String _formatTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

String _formatElapsed(Duration elapsed) {
  final hours = elapsed.inHours.toString().padLeft(2, '0');
  final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

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

bool _samePhoneNumber(String first, String second) {
  final firstKey = first.replaceAll(RegExp(r'[^0-9]'), '');
  final secondKey = second.replaceAll(RegExp(r'[^0-9]'), '');
  return firstKey.isNotEmpty && firstKey == secondKey;
}

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

Color _severityColor(String severity) {
  return switch (severity.toLowerCase()) {
    'high' => _HomeColors.red,
    'moderate' => _HomeColors.orange,
    _ => _HomeColors.green,
  };
}

abstract final class _HomeColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color orange = Color(0xFFF59E0B);
  static const Color blue = Color(0xFF2563EB);
  static const Color red = Color(0xFFE11D48);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;
}

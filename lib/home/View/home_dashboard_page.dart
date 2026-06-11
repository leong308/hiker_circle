import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../trail/Model/trail_models.dart';
import '../Model/hike_session_models.dart';
import 'active_hike_map_page.dart';
import 'first_aid_guide_page.dart';
import 'gear_checklist_page.dart';

class HomeDashboardPage extends StatelessWidget {
  const HomeDashboardPage({
    super.key,
    required this.phoneNumber,
    required this.plannedHike,
    required this.activeHike,
    required this.onStartHike,
    required this.onJoinTeamHike,
    required this.onOpenEmergencyContacts,
    required this.onOpenTrailDetail,
    required this.onOpenSosTab,
    required this.onActiveHikeChanged,
    required this.onCheckInRequested,
    required this.onPinLocationRequested,
    required this.onEndHike,
  });

  final String phoneNumber;
  final PlannedHike plannedHike;
  final ActiveHikeSession? activeHike;
  final Future<void> Function(Trail trail) onStartHike;
  final VoidCallback onJoinTeamHike;
  final VoidCallback onOpenEmergencyContacts;
  final ValueChanged<Trail> onOpenTrailDetail;
  final VoidCallback onOpenSosTab;
  final ValueChanged<ActiveHikeSession> onActiveHikeChanged;
  final Future<ActiveHikeSession> Function(ActiveHikeSession activeHike)
  onCheckInRequested;
  final Future<ActiveHikeSession> Function(ActiveHikeSession activeHike)
  onPinLocationRequested;
  final VoidCallback onEndHike;

  @override
  Widget build(BuildContext context) {
    final active = activeHike;

    return ColoredBox(
      color: _HomeColors.background,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 112),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: active == null
                  ? _PreparationDashboard(
                      phoneNumber: phoneNumber,
                      plannedHike: plannedHike,
                      onStartHike: () => unawaited(
                        _confirmPreparationThenStart(
                          context,
                          plannedHike.trail,
                        ),
                      ),
                      onJoinTeamHike: onJoinTeamHike,
                      onOpenEmergencyContacts: onOpenEmergencyContacts,
                      onOpenTrailDetail: onOpenTrailDetail,
                      onOpenSosTab: onOpenSosTab,
                    )
                  : _ActiveHikeDashboard(
                      activeHike: active,
                      onOpenFullMap: () => _openFullMap(context, active),
                      onCheckIn: () => unawaited(_checkIn(context, active)),
                      onPinLocation: () =>
                          unawaited(_pinLocation(context, active)),
                      onEndHike: () => unawaited(_confirmEndHike(context)),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmPreparationThenStart(
    BuildContext context,
    Trail trail,
  ) async {
    final missingItems = plannedHike.missingPreparationItems;
    if (missingItems.isEmpty) {
      await onStartHike(trail);
      return;
    }

    final shouldStart = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('Your safety preparation is incomplete.'),
          content: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Missing:\n${missingItems.map((item) => '- $item').join('\n')}',
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Start Anyway'),
            ),
          ],
        );
      },
    );

    if (shouldStart == true && context.mounted) {
      await onStartHike(trail);
    }
  }

  void _openFullMap(BuildContext context, ActiveHikeSession active) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ActiveHikeMapPage(activeHike: active),
      ),
    );
  }

  Future<void> _checkIn(BuildContext context, ActiveHikeSession active) async {
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
  }

  Future<void> _pinLocation(
    BuildContext context,
    ActiveHikeSession active,
  ) async {
    final updatedHike = await onPinLocationRequested(active);
    onActiveHikeChanged(updatedHike);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Current location pinned locally.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
    required this.phoneNumber,
    required this.plannedHike,
    required this.onStartHike,
    required this.onJoinTeamHike,
    required this.onOpenEmergencyContacts,
    required this.onOpenTrailDetail,
    required this.onOpenSosTab,
  });

  final String phoneNumber;
  final PlannedHike plannedHike;
  final VoidCallback onStartHike;
  final VoidCallback onJoinTeamHike;
  final VoidCallback onOpenEmergencyContacts;
  final ValueChanged<Trail> onOpenTrailDetail;
  final VoidCallback onOpenSosTab;

  @override
  Widget build(BuildContext context) {
    final hazards = plannedHike.trail.hazards;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HomeHeader(phoneNumber: phoneNumber),
        const SizedBox(height: 16),
        _StartHikeActions(
          onStartHike: onStartHike,
          onJoinTeamHike: onJoinTeamHike,
        ),
        const SizedBox(height: 18),
        _UpcomingHikeCard(
          plannedHike: plannedHike,
          onContinuePreparation: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => GearChecklistPage(plannedHike: plannedHike),
            ),
          ),
          onOpenTrail: () => onOpenTrailDetail(plannedHike.trail),
        ),
        if (plannedHike.missingPreparationItems.isNotEmpty) ...[
          const SizedBox(height: 14),
          _PreparationWarning(
            missingItems: plannedHike.missingPreparationItems,
          ),
        ],
        const SizedBox(height: 22),
        _SectionTitle(label: 'Safety Tools'),
        const SizedBox(height: 8),
        _SafetyToolsGrid(
          plannedHike: plannedHike,
          onOpenFirstAid: () => unawaited(_openFirstAidGuide(context)),
          onOpenGearChecklist: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => GearChecklistPage(plannedHike: plannedHike),
            ),
          ),
          onOpenOfflineMaps: () => onOpenTrailDetail(plannedHike.trail),
          onOpenEmergencyContacts: onOpenEmergencyContacts,
        ),
        const SizedBox(height: 22),
        _SectionTitle(label: 'Recent Hazards Near Saved Trails'),
        const SizedBox(height: 8),
        if (hazards.isEmpty)
          const _EmptyState(message: 'No recent hazards near saved trails.')
        else
          for (final hazard in hazards) ...[
            _HazardRow(hazard: hazard),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Future<void> _openFirstAidGuide(BuildContext context) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) => const FirstAidGuidePage(),
      ),
    );

    if (result == 'sos') {
      onOpenSosTab();
    }
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.phoneNumber});

  final String phoneNumber;

  @override
  Widget build(BuildContext context) {
    final statusLine = phoneNumber.isEmpty
        ? 'Ready for your next safe hike?'
        : 'Ready for your next safe hike? Signed in as $phoneNumber';

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, Trail Friend',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: _HomeColors.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatDate(DateTime.now())} - $statusLine',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _HomeColors.secondaryText,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          Tooltip(
            message: 'Notifications',
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size.square(36),
              onPressed: () {},
              child: const _CircleIcon(icon: CupertinoIcons.bell_fill),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartHikeActions extends StatelessWidget {
  const _StartHikeActions({
    required this.onStartHike,
    required this.onJoinTeamHike,
  });

  final VoidCallback onStartHike;
  final VoidCallback onJoinTeamHike;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onStartHike,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start Hike'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onJoinTeamHike,
            icon: const Icon(Icons.group_add_rounded),
            label: const Text('Join Team Hike'),
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
                              color: _HomeColors.secondaryText,
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
                              color: _HomeColors.text,
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
              label: 'Offline Map',
              value: plannedHike.offlineMapDownloaded
                  ? 'Downloaded'
                  : 'Not Downloaded',
            ),
            _InfoLine(
              label: 'Emergency Contacts',
              value: plannedHike.emergencyContactsSelected
                  ? '2 Selected'
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
  const _PreparationWarning({required this.missingItems});

  final List<String> missingItems;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
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
                  Text(
                    'Preparation reminder',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _HomeColors.text,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final item in missingItems)
                    Text(
                      '- $item',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _HomeColors.secondaryText,
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

class _SafetyToolsGrid extends StatelessWidget {
  const _SafetyToolsGrid({
    required this.plannedHike,
    required this.onOpenFirstAid,
    required this.onOpenGearChecklist,
    required this.onOpenOfflineMaps,
    required this.onOpenEmergencyContacts,
  });

  final PlannedHike plannedHike;
  final VoidCallback onOpenFirstAid;
  final VoidCallback onOpenGearChecklist;
  final VoidCallback onOpenOfflineMaps;
  final VoidCallback onOpenEmergencyContacts;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.62,
      children: [
        _ToolTile(
          icon: Icons.medical_services_rounded,
          title: 'First-Aid Guide',
          onTap: onOpenFirstAid,
        ),
        _ToolTile(
          icon: Icons.checklist_rounded,
          title: 'Gear Checklist',
          onTap: onOpenGearChecklist,
        ),
        _ToolTile(
          icon: Icons.offline_bolt_rounded,
          title: 'Offline Maps',
          onTap: onOpenOfflineMaps,
        ),
        _ToolTile(
          icon: Icons.contact_phone_rounded,
          title: 'Emergency Contacts',
          onTap: onOpenEmergencyContacts,
        ),
      ],
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Glyph(icon: icon),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _HomeColors.text,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
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

class _HazardRow extends StatelessWidget {
  const _HazardRow({required this.hazard});

  final TrailHazard hazard;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const _Glyph(
              icon: Icons.report_problem_rounded,
              color: _HomeColors.orange,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${hazard.type} reported at ${hazard.locationLabel}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _HomeColors.text,
                  fontWeight: FontWeight.w600,
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

class _ActiveHikeDashboard extends StatelessWidget {
  const _ActiveHikeDashboard({
    required this.activeHike,
    required this.onOpenFullMap,
    required this.onCheckIn,
    required this.onPinLocation,
    required this.onEndHike,
  });

  final ActiveHikeSession activeHike;
  final VoidCallback onOpenFullMap;
  final VoidCallback onCheckIn;
  final VoidCallback onPinLocation;
  final VoidCallback onEndHike;

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(activeHike.startedAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActiveHeader(activeHike: activeHike),
        const SizedBox(height: 16),
        _ActiveMetrics(
          elapsed: elapsed,
          expectedReturn: activeHike.draft.expectedReturnTime,
          batteryLevel: activeHike.batteryLevel,
        ),
        const SizedBox(height: 14),
        _ConnectionStatusCard(queuedUpdates: activeHike.queuedUpdates),
        const SizedBox(height: 14),
        _MiniMapCard(activeHike: activeHike),
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
        _MonitoringCard(activeHike: activeHike),
        const SizedBox(height: 22),
        _SectionTitle(label: 'Shared With'),
        const SizedBox(height: 8),
        const _SharedWithCard(),
        const SizedBox(height: 22),
        _SectionTitle(label: 'Team Snapshot'),
        const SizedBox(height: 8),
        const _TeamSnapshotCard(),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: onOpenFullMap,
          icon: const Icon(Icons.map_rounded),
          label: const Text('Open Full Map'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onEndHike,
          icon: const Icon(Icons.stop_circle_rounded),
          label: const Text('End Hike Session'),
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
                  color: _HomeColors.text,
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
    required this.elapsed,
    required this.expectedReturn,
    required this.batteryLevel,
  });

  final Duration elapsed;
  final DateTime expectedReturn;
  final int batteryLevel;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: SizedBox(
        height: 74,
        child: Row(
          children: [
            Expanded(
              child: _MetricCell(
                label: 'Elapsed Time',
                value: _formatElapsed(elapsed),
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
              child: _MetricCell(label: 'Battery', value: '$batteryLevel%'),
            ),
          ],
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
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: _HomeColors.text,
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
            color: _HomeColors.secondaryText,
            letterSpacing: 0,
          ),
        ),
      ],
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
            const _Glyph(icon: Icons.cloud_off_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Connection: Offline - Recording Locally. Your trail and emergency data are being stored on this phone. $queuedUpdates location updates are waiting to sync.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _HomeColors.text,
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
  const _MiniMapCard({required this.activeHike});

  final ActiveHikeSession activeHike;

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
                child: CustomPaint(
                  painter: _MiniTrailPainter(
                    color: Color(activeHike.trail.coverColorValue),
                    manualPins: activeHike.manualPins,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                Expanded(
                  child: _InfoLine(label: 'Altitude', value: '321 m'),
                ),
                Expanded(
                  child: _InfoLine(label: 'Compass', value: 'NE'),
                ),
              ],
            ),
            const _InfoLine(
              label: 'Next Checkpoint',
              value: 'Summit Junction, 420 m ahead',
            ),
          ],
        ),
      ),
    );
  }
}

class _MonitoringCard extends StatelessWidget {
  const _MonitoringCard({required this.activeHike});

  final ActiveHikeSession activeHike;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Column(
        children: [
          const _StatusRow(label: 'Route Status', value: 'On Route'),
          const _HorizontalSeparator(),
          const _StatusRow(label: 'Fall Detection', value: 'Active'),
          const _HorizontalSeparator(),
          _StatusRow(
            label: 'Location Recording',
            value:
                'Every ${activeHike.draft.locationRecordingInterval.inMinutes} min',
          ),
          const _HorizontalSeparator(),
          _StatusRow(
            label: 'Queued Updates',
            value: '${activeHike.queuedUpdates} waiting to sync',
          ),
          const _HorizontalSeparator(),
          _StatusRow(label: 'Check-Ins', value: '${activeHike.checkIns} saved'),
        ],
      ),
    );
  }
}

class _SharedWithCard extends StatelessWidget {
  const _SharedWithCard();

  @override
  Widget build(BuildContext context) {
    return const _InsetGroup(
      child: Column(
        children: [
          _StatusRow(label: 'Mother', value: 'Last update: 8 minutes ago'),
          _HorizontalSeparator(),
          _StatusRow(label: 'Team Alpha', value: 'Offline updates pending'),
        ],
      ),
    );
  }
}

class _TeamSnapshotCard extends StatelessWidget {
  const _TeamSnapshotCard();

  @override
  Widget build(BuildContext context) {
    return const _InsetGroup(
      child: Column(
        children: [
          _StatusRow(label: 'Jason - Leader', value: '120 m ahead'),
          _HorizontalSeparator(),
          _StatusRow(label: 'Sarah', value: '85 m behind'),
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
                color: _HomeColors.text,
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
                color: _HomeColors.secondaryText,
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

class _MiniTrailPainter extends CustomPainter {
  const _MiniTrailPainter({required this.color, required this.manualPins});

  final Color color;
  final int manualPins;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = color.withValues(alpha: 0.12);
    final routePaint = Paint()
      ..color = _HomeColors.green
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final recordedPaint = Paint()
      ..color = _HomeColors.green.withValues(alpha: 0.32)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawRect(Offset.zero & size, background);

    final path = Path()
      ..moveTo(size.width * 0.18, size.height * 0.78)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.58,
        size.width * 0.42,
        size.height * 0.66,
        size.width * 0.52,
        size.height * 0.44,
      )
      ..cubicTo(
        size.width * 0.60,
        size.height * 0.24,
        size.width * 0.74,
        size.height * 0.40,
        size.width * 0.84,
        size.height * 0.18,
      );
    canvas.drawPath(path, recordedPaint);
    canvas.drawPath(path, routePaint);

    _drawMarker(
      canvas,
      Offset(size.width * 0.44, size.height * 0.55),
      _HomeColors.green,
    );
    _drawMarker(
      canvas,
      Offset(size.width * 0.66, size.height * 0.32),
      _HomeColors.orange,
    );
    _drawMarker(
      canvas,
      Offset(size.width * 0.84, size.height * 0.18),
      _HomeColors.blue,
    );

    for (var index = 0; index < manualPins; index++) {
      _drawMarker(
        canvas,
        Offset(size.width * (0.34 + index * 0.08), size.height * 0.62),
        _HomeColors.red,
      );
    }
  }

  void _drawMarker(Canvas canvas, Offset center, Color color) {
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    canvas.drawCircle(center, 8, fill);
    canvas.drawCircle(center, 8, stroke);
  }

  @override
  bool shouldRepaint(covariant _MiniTrailPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.manualPins != manualPins;
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
                color: _HomeColors.secondaryText,
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
                color: _HomeColors.text,
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
          color: _HomeColors.secondaryText,
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
              color: _HomeColors.secondaryText,
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
      decoration: const BoxDecoration(
        color: Colors.white,
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
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
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
    return const Divider(
      height: 1,
      thickness: 0.7,
      color: _HomeColors.separator,
    );
  }
}

class _VerticalSeparator extends StatelessWidget {
  const _VerticalSeparator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 32,
      child: VerticalDivider(
        width: 1,
        thickness: 0.7,
        color: _HomeColors.separator,
      ),
    );
  }
}

String _formatDate(DateTime dateTime) {
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
  return '${dateTime.day} ${months[dateTime.month - 1]} ${dateTime.year}';
}

String _formatTime(DateTime dateTime) {
  final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final period = dateTime.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

String _formatElapsed(Duration elapsed) {
  final hours = elapsed.inHours.toString().padLeft(2, '0');
  final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
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
}

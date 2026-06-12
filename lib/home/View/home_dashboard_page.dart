import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../trail/Model/trail_models.dart';
import '../Model/hike_session_models.dart';
import '../ModelView/fall_stillness_monitor.dart';
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
    required this.onTriggerManualSos,
    required this.onActiveHikeChanged,
    required this.onCheckInRequested,
    required this.onPinLocationRequested,
    required this.onEndHike,
    required this.fallStillnessSnapshot,
    required this.onCancelFallStillnessSos,
  });

  final String phoneNumber;
  final PlannedHike plannedHike;
  final ActiveHikeSession? activeHike;
  final Future<void> Function(Trail trail) onStartHike;
  final VoidCallback onJoinTeamHike;
  final VoidCallback onOpenEmergencyContacts;
  final ValueChanged<Trail> onOpenTrailDetail;
  final VoidCallback onOpenSosTab;
  final VoidCallback onTriggerManualSos;
  final ValueChanged<ActiveHikeSession> onActiveHikeChanged;
  final Future<ActiveHikeSession> Function(ActiveHikeSession activeHike)
  onCheckInRequested;
  final Future<ActiveHikeSession> Function(ActiveHikeSession activeHike)
  onPinLocationRequested;
  final VoidCallback onEndHike;
  final FallStillnessMonitorSnapshot fallStillnessSnapshot;
  final VoidCallback onCancelFallStillnessSos;

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
                      onOpenTrailDetail: onOpenTrailDetail,
                      onOpenSosTab: onOpenSosTab,
                      onTriggerManualSos: onTriggerManualSos,
                    )
                  : _ActiveHikeDashboard(
                      activeHike: active,
                      fallStillnessSnapshot: fallStillnessSnapshot,
                      onOpenFullMap: () => _openFullMap(context, active),
                      onCheckIn: () => unawaited(_checkIn(context, active)),
                      onPinLocation: () =>
                          unawaited(_pinLocation(context, active)),
                      onEndHike: () => unawaited(_confirmEndHike(context)),
                      onCancelFallStillnessSos: onCancelFallStillnessSos,
                      onTriggerManualSos: onTriggerManualSos,
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
    required this.onOpenTrailDetail,
    required this.onOpenSosTab,
    required this.onTriggerManualSos,
  });

  final String phoneNumber;
  final PlannedHike plannedHike;
  final VoidCallback onStartHike;
  final VoidCallback onJoinTeamHike;
  final ValueChanged<Trail> onOpenTrailDetail;
  final VoidCallback onOpenSosTab;
  final VoidCallback onTriggerManualSos;

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
        const SizedBox(height: 12),
        _EmergencySosCard(onTriggerManualSos: onTriggerManualSos),
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
          onOpenWeatherReadiness: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => _SafetyToolDetailPage(
                icon: Icons.thunderstorm_rounded,
                title: 'Weather Readiness',
                subtitle:
                    'Dummy trail weather checklist for deciding whether to go, delay, or turn back.',
                rows: const [
                  ('Rain window', '2:00 PM - 5:00 PM'),
                  ('Heat index', 'High after noon'),
                  ('Lightning risk', 'Watch ridges and exposed peaks'),
                  ('Decision', 'Start early and set a turn-back time'),
                ],
              ),
            ),
          ),
          onOpenSignalBeacon: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => _SafetyToolDetailPage(
                icon: Icons.cell_tower_rounded,
                title: 'Signal Beacon',
                subtitle:
                    'Dummy local signal plan for weak-network areas before the backend is connected.',
                rows: const [
                  ('Last known signal', 'Car park and ridge shoulder'),
                  ('Fallback action', 'Pin location every 30 minutes'),
                  ('Buddy prompt', 'Ask team to confirm at checkpoints'),
                  ('Offline note', 'Keep whistle and torch reachable'),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        _SectionTitle(label: 'Recent Hazards Near Saved Trails'),
        const SizedBox(height: 8),
        if (hazards.isEmpty)
          const _EmptyState(message: 'No recent hazards near saved trails.')
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

class _EmergencySosCard extends StatelessWidget {
  const _EmergencySosCard({required this.onTriggerManualSos});

  final VoidCallback onTriggerManualSos;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTriggerManualSos,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const _Glyph(icon: Icons.sos_rounded, color: _HomeColors.red),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Emergency SOS',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _HomeColors.text,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Tap for manual SOS, even when you are not in a hike.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _HomeColors.secondaryText,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _HomeColors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onTriggerManualSos,
                  child: const Text('SOS'),
                ),
              ],
            ),
          ),
        ),
      ),
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
                                    color: _HomeColors.text,
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
                          color: _HomeColors.secondaryText,
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
                const Icon(
                  CupertinoIcons.chevron_forward,
                  color: _HomeColors.secondaryText,
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

class _SafetyToolsGrid extends StatelessWidget {
  const _SafetyToolsGrid({
    required this.plannedHike,
    required this.onOpenFirstAid,
    required this.onOpenGearChecklist,
    required this.onOpenWeatherReadiness,
    required this.onOpenSignalBeacon,
  });

  final PlannedHike plannedHike;
  final VoidCallback onOpenFirstAid;
  final VoidCallback onOpenGearChecklist;
  final VoidCallback onOpenWeatherReadiness;
  final VoidCallback onOpenSignalBeacon;

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
          subtitle: 'Offline steps',
          onTap: onOpenFirstAid,
        ),
        _ToolTile(
          icon: Icons.checklist_rounded,
          title: 'Gear Checklist',
          subtitle:
              '${plannedHike.checklistCompleted}/${plannedHike.checklistTotal} ready',
          onTap: onOpenGearChecklist,
        ),
        _ToolTile(
          icon: Icons.thunderstorm_rounded,
          title: 'Weather Readiness',
          subtitle: '${plannedHike.trail.weather.rainProbability}% rain risk',
          onTap: onOpenWeatherReadiness,
        ),
        _ToolTile(
          icon: Icons.cell_tower_rounded,
          title: 'Signal Beacon',
          subtitle: 'Local fallback',
          onTap: onOpenSignalBeacon,
        ),
      ],
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
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
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _HomeColors.secondaryText,
                    fontWeight: FontWeight.w600,
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
                                    color: _HomeColors.text,
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
                          color: _HomeColors.secondaryText,
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
                          color: _HomeColors.text,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Reported ${_formatRelativeDate(hazard.reportedAt)} - Tap for route impact and advice',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _HomeColors.secondaryText,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  CupertinoIcons.chevron_forward,
                  color: _HomeColors.secondaryText,
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
      if (plannedHike.offlineMapDownloaded) 'Route files available',
      if (plannedHike.emergencyContactsSelected) 'SOS contact list ready',
      if (plannedHike.phoneBatteryLevel >= 60) 'Battery above 60%',
      if (plannedHike.liveLocationConfigured) 'Live sharing configured',
    ];

    return Scaffold(
      backgroundColor: _HomeColors.background,
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
                                        color: _HomeColors.text,
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
                            value: '${plannedHike.phoneBatteryLevel}%',
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

class _SafetyToolDetailPage extends StatelessWidget {
  const _SafetyToolDetailPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.rows,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _HomeColors.background,
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
                    title: title,
                    subtitle: 'Prototype safety tool',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Glyph(icon: icon),
                          const SizedBox(height: 12),
                          Text(
                            subtitle,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: _HomeColors.text,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 14),
                          for (final row in rows) ...[
                            _InfoLine(label: row.$1, value: row.$2),
                          ],
                        ],
                      ),
                    ),
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

class _HazardDetailPage extends StatelessWidget {
  const _HazardDetailPage({required this.trail, required this.hazard});

  final Trail trail;
  final TrailHazard hazard;

  @override
  Widget build(BuildContext context) {
    final severityColor = _severityColor(hazard.severity);

    return Scaffold(
      backgroundColor: _HomeColors.background,
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
                                        color: _HomeColors.text,
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
                                  color: _HomeColors.text,
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
                        'This is dummy UI for now. Later this can refresh hazard status from community reports and ranger updates.',
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
                      color: _HomeColors.text,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
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
                  color: _HomeColors.text,
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
                  color: _HomeColors.secondaryText,
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
    required this.fallStillnessSnapshot,
    required this.onOpenFullMap,
    required this.onCheckIn,
    required this.onPinLocation,
    required this.onEndHike,
    required this.onCancelFallStillnessSos,
    required this.onTriggerManualSos,
  });

  final ActiveHikeSession activeHike;
  final FallStillnessMonitorSnapshot fallStillnessSnapshot;
  final VoidCallback onOpenFullMap;
  final VoidCallback onCheckIn;
  final VoidCallback onPinLocation;
  final VoidCallback onEndHike;
  final VoidCallback onCancelFallStillnessSos;
  final VoidCallback onTriggerManualSos;

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
        _EmergencySosCard(onTriggerManualSos: onTriggerManualSos),
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
        _MonitoringCard(
          activeHike: activeHike,
          fallStillnessSnapshot: fallStillnessSnapshot,
          onCancelFallStillnessSos: onCancelFallStillnessSos,
        ),
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

    return _InsetGroup(
      child: Column(
        children: [
          const _StatusRow(label: 'Route Status', value: 'On Route'),
          const _HorizontalSeparator(),
          _StatusRow(label: 'Fall Detection', value: fallDetectionValue),
          const _HorizontalSeparator(),
          _StatusRow(
            label: 'Sensor Sensitivity',
            value:
                '${settings.sensitivityLabel} (${settings.sensorSensitivity.round()}/10)',
          ),
          const _HorizontalSeparator(),
          _StatusRow(
            label: 'Response Countdown',
            value: settings.responseCountdownDurationLabel,
          ),
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

  String _stillnessCheckValue(FallStillnessMonitorSnapshot snapshot) {
    final seconds = snapshot.secondsRemaining;
    final suffix = snapshot.isBackpackTrapLikely ? ' extended' : '';
    if (seconds == null) {
      return 'Verifying$suffix';
    }
    return '$seconds sec$suffix';
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
                  'Possible fall detected. SOS in $seconds seconds.',
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

    final totalDurationSeconds = settings.stillnessDuration.inSeconds;
    if (totalDurationSeconds <= 0) {
      return null;
    }

    return 1 - (remaining / totalDurationSeconds).clamp(0, 1).toDouble();
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
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
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

String _formatRelativeDate(DateTime dateTime) {
  final now = DateTime.now();
  final difference = now.difference(dateTime);
  if (difference.inDays <= 0) {
    return 'today';
  }
  if (difference.inDays == 1) {
    return 'yesterday';
  }
  return '${difference.inDays} days ago';
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
}

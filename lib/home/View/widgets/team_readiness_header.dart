import 'package:flutter/material.dart';
import '../../../core/widgets/page_header_style.dart';

/// The readiness header keeps the team map at the top left and Close at the right.
class TeamReadinessHeader extends StatelessWidget {
  /// Binds map navigation without changing readiness or closing its parent flow.
  const TeamReadinessHeader({
    super.key,
    required this.onMap,
    required this.onClose,
  });
  final VoidCallback onMap, onClose;

  /// Reuses the app's header typography and circular controls.
  @override
  Widget build(BuildContext context) => PageHeader(
    title: 'Team Hike Launch',
    foregroundColor: Colors.white,
    leading: PageHeaderAction(
      key: const ValueKey('view-team-readiness-map'),
      tooltip: 'View team locations',
      icon: Icons.map_outlined,
      onPressed: onMap,
      color: Colors.white,
      surface: Colors.white.withValues(alpha: .12),
    ),
    actions: [
      PageHeaderAction(
        tooltip: 'Close',
        icon: Icons.close_rounded,
        onPressed: onClose,
        color: Colors.white,
        surface: Colors.white.withValues(alpha: .12),
      ),
    ],
  );
}

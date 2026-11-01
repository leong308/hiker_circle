// HikerBottomNavBar renders the app's shared destination controls and selected state.
import 'package:flutter/material.dart';
import 'package:liquid_glass_bar/liquid_glass_bar.dart';
import '../Model/hiker_bottom_nav_destination.dart';
export '../Model/hiker_bottom_nav_destination.dart';

/// Displays the hiker bottom nav bar.
class HikerBottomNavBar extends StatelessWidget {
  /// Creates hiker bottom nav bar.
  const HikerBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    this.destinations = standardDestinations,
    this.queuedSosCount = 0,
  }) : assert(destinations.length >= 2),
       assert(currentIndex >= 0),
       assert(currentIndex < destinations.length);

  static const List<HikerBottomNavDestination> standardDestinations = [
    HikerBottomNavDestination(label: 'Home', icon: Icons.home_rounded),
    HikerBottomNavDestination(label: 'SOS', icon: Icons.sos_rounded),
    HikerBottomNavDestination(label: 'Circle', icon: Icons.groups_2_rounded),
    HikerBottomNavDestination(label: 'Profile', icon: Icons.person_rounded),
  ];

  /// Reuses the same role-dependent destinations at startup and after live account updates.
  static List<HikerBottomNavDestination> destinationsForRole(bool isAdmin) => [
    ...standardDestinations,
    if (isAdmin)
      const HikerBottomNavDestination(
        label: 'Admin',
        icon: Icons.admin_panel_settings_rounded,
      ),
  ];

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<HikerBottomNavDestination> destinations;
  final int queuedSosCount;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isDark
        ? const Color(0xFF5FAF78)
        : const Color(0xFF3F8F5E);
    final inactiveColor = isDark
        ? const Color(0xFFA8B8AE)
        : const Color(0xFF5F7568);
    final glassColor = isDark
        ? const Color(0xFF141C17).withValues(alpha: 0.9)
        : const Color(0xFFEAF7EE).withValues(alpha: 0.86);

    return LiquidGlassBar(
      items: [
        for (var index = 0; index < destinations.length; index++)
          LiquidGlassBarItem(
            iconData: destinations[index].icon,
            iconWidget: destinations[index].label == 'SOS' && queuedSosCount > 0
                ? Semantics(
                    label: '$queuedSosCount queued SOS alerts',
                    child: Badge.count(
                      count: queuedSosCount,
                      backgroundColor: Theme.of(context).colorScheme.error,
                      textColor: Theme.of(context).colorScheme.onError,
                      child: Icon(
                        destinations[index].icon,
                        size: 23,
                        color: currentIndex == index
                            ? activeColor
                            : inactiveColor,
                      ),
                    ),
                  )
                : null,
            label: destinations[index].label,
          ),
      ],
      currentIndex: currentIndex,
      onTap: onDestinationSelected,
      style: LiquidGlassBarStyle(
        activeColor: activeColor,
        inactiveColor: inactiveColor,
        borderRadius: 34,
        height: 57,
        iconSize: 23,
        selectedIconScale: 1.15,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
        liquidGlassSettings: LiquidGlassSettings(
          thickness: 20,
          blur: 18,
          glassColor: glassColor,
          lightIntensity: isDark ? 0.32 : 0.7,
          refractiveIndex: 1.45,
        ),
      ),
    );
  }
}

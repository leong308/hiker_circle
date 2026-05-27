import 'package:flutter/material.dart';
import 'package:liquid_glass_bar/liquid_glass_bar.dart';

class HikerBottomNavDestination {
  const HikerBottomNavDestination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class HikerBottomNavBar extends StatelessWidget {
  const HikerBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    this.destinations = standardDestinations,
  }) : assert(destinations.length >= 2),
       assert(currentIndex >= 0),
       assert(currentIndex < destinations.length);

  static const List<HikerBottomNavDestination> standardDestinations = [
    HikerBottomNavDestination(label: 'Home', icon: Icons.home_rounded),
    HikerBottomNavDestination(label: 'Trail', icon: Icons.map_rounded),
    HikerBottomNavDestination(label: 'SOS', icon: Icons.sos_rounded),
    HikerBottomNavDestination(label: 'Plan', icon: Icons.event_note_rounded),
    HikerBottomNavDestination(label: 'Me', icon: Icons.person_rounded),
  ];

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<HikerBottomNavDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassBar(
      items: [
        for (final destination in destinations)
          LiquidGlassBarItem(
            iconData: destination.icon,
            label: destination.label,
          ),
      ],
      currentIndex: currentIndex,
      onTap: onDestinationSelected,
      style: LiquidGlassBarStyle(
        activeColor: const Color(0xFF3F8F5E),
        inactiveColor: const Color(0xFF5F7568),
        borderRadius: 34,
        height: 57,
        iconSize: 23,
        selectedIconScale: 1.15,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
        liquidGlassSettings: LiquidGlassSettings(
          thickness: 20,
          blur: 18,
          glassColor: const Color(0xFFEAF7EE).withValues(alpha: 0.86),
          lightIntensity: 0.7,
          refractiveIndex: 1.45,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../Model/active_hike_map_mode.dart';

/// Switches the live map viewpoint without starting route playback.
class ActiveHikeMapModeButton extends StatelessWidget {
  /// Creates the session map switch using the current mode.
  const ActiveHikeMapModeButton({
    super.key,
    required this.mode,
    required this.onPressed,
  });

  final ActiveHikeMapMode mode;
  final VoidCallback onPressed;

  /// Labels the action with the view that the next tap will open.
  @override
  Widget build(BuildContext context) {
    final firstPerson = mode == ActiveHikeMapMode.firstPerson;
    return Tooltip(
      message: firstPerson ? 'Switch to normal map' : 'Switch to FPV terrain',
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(firstPerson ? Icons.map_outlined : Icons.view_in_ar_rounded),
        label: Text(firstPerson ? 'Map' : 'FPV'),
      ),
    );
  }
}

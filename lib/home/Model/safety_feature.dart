import 'package:flutter/material.dart';

class SafetyFeature {
  const SafetyFeature({
    required this.icon,
    required this.title,
    required this.accent,
  });

  const SafetyFeature.planHike()
    : icon = Icons.route,
      title = 'Plan hike',
      accent = const Color(0xFF3F8F5E);

  const SafetyFeature.emergencyContacts()
    : icon = Icons.contact_phone,
      title = 'Emergency contacts',
      accent = const Color(0xFF5CA975);

  const SafetyFeature.sosMode()
    : icon = Icons.sos,
      title = 'SOS mode',
      accent = const Color(0xFF2F7D50);

  const SafetyFeature.teamSession()
    : icon = Icons.groups_2,
      title = 'Team session',
      accent = const Color(0xFF78BD8B);

  final IconData icon;
  final String title;
  final Color accent;
}

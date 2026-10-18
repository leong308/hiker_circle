// MeProfile, MeStat and MeSection describe the profile overview and account action groups.
import 'package:flutter/material.dart';

class MeProfile {
  const MeProfile({
    required this.displayName,
    required this.handle,
    required this.phoneNumber,
    required this.status,
    this.photoURL,
  });

  final String displayName;
  final String handle;
  final String phoneNumber;
  final String status;
  final String? photoURL;
}

class MeStat {
  const MeStat({required this.label, required this.value});

  final String label;
  final String value;
}

class MeActionItem {
  const MeActionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

class MeSection {
  const MeSection({required this.title, required this.items});

  final String title;
  final List<MeActionItem> items;
}

// MeProfile, MeStat and MeSection describe the profile overview and account action groups.
import 'package:flutter/material.dart';

/// Represents me profile.
class MeProfile {
  /// Creates me profile.
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

/// Represents me stat.
class MeStat {
  /// Creates me stat.
  const MeStat({required this.label, required this.value});

  final String label;
  final String value;
}

/// Represents me action item.
class MeActionItem {
  /// Creates me action item.
  const MeActionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

/// Represents me section.
class MeSection {
  /// Creates me section.
  const MeSection({required this.title, required this.items});

  final String title;
  final List<MeActionItem> items;
}

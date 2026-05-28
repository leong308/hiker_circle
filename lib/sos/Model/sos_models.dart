import 'package:flutter/material.dart';

class SosDashboard {
  const SosDashboard({
    required this.contactsReady,
    required this.contactsRequired,
    required this.authorityStatus,
    required this.queueStatus,
    required this.liveSharingStatus,
  });

  final int contactsReady;
  final int contactsRequired;
  final String authorityStatus;
  final String queueStatus;
  final String liveSharingStatus;
}

class EmergencyContact {
  const EmergencyContact({
    required this.name,
    required this.phoneNumber,
    required this.relationship,
  });

  final String name;
  final String phoneNumber;
  final String relationship;
}

class SosMetric {
  const SosMetric({required this.label, required this.value});

  final String label;
  final String value;
}

class SosActionDetail {
  const SosActionDetail({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class SosFeatureItem {
  const SosFeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailing;
}

class SosFeatureSection {
  const SosFeatureSection({required this.title, required this.items});

  final String title;
  final List<SosFeatureItem> items;
}

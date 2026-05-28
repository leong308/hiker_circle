import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../Model/sos_models.dart';

class SosRepository {
  const SosRepository();

  SosDashboard loadDashboard() {
    return const SosDashboard(
      contactsReady: 2,
      contactsRequired: 5,
      authorityStatus: 'Ready to cache when online',
      queueStatus: 'No unsent alerts',
      liveSharingStatus: 'Family sharing off',
    );
  }

  List<EmergencyContact> loadEmergencyContacts() {
    return const [
      EmergencyContact(
        name: 'Primary Contact',
        phoneNumber: '+6012 345 6789',
        relationship: 'Family',
      ),
      EmergencyContact(
        name: 'Trail Buddy',
        phoneNumber: '+6017 234 5678',
        relationship: 'Friend',
      ),
    ];
  }

  List<SosMetric> loadMetrics() {
    return const [
      SosMetric(label: 'Contacts', value: '2/3'),
      SosMetric(label: 'Queued', value: '0'),
      SosMetric(label: 'Live', value: 'Off'),
    ];
  }

  List<SosActionDetail> loadManualSosDetails() {
    return const [
      SosActionDetail(icon: CupertinoIcons.timer, label: '10s cancel'),
      SosActionDetail(icon: Icons.flash_on_rounded, label: 'Flash alert'),
      SosActionDetail(icon: Icons.volume_up_rounded, label: 'Loud alarm'),
      SosActionDetail(
        icon: Icons.location_on_rounded,
        label: 'Latest location',
      ),
      SosActionDetail(
        icon: Icons.battery_charging_full_rounded,
        label: 'Battery',
      ),
      SosActionDetail(icon: Icons.route_rounded, label: 'Last trail'),
    ];
  }

  List<SosFeatureSection> loadSections() {
    return const [
      SosFeatureSection(
        title: 'Queueing',
        items: [
          SosFeatureItem(
            icon: Icons.outbox_rounded,
            title: 'Offline alert queue',
            subtitle:
                'Unsent alerts stay queued and retry when network returns',
            trailing: 'Auto',
          ),
          SosFeatureItem(
            icon: Icons.my_location_rounded,
            title: 'Newest location refresh',
            subtitle:
                'Queued SOS messages attach the latest available location',
          ),
          SosFeatureItem(
            icon: Icons.network_check_rounded,
            title: 'Coverage estimation',
            subtitle: 'Network loss records can build local coverage estimates',
          ),
        ],
      ),
      SosFeatureSection(
        title: 'Live Location Sharing',
        items: [
          SosFeatureItem(
            icon: Icons.family_restroom_rounded,
            title: 'Family members',
            subtitle: 'Choose trusted people who can follow your live location',
            trailing: 'Choose',
          ),
        ],
      ),
      SosFeatureSection(
        title: 'Fall Then Stillness Detection',
        items: [
          SosFeatureItem(
            icon: Icons.sensors_rounded,
            title: 'Impact and stillness check',
            subtitle: 'Detect a sudden fall and watch for no movement after',
          ),
          SosFeatureItem(
            icon: Icons.notifications_active_rounded,
            title: 'Manual check-in alert',
            subtitle: 'Sound indicator asks the user to confirm false alarms',
          ),
          SosFeatureItem(
            icon: Icons.hourglass_bottom_rounded,
            title: 'SOS escalation timer',
            subtitle:
                'Trigger SOS if there is no response within the timeframe',
          ),
        ],
      ),
    ];
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../Model/sos_models.dart';

class SosRepository {
  const SosRepository();

  SosDashboard loadDashboard() {
    return const SosDashboard(
      contactsReady: 0,
      contactsRequired: 3,
      authorityStatus: 'Ready to cache when online',
      queueStatus: 'No unsent alerts',
      liveSharingStatus: 'Family sharing off',
    );
  }

  List<EmergencyContact> loadEmergencyContacts() {
    return const [];
  }

  List<SosMetric> loadMetrics() {
    return const [
      SosMetric(label: 'Contacts', value: '0/3'),
      SosMetric(label: 'Queued', value: '0'),
      SosMetric(label: 'Live', value: 'Off'),
    ];
  }

  List<SosActionDetail> loadManualSosDetails() {
    return const [
      SosActionDetail(icon: CupertinoIcons.timer, label: '10s cancel'),
      SosActionDetail(icon: Icons.alarm_rounded, label: 'Alarm volume'),
      SosActionDetail(icon: Icons.flash_on_rounded, label: 'SOS flash'),
      SosActionDetail(icon: Icons.location_on_rounded, label: 'GPS link'),
      SosActionDetail(icon: Icons.chat_bubble_rounded, label: 'WhatsApp alert'),
      SosActionDetail(icon: Icons.contacts_rounded, label: 'Saved contacts'),
      SosActionDetail(icon: Icons.cloud_done_rounded, label: 'Firebase log'),
    ];
  }

  List<SosFeatureSection> loadSections() {
    return const [
      SosFeatureSection(
        title: 'SOS Trigger Log',
        items: [
          SosFeatureItem(
            icon: Icons.chat_bubble_rounded,
            title: 'WhatsApp dispatch',
            subtitle: 'Send SOS messages to saved emergency contacts',
            trailing: 'Live',
          ),
          SosFeatureItem(
            icon: Icons.cloud_done_rounded,
            title: 'Firebase alert log',
            subtitle: 'Save every SOS with trigger time and GPS snapshot',
          ),
          SosFeatureItem(
            icon: Icons.fact_check_rounded,
            title: 'SOS trigger log',
            subtitle: 'Track sent, partial, failed, or missing-contact alerts',
          ),
        ],
      ),
      SosFeatureSection(
        title: 'Emergency Contacts',
        items: [
          SosFeatureItem(
            icon: Icons.contacts_rounded,
            title: 'Saved contact list',
            subtitle: 'Manual and duress SOS use your saved contact list',
          ),
        ],
      ),
      SosFeatureSection(
        title: 'Duress',
        items: [
          SosFeatureItem(
            icon: Icons.pan_tool_alt_rounded,
            title: 'Silent long press',
            subtitle: 'Hold the duress card to send without a countdown',
          ),
          SosFeatureItem(
            icon: Icons.visibility_off_rounded,
            title: 'Discreet message',
            subtitle: 'Ask contacts not to call if that could raise risk',
          ),
        ],
      ),
    ];
  }
}

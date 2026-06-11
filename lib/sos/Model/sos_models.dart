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

  factory EmergencyContact.fromFirestore(Map<String, dynamic> data) {
    return EmergencyContact(
      name: _stringFrom(data['name']),
      phoneNumber: _stringFrom(data['phoneNumber']),
      relationship: _stringFrom(data['relationship']),
    );
  }

  final String name;
  final String phoneNumber;
  final String relationship;

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phoneNumber': phoneNumber,
      'relationship': relationship,
    };
  }

  static String _stringFrom(Object? value) {
    if (value is String) {
      return value;
    }
    return '';
  }
}

enum SosAlertMode {
  manual,
  duress;

  String get firestoreValue {
    switch (this) {
      case SosAlertMode.manual:
        return 'manual';
      case SosAlertMode.duress:
        return 'duress';
    }
  }

  String get label {
    switch (this) {
      case SosAlertMode.manual:
        return 'Manual SOS';
      case SosAlertMode.duress:
        return 'Duress SOS';
    }
  }
}

enum SosAlertStatus {
  sent,
  partial,
  failed,
  noContacts;

  String get firestoreValue {
    switch (this) {
      case SosAlertStatus.sent:
        return 'sent';
      case SosAlertStatus.partial:
        return 'partial';
      case SosAlertStatus.failed:
        return 'failed';
      case SosAlertStatus.noContacts:
        return 'no_contacts';
    }
  }

  String get label {
    switch (this) {
      case SosAlertStatus.sent:
        return 'Sent';
      case SosAlertStatus.partial:
        return 'Partially sent';
      case SosAlertStatus.failed:
        return 'Failed';
      case SosAlertStatus.noContacts:
        return 'No contacts';
    }
  }
}

class SosContactDispatch {
  const SosContactDispatch({
    required this.contactName,
    required this.phoneNumber,
    required this.wasSent,
    this.errorMessage,
  });

  final String contactName;
  final String phoneNumber;
  final bool wasSent;
  final String? errorMessage;

  Map<String, dynamic> toFirestore() {
    return {
      'contactName': contactName,
      'phoneNumber': phoneNumber,
      'wasSent': wasSent,
      if (errorMessage case final errorMessage?) 'errorMessage': errorMessage,
    };
  }
}

class SosTriggerLocation {
  const SosTriggerLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.capturedAt,
  });

  factory SosTriggerLocation.fromPlatform(Map<Object?, Object?> data) {
    final latitude = data['latitude'];
    final longitude = data['longitude'];
    final accuracyMeters = data['accuracyMeters'];
    final capturedAtLocal = data['capturedAtLocal'];
    final capturedAtMillis = data['capturedAtMillis'];

    return SosTriggerLocation(
      latitude: latitude is num ? latitude.toDouble() : 0,
      longitude: longitude is num ? longitude.toDouble() : 0,
      accuracyMeters: accuracyMeters is num ? accuracyMeters.toDouble() : null,
      capturedAt: capturedAtMillis is num
          ? DateTime.fromMillisecondsSinceEpoch(
              capturedAtMillis.toInt(),
              isUtc: true,
            )
          : capturedAtLocal is String
          ? DateTime.tryParse(capturedAtLocal)
          : null,
    );
  }

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime? capturedAt;

  String get universalMapLink {
    return 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';
  }

  Map<String, dynamic> toFirestore() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'universalMapLink': universalMapLink,
      if (accuracyMeters case final accuracyMeters?)
        'accuracyMeters': accuracyMeters,
      if (capturedAt case final capturedAt?)
        'capturedAtLocal': capturedAt.toUtc().toIso8601String(),
    };
  }
}

class SosAlert {
  const SosAlert({
    required this.id,
    required this.mode,
    required this.status,
    required this.triggeredAt,
    required this.triggeredByPhoneNumber,
    required this.contactCount,
    required this.sentCount,
    required this.failedCount,
    required this.dispatches,
    required this.message,
    this.triggerLocation,
  });

  final String id;
  final SosAlertMode mode;
  final SosAlertStatus status;
  final DateTime triggeredAt;
  final String triggeredByPhoneNumber;
  final int contactCount;
  final int sentCount;
  final int failedCount;
  final List<SosContactDispatch> dispatches;
  final String message;
  final SosTriggerLocation? triggerLocation;

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'mode': mode.firestoreValue,
      'status': status.firestoreValue,
      'triggeredAtLocal': triggeredAt.toUtc().toIso8601String(),
      'triggeredByPhoneNumber': triggeredByPhoneNumber,
      'contactCount': contactCount,
      'sentCount': sentCount,
      'failedCount': failedCount,
      'dispatches': dispatches
          .map((dispatch) => dispatch.toFirestore())
          .toList(),
      'message': message,
      if (triggerLocation case final triggerLocation?)
        'triggerLocation': triggerLocation.toFirestore(),
    };
  }
}

class SosAlertResult {
  const SosAlertResult({required this.alert});

  final SosAlert alert;

  bool get hasSuccessfulDispatch => alert.sentCount > 0;
  bool get hasFailedDispatch => alert.failedCount > 0;
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

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
  medical,
  fallStillness,
  duress;

  String get firestoreValue {
    switch (this) {
      case SosAlertMode.manual:
        return 'manual';
      case SosAlertMode.medical:
        return 'medical';
      case SosAlertMode.fallStillness:
        return 'fall_stillness';
      case SosAlertMode.duress:
        return 'duress';
    }
  }

  String get label {
    switch (this) {
      case SosAlertMode.manual:
        return 'Manual SOS';
      case SosAlertMode.medical:
        return 'Medical Help';
      case SosAlertMode.fallStillness:
        return 'Fall SOS';
      case SosAlertMode.duress:
        return 'Duress SOS';
    }
  }

  bool get usesLoudEmergencyPattern {
    switch (this) {
      case SosAlertMode.manual:
      case SosAlertMode.medical:
      case SosAlertMode.fallStillness:
        return true;
      case SosAlertMode.duress:
        return false;
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

abstract final class SosAlertMessageComposer {
  static const String defaultCustomNote =
      'I need urgent help during my hike. Please call me now. If I do not answer, use the map link below and contact local emergency services.';

  static String compose({
    required SosAlertMode mode,
    required String phoneNumber,
    required DateTime triggeredAt,
    required SosTriggerLocation? triggerLocation,
    String? customNote,
  }) {
    final locationLine = triggerLocation == null
        ? 'Location: unavailable'
        : 'Location: ${triggerLocation.universalMapLink}';
    final accuracyLine = triggerLocation?.accuracyMeters == null
        ? null
        : 'GPS accuracy: ${triggerLocation!.accuracyMeters!.round()} m';
    final note = _normalizedNote(customNote);

    return [
      'HikerCircle SOS ALERT',
      'Type: ${mode.label}',
      'Hiker: $phoneNumber',
      'Triggered: ${triggeredAt.toUtc().toIso8601String()}',
      'Reason: ${reasonFor(mode)}',
      locationLine,
      if (accuracyLine != null) accuracyLine,
      'Message: $note',
      'Action: Call the hiker first. If there is no response, share this alert and map link with emergency responders.',
    ].join('\n');
  }

  static String reasonFor(SosAlertMode mode) {
    switch (mode) {
      case SosAlertMode.manual:
        return 'Manual emergency SOS was confirmed in the app.';
      case SosAlertMode.medical:
        return 'Medical help request was triggered from HikerCircle.';
      case SosAlertMode.fallStillness:
        return 'Possible fall followed by stillness was detected and escalated.';
      case SosAlertMode.duress:
        return 'Silent duress SOS was triggered. Avoid calling if that may increase risk.';
    }
  }

  static String _normalizedNote(String? customNote) {
    final trimmed = customNote?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return defaultCustomNote;
    }
    return trimmed;
  }
}

class SosLocalAlertFeedback {
  const SosLocalAlertFeedback({
    required this.alarmRequested,
    required this.flashlightRequested,
    required this.spokenPromptRequested,
    required this.updatedAt,
    required this.statusLabel,
    this.errorMessage,
  });

  factory SosLocalAlertFeedback.started({required DateTime updatedAt}) {
    return SosLocalAlertFeedback(
      alarmRequested: true,
      flashlightRequested: true,
      spokenPromptRequested: false,
      updatedAt: updatedAt,
      statusLabel: 'Alarm and flashlight requested',
    );
  }

  factory SosLocalAlertFeedback.stopped({required DateTime updatedAt}) {
    return SosLocalAlertFeedback(
      alarmRequested: false,
      flashlightRequested: false,
      spokenPromptRequested: false,
      updatedAt: updatedAt,
      statusLabel: 'Local SOS stopped',
    );
  }

  factory SosLocalAlertFeedback.failed({
    required DateTime updatedAt,
    required String errorMessage,
  }) {
    return SosLocalAlertFeedback(
      alarmRequested: false,
      flashlightRequested: false,
      spokenPromptRequested: false,
      updatedAt: updatedAt,
      statusLabel: 'Local SOS feedback failed',
      errorMessage: errorMessage,
    );
  }

  final bool alarmRequested;
  final bool flashlightRequested;
  final bool spokenPromptRequested;
  final DateTime updatedAt;
  final String statusLabel;
  final String? errorMessage;
}

class SosOutputVolumeStatus {
  const SosOutputVolumeStatus({
    required this.platform,
    required this.isIos,
    required this.canMeasureOutputVolume,
    required this.outputVolume,
    required this.minimumRequiredVolume,
  });

  factory SosOutputVolumeStatus.fromPlatform(
    Map<Object?, Object?>? data, {
    required double defaultMinimumRequiredVolume,
  }) {
    final volume = _normalizedDouble(data?['outputVolume']);
    final minimumRequiredVolume =
        _normalizedDouble(data?['minimumRequiredVolume']) ??
        defaultMinimumRequiredVolume.clamp(0.0, 1.0).toDouble();
    final platform = data?['platform'] is String
        ? data!['platform'] as String
        : 'unknown';
    final isIos = data?['isIos'] == true || platform == 'ios';

    return SosOutputVolumeStatus(
      platform: platform,
      isIos: isIos,
      canMeasureOutputVolume:
          data?['canMeasureOutputVolume'] == true && volume != null,
      outputVolume: volume,
      minimumRequiredVolume: minimumRequiredVolume,
    );
  }

  factory SosOutputVolumeStatus.unsupported({
    required double minimumRequiredVolume,
  }) {
    return SosOutputVolumeStatus(
      platform: 'unknown',
      isIos: false,
      canMeasureOutputVolume: false,
      outputVolume: null,
      minimumRequiredVolume: minimumRequiredVolume.clamp(0.0, 1.0).toDouble(),
    );
  }

  final String platform;
  final bool isIos;
  final bool canMeasureOutputVolume;
  final double? outputVolume;
  final double minimumRequiredVolume;

  bool get shouldGateForIos {
    return isIos && canMeasureOutputVolume;
  }

  bool get isAudible {
    if (!shouldGateForIos) {
      return true;
    }
    final volume = outputVolume;
    return volume != null && volume >= minimumRequiredVolume;
  }

  double get displayOutputVolume {
    final volume = outputVolume;
    if (volume == null) {
      return 0;
    }
    if (!isIos) {
      return volume;
    }

    // iOS hardware/media volume is exposed in coarse device steps. Rounding to
    // 16 steps makes the percentage match the native volume HUD more closely.
    return ((volume * 16).round() / 16).clamp(0.0, 1.0).toDouble();
  }

  int get outputVolumePercent {
    return (displayOutputVolume * 100).round();
  }

  int get minimumRequiredPercent {
    return ((minimumRequiredVolume * 100).clamp(0.0, 100.0)).round();
  }

  static double? _normalizedDouble(Object? value) {
    if (value is! num) {
      return null;
    }
    return value.toDouble().clamp(0.0, 1.0).toDouble();
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

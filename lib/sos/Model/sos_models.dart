// SOS models describe contacts, trigger locations, queued alerts, dispatch results and safety settings.
import 'package:flutter/material.dart';

import '../../app/Model/preferred_time_zone.dart';
import '../../home/Model/hike_shirt_color.dart';

/// Represents sos dashboard.
class SosDashboard {
  /// Creates sos dashboard.
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

/// Represents emergency contact.
class EmergencyContact {
  /// Creates emergency contact.
  const EmergencyContact({
    required this.name,
    required this.phoneNumber,
    required this.relationship,
  });

  /// Creates emergency contact from a cloud record.
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

  /// Serializes this value for cloud storage.
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phoneNumber': phoneNumber,
      'relationship': relationship,
    };
  }

  /// Computes string from.
  static String _stringFrom(Object? value) {
    if (value is String) {
      return value;
    }
    return '';
  }
}

/// Represents emergency contact candidate.
class EmergencyContactCandidate {
  /// Creates emergency contact candidate.
  const EmergencyContactCandidate({
    required this.fullName,
    required this.phoneNumbers,
    this.firstName,
    this.lastName,
  });

  /// Creates emergency contact candidate using from platform.
  factory EmergencyContactCandidate.fromPlatform(Map<Object?, Object?> data) {
    final phones = data['phoneNumbers'];
    return EmergencyContactCandidate(
      firstName: _stringFrom(data['firstName']),
      lastName: _stringFrom(data['lastName']),
      fullName: _stringFrom(data['fullName']) ?? '',
      phoneNumbers: phones is Iterable
          ? phones
                .whereType<String>()
                .where((phone) => phone.trim().isNotEmpty)
                .toList()
          : const [],
    );
  }

  final String? firstName;
  final String? lastName;
  final String fullName;
  final List<String> phoneNumbers;

  /// Returns display name.
  String get displayName {
    final combined = [
      firstName?.trim(),
      lastName?.trim(),
    ].whereType<String>().where((part) => part.isNotEmpty).join(' ');
    if (combined.isNotEmpty) {
      return combined;
    }
    return fullName.trim();
  }

  /// Returns primary phone number.
  String get primaryPhoneNumber {
    return phoneNumbers.isEmpty ? '' : phoneNumbers.first;
  }

  /// Computes string from.
  static String? _stringFrom(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }
}

/// Defines the sos alert mode choices.
enum SosAlertMode {
  manual,
  medical,
  fallStillness,
  prolongedStillness,
  duress;

  /// Returns firestore value.
  String get firestoreValue {
    switch (this) {
      case SosAlertMode.manual:
        return 'manual';
      case SosAlertMode.medical:
        return 'medical';
      case SosAlertMode.fallStillness:
        return 'fall_stillness';
      case SosAlertMode.prolongedStillness:
        return 'prolonged_stillness';
      case SosAlertMode.duress:
        return 'duress';
    }
  }

  /// Returns label.
  String get label {
    switch (this) {
      case SosAlertMode.manual:
        return 'Manual SOS';
      case SosAlertMode.medical:
        return 'Medical Help';
      case SosAlertMode.fallStillness:
        return 'Fall SOS';
      case SosAlertMode.prolongedStillness:
        return 'Prolonged-Stillness SOS';
      case SosAlertMode.duress:
        return 'Duress SOS';
    }
  }

  /// Returns uses loud emergency pattern.
  bool get usesLoudEmergencyPattern {
    switch (this) {
      case SosAlertMode.manual:
      case SosAlertMode.medical:
      case SosAlertMode.fallStillness:
      case SosAlertMode.prolongedStillness:
        return true;
      case SosAlertMode.duress:
        return false;
    }
  }
}

/// Defines the sos alert trigger source choices.
enum SosAlertTriggerSource {
  mobilePhone('mobile_phone'),
  emergencyButton('emergency_button'),
  automaticDetection('automatic_detection');

  /// Creates this model.
  const SosAlertTriggerSource(this.firestoreValue);

  final String firestoreValue;

  /// Creates from firestore.
  static SosAlertTriggerSource fromFirestore(Object? value) {
    return SosAlertTriggerSource.values.firstWhere(
      (source) => source.firestoreValue == value,
      orElse: () => SosAlertTriggerSource.mobilePhone,
    );
  }
}

/// Defines the sos alert status choices.
enum SosAlertStatus {
  sent,
  partial,
  unconfirmed,
  failed,
  queued,
  noContacts;

  /// Returns firestore value.
  String get firestoreValue {
    switch (this) {
      case SosAlertStatus.sent:
        return 'sent';
      case SosAlertStatus.partial:
        return 'partial';
      case SosAlertStatus.unconfirmed:
        return 'unconfirmed';
      case SosAlertStatus.failed:
        return 'failed';
      case SosAlertStatus.queued:
        return 'queued';
      case SosAlertStatus.noContacts:
        return 'no_contacts';
    }
  }

  /// Returns label.
  String get label {
    switch (this) {
      case SosAlertStatus.sent:
        return 'Sent';
      case SosAlertStatus.partial:
        return 'Contacts confirmed';
      case SosAlertStatus.unconfirmed:
        return 'Unconfirmed';
      case SosAlertStatus.failed:
        return 'Failed';
      case SosAlertStatus.queued:
        return 'Queued';
      case SosAlertStatus.noContacts:
        return 'No contacts';
    }
  }
}

/// Represents sos contact dispatch.
class SosContactDispatch {
  /// Creates sos contact dispatch.
  const SosContactDispatch({
    required this.contactName,
    required this.phoneNumber,
    required this.wasSent,
    this.retryable = true,
    this.errorMessage,
    this.providerMessageId,
    this.confirmationStatus = '',
    this.contactIndex = 0,
    this.updatedAtMillis = 0,
    this.nextRetryAtMillis = 0,
  });

  /// Creates sos contact dispatch from a cloud record.
  factory SosContactDispatch.fromFirestore(Map<String, dynamic> data) {
    return SosContactDispatch(
      contactName: _stringFrom(data['contactName']),
      phoneNumber: _stringFrom(data['phoneNumber']),
      wasSent: data['wasSent'] == true,
      confirmationStatus: data['confirmationStatus'] as String? ?? '',
      contactIndex: (data['contactIndex'] as num?)?.toInt() ?? 0,
      updatedAtMillis: (data['updatedAtMillis'] as num?)?.toInt() ?? 0,
      nextRetryAtMillis: (data['nextRetryAtMillis'] as num?)?.toInt() ?? 0,
      retryable: data['retryable'] != false,
      errorMessage: data['errorMessage'] is String
          ? data['errorMessage'] as String
          : null,
      providerMessageId: data['providerMessageId'] is String
          ? data['providerMessageId'] as String
          : null,
    );
  }

  final String contactName;
  final String phoneNumber;
  final bool wasSent;
  final bool retryable;
  final String? errorMessage;
  final String? providerMessageId;
  final String confirmationStatus;
  final int contactIndex, updatedAtMillis, nextRetryAtMillis;

  /// Unknown provider acceptance remains separate from a contact that definitely failed.
  bool get isUnconfirmed => confirmationStatus == 'unconfirmed';

  /// A fresh server attempt is still inside its acknowledgement window.
  bool get isConfirming => confirmationStatus == 'sending';

  /// Exposes an explicit contact result without implying the recipient read the message.
  String get confirmationLabel => wasSent
      ? 'Confirmed'
      : isUnconfirmed
      ? 'Unconfirmed'
      : isConfirming
      ? 'Confirming…'
      : retryable
      ? 'Failed · retry scheduled'
      : 'Failed';

  /// Serializes this value for cloud storage.
  Map<String, dynamic> toFirestore() {
    return {
      'contactName': contactName,
      'phoneNumber': phoneNumber,
      'wasSent': wasSent,
      'confirmationStatus': confirmationStatus,
      'contactIndex': contactIndex,
      'updatedAtMillis': updatedAtMillis,
      'nextRetryAtMillis': nextRetryAtMillis,
      'retryable': retryable,
      if (errorMessage case final errorMessage?) 'errorMessage': errorMessage,
      if (providerMessageId case final providerMessageId?)
        'providerMessageId': providerMessageId,
    };
  }

  /// Computes string from.
  static String _stringFrom(Object? value) {
    if (value is String) {
      return value;
    }
    return '';
  }
}

/// Represents sos trigger location.
class SosTriggerLocation {
  /// Creates sos trigger location.
  const SosTriggerLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.capturedAt,
  });

  /// Creates sos trigger location using from platform.
  factory SosTriggerLocation.fromPlatform(Map<Object?, Object?> data) {
    return SosTriggerLocation(
      latitude: _coordinateFrom(data['latitude']) ?? double.nan,
      longitude: _coordinateFrom(data['longitude']) ?? double.nan,
      accuracyMeters: _accuracyFrom(data['accuracyMeters']),
      capturedAt: _dateFrom(
        localValue: data['capturedAtLocal'],
        millisValue: data['capturedAtMillis'],
      ),
    );
  }

  /// Creates sos trigger location from a cloud record.
  factory SosTriggerLocation.fromFirestore(Map<String, dynamic> data) {
    return SosTriggerLocation(
      latitude: _coordinateFrom(data['latitude']) ?? double.nan,
      longitude: _coordinateFrom(data['longitude']) ?? double.nan,
      accuracyMeters: _accuracyFrom(data['accuracyMeters']),
      capturedAt: _dateFrom(localValue: data['capturedAtLocal']),
    );
  }

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime? capturedAt;

  /// Returns has valid position.
  bool get hasValidPosition =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  /// Returns universal map link.
  String get universalMapLink {
    return 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';
  }

  /// Serializes this value for cloud storage.
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

  /// Computes coordinate from.
  static double? _coordinateFrom(Object? value) {
    if (value is! num || !value.isFinite) {
      return null;
    }
    return value.toDouble();
  }

  /// Computes accuracy from.
  static double? _accuracyFrom(Object? value) {
    if (value is! num || !value.isFinite || value < 0) {
      return null;
    }
    return value.toDouble();
  }

  /// Computes date from.
  static DateTime? _dateFrom({Object? localValue, Object? millisValue}) {
    if (millisValue is num && millisValue.isFinite) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(
          millisValue.toInt(),
          isUtc: true,
        );
      } on ArgumentError {
        // Fall through to the ISO timestamp when native data is out of range.
      }
    }
    return localValue is String ? DateTime.tryParse(localValue) : null;
  }
}

/// Build emergency message text from the trigger, available location and selected time zone.
abstract final class SosAlertMessageComposer {
  static const String defaultCustomNote =
      'I need urgent help during my hike. Please call me now. If I do not answer, use the map link below and contact local emergency services.';
  static const String defaultDuressCustomNote =
      'I may be under pressure and cannot speak safely. Please monitor my location discreetly and contact local emergency services if I stop responding.';

  /// Computes default custom note for.
  static String defaultCustomNoteFor(SosAlertMode mode) =>
      mode == SosAlertMode.duress ? defaultDuressCustomNote : defaultCustomNote;

  /// Computes compose.
  static String compose({
    required SosAlertMode mode,
    required String phoneNumber,
    required DateTime triggeredAt,
    required SosTriggerLocation? triggerLocation,
    String? customNote,
    SosAlertTriggerSource triggerSource = SosAlertTriggerSource.mobilePhone,
    String preferredTimeZone = PreferredTimeZone.fallbackId,
    HikeShirtColor? shirtColor,
  }) {
    final validTriggerLocation = triggerLocation?.hasValidPosition == true
        ? triggerLocation
        : null;
    final locationLine = validTriggerLocation == null
        ? 'Location unavailable'
        : validTriggerLocation.universalMapLink;
    final accuracy = validTriggerLocation?.accuracyMeters;
    final accuracyLine = accuracy == null || !accuracy.isFinite || accuracy < 0
        ? null
        : 'Estimated accuracy: within ${accuracy.round()} m';
    final note = _normalizedNote(mode, customNote);

    return [
      '🚨 *HikerCircle SOS Alert*',
      '',
      '📞 *Hiker*\n$phoneNumber',
      '',
      '🕒 *Triggered*\n${PreferredTimeZone.formatInstant(triggeredAt, preferredTimeZone)}',
      '',
      '⚠️ *Reason*\n${reasonFor(mode, triggerSource: triggerSource)}',
      '',
      if (shirtColor != null) ...['👕 *Shirt colour*\n${shirtColor.label}', ''],
      '📍 *Location*\n$locationLine',
      if (accuracyLine != null) accuracyLine,
      '',
      "💬 *Hiker's message*\n$note",
      '',
      if (mode == SosAlertMode.duress)
        '✅ *What to do*\nDo not call if that may increase danger. Discreetly share this alert and location with emergency responders.'
      else
        '✅ *What to do*\nCall the hiker first. If there is no response, share this alert and map link with emergency responders.',
    ].join('\n');
  }

  /// Computes reason for.
  static String reasonFor(
    SosAlertMode mode, {
    SosAlertTriggerSource triggerSource = SosAlertTriggerSource.mobilePhone,
  }) {
    switch (mode) {
      case SosAlertMode.manual:
        return triggerSource == SosAlertTriggerSource.emergencyButton
            ? 'User triggered SOS through an emergency button.'
            : 'User triggered SOS through mobile phone.';
      case SosAlertMode.medical:
        return 'Medical help request was triggered from HikerCircle.';
      case SosAlertMode.fallStillness:
        return 'Possible fall followed by stillness was detected and escalated.';
      case SosAlertMode.prolongedStillness:
        return 'Location and phone movement remained still beyond the selected safe rest time.';
      case SosAlertMode.duress:
        return 'Silent duress SOS was triggered. Avoid calling if that may increase risk.';
    }
  }

  /// Computes normalized note.
  static String _normalizedNote(SosAlertMode mode, String? customNote) {
    final trimmed = customNote?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return defaultCustomNoteFor(mode);
    }
    return trimmed;
  }
}

/// Represents sos local alert feedback.
class SosLocalAlertFeedback {
  /// Creates sos local alert feedback.
  const SosLocalAlertFeedback({
    required this.alarmRequested,
    required this.flashlightRequested,
    required this.spokenPromptRequested,
    required this.updatedAt,
    required this.statusLabel,
    this.errorMessage,
  });

  /// Creates sos local alert feedback using started.
  factory SosLocalAlertFeedback.started({required DateTime updatedAt}) {
    return SosLocalAlertFeedback(
      alarmRequested: true,
      flashlightRequested: true,
      spokenPromptRequested: false,
      updatedAt: updatedAt,
      statusLabel: 'Alarm and flashlight requested',
    );
  }

  /// Creates sos local alert feedback using stopped.
  factory SosLocalAlertFeedback.stopped({required DateTime updatedAt}) {
    return SosLocalAlertFeedback(
      alarmRequested: false,
      flashlightRequested: false,
      spokenPromptRequested: false,
      updatedAt: updatedAt,
      statusLabel: 'Local SOS stopped',
    );
  }

  /// Creates sos local alert feedback using failed.
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

/// Represents sos output volume status.
class SosOutputVolumeStatus {
  /// Creates sos output volume status.
  const SosOutputVolumeStatus({
    required this.platform,
    required this.isIos,
    required this.canMeasureOutputVolume,
    required this.outputVolume,
    required this.minimumRequiredVolume,
  });

  /// Creates sos output volume status using from platform.
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

  /// Creates sos output volume status using unsupported.
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

  /// Returns should gate for ios.
  bool get shouldGateForIos {
    return isIos && canMeasureOutputVolume;
  }

  /// Returns is audible.
  bool get isAudible {
    if (!shouldGateForIos) {
      return true;
    }
    final volume = outputVolume;
    return volume != null && volume >= minimumRequiredVolume;
  }

  /// Returns display output volume.
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

  /// Returns output volume percent.
  int get outputVolumePercent {
    return (displayOutputVolume * 100).round();
  }

  /// Returns minimum required percent.
  int get minimumRequiredPercent {
    return ((minimumRequiredVolume * 100).clamp(0.0, 100.0)).round();
  }

  /// Computes normalized double.
  static double? _normalizedDouble(Object? value) {
    if (value is! num || !value.isFinite) {
      return null;
    }
    return value.toDouble().clamp(0.0, 1.0).toDouble();
  }
}

/// Represents sos alert.
class SosAlert {
  /// Creates sos alert.
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
    this.triggerSource = SosAlertTriggerSource.mobilePhone,
    this.shirtColor,
  });

  /// Creates sos alert from a cloud record.
  factory SosAlert.fromFirestore(Map<String, dynamic> data) {
    final dispatches = data['dispatches'];
    final triggerLocation = data['triggerLocation'];
    final parsedTriggerLocation = triggerLocation is Map
        ? SosTriggerLocation.fromFirestore(
            Map<String, dynamic>.from(triggerLocation),
          )
        : null;
    return SosAlert(
      id: _stringFrom(data['id']),
      mode: _modeFrom(data['mode']),
      status: _statusFrom(data['status']),
      triggeredAt:
          DateTime.tryParse(_stringFrom(data['triggeredAtLocal'])) ??
          DateTime.now().toUtc(),
      triggeredByPhoneNumber: _stringFrom(data['triggeredByPhoneNumber']),
      contactCount: _intFrom(data['contactCount']),
      sentCount: _intFrom(data['sentCount']),
      failedCount: _intFrom(data['failedCount']),
      dispatches: dispatches is Iterable
          ? dispatches
                .whereType<Map>()
                .map(
                  (dispatch) => SosContactDispatch.fromFirestore(
                    Map<String, dynamic>.from(dispatch),
                  ),
                )
                .toList()
          : const [],
      message: _stringFrom(data['message']),
      triggerSource: SosAlertTriggerSource.fromFirestore(data['triggerSource']),
      shirtColor: HikeShirtColor.fromName(data['shirtColor']),
      triggerLocation: parsedTriggerLocation?.hasValidPosition == true
          ? parsedTriggerLocation
          : null,
    );
  }

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
  final SosAlertTriggerSource triggerSource;
  final HikeShirtColor? shirtColor;

  /// A count replaces the ambiguous Partial label for mixed contact results.
  String get confirmationLabel => status == SosAlertStatus.unconfirmed
      ? 'Unconfirmed · $sentCount of $contactCount contacts confirmed'
      : '$sentCount of $contactCount contacts confirmed';

  /// Counts unknown delivery outcomes independently of known failures.
  int get unconfirmedCount => dispatches.where((p) => p.isUnconfirmed).length;

  /// Serializes this value for cloud storage.
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
      'triggerSource': triggerSource.firestoreValue,
      if (shirtColor != null) 'shirtColor': shirtColor!.name,
      if (triggerLocation case final triggerLocation?)
        'triggerLocation': triggerLocation.toFirestore(),
    };
  }

  /// Computes mode from.
  static SosAlertMode _modeFrom(Object? value) {
    if (value is String) {
      for (final mode in SosAlertMode.values) {
        if (mode.firestoreValue == value) {
          return mode;
        }
      }
    }
    return SosAlertMode.manual;
  }

  /// Computes status from.
  static SosAlertStatus _statusFrom(Object? value) {
    if (value is String) {
      for (final status in SosAlertStatus.values) {
        if (status.firestoreValue == value) {
          return status;
        }
      }
    }
    return SosAlertStatus.failed;
  }

  /// Computes string from.
  static String _stringFrom(Object? value) {
    if (value is String) {
      return value;
    }
    return '';
  }

  /// Computes int from.
  static int _intFrom(Object? value) {
    if (value is num && value.isFinite) {
      return value.toInt();
    }
    return 0;
  }
}

/// Represents sos alert result.
class SosAlertResult {
  /// Creates sos alert result.
  const SosAlertResult({
    required this.alert,
    this.queuedForRetry = false,
    this.queuedAlertCount = 0,
  });

  final SosAlert alert;
  final bool queuedForRetry;
  final int queuedAlertCount;

  /// Returns has successful dispatch.
  bool get hasSuccessfulDispatch => alert.sentCount > 0;

  /// Returns has failed dispatch.
  bool get hasFailedDispatch => alert.failedCount > 0;
}

/// Represents sos queued dispatch.
class SosQueuedDispatch {
  /// Creates sos queued dispatch.
  const SosQueuedDispatch({
    required this.id,
    required this.mode,
    required this.triggeredAt,
    required this.createdAt,
    required this.sendStatus,
    required this.retryCount,
    required this.contactCount,
    required this.pendingContactCount,
    required this.lastError,
    required this.message,
    this.alertId = '',
    this.triggerLocation,
  });

  final int id;
  final String alertId;
  final SosAlertMode mode;
  final DateTime triggeredAt;
  final DateTime createdAt;
  final String sendStatus;
  final int retryCount;
  final int contactCount;
  final int pendingContactCount;
  final String lastError;
  final String message;
  final SosTriggerLocation? triggerLocation;
}

/// Represents sos metric.
class SosMetric {
  /// Creates sos metric.
  const SosMetric({required this.label, required this.value});

  final String label;
  final String value;
}

/// Represents sos feature item.
class SosFeatureItem {
  /// Creates sos feature item.
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

/// Represents sos feature section.
class SosFeatureSection {
  /// Creates sos feature section.
  const SosFeatureSection({required this.title, required this.items});

  final String title;
  final List<SosFeatureItem> items;
}

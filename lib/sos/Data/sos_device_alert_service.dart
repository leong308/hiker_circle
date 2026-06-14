import 'package:flutter/services.dart';

import '../Model/sos_models.dart';

class SosDeviceAlertService {
  const SosDeviceAlertService();

  static const String sosAlarmAsset = 'assets/audios/sos_alarm.mp3';
  static const String medicalAlarmAsset = 'assets/audios/med_alarm.mp3';
  static const double minimumAudibleOutputVolume = 0.55;
  static const MethodChannel _channel = MethodChannel(
    'hiker_circle/sos_device_alerts',
  );

  Future<void> startManualSosPattern({
    String alarmAsset = sosAlarmAsset,
  }) async {
    await _channel.invokeMethod<void>('startManualSosPattern', {
      'alarmAsset': alarmAsset,
    });
  }

  Future<void> startSosPatternForMode(SosAlertMode mode) async {
    await startManualSosPattern(alarmAsset: alarmAssetForMode(mode));
  }

  Future<void> startSirenOnlyForMode(SosAlertMode mode) async {
    await _channel.invokeMethod<void>('startSirenOnly', {
      'alarmAsset': alarmAssetForMode(mode),
    });
  }

  String alarmAssetForMode(SosAlertMode mode) {
    return switch (mode) {
      SosAlertMode.medical => medicalAlarmAsset,
      _ => sosAlarmAsset,
    };
  }

  Future<void> stopManualSosPattern() async {
    await _channel.invokeMethod<void>('stopManualSosPattern');
  }

  Future<void> startFlashlightPattern() async {
    await _channel.invokeMethod<void>('startFlashlightPattern');
  }

  Future<void> stopFlashlightPattern() async {
    await _channel.invokeMethod<void>('stopFlashlightPattern');
  }

  Future<void> startFallStillnessCountdownVibration() async {
    try {
      await _channel.invokeMethod<void>('startFallStillnessCountdownVibration');
    } on MissingPluginException {
      await HapticFeedback.vibrate();
    }
  }

  Future<void> stopFallStillnessCountdownVibration() async {
    try {
      await _channel.invokeMethod<void>('stopFallStillnessCountdownVibration');
    } on MissingPluginException {
      // Optional native helper. The fallback haptic call is one-shot only.
    }
  }

  Future<int?> getBatteryLevel() async {
    try {
      final batteryLevel = await _channel.invokeMethod<int>('getBatteryLevel');
      if (batteryLevel == null) {
        return null;
      }
      return batteryLevel.clamp(0, 100).toInt();
    } on MissingPluginException {
      return null;
    }
  }

  Future<List<EmergencyContactCandidate>> loadDeviceContacts() async {
    try {
      final rawContacts = await _channel.invokeListMethod<Object?>(
        'getDeviceContacts',
      );
      if (rawContacts == null) {
        return const [];
      }

      return rawContacts
          .whereType<Map<Object?, Object?>>()
          .map(EmergencyContactCandidate.fromPlatform)
          .where(
            (contact) =>
                contact.displayName.isNotEmpty &&
                contact.phoneNumbers.isNotEmpty,
          )
          .toList();
    } on MissingPluginException {
      return const [];
    }
  }

  Future<void> beginOutputVolumeMonitoring() async {
    try {
      await _channel.invokeMethod<void>('beginOutputVolumeMonitoring');
    } on MissingPluginException {
      // Optional native helper. Platforms without it can still return volume.
    }
  }

  Future<void> endOutputVolumeMonitoring() async {
    try {
      await _channel.invokeMethod<void>('endOutputVolumeMonitoring');
    } on MissingPluginException {
      // Optional native helper.
    }
  }

  Future<void> speakFallStillnessPrompt({required String message}) async {
    await _channel.invokeMethod<void>('speakFallStillnessPrompt', {
      'message': message,
    });
  }

  Future<void> stopSpokenPrompt() async {
    await _channel.invokeMethod<void>('stopSpokenPrompt');
  }

  Future<SosOutputVolumeStatus> getOutputVolumeStatus({
    double minimumRequiredVolume = minimumAudibleOutputVolume,
  }) async {
    try {
      final volumeData = await _channel.invokeMapMethod<Object?, Object?>(
        'getOutputVolumeStatus',
        {'minimumRequiredVolume': minimumRequiredVolume},
      );
      return SosOutputVolumeStatus.fromPlatform(
        volumeData,
        defaultMinimumRequiredVolume: minimumRequiredVolume,
      );
    } on MissingPluginException {
      return SosOutputVolumeStatus.unsupported(
        minimumRequiredVolume: minimumRequiredVolume,
      );
    }
  }

  Future<SosTriggerLocation?> getCurrentTriggerLocation({
    bool allowLastKnown = false,
  }) async {
    final locationData = await _channel.invokeMapMethod<Object?, Object?>(
      'getCurrentTriggerLocation',
      {'allowLastKnown': allowLastKnown},
    );
    if (locationData == null) {
      return null;
    }

    return SosTriggerLocation.fromPlatform(locationData);
  }

  Future<void> setPreciseLocationEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setPreciseLocationEnabled', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Platforms without the native helper will use their default accuracy.
    }
  }

  Future<void> shareText({
    required String subject,
    required String text,
  }) async {
    await _channel.invokeMethod<void>('shareText', {
      'subject': subject,
      'text': text,
    });
  }
}

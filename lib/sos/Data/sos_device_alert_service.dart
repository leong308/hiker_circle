// SosDeviceAlertService bridges native location, speech, sound, vibration and emergency device controls.
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

  Future<void> stopManualSosPattern({bool strict = false}) =>
      _stopNativeOutput('stopManualSosPattern', strict: strict);

  Future<void> startFlashlightPattern() async {
    await _channel.invokeMethod<void>('startFlashlightPattern');
  }

  Future<void> stopFlashlightPattern() async {
    try {
      await _channel.invokeMethod<void>('stopFlashlightPattern');
    } on MissingPluginException {
      // Optional native cleanup.
    } on PlatformException {
      // Cleanup is best-effort when the native activity is already stopping.
    }
  }

  Future<void> startFallStillnessCountdownVibration() async {
    try {
      await _channel.invokeMethod<void>('startFallStillnessCountdownVibration');
    } on MissingPluginException {
      await HapticFeedback.vibrate();
    }
  }

  Future<void> stopFallStillnessCountdownVibration({bool strict = false}) =>
      _stopNativeOutput('stopFallStillnessCountdownVibration', strict: strict);

  /// Explicit slide cancellation must report failure and release its busy state
  /// if native cleanup stalls. Other lifecycle callers retain best-effort stops.
  Future<void> _stopNativeOutput(String method, {required bool strict}) async {
    try {
      final operation = _channel.invokeMethod<void>(method);
      if (strict) {
        await operation.timeout(const Duration(seconds: 4));
      } else {
        await operation;
      }
    } on MissingPluginException {
      // Desktop/web do not provide the optional hardware outputs.
    } on PlatformException {
      if (strict) rethrow;
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
    } on PlatformException {
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
    } on PlatformException {
      // Volume monitoring is advisory and must never block emergency actions.
    }
  }

  Future<void> endOutputVolumeMonitoring() async {
    try {
      await _channel.invokeMethod<void>('endOutputVolumeMonitoring');
    } on MissingPluginException {
      // Optional native helper.
    } on PlatformException {
      // Optional native cleanup.
    }
  }

  Future<void> speakFallStillnessPrompt({required String message}) async {
    await _channel.invokeMethod<void>('speakFallStillnessPrompt', {
      'message': message,
    });
  }

  /// Completes when the native utterance finishes, rather than when it is queued.
  Future<bool> speakHikePrecaution({
    required String requestId,
    required String message,
  }) async =>
      await _channel.invokeMethod<bool>('speakHikePrecaution', {
        'requestId': requestId,
        'message': message,
      }) ??
      false;

  /// Stop only this routine warning; never cancel a newer SOS voice prompt.
  Future<void> stopHikePrecaution(String requestId) async {
    await _channel.invokeMethod<void>('stopHikePrecaution', {
      'requestId': requestId,
    });
  }

  Future<void> stopSpokenPrompt({bool strict = false}) =>
      _stopNativeOutput('stopSpokenPrompt', strict: strict);

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
    } on PlatformException {
      return SosOutputVolumeStatus.unsupported(
        minimumRequiredVolume: minimumRequiredVolume,
      );
    }
  }

  Future<SosTriggerLocation?> getCurrentTriggerLocation({
    bool allowLastKnown = false,
    bool requirePrecise = false,
  }) async {
    final locationData = await _channel.invokeMapMethod<Object?, Object?>(
      'getCurrentTriggerLocation',
      {'allowLastKnown': allowLastKnown, 'requirePrecise': requirePrecise},
    );
    if (locationData == null) {
      return null;
    }

    final location = SosTriggerLocation.fromPlatform(locationData);
    return location.hasValidPosition ? location : null;
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

  /// Keep ordinary text sharing unchanged; hike cards use a separate native
  /// action with a cached PNG and temporary read access for the receiving app.
  Future<void> shareHike({
    required String subject,
    required String text,
    Uint8List? routeImage,
  }) async {
    if (routeImage == null || routeImage.isEmpty) {
      return shareText(subject: subject, text: text);
    }
    await _channel.invokeMethod<void>('shareHike', {
      'subject': subject,
      'text': text,
      'image': routeImage,
    });
  }
}

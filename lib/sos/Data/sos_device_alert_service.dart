import 'package:flutter/services.dart';

import '../Model/sos_models.dart';

class SosDeviceAlertService {
  const SosDeviceAlertService();

  static const MethodChannel _channel = MethodChannel(
    'hiker_circle/sos_device_alerts',
  );

  Future<void> startManualSosPattern() async {
    await _channel.invokeMethod<void>('startManualSosPattern');
  }

  Future<void> stopManualSosPattern() async {
    await _channel.invokeMethod<void>('stopManualSosPattern');
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

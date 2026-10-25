import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _securityChannel = MethodChannel('hiker_circle/security');

/// Keep Flutter's provider aligned with the native iOS signing configuration.
/// Personal Team release/profile builds are private development builds and use
/// a per-installation debug token registered in Firebase, never a bundled token.
Future<AppleAppCheckProvider> appleAppCheckProviderForBuild({
  bool isDebug = kDebugMode,
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
}) async {
  if (isDebug) return const AppleDebugProvider();
  if (!isWeb && (platform ?? defaultTargetPlatform) == TargetPlatform.iOS) {
    final provider = await _securityChannel.invokeMethod<String>(
      'appCheckProvider',
    );
    switch (provider) {
      case 'debug':
        return const AppleDebugProvider();
      case 'appAttestWithDeviceCheckFallback':
        return const AppleAppAttestWithDeviceCheckFallbackProvider();
      default:
        throw StateError(
          'The iOS App Check build configuration is unavailable.',
        );
    }
  }
  return const AppleAppAttestWithDeviceCheckFallbackProvider();
}

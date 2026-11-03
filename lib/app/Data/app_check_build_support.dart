import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _securityChannel = MethodChannel('hiker_circle/security');
const _buildConfigChannel = MethodChannel('hiker_circle/build_config');

/// Match native initialization for private development and production builds.
/// A development signing flag is supplied by the build, never by user input.
/// Its debug token stays specific to the installation and is not bundled here.
Future<AndroidAppCheckProvider> androidAppCheckProviderForBuild({
  bool isDebug = kDebugMode,
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
}) async {
  if (isDebug) return const AndroidDebugProvider();
  if (!isWeb && (platform ?? defaultTargetPlatform) == TargetPlatform.android) {
    final developmentOnly = await _buildConfigChannel.invokeMethod<bool>(
      'isDevelopmentOnlyRelease',
    );
    if (developmentOnly == null) {
      throw StateError(
        'The Android App Check build configuration is unavailable.',
      );
    }
    if (developmentOnly) return const AndroidDebugProvider();
  }
  return const AndroidPlayIntegrityProvider();
}

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

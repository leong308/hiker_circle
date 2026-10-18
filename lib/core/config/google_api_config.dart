// GoogleApiConfig exposes mobile-public map configuration; private provider credentials remain
// server managed.
import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract final class GoogleApiConfig {
  // Required by the separately restricted key used for direct Android betas.
  static const bool publicAndroidBeta = bool.fromEnvironment('HC_PUBLIC_BETA');
  static Map<String, String> get androidBetaHeaders => publicAndroidBeta
      ? const {
          'X-Android-Package': 'com.leongziqi.hikercircle',
          'X-Android-Cert': '4E84B7B37406768A071559598FFE800C61987B3A',
        }
      : const {};
  static String _dotenvValue(String key) {
    try {
      return dotenv.env[key]?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  static const String _mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
  );

  static String get mapboxAccessToken {
    final buildValue = _mapboxAccessToken.trim();
    if (buildValue.isNotEmpty) return buildValue;
    return _dotenvValue('MAPBOX_ACCESS_TOKEN');
  }

  static bool get hasMapboxAccessToken => mapboxAccessToken.trim().isNotEmpty;

  // Provider secrets are Firebase Secret Manager inputs, never Flutter assets.
  static String get routesApiKey => '';
  static String get geocodingApiKey => '';
  static String get geoapifyApiKey => '';
  static String get openRouteServiceApiKey => '';
  static bool get hasRoutesApiKey => true;
  static bool get hasGeocodingApiKey => true;
  static bool get hasGeoapifyApiKey => true;
  static bool get hasOpenRouteServiceApiKey => true;
}

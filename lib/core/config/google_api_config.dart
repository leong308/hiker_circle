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

  static const String _routesApiKey = String.fromEnvironment(
    'GOOGLE_ROUTES_API_KEY',
  );

  static String get routesApiKey {
    final buildValue = _routesApiKey.trim();
    if (buildValue.isNotEmpty) return buildValue;
    return _dotenvValue('GOOGLE_ROUTES_API_KEY');
  }

  static const String _geocodingApiKey = String.fromEnvironment(
    'GOOGLE_GEOCODING_API_KEY',
  );

  static String get geocodingApiKey {
    final buildValue = _geocodingApiKey.trim();
    if (buildValue.isNotEmpty) return buildValue;
    final dotenvValue = _dotenvValue('GOOGLE_GEOCODING_API_KEY');
    if (dotenvValue.isNotEmpty) return dotenvValue;
    return routesApiKey;
  }

  static bool get hasRoutesApiKey => routesApiKey.trim().isNotEmpty;

  static bool get hasGeocodingApiKey => geocodingApiKey.trim().isNotEmpty;

  static const String _geoapifyApiKey = String.fromEnvironment(
    'GEOAPIFY_API_KEY',
  );

  static String get geoapifyApiKey {
    final buildValue = _geoapifyApiKey.trim();
    if (buildValue.isNotEmpty) return buildValue;
    return _dotenvValue('GEOAPIFY_API_KEY');
  }

  static bool get hasGeoapifyApiKey => geoapifyApiKey.trim().isNotEmpty;

  static const String _openRouteServiceApiKey = String.fromEnvironment(
    'OPENROUTESERVICE_API_KEY',
  );

  static String get openRouteServiceApiKey {
    final buildValue = _openRouteServiceApiKey.trim();
    if (buildValue.isNotEmpty) return buildValue;
    return _dotenvValue('OPENROUTESERVICE_API_KEY');
  }

  static bool get hasOpenRouteServiceApiKey =>
      openRouteServiceApiKey.trim().isNotEmpty;
}

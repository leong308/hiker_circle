// GoogleApiConfig exposes mobile-public map configuration; private provider credentials remain
// server managed.
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Represents google api config.
abstract final class GoogleApiConfig {
  // Required by the separately restricted key used for direct Android betas.
  static const bool publicAndroidBeta = bool.fromEnvironment('HC_PUBLIC_BETA');

  /// Returns android beta headers.
  static Map<String, String> get androidBetaHeaders => publicAndroidBeta
      ? const {
          'X-Android-Package': 'com.leongziqi.hikercircle',
          'X-Android-Cert': '4E84B7B37406768A071559598FFE800C61987B3A',
        }
      : const {};

  /// Computes dotenv value.
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

  /// Returns mapbox access token.
  static String get mapboxAccessToken {
    final buildValue = _mapboxAccessToken.trim();
    if (buildValue.isNotEmpty) return buildValue;
    return _dotenvValue('MAPBOX_ACCESS_TOKEN');
  }

  /// Returns has mapbox access token.
  static bool get hasMapboxAccessToken => mapboxAccessToken.trim().isNotEmpty;

  // Provider secrets are Firebase Secret Manager inputs, never Flutter assets.
  /// Returns routes api key.
  static String get routesApiKey => '';

  /// Returns geocoding api key.
  static String get geocodingApiKey => '';

  /// Returns geoapify api key.
  static String get geoapifyApiKey => '';

  /// Returns open route service api key.
  static String get openRouteServiceApiKey => '';

  /// Returns has routes api key.
  static bool get hasRoutesApiKey => true;

  /// Returns has geocoding api key.
  static bool get hasGeocodingApiKey => true;

  /// Returns has geoapify api key.
  static bool get hasGeoapifyApiKey => true;

  /// Returns has open route service api key.
  static bool get hasOpenRouteServiceApiKey => true;
}

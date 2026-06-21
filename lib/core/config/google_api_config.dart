import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract final class GoogleApiConfig {
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
    final env = _mapboxAccessToken.trim();
    if (env.isNotEmpty) return env;
    final dot = _dotenvValue('MAPBOX_ACCESS_TOKEN');
    if (dot.isNotEmpty) return dot;
    return '';
  }

  static bool get hasMapboxAccessToken => mapboxAccessToken.trim().isNotEmpty;

  static const String _routesApiKey = String.fromEnvironment(
    'GOOGLE_ROUTES_API_KEY',
  );

  static String get routesApiKey {
    final env = _routesApiKey.trim();
    if (env.isNotEmpty) return env;
    final dot = _dotenvValue('GOOGLE_ROUTES_API_KEY');
    if (dot.isNotEmpty) return dot;
    return '';
  }

  static const String _geocodingApiKey = String.fromEnvironment(
    'GOOGLE_GEOCODING_API_KEY',
  );

  static String get geocodingApiKey {
    final env = _geocodingApiKey.trim();
    if (env.isNotEmpty) return env;
    final dot = _dotenvValue('GOOGLE_GEOCODING_API_KEY');
    if (dot.isNotEmpty) return dot;
    return routesApiKey;
  }

  static bool get hasRoutesApiKey => routesApiKey.trim().isNotEmpty;

  static bool get hasGeocodingApiKey => geocodingApiKey.trim().isNotEmpty;

  static const String _geoapifyApiKey = String.fromEnvironment(
    'GEOAPIFY_API_KEY',
  );

  static String get geoapifyApiKey {
    final env = _geoapifyApiKey.trim();
    if (env.isNotEmpty) return env;
    final dot = _dotenvValue('GEOAPIFY_API_KEY');
    if (dot.isNotEmpty) return dot;
    return '';
  }

  static bool get hasGeoapifyApiKey => geoapifyApiKey.trim().isNotEmpty;

  static const String _openRouteServiceApiKey = String.fromEnvironment(
    'OPENROUTESERVICE_API_KEY',
  );

  static String get openRouteServiceApiKey {
    final env = _openRouteServiceApiKey.trim();
    if (env.isNotEmpty) return env;
    final dot = _dotenvValue('OPENROUTESERVICE_API_KEY');
    if (dot.isNotEmpty) return dot;
    return '';
  }

  static bool get hasOpenRouteServiceApiKey =>
      openRouteServiceApiKey.trim().isNotEmpty;
}

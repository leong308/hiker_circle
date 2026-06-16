import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract final class GoogleApiConfig {
  static const String _routesApiKey = String.fromEnvironment(
    'GOOGLE_ROUTES_API_KEY',
  );

  static String get routesApiKey {
    final env = _routesApiKey.trim();
    if (env.isNotEmpty) return env;
    final dot = dotenv.env['GOOGLE_ROUTES_API_KEY']?.trim();
    if (dot != null && dot.isNotEmpty) return dot;
    return '';
  }

  static const String _geocodingApiKey = String.fromEnvironment(
    'GOOGLE_GEOCODING_API_KEY',
  );

  static String get geocodingApiKey {
    final env = _geocodingApiKey.trim();
    if (env.isNotEmpty) return env;
    final dot = dotenv.env['GOOGLE_GEOCODING_API_KEY']?.trim();
    if (dot != null && dot.isNotEmpty) return dot;
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
    final dot = dotenv.env['GEOAPIFY_API_KEY']?.trim();
    if (dot != null && dot.isNotEmpty) return dot;
    return '';
  }

  static bool get hasGeoapifyApiKey => geoapifyApiKey.trim().isNotEmpty;

  static const String _openRouteServiceApiKey = String.fromEnvironment(
    'OPENROUTESERVICE_API_KEY',
  );

  static String get openRouteServiceApiKey {
    final env = _openRouteServiceApiKey.trim();
    if (env.isNotEmpty) return env;
    final dot = dotenv.env['OPENROUTESERVICE_API_KEY']?.trim();
    if (dot != null && dot.isNotEmpty) return dot;
    return '';
  }

  static bool get hasOpenRouteServiceApiKey =>
      openRouteServiceApiKey.trim().isNotEmpty;
}

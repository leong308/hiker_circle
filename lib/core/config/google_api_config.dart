abstract final class GoogleApiConfig {
  static const String routesApiKey = String.fromEnvironment(
    'GOOGLE_ROUTES_API_KEY',
    defaultValue: 'AIzaSyBSE9pYXRQP82L7EF0-Lbde-6mFDMAYFEc',
  );

  static const String _geocodingApiKey = String.fromEnvironment(
    'GOOGLE_GEOCODING_API_KEY',
  );

  static String get geocodingApiKey =>
      _geocodingApiKey.trim().isEmpty ? routesApiKey : _geocodingApiKey;

  static bool get hasRoutesApiKey {
    return routesApiKey.trim().isNotEmpty;
  }

  static bool get hasGeocodingApiKey => geocodingApiKey.trim().isNotEmpty;
}

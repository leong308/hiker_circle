abstract final class GoogleApiConfig {
  static const String routesApiKey = String.fromEnvironment(
    'GOOGLE_ROUTES_API_KEY',
    defaultValue: 'AIzaSyBSE9pYXRQP82L7EF0-Lbde-6mFDMAYFEc',
  );

  static bool get hasRoutesApiKey {
    return routesApiKey.trim().isNotEmpty;
  }
}

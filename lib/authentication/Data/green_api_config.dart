class GreenApiConfig {
  const GreenApiConfig({
    this.apiUrl = const String.fromEnvironment(
      'GREEN_API_URL',
      defaultValue: 'https://api.green-api.com',
    ),
    this.instanceId = const String.fromEnvironment(
      'GREEN_API_INSTANCE_ID',
      defaultValue: '7105263915',
    ),
    this.apiToken = const String.fromEnvironment(
      'GREEN_API_TOKEN',
      defaultValue: '17e6365828764ab1a0cdbcf105a04c69d915bcdea43f409d9c',
    ),
  });

  final String apiUrl;
  final String instanceId;
  final String apiToken;

  bool get isConfigured => instanceId.isNotEmpty && apiToken.isNotEmpty;

  void validate() {
    if (!isConfigured) {
      throw const GreenApiConfigException(
        'GreenAPI is not configured. Run the app with GREEN_API_INSTANCE_ID '
        'and GREEN_API_TOKEN dart defines.',
      );
    }
  }
}

class GreenApiConfigException implements Exception {
  const GreenApiConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

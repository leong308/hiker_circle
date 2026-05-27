import 'dart:convert';

import 'package:http/http.dart' as http;

import 'green_api_config.dart';

class GreenApiClient {
  GreenApiClient({required GreenApiConfig config, http.Client? httpClient})
    : _config = config,
      _httpClient = httpClient ?? http.Client();

  final GreenApiConfig _config;
  final http.Client _httpClient;

  Future<void> sendMessage({
    required String chatId,
    required String message,
  }) async {
    _config.validate();
    final uri = Uri.parse(
      '${_config.apiUrl}/waInstance${_config.instanceId}/sendMessage/'
      '${_config.apiToken}',
    );

    final response = await _httpClient.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'chatId': chatId, 'message': message}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GreenApiException(
        'GreenAPI rejected the message request '
        '(${response.statusCode}): ${response.body}',
      );
    }
  }
}

class GreenApiException implements Exception {
  const GreenApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

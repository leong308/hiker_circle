// PrivateProviderClient forwards authenticated provider operations to Firebase and reconstructs HTTP
// responses without shipping provider secrets.
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;

/// Only Firebase receives provider secrets. The mobile binary carries no key.
abstract final class PrivateProviderClient {
  /// Computes request.
  static Future<http.Response> request(
    String operation,
    Map<String, Object?> data,
  ) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('requestPrivateProvider')
        .call<Map<String, dynamic>>({'operation': operation, ...data});
    final value = result.data;
    final bytes = value['base64'] is String
        ? base64Decode(value['base64'] as String)
        : utf8.encode(value['body'] as String? ?? '{}');
    return http.Response.bytes(
      bytes,
      (value['httpStatus'] as num?)?.toInt() ?? 502,
    );
  }
}

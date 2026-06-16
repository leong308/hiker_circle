import 'dart:convert';

import 'package:http/http.dart' as http;

class OpenTopoDataException implements Exception {
  const OpenTopoDataException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OpenTopoDataResult {
  const OpenTopoDataResult({
    required this.elevations,
  });

  final List<double> elevations;

  double get elevationGainMeters {
    if (elevations.length < 2) return 0;
    var gain = 0.0;
    for (var i = 1; i < elevations.length; i++) {
      final diff = elevations[i] - elevations[i - 1];
      if (diff > 0) gain += diff;
    }
    return gain;
  }
}

class OpenTopoDataService {
  OpenTopoDataService({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<OpenTopoDataResult> getElevations({
    required List<List<double>> coordinates,
  }) async {
    final client = _client ?? http.Client();
    try {
      final locations = coordinates
          .map((c) => '${c[1]},${c[0]}')
          .join('|');
      final response = await client.get(
        Uri.https(
          'api.opentopodata.org',
          '/v1/aster30m',
          {'locations': locations},
        ),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OpenTopoDataException(
          'OpenTopoData ${response.statusCode}: ${response.body}',
        );
      }

      return _parseResponse(response.body);
    } on OpenTopoDataException {
      rethrow;
    } catch (_) {
      throw const OpenTopoDataException(
        'Unable to fetch elevation data.',
      );
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  OpenTopoDataResult _parseResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const OpenTopoDataException('Unexpected response format.');
    }

    final results = decoded['results'];
    if (results is! List || results.isEmpty) {
      throw const OpenTopoDataException('No elevation data returned.');
    }

    final elevations = results.map((r) {
      if (r is! Map) return 0.0;
      final elevation = r['elevation'];
      if (elevation is num) return elevation.toDouble();
      return 0.0;
    }).toList();

    if (elevations.isEmpty) {
      throw const OpenTopoDataException('Empty elevation data.');
    }

    return OpenTopoDataResult(elevations: elevations);
  }
}

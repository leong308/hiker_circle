// OpenTopoDataService samples route elevations and derives an elevation range/ascent estimate from
// the returned profile.
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Represents open topo data exception.
class OpenTopoDataException implements Exception {
  /// Creates open topo data exception.
  const OpenTopoDataException(this.message);

  final String message;

  /// Converts to string.
  @override
  String toString() => message;
}

/// Represents open topo data result.
class OpenTopoDataResult {
  /// Creates open topo data result.
  const OpenTopoDataResult({required this.elevations});

  final List<double> elevations;

  /// Returns minimum elevation meters.
  double? get minimumElevationMeters {
    final values = elevations.where((value) => value.isFinite).toList();
    if (values.isEmpty) return null;
    return values.reduce((first, second) => first < second ? first : second);
  }

  /// Returns maximum elevation meters.
  double? get maximumElevationMeters {
    final values = elevations.where((value) => value.isFinite).toList();
    if (values.isEmpty) return null;
    return values.reduce((first, second) => first > second ? first : second);
  }

  /// Returns elevation gain meters.
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

/// Represents open topo data service.
class OpenTopoDataService {
  /// Creates open topo data service.
  OpenTopoDataService({http.Client? client}) : _client = client;

  final http.Client? _client;

  /// Returns elevations.
  Future<OpenTopoDataResult> getElevations({
    required List<List<double>> coordinates,
  }) async {
    final client = _client ?? http.Client();
    try {
      final locations = coordinates.map((c) => '${c[1]},${c[0]}').join('|');
      final response = await client.get(
        Uri.https('api.opentopodata.org', '/v1/aster30m', {
          'locations': locations,
        }),
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
      throw const OpenTopoDataException('Unable to fetch elevation data.');
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  /// Parses response.
  OpenTopoDataResult _parseResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const OpenTopoDataException('Unexpected response format.');
    }

    final results = decoded['results'];
    if (results is! List || results.isEmpty) {
      throw const OpenTopoDataException('No elevation data returned.');
    }

    final elevations = <double>[];
    for (final result in results) {
      if (result is! Map) continue;
      final elevation = result['elevation'];
      if (elevation is num && elevation.isFinite) {
        elevations.add(elevation.toDouble());
      }
    }

    if (elevations.isEmpty) {
      throw const OpenTopoDataException('Empty elevation data.');
    }

    return OpenTopoDataResult(elevations: elevations);
  }
}

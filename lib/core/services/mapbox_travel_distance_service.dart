// MapboxTravelDistanceService batches driving-distance lookups and caches results; unavailable
// distances remain unknown.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/google_api_config.dart';

typedef TravelDestination = ({String id, double latitude, double longitude});

/// Distances along Mapbox's fastest driving routes, in kilometres.
/// Null means unavailable; never substitute a straight-line estimate.
class MapboxTravelDistanceService {
  MapboxTravelDistanceService({http.Client? client, String? accessToken})
    : _client = client,
      _accessToken = accessToken ?? GoogleApiConfig.mapboxAccessToken;

  final http.Client? _client;
  final String _accessToken;
  final _cache = <String, ({double? km, DateTime expires})>{};

  static bool _valid(double lat, double lon) =>
      lat.isFinite && lon.isFinite && lat.abs() <= 90 && lon.abs() <= 180;

  Future<Map<String, double?>> distancesKm({
    required double latitude,
    required double longitude,
    required List<TravelDestination> destinations,
  }) async {
    final result = <String, double?>{for (final d in destinations) d.id: null};
    if (!_valid(latitude, longitude) || _accessToken.trim().isEmpty) {
      return result;
    }
    final now = DateTime.now();
    _cache.removeWhere((_, value) => !value.expires.isAfter(now));
    String key(TravelDestination d) =>
        '$latitude,$longitude:${d.latitude},${d.longitude}';
    final pending = <TravelDestination>[];
    for (final d in destinations) {
      if (!_valid(d.latitude, d.longitude)) continue;
      final cached = _cache[key(d)];
      if (cached != null) {
        result[d.id] = cached.km;
      } else {
        pending.add(d);
      }
    }
    final client = _client ?? http.Client();
    try {
      // One origin plus at most 24 destinations per Mapbox request.
      for (var offset = 0; offset < pending.length; offset += 24) {
        final batch = pending.skip(offset).take(24).toList();
        final coordinates = [
          '$longitude,$latitude',
          for (final d in batch) '${d.longitude},${d.latitude}',
        ].join(';');
        // Matrix requires at least two elements. Include the origin's zero
        // distance when requesting only one destination, then skip it below.
        final single = batch.length == 1;
        final uri = Uri.https(
          'api.mapbox.com',
          '/directions-matrix/v1/mapbox/driving/$coordinates',
          {
            'access_token': _accessToken,
            'sources': '0',
            'destinations': single
                ? '0;1'
                : List.generate(batch.length, (i) => '${i + 1}').join(';'),
            'annotations': 'distance',
          },
        );
        try {
          final response = await client
              .get(uri)
              .timeout(const Duration(seconds: 15));
          if (response.statusCode != 200) continue;
          final body = jsonDecode(response.body);
          if (body is! Map || body['code'] != 'Ok') continue;
          final matrix = body['distances'];
          final sources = body['sources'];
          final targets = body['destinations'];
          if (matrix is! List ||
              matrix.length != 1 ||
              matrix.first is! List ||
              sources is! List ||
              sources.isEmpty ||
              targets is! List) {
            continue;
          }
          final row = matrix.first as List;
          final expected = batch.length + (single ? 1 : 0);
          if (row.length != expected || targets.length != expected) continue;
          // A distant road snap can otherwise produce a convincing but
          // misleading distance to a remote summit or inaccessible trailhead.
          bool nearRoad(dynamic waypoint) =>
              waypoint is Map &&
              waypoint['distance'] is num &&
              (waypoint['distance'] as num).isFinite &&
              (waypoint['distance'] as num) >= 0 &&
              (waypoint['distance'] as num) <= 1000;
          for (var i = 0; i < batch.length; i++) {
            final column = i + (single ? 1 : 0);
            final meters = row[column];
            final km =
                meters is num &&
                    meters.isFinite &&
                    meters >= 0 &&
                    nearRoad(sources.first) &&
                    nearRoad(targets[column])
                ? meters.toDouble() / 1000
                : null;
            result[batch[i].id] = km;
            _cache[key(batch[i])] = (
              km: km,
              expires: now.add(const Duration(minutes: 10)),
            );
          }
        } catch (_) {
          // Keep other successful batches and allow a later refresh to retry.
        }
      }
    } finally {
      if (_client == null) client.close();
    }
    if (_cache.length > 1000) _cache.clear();
    return result;
  }
}

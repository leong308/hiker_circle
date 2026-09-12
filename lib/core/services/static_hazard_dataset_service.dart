import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../app/Data/local_session_database.dart';
import '../../trail/Model/trail_models.dart';
import '../config/google_api_config.dart';
import 'hiking_route_service.dart';

typedef HazardDatasetProgress = void Function(int completed, int total);

class StaticHazardDatasetException implements Exception {
  const StaticHazardDatasetException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Downloads a compact, trail-corridor subset of mapped static features.
///
/// Mapbox Tilequery always returns the closest point on a feature, which keeps
/// the SQLite dataset small and gives the map a useful caution-marker location.
/// The dataset deliberately does not infer wildlife presence from waterways.
class StaticHazardDatasetService {
  StaticHazardDatasetService({
    required LocalSessionDatabase database,
    http.Client? client,
    String? accessToken,
  }) : _database = database,
       _client = client ?? http.Client(),
       _accessToken = accessToken;

  final LocalSessionDatabase _database;
  final http.Client _client;
  final String? _accessToken;

  static const _tilesetId = 'mapbox.mapbox-streets-v8';
  static const _sourceUrl =
      'https://docs.mapbox.com/data/tilesets/reference/mapbox-streets-v8/';
  static const _queryRadiusMeters = 175;
  static const _maxSamplesPerTrail = 10;
  static const _automaticRefreshAge = Duration(days: 30);
  static const _bridgeWaterwayToleranceMeters = 30.0;
  static final Map<String, Future<List<LocalTrailHazardMatch>>>
  _automaticDownloads = {};

  Future<LocalHazardDatasetSummary> loadSummary() {
    return _database.loadStaticHazardDatasetSummary();
  }

  /// Returns cached hazards immediately when this trail was scanned recently.
  /// Otherwise it performs a compact background download for this trail only.
  /// Network failures leave the existing offline data untouched.
  Future<List<LocalTrailHazardMatch>> ensureForTrail(
    Trail trail, {
    HikingRouteResult? route,
  }) async {
    final cached = await _database.loadStaticHazardsForTrail(trail.trailId);
    final scannedAt = await _database.loadStaticHazardScanTime(trail.trailId);
    if (scannedAt != null &&
        DateTime.now().toUtc().difference(scannedAt.toUtc()) <
            _automaticRefreshAge) {
      return cached;
    }
    final token = _resolvedAccessToken;
    if (token.isEmpty) return cached;

    final key = trail.trailId.trim();
    final existing = _automaticDownloads[key];
    if (existing != null) {
      try {
        return await existing;
      } catch (_) {
        return cached;
      }
    }
    final download = _downloadForSingleTrail(trail, token, route: route);
    _automaticDownloads[key] = download;
    try {
      return await download;
    } catch (_) {
      return cached;
    } finally {
      if (identical(_automaticDownloads[key], download)) {
        _automaticDownloads.remove(key);
      }
    }
  }

  String get _resolvedAccessToken =>
      _accessToken?.trim() ?? GoogleApiConfig.mapboxAccessToken;

  Future<LocalHazardDatasetSummary> downloadForTrails(
    List<Trail> trails, {
    HazardDatasetProgress? onProgress,
  }) async {
    final token = _resolvedAccessToken;
    if (token.isEmpty) {
      throw const StaticHazardDatasetException(
        'A Mapbox access token is required to download trail hazards.',
      );
    }
    final usableTrails = trails
        .where((trail) => _pointsForTrail(trail).isNotEmpty)
        .toList(growable: false);
    if (usableTrails.isEmpty) {
      throw const StaticHazardDatasetException(
        'No saved trail coordinates are available yet. Open Trails online once, then retry.',
      );
    }

    final work = <({Trail trail, _RouteSample sample})>[];
    for (final trail in usableTrails) {
      for (final sample in _sampleTrail(_pointsForTrail(trail))) {
        work.add((trail: trail, sample: sample));
      }
    }
    onProgress?.call(0, work.length);

    final hazardsById = <String, LocalStaticHazard>{};
    final matchesById = <String, LocalTrailHazardMatch>{};
    var completed = 0;
    var successfulQueries = 0;
    Object? lastError;

    for (final item in work) {
      try {
        final features = await _query(item.sample, token);
        successfulQueries++;
        for (final parsed in _parseFeatures(
          features,
          trail: item.trail,
          sample: item.sample,
        )) {
          final existing = matchesById[parsed.match.hazard.hazardId];
          if (existing == null ||
              parsed.match.distanceMeters < existing.distanceMeters) {
            hazardsById[parsed.hazard.hazardId] = parsed.hazard;
            matchesById[parsed.match.hazard.hazardId] = parsed.match;
          }
        }
      } catch (error) {
        lastError = error;
      } finally {
        completed++;
        onProgress?.call(completed, work.length);
      }
    }

    if (successfulQueries == 0) {
      throw StaticHazardDatasetException(
        'Mapbox returned no successful hazard queries. ${lastError ?? 'Check the connection and token restrictions.'}',
      );
    }

    await _database.replaceStaticHazardDataset(
      hazards: hazardsById.values.toList(growable: false),
      matches: matchesById.values.toList(growable: false),
      scannedTrailCount: usableTrails.length,
      scannedTrailIds: usableTrails.map((trail) => trail.trailId),
    );
    return _database.loadStaticHazardDatasetSummary();
  }

  Future<List<LocalTrailHazardMatch>> _downloadForSingleTrail(
    Trail trail,
    String token, {
    HikingRouteResult? route,
  }) async {
    final points = _pointsForTrail(trail, route: route);
    if (points.isEmpty) {
      return _database.loadStaticHazardsForTrail(trail.trailId);
    }
    final hazardsById = <String, LocalStaticHazard>{};
    final matchesById = <String, LocalTrailHazardMatch>{};
    var successfulQueries = 0;
    Object? lastError;
    final samples = _sampleTrail(points);
    for (final sample in samples) {
      try {
        final features = await _query(sample, token);
        successfulQueries++;
        for (final parsed in _parseFeatures(
          features,
          trail: trail,
          sample: sample,
        )) {
          final existing = matchesById[parsed.hazard.hazardId];
          if (existing == null ||
              parsed.match.distanceMeters < existing.distanceMeters) {
            hazardsById[parsed.hazard.hazardId] = parsed.hazard;
            matchesById[parsed.hazard.hazardId] = parsed.match;
          }
        }
      } catch (error) {
        lastError = error;
      }
    }
    if (successfulQueries != samples.length) {
      throw StaticHazardDatasetException(
        'Unable to refresh mapped hazards. ${lastError ?? 'Check the connection and token restrictions.'}',
      );
    }
    final scannedAt = DateTime.now().toUtc();
    await _database.replaceStaticHazardsForTrail(
      trailId: trail.trailId,
      hazards: hazardsById.values.toList(growable: false),
      matches: matchesById.values.toList(growable: false),
      scannedAt: scannedAt,
    );
    return _database.loadStaticHazardsForTrail(trail.trailId);
  }

  Future<void> clear() => _database.clearStaticHazardDataset();

  Future<List<Map<String, dynamic>>> _query(
    _RouteSample sample,
    String token,
  ) async {
    final uri = Uri.https(
      'api.mapbox.com',
      '/v4/$_tilesetId/tilequery/${sample.longitude},${sample.latitude}.json',
      {
        'radius': '$_queryRadiusMeters',
        'limit': '50',
        'dedupe': 'true',
        'layers': 'waterway,structure,road',
        'access_token': token,
      },
    );
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      var detail = 'HTTP ${response.statusCode}';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['message'] != null) {
          detail = body['message'].toString();
        }
      } catch (_) {}
      throw StaticHazardDatasetException('Tilequery failed: $detail');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['features'] is! List) return const [];
    return (decoded['features'] as List)
        .whereType<Map>()
        .map((feature) => Map<String, dynamic>.from(feature))
        .toList(growable: false);
  }

  List<({LocalStaticHazard hazard, LocalTrailHazardMatch match})>
  _parseFeatures(
    List<Map<String, dynamic>> features, {
    required Trail trail,
    required _RouteSample sample,
  }) {
    final parsed =
        <({LocalStaticHazard hazard, LocalTrailHazardMatch match})>[];
    final waterways = <_FeaturePoint>[];
    final bridges = <({Map<String, dynamic> feature, _FeaturePoint point})>[];
    for (final feature in features) {
      final point = _featurePoint(feature);
      if (point != null && point.layer == 'waterway' && _isWaterway(point)) {
        waterways.add(point);
      }
      if (point != null &&
          point.layer == 'road' &&
          point.structure == 'bridge') {
        bridges.add((feature: feature, point: point));
      }
      final hazard = _parseFeature(feature, trail: trail, sample: sample);
      if (hazard != null) parsed.add(hazard);
    }
    for (final bridge in bridges) {
      _FeaturePoint? crossedWaterway;
      var closestDistance = double.infinity;
      for (final waterway in waterways) {
        final distance = _distanceBetween(bridge.point, waterway);
        if (distance < closestDistance) {
          closestDistance = distance;
          crossedWaterway = waterway;
        }
      }
      if (crossedWaterway == null ||
          closestDistance > _bridgeWaterwayToleranceMeters) {
        continue;
      }
      parsed.add(
        _parseBridgeFeature(
          bridge.feature,
          bridge.point,
          crossedWaterway,
          trail: trail,
          sample: sample,
        ),
      );
    }
    return parsed;
  }

  ({LocalStaticHazard hazard, LocalTrailHazardMatch match})? _parseFeature(
    Map<String, dynamic> feature, {
    required Trail trail,
    required _RouteSample sample,
  }) {
    final geometry = feature['geometry'];
    final properties = feature['properties'];
    if (geometry is! Map || properties is! Map) return null;
    final coordinates = geometry['coordinates'];
    final tilequery = properties['tilequery'];
    if (coordinates is! List || coordinates.length < 2 || tilequery is! Map) {
      return null;
    }
    final longitude = (coordinates[0] as num?)?.toDouble();
    final latitude = (coordinates[1] as num?)?.toDouble();
    final distance = (tilequery['distance'] as num?)?.toDouble();
    final layer = tilequery['layer']?.toString().toLowerCase() ?? '';
    final featureClass = properties['class']?.toString().toLowerCase() ?? '';
    final featureType = properties['type']?.toString().toLowerCase() ?? '';
    if (longitude == null || latitude == null || distance == null) return null;

    late final String hazardType;
    if (layer == 'structure' && featureClass == 'cliff') {
      hazardType = 'cliff';
    } else if (layer == 'waterway' &&
        const {
          'river',
          'stream',
          'stream_intermittent',
        }.contains(featureClass.isEmpty ? featureType : featureClass)) {
      hazardType = featureClass.isEmpty ? featureType : featureClass;
    } else {
      return null;
    }

    final isOnRoute = distance <= (hazardType == 'cliff' ? 20 : 8);
    final relationship = isOnRoute
        ? hazardType == 'cliff'
              ? 'on_route'
              : 'possible_crossing'
        : 'nearby';
    final isCliff = hazardType == 'cliff';
    final featureId =
        feature['id']?.toString() ??
        '${longitude.toStringAsFixed(5)},${latitude.toStringAsFixed(5)}';
    final hazardId = 'mapbox:${trail.trailId}:$layer:$hazardType:$featureId';
    final now = DateTime.now().toUtc();
    final roundedDistance = distance.round();
    final title = isCliff
        ? isOnRoute
              ? 'Mapped cliff at route'
              : 'Mapped cliff nearby'
        : isOnRoute
        ? 'Possible water crossing'
        : 'Waterway nearby';
    final description = isCliff
        ? 'Map data places a cliff about $roundedDistance m from this route position. Coverage may be incomplete.'
        : 'Map data places a ${_waterwayLabel(hazardType)} about $roundedDistance m from this route position. This does not confirm current depth, flow, flooding, or a safe crossing.';
    final guidance = isCliff
        ? 'Keep back from exposed edges, avoid shortcuts, and reassess in poor visibility or wet conditions.'
        : 'Check the actual crossing, recent rainfall, and local advice. Do not infer wildlife presence from water alone.';
    final hazard = LocalStaticHazard(
      hazardId: hazardId,
      hazardType: hazardType,
      title: title,
      description: description,
      latitude: latitude,
      longitude: longitude,
      severity: isOnRoute ? 'warning' : 'caution',
      confidence: 'mapped_feature',
      sourceName: 'Mapbox Streets / OpenStreetMap',
      sourceUrl: _sourceUrl,
      sourceFeatureId: featureId,
      safetyGuidance: guidance,
      downloadedAt: now,
      expiresAt: now.add(const Duration(days: 90)),
    );
    return (
      hazard: hazard,
      match: LocalTrailHazardMatch(
        trailId: trail.trailId,
        hazard: hazard,
        relationship: relationship,
        distanceMeters: distance,
        routeProgress: sample.progress,
        computedAt: now,
      ),
    );
  }

  ({LocalStaticHazard hazard, LocalTrailHazardMatch match}) _parseBridgeFeature(
    Map<String, dynamic> feature,
    _FeaturePoint bridge,
    _FeaturePoint waterway, {
    required Trail trail,
    required _RouteSample sample,
  }) {
    final isOnRoute = bridge.distance <= 12;
    final featureId =
        feature['id']?.toString() ??
        '${bridge.longitude.toStringAsFixed(5)},${bridge.latitude.toStringAsFixed(5)}';
    final now = DateTime.now().toUtc();
    final waterwayLabel = _waterwayLabel(
      waterway.featureClass.isEmpty
          ? waterway.featureType
          : waterway.featureClass,
    );
    final roundedDistance = bridge.distance.round();
    final hazard = LocalStaticHazard(
      hazardId: 'mapbox:${trail.trailId}:road:bridge_crossing:$featureId',
      hazardType: 'bridge_crossing',
      title: isOnRoute
          ? 'Mapped bridge at water crossing'
          : 'Mapped bridge crossing nearby',
      description:
          'Map data places a bridge over a $waterwayLabel about $roundedDistance m from this route position. Its condition and accessibility are not verified.',
      latitude: bridge.latitude,
      longitude: bridge.longitude,
      severity: isOnRoute ? 'warning' : 'caution',
      confidence: 'mapped_feature_pair',
      sourceName: 'Mapbox Streets / OpenStreetMap',
      sourceUrl: _sourceUrl,
      sourceFeatureId: featureId,
      safetyGuidance:
          'Inspect the bridge before crossing. Do not use it if damaged, submerged, closed, or unsafe after heavy rain.',
      downloadedAt: now,
      expiresAt: now.add(const Duration(days: 90)),
    );
    return (
      hazard: hazard,
      match: LocalTrailHazardMatch(
        trailId: trail.trailId,
        hazard: hazard,
        relationship: isOnRoute ? 'bridge_crossing' : 'bridge_crossing_nearby',
        distanceMeters: bridge.distance,
        routeProgress: sample.progress,
        computedAt: now,
      ),
    );
  }

  _FeaturePoint? _featurePoint(Map<String, dynamic> feature) {
    final geometry = feature['geometry'];
    final properties = feature['properties'];
    if (geometry is! Map || properties is! Map) return null;
    final coordinates = geometry['coordinates'];
    final tilequery = properties['tilequery'];
    if (coordinates is! List || coordinates.length < 2 || tilequery is! Map) {
      return null;
    }
    final longitude = (coordinates[0] as num?)?.toDouble();
    final latitude = (coordinates[1] as num?)?.toDouble();
    final distance = (tilequery['distance'] as num?)?.toDouble();
    if (longitude == null || latitude == null || distance == null) return null;
    return _FeaturePoint(
      latitude: latitude,
      longitude: longitude,
      distance: distance,
      layer: tilequery['layer']?.toString().toLowerCase() ?? '',
      featureClass: properties['class']?.toString().toLowerCase() ?? '',
      featureType: properties['type']?.toString().toLowerCase() ?? '',
      structure: properties['structure']?.toString().toLowerCase() ?? '',
    );
  }

  bool _isWaterway(_FeaturePoint point) =>
      const {'river', 'stream', 'stream_intermittent'}.contains(
        point.featureClass.isEmpty ? point.featureType : point.featureClass,
      );

  double _distanceBetween(_FeaturePoint first, _FeaturePoint second) {
    const earthRadiusMeters = 6371000.0;
    final latitude1 = first.latitude * math.pi / 180;
    final latitude2 = second.latitude * math.pi / 180;
    final latitudeDelta = (second.latitude - first.latitude) * math.pi / 180;
    final longitudeDelta = (second.longitude - first.longitude) * math.pi / 180;
    final a =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(latitude1) *
            math.cos(latitude2) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    final clamped = a.clamp(0.0, 1.0);
    return earthRadiusMeters *
        2 *
        math.atan2(math.sqrt(clamped), math.sqrt(1 - clamped));
  }

  List<LatLng> _pointsForTrail(Trail trail, {HikingRouteResult? route}) {
    final encoded =
        route?.encodedPolyline.trim() ??
        trail.routeEncodedPolyline?.trim() ??
        '';
    if (encoded.isNotEmpty) {
      try {
        final decoded = PolylineCodec.decode(encoded);
        if (decoded.isNotEmpty) return decoded;
      } catch (_) {}
    }
    final checkpoints = trail.checkpoints
        .where((checkpoint) => checkpoint.hasValidCoordinate)
        .map((checkpoint) => LatLng(checkpoint.latitude, checkpoint.longitude))
        .toList(growable: false);
    if (checkpoints.isNotEmpty) return checkpoints;
    if (trail.latitude >= -90 &&
        trail.latitude <= 90 &&
        trail.longitude >= -180 &&
        trail.longitude <= 180) {
      return [LatLng(trail.latitude, trail.longitude)];
    }
    return const [];
  }

  List<_RouteSample> _sampleTrail(List<LatLng> points) {
    if (points.length <= _maxSamplesPerTrail) {
      return [
        for (final (index, point) in points.indexed)
          _RouteSample(
            latitude: point.latitude,
            longitude: point.longitude,
            progress: points.length == 1 ? 0 : index / (points.length - 1),
          ),
      ];
    }
    return [
      for (
        var sampleIndex = 0;
        sampleIndex < _maxSamplesPerTrail;
        sampleIndex++
      )
        () {
          final progress = sampleIndex / (_maxSamplesPerTrail - 1);
          final point = points[(progress * (points.length - 1)).round()];
          return _RouteSample(
            latitude: point.latitude,
            longitude: point.longitude,
            progress: progress,
          );
        }(),
    ];
  }

  String _waterwayLabel(String type) => switch (type) {
    'stream_intermittent' => 'seasonal stream',
    _ => type,
  };
}

class _FeaturePoint {
  const _FeaturePoint({
    required this.latitude,
    required this.longitude,
    required this.distance,
    required this.layer,
    required this.featureClass,
    required this.featureType,
    required this.structure,
  });

  final double latitude;
  final double longitude;
  final double distance;
  final String layer;
  final String featureClass;
  final String featureType;
  final String structure;
}

class _RouteSample {
  const _RouteSample({
    required this.latitude,
    required this.longitude,
    required this.progress,
  });

  final double latitude;
  final double longitude;
  final double progress;
}

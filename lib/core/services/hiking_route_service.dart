import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../trail/Model/trail_models.dart';
import 'google_routes_service.dart';

class HikingRouteServiceException implements Exception {
  const HikingRouteServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HikingRouteService {
  const HikingRouteService({
    http.Client? client,
    GoogleRoutesService googleRoutesService = const GoogleRoutesService(),
  }) : _client = client,
       _googleRoutesService = googleRoutesService;

  final http.Client? _client;
  final GoogleRoutesService _googleRoutesService;

  Future<GoogleRouteResult> findHikingRouteForTrail(Trail trail) async {
    if (trail.checkpoints.length < 2) {
      throw const HikingRouteServiceException(
        'Trail needs at least a start and destination point.',
      );
    }

    final client = _client ?? http.Client();
    Object? hikingError;
    try {
      return await _findOpenStreetMapRoute(trail: trail, client: client);
    } catch (error) {
      hikingError = error;
    } finally {
      if (_client == null) {
        client.close();
      }
    }

    try {
      final googleRoute = await _googleRoutesService
          .computeWalkingRouteForTrail(trail);
      if (!_routeDistanceLooksUsable(trail, googleRoute.distanceMeters)) {
        throw GoogleRoutesServiceException(
          'Google route distance ${googleRoute.distanceLabel} does not match ${trail.distanceLabel}.',
        );
      }
      return googleRoute;
    } on GoogleRoutesServiceException catch (googleError) {
      throw HikingRouteServiceException(
        'No live hiking route found. OSM: $hikingError. Google: ${googleError.message}',
      );
    }
  }

  Future<GoogleRouteResult> _findOpenStreetMapRoute({
    required Trail trail,
    required http.Client client,
  }) async {
    final strictCandidates = await _loadOpenStreetMapCandidates(
      trail: trail,
      client: client,
      includeConnectorRoads: false,
    );
    var graphRoute = _graphRouteFor(
      trail,
      strictCandidates,
      mode: _RouteCheckpointMode.allCheckpoints,
    );
    graphRoute ??= _graphRouteFor(
      trail,
      strictCandidates,
      mode: _RouteCheckpointMode.endpointsOnly,
    );
    if (graphRoute != null) {
      return GoogleRouteResult(
        distanceMeters: graphRoute.distanceMeters,
        duration: _estimatedHikingDuration(graphRoute.distanceMeters),
        encodedPolyline: _PolylineEncoder.encode(graphRoute.points),
        sourceLabel: graphRoute.sourceLabel,
      );
    }

    final connectorCandidates = await _loadOpenStreetMapCandidates(
      trail: trail,
      client: client,
      includeConnectorRoads: true,
    );
    graphRoute = _graphRouteFor(
      trail,
      connectorCandidates,
      mode: _RouteCheckpointMode.allCheckpoints,
    );
    graphRoute ??= _graphRouteFor(
      trail,
      connectorCandidates,
      mode: _RouteCheckpointMode.endpointsOnly,
    );
    if (graphRoute != null) {
      return GoogleRouteResult(
        distanceMeters: graphRoute.distanceMeters,
        duration: _estimatedHikingDuration(graphRoute.distanceMeters),
        encodedPolyline: _PolylineEncoder.encode(graphRoute.points),
        sourceLabel: graphRoute.sourceLabel,
      );
    }

    throw const HikingRouteServiceException(
      'No connected hiking path found through this trail\'s checkpoints.',
    );
  }

  Future<List<_HikingCandidate>> _loadOpenStreetMapCandidates({
    required Trail trail,
    required http.Client client,
    required bool includeConnectorRoads,
  }) async {
    final center = _centerFor(trail);
    final radiusMeters = _searchRadiusMeters(trail);
    final walkableWays = includeConnectorRoads
        ? 'path|track|footway|steps|bridleway|pedestrian|service|residential|unclassified|living_street|road'
        : 'path|track|footway|steps|bridleway|pedestrian';
    final query =
        '''
[out:json][timeout:14];
rel(around:$radiusMeters,${center.latitude},${center.longitude})["route"="hiking"]->.hikingRoutes;
rel(around:$radiusMeters,${center.latitude},${center.longitude})["route"="foot"]->.footRoutes;
way(r.hikingRoutes)->.hikingRouteWays;
way(r.footRoutes)->.footRouteWays;
(
  .hikingRouteWays;
  .footRouteWays;
  way(around:$radiusMeters,${center.latitude},${center.longitude})["highway"~"$walkableWays"]["access"!~"private|no"]["foot"!~"no"];
  way(around:$radiusMeters,${center.latitude},${center.longitude})["foot"~"yes|designated|permissive"]["access"!~"private|no"];
  way(around:$radiusMeters,${center.latitude},${center.longitude})["sac_scale"];
  way(around:$radiusMeters,${center.latitude},${center.longitude})["trail_visibility"];
);
out tags geom;
''';

    http.Response? response;
    Object? lastError;
    for (final endpoint in _overpassEndpoints) {
      try {
        response = await client
            .post(
              endpoint,
              headers: const {
                'Accept': 'application/json',
                'Content-Type': 'application/x-www-form-urlencoded',
                'User-Agent': 'HikerCircle/1.0 route preview',
              },
              body: {'data': query},
            )
            .timeout(const Duration(seconds: 18));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          break;
        }
      } catch (error) {
        lastError = error;
      }
    }

    if (response == null) {
      throw HikingRouteServiceException(
        'OpenStreetMap Overpass unavailable: $lastError',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HikingRouteServiceException(
        'OpenStreetMap Overpass ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const HikingRouteServiceException(
        'OpenStreetMap returned an unexpected response.',
      );
    }

    final elements = decoded['elements'];
    if (elements is! List) {
      return const [];
    }

    return elements
        .whereType<Map>()
        .map(_candidateFromElement)
        .whereType<_HikingCandidate>()
        .toList();
  }

  _GraphRoute? _graphRouteFor(
    Trail trail,
    List<_HikingCandidate> candidates, {
    required _RouteCheckpointMode mode,
  }) {
    if (candidates.isEmpty) {
      return null;
    }

    final graph = _HikingGraph();
    for (final candidate in candidates) {
      graph.addWay(
        candidate.points,
        weightMultiplier: _routingWeightMultiplier(candidate.tags),
      );
    }
    graph.connectNearbyNodes(maxDistanceMeters: 22);

    if (graph.nodeCount < 2) {
      return null;
    }

    final sortedCheckpoints = [...trail.checkpoints]
      ..sort((a, b) => a.order.compareTo(b.order));
    final checkpoints = mode == _RouteCheckpointMode.allCheckpoints
        ? sortedCheckpoints
        : [sortedCheckpoints.first, sortedCheckpoints.last];
    final maxSnapDistance = _maxGraphSnapDistance(trail);
    final routePoints = <_LatLng>[];

    for (var index = 1; index < checkpoints.length; index++) {
      final origin = checkpoints[index - 1];
      final destination = checkpoints[index];
      final originNode = graph.nearestNode(
        _LatLng(origin.latitude, origin.longitude),
      );
      final destinationNode = graph.nearestNode(
        _LatLng(destination.latitude, destination.longitude),
      );

      if (originNode == null ||
          destinationNode == null ||
          originNode.distanceMeters > maxSnapDistance ||
          destinationNode.distanceMeters > maxSnapDistance) {
        return null;
      }

      final segment = graph.shortestPath(
        originNode.nodeIndex,
        destinationNode.nodeIndex,
      );
      if (segment.length < 2) {
        return null;
      }

      if (routePoints.isEmpty) {
        routePoints.addAll(segment);
      } else {
        routePoints.addAll(segment.skip(1));
      }
    }

    final simplifiedPoints = _simplifyForStaticMap(routePoints);
    if (simplifiedPoints.length < 2) {
      return null;
    }

    final distanceMeters = _pathDistanceMeters(routePoints).round();
    if (!_routeDistanceLooksUsable(trail, distanceMeters)) {
      return null;
    }

    return _GraphRoute(
      points: simplifiedPoints,
      distanceMeters: distanceMeters,
      sourceLabel: mode == _RouteCheckpointMode.allCheckpoints
          ? 'OSM connected walking/hiking route'
          : 'OSM start-to-end walking/hiking route',
    );
  }

  _HikingCandidate? _candidateFromElement(Map element) {
    final rawGeometry = element['geometry'];
    if (rawGeometry is! List || rawGeometry.length < 2) {
      return null;
    }

    final points = rawGeometry
        .whereType<Map>()
        .map((point) {
          final lat = point['lat'];
          final lon = point['lon'];
          if (lat is! num || lon is! num) {
            return null;
          }
          return _LatLng(lat.toDouble(), lon.toDouble());
        })
        .whereType<_LatLng>()
        .toList();

    if (points.length < 2) {
      return null;
    }

    final tags = element['tags'] is Map
        ? Map<String, dynamic>.from(element['tags'] as Map)
        : <String, dynamic>{};

    return _HikingCandidate(points: points, tags: tags);
  }

  double _routingWeightMultiplier(Map<String, dynamic> tags) {
    final highway = tags['highway'];
    if (tags.containsKey('sac_scale') || tags.containsKey('trail_visibility')) {
      return 0.7;
    }
    if (highway == 'path' || highway == 'footway' || highway == 'steps') {
      return 0.8;
    }
    if (highway == 'track' || highway == 'bridleway') {
      return 1.0;
    }
    if (highway == 'pedestrian' || highway == 'living_street') {
      return 1.3;
    }
    if (highway == 'service' ||
        highway == 'residential' ||
        highway == 'unclassified' ||
        highway == 'road') {
      return 2.2;
    }
    return 1.5;
  }

  bool _routeDistanceLooksUsable(Trail trail, int distanceMeters) {
    final expectedDistanceMeters = trail.distanceKm * 1000;
    if (expectedDistanceMeters <= 0) {
      return true;
    }

    final ratio = distanceMeters / expectedDistanceMeters;
    return ratio >= 0.45 && ratio <= 2.1;
  }

  _LatLng _centerFor(Trail trail) {
    final checkpoints = trail.checkpoints;
    final latitude =
        checkpoints.fold<double>(0, (sum, point) => sum + point.latitude) /
        checkpoints.length;
    final longitude =
        checkpoints.fold<double>(0, (sum, point) => sum + point.longitude) /
        checkpoints.length;
    return _LatLng(latitude, longitude);
  }

  int _searchRadiusMeters(Trail trail) {
    final start = trail.checkpoints.first;
    final end = trail.checkpoints.last;
    final directDistance = _distanceMeters(
      _LatLng(start.latitude, start.longitude),
      _LatLng(end.latitude, end.longitude),
    );
    return (directDistance + 2500).clamp(2200, 8500).round();
  }

  double _maxGraphSnapDistance(Trail trail) {
    final expectedTrailDistanceMeters = trail.distanceKm * 1000;
    if (expectedTrailDistanceMeters <= 0) {
      return 180;
    }
    return (expectedTrailDistanceMeters * 0.045).clamp(90, 420).toDouble();
  }

  Duration _estimatedHikingDuration(int distanceMeters) {
    const hikingSpeedMetersPerHour = 3200;
    final minutes = math.max(
      1,
      (distanceMeters / hikingSpeedMetersPerHour * 60).round(),
    );
    return Duration(minutes: minutes);
  }

  double _pathDistanceMeters(List<_LatLng> points) {
    var distance = 0.0;
    for (var index = 1; index < points.length; index++) {
      distance += _distanceMeters(points[index - 1], points[index]);
    }
    return distance;
  }

  List<_LatLng> _simplifyForStaticMap(List<_LatLng> points) {
    if (points.length <= 160) {
      return points;
    }

    var simplified = _douglasPeucker(points, toleranceMeters: 10);
    if (simplified.length <= 160) {
      return simplified;
    }

    final stride = (simplified.length / 150).ceil();
    simplified = [
      for (var index = 0; index < simplified.length; index += stride)
        simplified[index],
      if (simplified.last != points.last) points.last,
    ];
    return simplified;
  }

  List<_LatLng> _douglasPeucker(
    List<_LatLng> points, {
    required double toleranceMeters,
  }) {
    if (points.length <= 2) {
      return points;
    }

    var maxDistance = 0.0;
    var splitIndex = 0;
    for (var index = 1; index < points.length - 1; index++) {
      final distance = _perpendicularDistanceMeters(
        point: points[index],
        lineStart: points.first,
        lineEnd: points.last,
      );
      if (distance > maxDistance) {
        maxDistance = distance;
        splitIndex = index;
      }
    }

    if (maxDistance <= toleranceMeters) {
      return [points.first, points.last];
    }

    final left = _douglasPeucker(
      points.sublist(0, splitIndex + 1),
      toleranceMeters: toleranceMeters,
    );
    final right = _douglasPeucker(
      points.sublist(splitIndex),
      toleranceMeters: toleranceMeters,
    );
    return [...left.take(left.length - 1), ...right];
  }

  double _perpendicularDistanceMeters({
    required _LatLng point,
    required _LatLng lineStart,
    required _LatLng lineEnd,
  }) {
    final segmentLength = _distanceMeters(lineStart, lineEnd);
    if (segmentLength == 0) {
      return _distanceMeters(point, lineStart);
    }

    final x0 =
        _degreesToRadians(point.longitude - lineStart.longitude) *
        math.cos(_degreesToRadians((point.latitude + lineStart.latitude) / 2)) *
        6371000;
    final y0 = _degreesToRadians(point.latitude - lineStart.latitude) * 6371000;
    final x1 =
        _degreesToRadians(lineEnd.longitude - lineStart.longitude) *
        math.cos(
          _degreesToRadians((lineEnd.latitude + lineStart.latitude) / 2),
        ) *
        6371000;
    final y1 =
        _degreesToRadians(lineEnd.latitude - lineStart.latitude) * 6371000;

    final area = (x1 * y0 - y1 * x0).abs();
    return area / segmentLength;
  }

  double _distanceMeters(_LatLng a, _LatLng b) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _degreesToRadians(b.latitude - a.latitude);
    final dLon = _degreesToRadians(b.longitude - a.longitude);
    final lat1 = _degreesToRadians(a.latitude);
    final lat2 = _degreesToRadians(b.latitude);
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * earthRadiusMeters * math.asin(math.sqrt(h));
  }

  double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180;
  }
}

final _overpassEndpoints = [
  Uri.https('overpass-api.de', '/api/interpreter'),
  Uri.https('overpass.kumi.systems', '/api/interpreter'),
  Uri.https('overpass.osm.ch', '/api/interpreter'),
];

enum _RouteCheckpointMode { allCheckpoints, endpointsOnly }

class _GraphRoute {
  const _GraphRoute({
    required this.points,
    required this.distanceMeters,
    required this.sourceLabel,
  });

  final List<_LatLng> points;
  final int distanceMeters;
  final String sourceLabel;
}

class _HikingCandidate {
  const _HikingCandidate({required this.points, required this.tags});

  final List<_LatLng> points;
  final Map<String, dynamic> tags;
}

class _LatLng {
  const _LatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class _NearestNode {
  const _NearestNode({required this.nodeIndex, required this.distanceMeters});

  final int nodeIndex;
  final double distanceMeters;
}

class _GraphEdge {
  const _GraphEdge({required this.to, required this.weightMeters});

  final int to;
  final double weightMeters;
}

class _QueueEntry {
  const _QueueEntry({required this.nodeIndex, required this.distanceMeters});

  final int nodeIndex;
  final double distanceMeters;
}

class _MinHeap {
  final _items = <_QueueEntry>[];

  bool get isEmpty => _items.isEmpty;

  void add(_QueueEntry entry) {
    _items.add(entry);
    _bubbleUp(_items.length - 1);
  }

  _QueueEntry removeMin() {
    final min = _items.first;
    final last = _items.removeLast();
    if (_items.isNotEmpty) {
      _items[0] = last;
      _bubbleDown(0);
    }
    return min;
  }

  void _bubbleUp(int index) {
    while (index > 0) {
      final parent = (index - 1) >> 1;
      if (_items[parent].distanceMeters <= _items[index].distanceMeters) {
        break;
      }
      _swap(parent, index);
      index = parent;
    }
  }

  void _bubbleDown(int index) {
    while (true) {
      final left = index * 2 + 1;
      final right = left + 1;
      var smallest = index;

      if (left < _items.length &&
          _items[left].distanceMeters < _items[smallest].distanceMeters) {
        smallest = left;
      }
      if (right < _items.length &&
          _items[right].distanceMeters < _items[smallest].distanceMeters) {
        smallest = right;
      }
      if (smallest == index) {
        break;
      }
      _swap(index, smallest);
      index = smallest;
    }
  }

  void _swap(int first, int second) {
    final value = _items[first];
    _items[first] = _items[second];
    _items[second] = value;
  }
}

class _HikingGraph {
  final _nodes = <_LatLng>[];
  final _nodeIndexes = <String, int>{};
  final _edges = <int, List<_GraphEdge>>{};

  int get nodeCount => _nodes.length;

  void addWay(List<_LatLng> points, {required double weightMultiplier}) {
    if (points.length < 2) {
      return;
    }

    for (var index = 1; index < points.length; index++) {
      final from = _nodeIndexFor(points[index - 1]);
      final to = _nodeIndexFor(points[index]);
      if (from == to) {
        continue;
      }
      final distance =
          _distanceBetween(points[index - 1], points[index]) * weightMultiplier;
      _addEdgePair(from, to, distance);
    }
  }

  void connectNearbyNodes({required double maxDistanceMeters}) {
    if (_nodes.length < 2) {
      return;
    }

    const cellSizeDegrees = 0.00022;
    final buckets = <String, List<int>>{};
    for (var index = 0; index < _nodes.length; index++) {
      final key = _bucketKey(_nodes[index], cellSizeDegrees);
      buckets.putIfAbsent(key, () => []).add(index);
    }

    for (var index = 0; index < _nodes.length; index++) {
      final point = _nodes[index];
      final latBucket = (point.latitude / cellSizeDegrees).floor();
      final lonBucket = (point.longitude / cellSizeDegrees).floor();
      for (var dLat = -1; dLat <= 1; dLat++) {
        for (var dLon = -1; dLon <= 1; dLon++) {
          final nearbyIndexes =
              buckets['${latBucket + dLat}:'
                  '${lonBucket + dLon}'];
          if (nearbyIndexes == null) {
            continue;
          }
          for (final otherIndex in nearbyIndexes) {
            if (otherIndex <= index || _hasEdge(index, otherIndex)) {
              continue;
            }
            final distance = _distanceBetween(point, _nodes[otherIndex]);
            if (distance > 0 && distance <= maxDistanceMeters) {
              _addEdgePair(index, otherIndex, distance * 1.15);
            }
          }
        }
      }
    }
  }

  _NearestNode? nearestNode(_LatLng target) {
    if (_nodes.isEmpty) {
      return null;
    }

    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var index = 0; index < _nodes.length; index++) {
      final distance = _distanceBetween(_nodes[index], target);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    }

    return _NearestNode(nodeIndex: bestIndex, distanceMeters: bestDistance);
  }

  List<_LatLng> shortestPath(int origin, int destination) {
    final distances = List<double>.filled(_nodes.length, double.infinity);
    final previous = List<int?>.filled(_nodes.length, null);
    final queue = _MinHeap();

    distances[origin] = 0;
    queue.add(_QueueEntry(nodeIndex: origin, distanceMeters: 0));

    while (!queue.isEmpty) {
      final current = queue.removeMin();
      if (current.distanceMeters > distances[current.nodeIndex]) {
        continue;
      }
      if (current.nodeIndex == destination) {
        break;
      }

      for (final edge in _edges[current.nodeIndex] ?? const <_GraphEdge>[]) {
        final nextDistance = current.distanceMeters + edge.weightMeters;
        if (nextDistance >= distances[edge.to]) {
          continue;
        }
        distances[edge.to] = nextDistance;
        previous[edge.to] = current.nodeIndex;
        queue.add(
          _QueueEntry(nodeIndex: edge.to, distanceMeters: nextDistance),
        );
      }
    }

    if (!distances[destination].isFinite) {
      return const [];
    }

    final routeIndexes = <int>[];
    int? current = destination;
    while (current != null) {
      routeIndexes.add(current);
      if (current == origin) {
        break;
      }
      current = previous[current];
    }

    if (routeIndexes.last != origin) {
      return const [];
    }

    return routeIndexes.reversed.map((index) => _nodes[index]).toList();
  }

  int _nodeIndexFor(_LatLng point) {
    final key = _nodeKey(point);
    final existing = _nodeIndexes[key];
    if (existing != null) {
      return existing;
    }

    final index = _nodes.length;
    _nodes.add(point);
    _nodeIndexes[key] = index;
    return index;
  }

  void _addEdgePair(int from, int to, double distance) {
    _edges
        .putIfAbsent(from, () => [])
        .add(_GraphEdge(to: to, weightMeters: distance));
    _edges
        .putIfAbsent(to, () => [])
        .add(_GraphEdge(to: from, weightMeters: distance));
  }

  bool _hasEdge(int from, int to) {
    return _edges[from]?.any((edge) => edge.to == to) ?? false;
  }

  String _nodeKey(_LatLng point) {
    final lat = (point.latitude * 1000000).round();
    final lon = (point.longitude * 1000000).round();
    return '$lat:$lon';
  }

  String _bucketKey(_LatLng point, double cellSizeDegrees) {
    final latBucket = (point.latitude / cellSizeDegrees).floor();
    final lonBucket = (point.longitude / cellSizeDegrees).floor();
    return '$latBucket:$lonBucket';
  }

  double _distanceBetween(_LatLng a, _LatLng b) {
    const earthRadiusMeters = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * earthRadiusMeters * math.asin(math.sqrt(h));
  }
}

abstract final class _PolylineEncoder {
  static String encode(List<_LatLng> points) {
    var previousLatitude = 0;
    var previousLongitude = 0;
    final buffer = StringBuffer();

    for (final point in points) {
      final latitude = (point.latitude * 100000).round();
      final longitude = (point.longitude * 100000).round();
      buffer
        ..write(_encodeValue(latitude - previousLatitude))
        ..write(_encodeValue(longitude - previousLongitude));
      previousLatitude = latitude;
      previousLongitude = longitude;
    }

    return buffer.toString();
  }

  static String _encodeValue(int value) {
    var encoded = value < 0 ? ~(value << 1) : value << 1;
    final buffer = StringBuffer();
    while (encoded >= 0x20) {
      buffer.writeCharCode((0x20 | (encoded & 0x1f)) + 63);
      encoded >>= 5;
    }
    buffer.writeCharCode(encoded + 63);
    return buffer.toString();
  }
}

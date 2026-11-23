// TrailHazardEnrichmentService relates OSM water/bridge features and terrain-derived steep sections
// to positions along a trail route.
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../app/Data/local_session_database.dart';
import '../../trail/Model/trail_models.dart';
import 'hiking_route_service.dart';

/// Adds route-specific cautions that are not exposed by Mapbox Streets.
///
/// OpenStreetMap supplies mapped ford, assisted-trail, scrambling and surface
/// tags. Open-Meteo's Copernicus DEM elevation samples supply estimated steep
/// ascent/descent sections. Results are persisted by the caller in the same
/// offline SQLite hazard dataset as the Mapbox cautions.
class TrailHazardEnrichmentService {
  /// Creates trail hazard enrichment service.
  TrailHazardEnrichmentService({
    required http.Client client,
    Uri? overpassEndpoint,
    Uri? elevationEndpoint,
  }) : _client = client,
       _overpassEndpoint =
           overpassEndpoint ??
           Uri.parse('https://overpass-api.de/api/interpreter'),
       _elevationEndpoint =
           elevationEndpoint ??
           Uri.parse('https://api.open-meteo.com/v1/elevation');

  final http.Client _client;
  final Uri _overpassEndpoint;
  final Uri _elevationEndpoint;

  static const _osmSourceUrl = 'https://www.openstreetmap.org/';
  static const _elevationSourceUrl =
      'https://open-meteo.com/en/docs/elevation-api';
  static const _routeCorridorMeters = 35.0;
  // Cautions begin at 12.5 degrees in either travel direction.
  static final _minimumSteepGradePercent = math.tan(12.5 * math.pi / 180) * 100;
  static const _minimumSteepRiseMeters = 15.0;
  static const _steepWindowIntervals = 3;
  static const _maximumElevationSamples = 500;
  static const _elevationSpacingMeters = 100.0;
  static const _maximumOverpassPointsPerQuery = 60;

  /// Fetches for trail.
  Future<List<LocalTrailHazardMatch>> fetchForTrail({
    required Trail trail,
    required List<LatLng> routePoints,
  }) async {
    if (routePoints.isEmpty) return const [];
    final results = <LocalTrailHazardMatch>[];
    try {
      results.addAll(await _fetchOsmHazards(trail, routePoints));
    } catch (_) {
      // Each provider is optional. Keep any hazards supplied by the other
      // provider and allow the existing offline dataset to remain usable.
    }
    try {
      results.addAll(await _fetchSteepSections(trail, routePoints));
    } catch (_) {}
    return _deduplicate(results);
  }

  /// Fetches osm hazards.
  Future<List<LocalTrailHazardMatch>> _fetchOsmHazards(
    Trail trail,
    List<LatLng> routePoints,
  ) async {
    final queryPoints = _sampleRoute(
      routePoints,
      spacingMeters: 120,
      maximumPoints: 720,
    );
    final chunks = <List<_RoutePosition>>[];
    for (var start = 0; start < queryPoints.length; start += 59) {
      final end = math.min(
        start + _maximumOverpassPointsPerQuery,
        queryPoints.length,
      );
      chunks.add(queryPoints.sublist(start, end));
      if (end == queryPoints.length) break;
    }

    final byElement = <String, Map<String, dynamic>>{};
    for (final chunk in chunks) {
      final coordinates = chunk
          .map(
            (position) =>
                '${position.point.latitude.toStringAsFixed(6)},'
                '${position.point.longitude.toStringAsFixed(6)}',
          )
          .join();
      final around =
          '(around:${_routeCorridorMeters.round()},'
          '${coordinates.substring(0, coordinates.length - 1)})';
      final query =
          '''
[out:json][timeout:25];
(
  nwr["ford"]$around;
  nwr["bridge"]$around;
  nwr["waterway"~"^(river|stream)\$"]$around;
  nwr["highway"~"^(ford|ladder|via_ferrata)\$"]$around;
  nwr[~"^(assisted_trail|ladder|safety_rope|rungs)\$"~"."]$around;
  nwr["sac_scale"~"^(demanding_mountain_hiking|alpine_hiking|demanding_alpine_hiking|difficult_alpine_hiking)\$"]$around;
  nwr[~"^(surface|smoothness|tracktype|natural)\$"~"^(mud|scree|loose_gravel|rock|stone|rocky|pebblestone|gravel|bad|very_bad|horrible|very_horrible|impassable|grade4|grade5)\$"]$around;
);
out body geom;
''';
      // API: Overpass trail hazards
      final response = await _client
          .post(
            _overpassEndpoint,
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded',
              'User-Agent': 'HikerCircle/1.1 trail-hazard-cache',
            },
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw StateError('Overpass returned HTTP ${response.statusCode}.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['elements'] is! List) continue;
      for (final raw in (decoded['elements'] as List).whereType<Map>()) {
        final element = Map<String, dynamic>.from(raw);
        final key = '${element['type']}:${element['id']}';
        byElement[key] = element;
      }
    }

    final matches = <LocalTrailHazardMatch>[];
    matches.addAll(
      _parseOsmWaterAndBridges(trail, routePoints, byElement.values),
    );
    for (final element in byElement.values) {
      matches.addAll(_parseOsmElement(trail, routePoints, element));
    }
    return matches;
  }

  /// Parses osm element.
  List<LocalTrailHazardMatch> _parseOsmElement(
    Trail trail,
    List<LatLng> routePoints,
    Map<String, dynamic> element,
  ) {
    final rawTags = element['tags'];
    if (rawTags is! Map) return const [];
    final tags = <String, String>{
      for (final entry in rawTags.entries)
        entry.key.toString().toLowerCase(): entry.value
            .toString()
            .toLowerCase(),
    };
    final geometry = _elementGeometry(element);
    if (geometry.isEmpty) return const [];
    final nearest = _nearestGeometryToRoute(geometry, routePoints);
    if (nearest.distanceMeters > _routeCorridorMeters + 5) return const [];

    final types = _osmHazardTypes(tags);
    if (types.isEmpty) return const [];
    final elementType = element['type']?.toString() ?? 'element';
    final elementId =
        element['id']?.toString() ??
        '${nearest.featurePoint.latitude.toStringAsFixed(5)},'
            '${nearest.featurePoint.longitude.toStringAsFixed(5)}';
    final now = DateTime.now().toUtc();
    return [
      for (final type in types)
        () {
          final content = _contentFor(type, tags);
          final hazard = LocalStaticHazard(
            hazardId: 'osm:${trail.trailId}:$type:$elementType:$elementId',
            hazardType: type,
            title: content.title,
            description: content.description,
            latitude: nearest.featurePoint.latitude,
            longitude: nearest.featurePoint.longitude,
            severity: nearest.distanceMeters <= 10 ? 'warning' : 'caution',
            confidence: 'mapped_osm_tag',
            sourceName: 'OpenStreetMap contributors',
            sourceUrl: _osmSourceUrl,
            sourceFeatureId: '$elementType/$elementId',
            safetyGuidance: content.guidance,
            downloadedAt: now,
            expiresAt: now.add(const Duration(days: 90)),
          );
          return LocalTrailHazardMatch(
            trailId: trail.trailId,
            hazard: hazard,
            relationship: nearest.distanceMeters <= 10
                ? 'on_route'
                : 'near_route',
            distanceMeters: nearest.distanceMeters,
            routeProgress: nearest.routeProgress,
            computedAt: now,
          );
        }(),
    ];
  }

  /// Parses osm water and bridges.
  List<LocalTrailHazardMatch> _parseOsmWaterAndBridges(
    Trail trail,
    List<LatLng> routePoints,
    Iterable<Map<String, dynamic>> elements,
  ) {
    final waterways =
        <({Map<String, dynamic> element, List<LatLng> geometry})>[];
    final crossings =
        <({Map<String, dynamic> element, List<LatLng> geometry})>[];
    for (final element in elements) {
      final rawTags = element['tags'];
      if (rawTags is! Map) continue;
      final tags = <String, String>{
        for (final entry in rawTags.entries)
          entry.key.toString().toLowerCase(): entry.value
              .toString()
              .toLowerCase(),
      };
      final geometry = _elementGeometry(element);
      if (geometry.isEmpty) continue;
      if (const {'river', 'stream'}.contains(tags['waterway'])) {
        waterways.add((element: element, geometry: geometry));
      }
      final isFord =
          (tags['ford'] != null && tags['ford'] != 'no') ||
          tags['highway'] == 'ford';
      final isHikingBridge =
          _isPositiveTag(tags['bridge']) && _isHikingBridge(tags);
      if (isHikingBridge || isFord) {
        crossings.add((element: element, geometry: geometry));
      }
    }

    final now = DateTime.now().toUtc();
    final matches = <LocalTrailHazardMatch>[];
    for (final crossing in crossings) {
      final tags = Map<String, dynamic>.from(crossing.element['tags'] as Map);
      if (!_isPositiveTag(tags['bridge']?.toString().toLowerCase())) continue;
      final nearest = _nearestGeometryToRoute(crossing.geometry, routePoints);
      if (nearest.distanceMeters > 15) continue;
      final elementType = crossing.element['type']?.toString() ?? 'way';
      final elementId = crossing.element['id']?.toString() ?? 'mapped';
      final hazard = LocalStaticHazard(
        hazardId:
            'osm:${trail.trailId}:bridge_crossing:$elementType:$elementId',
        hazardType: 'bridge_crossing',
        title: 'Mapped bridge crossing',
        description:
            'OpenStreetMap identifies a bridge on this route. Its present condition and accessibility are not verified.',
        latitude: nearest.featurePoint.latitude,
        longitude: nearest.featurePoint.longitude,
        severity: nearest.distanceMeters <= 10 ? 'warning' : 'caution',
        confidence: 'mapped_osm_tag',
        sourceName: 'OpenStreetMap contributors',
        sourceUrl: _osmSourceUrl,
        sourceFeatureId: '$elementType/$elementId',
        safetyGuidance:
            'Inspect the bridge before crossing. Do not use it if damaged, submerged, closed or unsafe after heavy rain.',
        downloadedAt: now,
        expiresAt: now.add(const Duration(days: 90)),
      );
      matches.add(
        LocalTrailHazardMatch(
          trailId: trail.trailId,
          hazard: hazard,
          relationship: 'bridge_crossing',
          distanceMeters: nearest.distanceMeters,
          routeProgress: nearest.routeProgress,
          computedAt: now,
        ),
      );
    }

    for (final waterway in waterways) {
      final nearest = _nearestGeometryToRoute(waterway.geometry, routePoints);
      if (nearest.distanceMeters > 10) continue;
      final hasMappedCrossing = crossings.any(
        (crossing) =>
            _minimumGeometryDistance(waterway.geometry, crossing.geometry) <=
            30,
      );
      if (hasMappedCrossing) continue;
      final rawTags = Map<String, dynamic>.from(
        waterway.element['tags'] as Map,
      );
      final waterwayType =
          rawTags['intermittent']?.toString().toLowerCase() == 'yes'
          ? 'stream_intermittent'
          : rawTags['waterway']?.toString().toLowerCase() ?? 'stream';
      final elementType = waterway.element['type']?.toString() ?? 'way';
      final elementId = waterway.element['id']?.toString() ?? 'mapped';
      final label = waterwayType == 'stream_intermittent'
          ? 'seasonal stream'
          : waterwayType;
      final hazard = LocalStaticHazard(
        hazardId: 'osm:${trail.trailId}:$waterwayType:$elementType:$elementId',
        hazardType: waterwayType,
        title: 'Possible water crossing',
        description:
            'OpenStreetMap places a $label within ${nearest.distanceMeters.round()} m of this route. This does not confirm present depth, flow or a safe crossing.',
        latitude: nearest.featurePoint.latitude,
        longitude: nearest.featurePoint.longitude,
        severity: 'warning',
        confidence: 'mapped_osm_geometry',
        sourceName: 'OpenStreetMap contributors',
        sourceUrl: _osmSourceUrl,
        sourceFeatureId: '$elementType/$elementId',
        safetyGuidance:
            'Check the actual crossing, recent rainfall and local advice. Do not enter fast, rising or opaque water.',
        downloadedAt: now,
        expiresAt: now.add(const Duration(days: 90)),
      );
      matches.add(
        LocalTrailHazardMatch(
          trailId: trail.trailId,
          hazard: hazard,
          relationship: 'possible_crossing',
          distanceMeters: nearest.distanceMeters,
          routeProgress: nearest.routeProgress,
          computedAt: now,
        ),
      );
    }
    return matches;
  }

  /// Checks whether hiking bridge.
  bool _isHikingBridge(Map<String, String> tags) {
    // Exclude motorway/street bridges that merely pass above or below the
    // trail. Distance-to-polyline alone cannot distinguish grade-separated
    // crossings, while these OSM highway values describe a trail segment.
    return const {
      'path',
      'footway',
      'steps',
      'pedestrian',
      'track',
      'bridleway',
    }.contains(tags['highway']);
  }

  /// Computes osm hazard types.
  List<String> _osmHazardTypes(Map<String, String> tags) {
    final types = <String>[];
    final ford = tags['ford'];
    if ((ford != null && ford != 'no') || tags['highway'] == 'ford') {
      types.add(
        ford == 'stepping_stones' ? 'stepping_stones' : 'ford_crossing',
      );
    }
    if (tags['highway'] == 'ladder' ||
        _isPositiveTag(tags['ladder']) ||
        _isPositiveTag(tags['rungs'])) {
      types.add('ladder_section');
    } else if (_isPositiveTag(tags['safety_rope']) ||
        _isPositiveTag(tags['assisted_trail'])) {
      types.add('rope_assisted_section');
    } else if (tags['highway'] == 'via_ferrata' ||
        const {
          'demanding_mountain_hiking',
          'alpine_hiking',
          'demanding_alpine_hiking',
          'difficult_alpine_hiking',
        }.contains(tags['sac_scale'])) {
      types.add('scrambling_section');
    }

    final surface = tags['surface'];
    final natural = tags['natural'];
    if (natural == 'scree' ||
        const {'scree', 'loose_gravel'}.contains(surface)) {
      types.add('loose_rock');
    } else if (surface == 'mud') {
      types.add('muddy_surface');
    } else if (const {
          'rock',
          'stone',
          'rocky',
          'pebblestone',
          'gravel',
        }.contains(surface) ||
        const {
          'bad',
          'very_bad',
          'horrible',
          'very_horrible',
          'impassable',
        }.contains(tags['smoothness']) ||
        const {'grade4', 'grade5'}.contains(tags['tracktype'])) {
      types.add('rough_surface');
    }
    return types.toSet().toList(growable: false);
  }

  /// Checks whether positive tag.
  bool _isPositiveTag(String? value) {
    return value != null &&
        value.isNotEmpty &&
        value != 'no' &&
        value != 'none';
  }

  /// Computes content for.
  ({String title, String description, String guidance}) _contentFor(
    String type,
    Map<String, String> tags,
  ) {
    return switch (type) {
      'stepping_stones' => (
        title: 'Stepping-stone river crossing',
        description:
            'OpenStreetMap identifies stepping stones on or beside this route. Water depth, flow and stone condition can change.',
        guidance:
            'Check recent rain and water flow. Turn back if stones are submerged, slippery or the crossing is uncertain.',
      ),
      'ford_crossing' => (
        title: 'River ford crossing',
        description:
            'OpenStreetMap identifies a ford on or beside this route. A ford requires passing through the water.',
        guidance:
            'Assess depth, speed and footing before entering. Do not cross fast, rising or opaque water.',
      ),
      'ladder_section' => (
        title: 'Ladder or rung section',
        description:
            'OpenStreetMap identifies a ladder or fixed-rung section near this route.',
        guidance:
            'Keep three points of contact, allow one hiker at a time and avoid the section if equipment is loose or damaged.',
      ),
      'rope_assisted_section' => (
        title: 'Rope-assisted section',
        description:
            'OpenStreetMap identifies fixed rope or other trail assistance near this route.',
        guidance:
            'Inspect the aid before loading it, maintain spacing and avoid relying on damaged or waterlogged equipment.',
      ),
      'scrambling_section' => (
        title: 'Scrambling section',
        description:
            'Mapped hiking difficulty indicates a section where hands, careful route choice or exposed movement may be required.',
        guidance:
            'Proceed only with suitable experience and dry conditions. Turn back if exposure or footing exceeds the group\'s ability.',
      ),
      'loose_rock' => (
        title: 'Loose rock or scree',
        description:
            'Mapped surface data identifies loose rock, scree or loose gravel near this route.',
        guidance:
            'Use deliberate footing, keep distance between hikers and avoid dislodging rocks onto people below.',
      ),
      'muddy_surface' => (
        title: 'Muddy trail surface',
        description:
            'Mapped surface data identifies mud near this route. Conditions may worsen after rain.',
        guidance:
            'Use footwear with grip, slow down and avoid widening the trail around muddy sections.',
      ),
      _ => (
        title: 'Rough trail surface',
        description:
            'Mapped surface data identifies rough, rocky or poorly passable ground near this route.',
        guidance:
            'Allow extra time, watch footing and reassess if the surface is unstable or unsuitable for the group.',
      ),
    };
  }

  /// Fetches steep sections.
  Future<List<LocalTrailHazardMatch>> _fetchSteepSections(
    Trail trail,
    List<LatLng> routePoints,
  ) async {
    final positions = _sampleRoute(
      routePoints,
      spacingMeters: _elevationSpacingMeters,
      maximumPoints: _maximumElevationSamples,
    );
    if (positions.length < 2) return const [];
    final elevations = <double?>[];
    for (var start = 0; start < positions.length; start += 100) {
      final chunk = positions.sublist(
        start,
        math.min(start + 100, positions.length),
      );
      final uri = _elevationEndpoint.replace(
        queryParameters: {
          'latitude': chunk
              .map((position) => position.point.latitude.toStringAsFixed(6))
              .join(','),
          'longitude': chunk
              .map((position) => position.point.longitude.toStringAsFixed(6))
              .join(','),
        },
      );
      // API: Open-Meteo route elevations
      final response = await _client
          .get(uri, headers: const {'User-Agent': 'HikerCircle/1.1'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw StateError('Elevation API returned HTTP ${response.statusCode}.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['elevation'] is! List) {
        throw const FormatException('Elevation API response is incomplete.');
      }
      final values = (decoded['elevation'] as List)
          .map((value) => value is num ? value.toDouble() : null)
          .toList(growable: false);
      if (values.length != chunk.length) {
        throw const FormatException(
          'Elevation API returned the wrong sample count.',
        );
      }
      elevations.addAll(values);
    }

    final candidates = <_SteepCandidate>[];
    for (var index = _steepWindowIntervals; index < positions.length; index++) {
      final previousElevation = elevations[index - _steepWindowIntervals];
      final elevation = elevations[index];
      if (previousElevation == null || elevation == null) continue;
      var horizontal = 0.0;
      for (
        var segment = index - _steepWindowIntervals + 1;
        segment <= index;
        segment++
      ) {
        horizontal += _distance(
          positions[segment - 1].point,
          positions[segment].point,
        );
      }
      if (horizontal < 60) continue;
      final rise = elevation - previousElevation;
      final grade = rise / horizontal * 100;
      if (grade.abs() < _minimumSteepGradePercent ||
          rise.abs() < _minimumSteepRiseMeters) {
        continue;
      }
      candidates.add(
        _SteepCandidate(
          index: index,
          type: grade > 0 ? 'steep_ascent' : 'steep_descent',
          gradePercent: grade,
          riseMeters: rise,
          spanMeters: horizontal,
          position: positions[index],
        ),
      );
    }
    if (candidates.isEmpty) return const [];

    final runs = <_SteepCandidate>[];
    var current = candidates.first;
    var previousIndex = current.index;
    for (final candidate in candidates.skip(1)) {
      if (candidate.type == current.type &&
          candidate.index <= previousIndex + 1) {
        if (candidate.gradePercent.abs() > current.gradePercent.abs()) {
          current = candidate;
        }
      } else {
        runs.add(current);
        current = candidate;
      }
      previousIndex = candidate.index;
    }
    runs.add(current);

    final now = DateTime.now().toUtc();
    return [
      for (final candidate in runs)
        () {
          final ascent = candidate.type == 'steep_ascent';
          final grade = candidate.gradePercent.abs().round();
          final rise = candidate.riseMeters.abs().round();
          final span = candidate.spanMeters.round();
          final steepness = grade >= 40
              ? 'Extremely steep'
              : grade >= 30
              ? 'Very steep'
              : 'Steep';
          final hazard = LocalStaticHazard(
            hazardId:
                'terrain:${trail.trailId}:${candidate.type}:'
                '${(candidate.position.progress * 10000).round()}',
            hazardType: candidate.type,
            title: ascent ? 'Steep uphill section' : 'Steep downhill section',
            description:
                '$steepness ${ascent ? 'climb' : 'descent'} ahead. The route '
                '${ascent ? 'rises' : 'drops'} about $rise m over roughly '
                '$span m.',
            latitude: candidate.position.point.latitude,
            longitude: candidate.position.point.longitude,
            severity: grade >= 35 ? 'warning' : 'caution',
            confidence: 'terrain_estimate_90m',
            sourceName: 'Open-Meteo / Copernicus DEM',
            sourceUrl: _elevationSourceUrl,
            sourceFeatureId:
                '${candidate.type}:${candidate.position.progress.toStringAsFixed(4)}:'
                'grade=$grade:change=$rise:span=$span',
            safetyGuidance: ascent
                ? 'Shorten your pace, keep the group together and turn back if fatigue or footing becomes unsafe.'
                : 'Descend slowly with controlled steps, keep spacing and avoid loose or wet edges.',
            downloadedAt: now,
            expiresAt: now.add(const Duration(days: 90)),
          );
          return LocalTrailHazardMatch(
            trailId: trail.trailId,
            hazard: hazard,
            relationship: 'on_route',
            distanceMeters: 0,
            routeProgress: candidate.position.progress,
            computedAt: now,
          );
        }(),
    ];
  }

  /// Computes element geometry.
  List<LatLng> _elementGeometry(Map<String, dynamic> element) {
    final geometry = element['geometry'];
    if (geometry is List) {
      return geometry
          .whereType<Map>()
          .map(
            (point) => LatLng(
              (point['lat'] as num?)?.toDouble() ?? double.nan,
              (point['lon'] as num?)?.toDouble() ?? double.nan,
            ),
          )
          .where((point) => point.latitude.isFinite && point.longitude.isFinite)
          .toList(growable: false);
    }
    final latitude =
        (element['lat'] as num?)?.toDouble() ??
        ((element['center'] as Map?)?['lat'] as num?)?.toDouble();
    final longitude =
        (element['lon'] as num?)?.toDouble() ??
        ((element['center'] as Map?)?['lon'] as num?)?.toDouble();
    if (latitude == null || longitude == null) return const [];
    return [LatLng(latitude, longitude)];
  }

  /// Computes nearest geometry to route.
  _NearestRouteMatch _nearestGeometryToRoute(
    List<LatLng> geometry,
    List<LatLng> route,
  ) {
    var bestDistance = double.infinity;
    var bestFeaturePoint = geometry.first;
    var bestProgress = 0.0;
    for (final featurePoint in geometry) {
      if (route.length == 1) {
        final distance = _distance(featurePoint, route.single);
        if (distance < bestDistance) {
          bestDistance = distance;
          bestFeaturePoint = featurePoint;
          bestProgress = 0;
        }
        continue;
      }
      for (var index = 1; index < route.length; index++) {
        final start = route[index - 1];
        final end = route[index];
        const latitudeScale = 111320.0;
        final longitudeScale =
            latitudeScale * math.cos(featurePoint.latitude * math.pi / 180);
        final segmentX = (end.longitude - start.longitude) * longitudeScale;
        final segmentY = (end.latitude - start.latitude) * latitudeScale;
        final pointX =
            (featurePoint.longitude - start.longitude) * longitudeScale;
        final pointY = (featurePoint.latitude - start.latitude) * latitudeScale;
        final lengthSquared = segmentX * segmentX + segmentY * segmentY;
        final fraction = lengthSquared <= 0
            ? 0.0
            : ((pointX * segmentX + pointY * segmentY) / lengthSquared).clamp(
                0.0,
                1.0,
              );
        final deltaX = pointX - segmentX * fraction;
        final deltaY = pointY - segmentY * fraction;
        final distance = math.sqrt(deltaX * deltaX + deltaY * deltaY);
        if (distance < bestDistance) {
          bestDistance = distance;
          bestFeaturePoint = featurePoint;
          bestProgress = (index - 1 + fraction) / (route.length - 1);
        }
      }
    }
    return _NearestRouteMatch(
      featurePoint: bestFeaturePoint,
      distanceMeters: bestDistance,
      routeProgress: bestProgress,
    );
  }

  /// Computes minimum geometry distance.
  double _minimumGeometryDistance(List<LatLng> first, List<LatLng> second) {
    var minimum = double.infinity;
    for (final firstPoint in first) {
      for (final secondPoint in second) {
        minimum = math.min(minimum, _distance(firstPoint, secondPoint));
      }
    }
    return minimum;
  }

  /// Computes sample route.
  List<_RoutePosition> _sampleRoute(
    List<LatLng> points, {
    required double spacingMeters,
    required int maximumPoints,
  }) {
    if (points.length == 1) {
      return [_RoutePosition(point: points.single, progress: 0)];
    }
    final cumulative = <double>[0];
    for (var index = 1; index < points.length; index++) {
      cumulative.add(
        cumulative.last + _distance(points[index - 1], points[index]),
      );
    }
    final total = cumulative.last;
    if (total <= 0) {
      return [_RoutePosition(point: points.first, progress: 0)];
    }
    final effectiveSpacing = math.max(
      spacingMeters,
      total / math.max(1, maximumPoints - 1),
    );
    final sampleCount = math.min(
      maximumPoints,
      math.max(2, (total / effectiveSpacing).ceil() + 1),
    );
    final samples = <_RoutePosition>[];
    var segmentIndex = 1;
    for (var sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
      final target = sampleIndex == sampleCount - 1
          ? total
          : math.min(total, sampleIndex * effectiveSpacing);
      while (segmentIndex < cumulative.length - 1 &&
          cumulative[segmentIndex] < target) {
        segmentIndex++;
      }
      final startDistance = cumulative[segmentIndex - 1];
      final segmentDistance = cumulative[segmentIndex] - startDistance;
      final fraction = segmentDistance <= 0
          ? 0.0
          : ((target - startDistance) / segmentDistance).clamp(0.0, 1.0);
      final start = points[segmentIndex - 1];
      final end = points[segmentIndex];
      samples.add(
        _RoutePosition(
          point: LatLng(
            start.latitude + (end.latitude - start.latitude) * fraction,
            start.longitude + (end.longitude - start.longitude) * fraction,
          ),
          progress: target / total,
        ),
      );
    }
    return samples;
  }

  /// Computes deduplicate.
  List<LocalTrailHazardMatch> _deduplicate(
    List<LocalTrailHazardMatch> matches,
  ) {
    final byId = <String, LocalTrailHazardMatch>{};
    for (final match in matches) {
      final prior = byId[match.hazard.hazardId];
      if (prior == null || match.distanceMeters < prior.distanceMeters) {
        byId[match.hazard.hazardId] = match;
      }
    }
    return byId.values.toList(growable: false)
      ..sort((a, b) => a.routeProgress.compareTo(b.routeProgress));
  }

  /// Computes distance.
  double _distance(LatLng first, LatLng second) {
    const radius = 6371000.0;
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
    return radius *
        2 *
        math.atan2(
          math.sqrt(a.clamp(0.0, 1.0)),
          math.sqrt((1 - a).clamp(0.0, 1.0)),
        );
  }
}

/// Represents route position.
class _RoutePosition {
  /// Creates route position.
  const _RoutePosition({required this.point, required this.progress});

  final LatLng point;
  final double progress;
}

/// Represents nearest route match.
class _NearestRouteMatch {
  /// Creates nearest route match.
  const _NearestRouteMatch({
    required this.featurePoint,
    required this.distanceMeters,
    required this.routeProgress,
  });

  final LatLng featurePoint;
  final double distanceMeters;
  final double routeProgress;
}

/// Represents steep candidate.
class _SteepCandidate {
  /// Creates steep candidate.
  const _SteepCandidate({
    required this.index,
    required this.type,
    required this.gradePercent,
    required this.riseMeters,
    required this.spanMeters,
    required this.position,
  });

  final int index;
  final String type;
  final double gradePercent;
  final double riseMeters;
  final double spanMeters;
  final _RoutePosition position;
}

import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../app/Data/local_session_database.dart';
import '../../home/Model/route_gear_assessment.dart';
import '../../trail/Model/trail_models.dart';
import 'hiking_route_service.dart';

/// Queries a slightly expanded, simplified corridor, then checks every returned
/// geometry against the original route with a strict 50 m segment-distance test.
class RouteGearAnalysisService {
  RouteGearAnalysisService({
    required this.database,
    http.Client? client,
    Future<HikingRouteResult> Function(Trail)? routeLoader,
    Uri? endpoint,
  }) : _client = client ?? http.Client(),
       _routeLoader =
           routeLoader ??
           HikingRouteService(
             localDatabase: database,
           ).findHikingRouteForTrailWithCache,
       _endpoint =
           endpoint ?? Uri.parse('https://overpass-api.de/api/interpreter');
  final LocalSessionDatabase database;
  final http.Client _client;
  final Future<HikingRouteResult> Function(Trail) _routeLoader;
  final Uri _endpoint;
  void dispose() => _client.close();

  final _pending = <String, Future<RouteGearAssessment>>{};
  final _memory = <String, RouteGearAssessment>{};
  static String inputKey(Trail trail) => sha256
      .convert(
        utf8.encode(
          'gear50-v1|${trail.trailId}|${HikingRouteService.checkpointsHash(trail.checkpoints)}|${trail.routeEncodedPolyline ?? ''}',
        ),
      )
      .toString();
  RouteGearAssessment? peek(Trail trail) => _memory[inputKey(trail)];
  Future<RouteGearAssessment> analyze(Trail trail, {bool force = false}) {
    final key = inputKey(trail), cached = _memory[inputKey(trail)];
    if (!force &&
        cached != null &&
        (cached.usable
            ? cached.isFresh
            : DateTime.now().difference(cached.checkedAt) <
                  const Duration(minutes: 5))) {
      return Future.value(cached);
    }
    return _pending.putIfAbsent(
      key,
      () => _load(trail, key, force)
          .then((value) {
            if (_memory.length >= 128) _memory.remove(_memory.keys.first);
            _memory[key] = value;
            return value;
          })
          .whenComplete(() {
            _pending.remove(key);
          }),
    );
  }

  Future<RouteGearAssessment> _load(Trail trail, String key, bool force) async {
    RouteGearAssessment? cached;
    String? storageKey;
    try {
      final result = await _routeLoader(
        trail,
      ).timeout(const Duration(seconds: 45));
      final route = PolylineCodec.decode(result.encodedPolyline);
      if (route.length < 2 ||
          route.any(
            (p) =>
                !p.latitude.isFinite ||
                !p.longitude.isFinite ||
                p.latitude.abs() > 90 ||
                p.longitude.abs() > 180,
          )) {
        throw const FormatException('No usable route');
      }
      storageKey =
          'gear50-v1:${sha256.convert(utf8.encode(result.encodedPolyline))}';
      try {
        final stored = await database.loadLocalPreference(
          ownerPhoneNumber: '',
          key: storageKey,
        );
        if (stored is Map) {
          cached = RouteGearAssessment.fromJson({...stored, 'routeKey': key});
        }
      } catch (_) {}
      if (!force && cached?.isFresh == true && cached?.status == 'complete') {
        return cached!;
      }
      final simplified = _simplify(route, 5);
      final elements = <String, Map<String, dynamic>>{};
      bool complete = true;
      var successful = 0;
      for (var start = 0; start < simplified.length - 1; start += 179) {
        if (start >= 179 * 20) {
          complete = false;
          break;
        }
        final chunk = simplified.sublist(
          start,
          math.min(start + 180, simplified.length),
        );
        final coords = chunk
            .map(
              (p) =>
                  '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}',
            )
            .join(',');
        // 5 m simplification tolerance plus coordinate rounding; results are
        // always filtered to 50 m from the ORIGINAL geometry below.
        final around = '(around:56,$coords)';
        final query =
            '''[out:json][timeout:20];(
          nwr["waterway"~"^(river|stream|tidal_channel)\$"]$around;
          nwr["ford"]$around;
          way["highway"]$around;
          nwr["natural"~"^(scree|bare_rock|wetland|water)\$"]$around;
          nwr["ladder"]$around;
          nwr["safety_rope"]$around;
        );out body geom;''';
        try {
          final response = await _client
              .post(
                _endpoint,
                body: {'data': query},
                headers: {
                  'User-Agent': 'HikerCircle route gear analysis',
                  'Accept': 'application/json',
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
              )
              .timeout(const Duration(seconds: 25));
          if (response.statusCode != 200) {
            throw StateError('Map service unavailable');
          }
          final json = jsonDecode(response.body);
          if (json is! Map ||
              json['elements'] is! List ||
              json['remark'] != null) {
            throw const FormatException('Incomplete map response');
          }
          for (final raw in (json['elements'] as List).whereType<Map>()) {
            elements['${raw['type']}/${raw['id']}'] = Map<String, dynamic>.from(
              raw,
            );
          }
          successful++;
        } catch (_) {
          complete = false;
          break;
        }
      }
      if (successful == 0) throw StateError('No map coverage');
      final assessment = await compute(_classifyInBackground, {
        'route': route,
        'elements': elements.values.toList(),
        'key': key,
        'complete': complete,
      });
      if (complete) {
        try {
          await database.saveLocalPreference(
            ownerPhoneNumber: '',
            key: storageKey,
            value: assessment.toJson(),
          );
        } catch (_) {}
      }
      return assessment;
    } catch (_) {
      // Retain dated findings offline, never substitute a clean-route result.
      return cached ??
          RouteGearAssessment(
            routeKey: key,
            checkedAt: DateTime.now(),
            status: 'unavailable',
          );
    }
  }

  static RouteGearAssessment classify(
    List<LatLng> route,
    Iterable<Map<String, dynamic>> elements, {
    String routeKey = 'test',
    bool complete = true,
  }) {
    final projector = _Projector(route.first.latitude);
    final line = route.map(projector.point).toList();
    final nearby =
        <
          ({
            Map tags,
            List<_Point> geometry,
            double distance,
            _Point routePoint,
          })
        >[];
    for (final element in elements) {
      final tags = element['tags'];
      if (tags is! Map) continue;
      final paths = _geometries(element);
      for (final path in paths) {
        final geometry = path.map(projector.point).toList();
        if (geometry.isEmpty) continue;
        final match = _nearest(geometry, line);
        if (match.distance <= 50) {
          nearby.add((
            tags: tags,
            geometry: geometry,
            distance: match.distance,
            routePoint: match.point,
          ));
        }
      }
    }
    bool positive(Object? value) =>
        value != null && value != 'no' && value != 'none';
    final bridges = nearby
        .where(
          (f) =>
              positive(f.tags['bridge']) &&
              const {
                'path',
                'footway',
                'steps',
                'pedestrian',
                'track',
                'bridleway',
              }.contains(f.tags['highway']),
        )
        .toList();
    var water = false,
        crossing = false,
        rough = false,
        mud = false,
        technical = false,
        surface = false;
    for (final f in nearby) {
      final t = f.tags;
      final ford = positive(t['ford']) || t['highway'] == 'ford';
      final waterway = const {
        'river',
        'stream',
        'tidal_channel',
      }.contains(t['waterway']);
      if (waterway || t['natural'] == 'water' || ford) water = true;
      if (ford && f.distance <= 10) crossing = true;
      if (waterway && !positive(t['tunnel'])) {
        // Check each route segment: one bridge must not mask another crossing
        // of the same river further along a looping route.
        for (var j = 1; j < line.length; j++) {
          final at = _nearest(f.geometry, [line[j - 1], line[j]]);
          if (at.distance > 2) continue;
          final bridged = bridges.any(
            (b) => _nearest([at.point], b.geometry).distance <= 12,
          );
          if (!bridged) crossing = true;
        }
      }
      final s = t['surface'];
      final path = const {
        'path',
        'footway',
        'steps',
        'pedestrian',
        'track',
        'bridleway',
      }.contains(t['highway']);
      if (path && f.distance <= 10 && s != null) surface = true;
      if (t['natural'] == 'scree' ||
          (path &&
              const {
                'unpaved',
                'dirt',
                'earth',
                'ground',
                'grass',
                'sand',
                'mud',
                'gravel',
                'fine_gravel',
                'loose_gravel',
                'rock',
                'rocky',
                'stone',
                'pebblestone',
              }.contains(s))) {
        rough = true;
      }
      if (t['natural'] == 'wetland' || (path && s == 'mud')) mud = true;
      if ((f.distance <= 10 &&
              (positive(t['ladder']) || positive(t['safety_rope']))) ||
          (path &&
              const {
                'mountain_hiking',
                'demanding_mountain_hiking',
                'alpine_hiking',
                'demanding_alpine_hiking',
                'difficult_alpine_hiking',
              }.contains(t['sac_scale']))) {
        technical = true;
      }
    }
    return RouteGearAssessment(
      routeKey: routeKey,
      checkedAt: DateTime.now(),
      status: complete ? 'complete' : 'partial',
      featureCount: nearby.length,
      waterNearby: water,
      possibleCrossing: crossing,
      rough: rough,
      muddy: mud,
      technical: technical,
      surfaceMapped: surface,
    );
  }
}

List<List<LatLng>> _geometries(Map element) {
  List<LatLng> points(Object? raw) => raw is List
      ? raw
            .whereType<Map>()
            .where((p) => p['lat'] is num && p['lon'] is num)
            .map(
              (p) => LatLng(
                (p['lat'] as num).toDouble(),
                (p['lon'] as num).toDouble(),
              ),
            )
            .where((p) => p.latitude.isFinite && p.longitude.isFinite)
            .toList()
      : [];
  if (element['geometry'] is List) return [points(element['geometry'])];
  if (element['members'] is List) {
    return (element['members'] as List)
        .whereType<Map>()
        .map((m) => points(m['geometry']))
        .where((g) => g.isNotEmpty)
        .toList();
  }
  if (element['lat'] is num && element['lon'] is num) {
    return [
      [
        LatLng(
          (element['lat'] as num).toDouble(),
          (element['lon'] as num).toDouble(),
        ),
      ],
    ];
  }
  return [];
}

typedef _Point = ({double x, double y});

class _Projector {
  _Projector(double latitude)
    : scale = 111320 * math.cos(latitude * math.pi / 180);
  final double scale;
  _Point point(LatLng p) => (x: p.longitude * scale, y: p.latitude * 111320);
}

double _dist(_Point a, _Point b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
_Point _project(_Point p, _Point a, _Point b) {
  final dx = b.x - a.x, dy = b.y - a.y, len = dx * dx + dy * dy;
  final t = len == 0
      ? 0.0
      : (((p.x - a.x) * dx + (p.y - a.y) * dy) / len).clamp(0.0, 1.0);
  return (x: a.x + t * dx, y: a.y + t * dy);
}

_Point? _intersection(_Point a, _Point b, _Point c, _Point d) {
  final rx = b.x - a.x, ry = b.y - a.y, sx = d.x - c.x, sy = d.y - c.y;
  final cross = rx * sy - ry * sx;
  if (cross.abs() < 1e-10) return null;
  final t = ((c.x - a.x) * sy - (c.y - a.y) * sx) / cross;
  final u = ((c.x - a.x) * ry - (c.y - a.y) * rx) / cross;
  return t >= 0 && t <= 1 && u >= 0 && u <= 1
      ? (x: a.x + t * rx, y: a.y + t * ry)
      : null;
}

({double distance, _Point point}) _nearest(
  List<_Point> geometry,
  List<_Point> line,
) {
  var best = double.infinity;
  var point = line.first;
  for (var i = 0; i < math.max(1, geometry.length - 1); i++) {
    final a = geometry[i], b = geometry[math.min(i + 1, geometry.length - 1)];
    for (var j = 0; j < math.max(1, line.length - 1); j++) {
      final c = line[j], d = line[math.min(j + 1, line.length - 1)];
      if (math.max(math.min(a.x, b.x), math.min(c.x, d.x)) -
                  math.min(math.max(a.x, b.x), math.max(c.x, d.x)) >
              50 ||
          math.max(math.min(a.y, b.y), math.min(c.y, d.y)) -
                  math.min(math.max(a.y, b.y), math.max(c.y, d.y)) >
              50) {
        continue;
      }
      final crossing = _intersection(a, b, c, d);
      if (crossing != null) return (distance: 0, point: crossing);
      for (final p in [a, b]) {
        final q = _project(p, c, d), distance = _dist(p, _project(p, c, d));
        if (distance < best) {
          best = distance;
          point = q;
        }
      }
      for (final q in [c, d]) {
        final distance = _dist(q, _project(q, a, b));
        if (distance < best) {
          best = distance;
          point = q;
        }
      }
    }
  }
  return (distance: best, point: point);
}

List<LatLng> _simplify(List<LatLng> points, double tolerance) {
  final projector = _Projector(points.first.latitude),
      keep = <int>{0, points.length - 1};
  final stack = <(int, int)>[(0, points.length - 1)];
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    var far = tolerance;
    var index = -1;
    for (var i = a + 1; i < b; i++) {
      final p = projector.point(points[i]);
      final distance = _dist(
        p,
        _project(p, projector.point(points[a]), projector.point(points[b])),
      );
      if (distance > far) {
        far = distance;
        index = i;
      }
    }
    if (index >= 0) {
      keep.add(index);
      stack.add((a, index));
      stack.add((index, b));
    }
  }
  final indices = keep.toList()..sort();
  return indices.map((i) => points[i]).toList();
}

RouteGearAssessment _classifyInBackground(Map<String, dynamic> payload) =>
    RouteGearAnalysisService.classify(
      payload['route'] as List<LatLng>,
      payload['elements'] as List<Map<String, dynamic>>,
      routeKey: payload['key'] as String,
      complete: payload['complete'] as bool,
    );

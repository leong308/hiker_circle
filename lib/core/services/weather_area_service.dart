// WeatherAreaService composes and caches a geographic weather image from proxied map tiles for the
// selected weather layer.
import 'private_provider_client.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import 'weather_map_service.dart';

/// One fixed zoom, independent of the map camera. At Malaysian latitudes the
/// 100 km bounding box requires at most four 256px tiles per selected layer.
class WeatherAreaGrid {
  /// Creates weather area grid.
  WeatherAreaGrid(this.latitude, this.longitude) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 80 ||
        longitude.abs() > 180) {
      throw ArgumentError('Unsupported weather location');
    }
    final latRadius = radiusKm / earthRadiusKm * 180 / math.pi;
    final lonRadius =
        math.asin(
          math.sin(radiusKm / earthRadiusKm) /
              math.cos(latitude * math.pi / 180),
        ) *
        180 /
        math.pi;
    left = tileX(longitude - lonRadius).floor();
    right = tileX(longitude + lonRadius).floor();
    top = tileY(latitude + latRadius).floor();
    bottom = tileY(latitude - latRadius).floor();
  }
  static const zoom = 8;
  static const radiusKm = 50.0;
  static const earthRadiusKm = 6371.0;
  static const tilesPerWorld = 256;
  final double latitude;
  final double longitude;
  late final int left, right, top, bottom;

  /// Returns width.
  int get width => (right - left + 1) * 256;

  /// Returns height.
  int get height => (bottom - top + 1) * 256;

  /// Returns tile count.
  int get tileCount => (right - left + 1) * (bottom - top + 1);

  /// Computes tile x.
  static double tileX(double lon) => (lon + 180) / 360 * tilesPerWorld;

  /// Computes tile y.
  static double tileY(double lat) {
    final radians = lat * math.pi / 180;
    return (1 - math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) /
        2 *
        tilesPerWorld;
  }

  /// Computes longitude at.
  static double longitudeAt(double x) => x / tilesPerWorld * 360 - 180;

  /// Computes latitude at.
  static double latitudeAt(double y) {
    final n = math.pi * (1 - 2 * y / tilesPerWorld);
    return math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
  }

  /// Returns corners.
  List<List<double>> get corners => [
    [longitudeAt(left.toDouble()), latitudeAt(top.toDouble())],
    [longitudeAt(right + 1.0), latitudeAt(top.toDouble())],
    [longitudeAt(right + 1.0), latitudeAt(bottom + 1.0)],
    [longitudeAt(left.toDouble()), latitudeAt(bottom + 1.0)],
  ];

  /// Geodesic 50 km circle, projected into the same Mercator plane as tiles.
  ui.Path get clipPath {
    final path = ui.Path();
    final lat = latitude * math.pi / 180;
    final lon = longitude * math.pi / 180;
    const angular = radiusKm / earthRadiusKm;
    for (var i = 0; i <= 180; i++) {
      final bearing = i * 2 * math.pi / 180;
      final pLat = math.asin(
        math.sin(lat) * math.cos(angular) +
            math.cos(lat) * math.sin(angular) * math.cos(bearing),
      );
      final pLon =
          lon +
          math.atan2(
            math.sin(bearing) * math.sin(angular) * math.cos(lat),
            math.cos(angular) - math.sin(lat) * math.sin(pLat),
          );
      final x = (tileX(pLon * 180 / math.pi) - left) * 256;
      final y = (tileY(pLat * 180 / math.pi) - top) * 256;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }
}

/// Represents weather area image.
class WeatherAreaImage {
  /// Creates weather area image.
  const WeatherAreaImage(this.grid, this.png, this.loadedAt);
  final WeatherAreaGrid grid;
  final Uint8List png;
  final DateTime loadedAt;
}

/// Represents weather area service.
class WeatherAreaService {
  /// Creates weather area service.
  WeatherAreaService({http.Client? client, DateTime Function()? now})
    : _client = client,
      _now = now ?? DateTime.now;
  static final shared = WeatherAreaService();
  final http.Client? _client;
  final DateTime Function() _now;
  final _cache = <String, WeatherAreaImage>{};
  final _pending = <String, Future<WeatherAreaImage>>{};

  /// Loads.
  Future<WeatherAreaImage> load({
    required double latitude,
    required double longitude,
    required WeatherMapLayer layer,
    required String apiKey,
    bool refresh = false,
  }) async {
    final grid = WeatherAreaGrid(latitude, longitude);
    if (layer == WeatherMapLayer.off || apiKey.isEmpty) {
      throw ArgumentError('Weather layer and key required');
    }
    final key = '$latitude,$longitude/${layer.name}/$apiKey';
    final pending = _pending[key];
    if (pending != null) return pending;
    final cached = _cache[key];
    if (!refresh &&
        cached != null &&
        _now().difference(cached.loadedAt) < const Duration(hours: 3)) {
      return cached;
    }
    final future = _download(grid, layer, apiKey);
    _pending[key] = future;
    try {
      final result = await future;
      if (_cache.length >= 16) _cache.remove(_cache.keys.first);
      _cache[key] = result;
      return result;
    } finally {
      _pending.remove(key);
    }
  }

  /// Downloads.
  Future<WeatherAreaImage> _download(
    WeatherAreaGrid grid,
    WeatherMapLayer layer,
    String apiKey,
  ) async {
    final client = _client ?? http.Client();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..clipPath(grid.clipPath);
    final decoded = <ui.Image>[];
    ui.Picture? picture;
    ui.Image? composite;
    try {
      // Strengthen alpha only: the provider's data colors stay intact and
      // truly transparent/no-precipitation pixels remain transparent.
      final gain = layer == WeatherMapLayer.rain ? 3.0 : 2.0;
      final paint = ui.Paint()
        ..colorFilter = ui.ColorFilter.matrix([
          1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          gain,
          0,
        ]);
      for (var y = grid.top; y <= grid.bottom; y++) {
        for (var x = grid.left; x <= grid.right; x++) {
          final url = WeatherMapService.tileTemplate(layer, apiKey)
              .replaceAll('{z}', '${WeatherAreaGrid.zoom}')
              .replaceAll('{x}', '${x % WeatherAreaGrid.tilesPerWorld}')
              .replaceAll('{y}', '$y');
          final response =
              await (_client == null
                      ? PrivateProviderClient.request('weatherTile', {
                          'layer': layer.tileName,
                          'z': WeatherAreaGrid.zoom,
                          'x': x % WeatherAreaGrid.tilesPerWorld,
                          'y': y,
                        })
                      : client.get(Uri.parse(url)))
                  .timeout(const Duration(seconds: 12));
          if (response.statusCode != 200) {
            throw StateError(
              'Weather tiles unavailable (${response.statusCode})',
            );
          }
          final codec = await ui.instantiateImageCodec(response.bodyBytes);
          ui.Image tile;
          try {
            tile = (await codec.getNextFrame()).image;
          } finally {
            codec.dispose();
          }
          decoded.add(tile);
          canvas.drawImageRect(
            tile,
            ui.Rect.fromLTWH(
              0,
              0,
              tile.width.toDouble(),
              tile.height.toDouble(),
            ),
            ui.Rect.fromLTWH(
              (x - grid.left) * 256.0,
              (y - grid.top) * 256.0,
              256,
              256,
            ),
            paint,
          );
        }
      }
      picture = recorder.endRecording();
      composite = await picture.toImage(grid.width, grid.height);
      final bytes = await composite.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Weather image unavailable');
      return WeatherAreaImage(grid, bytes.buffer.asUint8List(), _now());
    } finally {
      if (recorder.isRecording) recorder.endRecording().dispose();
      picture?.dispose();
      composite?.dispose();
      for (final tile in decoded) {
        tile.dispose();
      }
      if (_client == null) client.close();
    }
  }
}

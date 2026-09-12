import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../app/Data/local_session_database.dart';

typedef OfflineMapProgress = void Function(double progress);

/// Manages the device-wide Malaysia offline basemap.
///
/// Mapbox owns the binary tile store. SQLite records the durable region
/// identity, coverage, progress, size and errors used by App Settings.
class OfflineMapService {
  OfflineMapService(this._database);

  final LocalSessionDatabase _database;

  static bool get isSupported => !kIsWeb;

  static const String malaysiaRegionKey = 'country:MY';
  static const String malaysiaRegionId = 'country-malaysia-v1';
  static const String styleUri = 'mapbox://styles/mapbox/outdoors-v12';
  static const int malaysiaMinZoom = 4;
  static const int malaysiaMaxZoom = 12;

  static const Map<String, dynamic> _bounds = {
    'coverage': 'Malaysia',
    'west': 99.4,
    'east': 119.6,
    'south': 0.8,
    'north': 7.6,
    'geometry': 'Peninsular and East Malaysia',
  };

  Future<LocalOfflineMapRegion?> loadMalaysiaRegion() async {
    final saved = await _database.loadOfflineMapRegion(malaysiaRegionKey);
    if (kIsWeb) return saved;
    try {
      final tileStore = await TileStore.createDefault();
      final nativeRegion = await tileStore.tileRegion(malaysiaRegionId);
      final reconciled = _record(
        bounds: saved?.bounds ?? _bounds,
        status:
            nativeRegion.requiredResourceCount > 0 &&
                nativeRegion.completedResourceCount >=
                    nativeRegion.requiredResourceCount
            ? 'complete'
            : saved?.status == 'failed'
            ? 'failed'
            : 'downloading',
        completedResourceCount: nativeRegion.completedResourceCount,
        requiredResourceCount: nativeRegion.requiredResourceCount,
        completedBytes: nativeRegion.completedResourceSize,
        downloadedAt:
            saved?.downloadedAt ??
            (nativeRegion.requiredResourceCount > 0 &&
                    nativeRegion.completedResourceCount >=
                        nativeRegion.requiredResourceCount
                ? DateTime.now().toUtc()
                : null),
        lastError: saved?.lastError ?? '',
      );
      await _database.upsertOfflineMapRegion(reconciled);
      return reconciled;
    } catch (_) {
      // No native region exists yet. SQLite may still contain a failed record
      // with the useful reason from the previous attempt.
      return saved;
    }
  }

  Future<LocalOfflineMapRegion> downloadMalaysia({
    OfflineMapProgress? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Offline map downloads are not supported on web.');
    }
    const bounds = _bounds;
    var record = _record(bounds: bounds, status: 'downloading');
    await _database.upsertOfflineMapRegion(record);

    try {
      final offlineManager = await OfflineManager.create();
      final tileStore = await TileStore.createDefault();
      tileStore.setDiskQuota(null);
      await offlineManager.loadStylePack(
        styleUri,
        StylePackLoadOptions(
          glyphsRasterizationMode:
              GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
          metadata: {'coverage': 'Malaysia'},
          acceptExpired: true,
        ),
        null,
      );

      var progressWrite = Future<void>.value();
      final tileRegion = await tileStore.loadTileRegion(
        malaysiaRegionId,
        TileRegionLoadOptions(
          geometry: _malaysiaGeometry,
          descriptorsOptions: [
            TilesetDescriptorOptions(
              styleURI: styleUri,
              minZoom: malaysiaMinZoom,
              maxZoom: malaysiaMaxZoom,
            ),
          ],
          acceptExpired: true,
          networkRestriction: NetworkRestriction.NONE,
        ),
        (progress) {
          final total = progress.requiredResourceCount;
          onProgress?.call(
            total <= 0 ? 0 : progress.completedResourceCount / total,
          );
          final progressRecord = _record(
            bounds: bounds,
            status: 'downloading',
            completedResourceCount: progress.completedResourceCount,
            requiredResourceCount: progress.requiredResourceCount,
            completedBytes: progress.completedResourceSize,
          );
          record = progressRecord;
          progressWrite = progressWrite.then(
            (_) => _database.upsertOfflineMapRegion(progressRecord),
          );
        },
      );
      await progressWrite;
      record = _record(
        bounds: bounds,
        status: 'complete',
        completedResourceCount: tileRegion.completedResourceCount,
        requiredResourceCount: tileRegion.requiredResourceCount,
        completedBytes: tileRegion.completedResourceSize,
        downloadedAt: DateTime.now().toUtc(),
      );
      await _database.upsertOfflineMapRegion(record);
      onProgress?.call(1);
      return record;
    } catch (error) {
      final failed = _record(
        bounds: bounds,
        status: 'failed',
        completedResourceCount: record.completedResourceCount,
        requiredResourceCount: record.requiredResourceCount,
        completedBytes: record.completedBytes,
        lastError: error.toString(),
      );
      await _database.upsertOfflineMapRegion(failed);
      rethrow;
    }
  }

  Future<void> removeMalaysia() async {
    if (!kIsWeb) {
      final tileStore = await TileStore.createDefault();
      await tileStore.removeRegion(malaysiaRegionId);
    }
    await _database.deleteOfflineMapRegion(malaysiaRegionKey);
  }

  Future<void> removeAllTileRegions() async {
    if (kIsWeb) return;
    final regions = await _database.loadOfflineMapRegions();
    if (regions.isEmpty) return;
    final tileStore = await TileStore.createDefault();
    for (final region in regions) {
      await tileStore.removeRegion(region.regionId);
    }
  }

  LocalOfflineMapRegion _record({
    required Map<String, dynamic> bounds,
    required String status,
    int completedResourceCount = 0,
    int requiredResourceCount = 0,
    int completedBytes = 0,
    DateTime? downloadedAt,
    String lastError = '',
  }) {
    return LocalOfflineMapRegion(
      trailId: malaysiaRegionKey,
      regionId: malaysiaRegionId,
      styleUri: styleUri,
      bounds: bounds,
      minZoom: malaysiaMinZoom,
      maxZoom: malaysiaMaxZoom,
      status: status,
      completedResourceCount: completedResourceCount,
      requiredResourceCount: requiredResourceCount,
      completedBytes: completedBytes,
      downloadedAt: downloadedAt,
      updatedAt: DateTime.now().toUtc(),
      lastError: lastError,
    );
  }

  /// Separate polygons avoid downloading the large sea corridor between
  /// Peninsular Malaysia and Sabah/Sarawak.
  static const Map<String, dynamic> _malaysiaGeometry = {
    'type': 'MultiPolygon',
    'coordinates': [
      [
        [
          [99.4, 0.8],
          [104.9, 0.8],
          [104.9, 7.6],
          [99.4, 7.6],
          [99.4, 0.8],
        ],
      ],
      [
        [
          [109.4, 0.8],
          [119.6, 0.8],
          [119.6, 7.6],
          [109.4, 7.6],
          [109.4, 0.8],
        ],
      ],
    ],
  };
}

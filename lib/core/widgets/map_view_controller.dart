// Keeps the map's position and annotations while changing its presentation.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import 'map_controls.dart';
import 'map_utils.dart';

/// Represents map view controller.
class MapViewController extends ChangeNotifier {
  /// Creates map view controller.
  MapViewController({
    MapViewSettings settings = const MapViewSettings(),
    this.onBeforeStyleReload,
    this.readinessTimeout = const Duration(seconds: 12),
  }) : _settings = settings,
       _activeSettings = settings,
       _appliedSettings = settings;

  final FutureOr<void> Function()? onBeforeStyleReload;
  final Duration readinessTimeout;
  MapViewSettings _settings;
  MapViewSettings _activeSettings;
  MapViewSettings _appliedSettings;
  mapbox.MapboxMap? _map;
  mapbox.CameraState? _savedCamera;
  double? _savedPitch;
  Completer<bool> _ready = Completer<bool>();
  Future<void>? _styleSetup;
  Object? _styleSetupToken;
  Future<void> Function()? _earlyStyleRenderer;
  Future<void> _changes = Future<void>.value();
  int _mapEpoch = 0;
  int _revision = 0;
  int _preparedRevision = -1;
  int _request = 0;
  bool _disposed = false;
  bool _changing = false;
  bool _styleReady = false;
  bool _needsReload = false;
  bool _awaitingStyleLoad = false;
  bool _hasPreparedStyle = false;
  double zoom = 13;
  double latitude = 0;
  double bearing = 0;

  /// The latest picker choice may be queued behind an earlier native load.
  MapViewSettings get settings => _settings;

  /// Returns display settings.
  MapViewSettings get displaySettings => _appliedSettings;

  /// Returns has map.
  bool get hasMap => !_disposed && _map != null;

  /// Returns is changing.
  bool get isChanging => _changing;

  /// Returns is style ready.
  bool get isStyleReady => !_disposed && _styleReady;

  /// Returns style unavailable.
  bool get styleUnavailable => _needsReload && !_awaitingStyleLoad;

  /// Computes attach.
  void attach(mapbox.MapboxMap map) {
    if (_disposed) return;
    if (identical(map, _map)) return;
    if (!_ready.isCompleted) _ready.complete(false);
    _mapEpoch++;
    _revision++;
    _map = map;
    _activeSettings = _settings;
    _preparedRevision = -1;
    _ready = Completer<bool>();
    _styleSetup = null;
    _styleSetupToken = null;
    _savedCamera = null;
    _savedPitch = null;
    _styleReady = false;
    _needsReload = false;
    _awaitingStyleLoad = true;
    _hasPreparedStyle = false;
    _changing = false;
    final earlyRenderer = _earlyStyleRenderer;
    _earlyStyleRenderer = null;
    unawaited(_refreshCamera());
    if (earlyRenderer != null) unawaited(styleLoaded(earlyRenderer));
    notifyListeners();
  }

  /// Computes camera changed.
  void cameraChanged(mapbox.CameraChangedEventData event) {
    _updateScale(event.cameraState);
  }

  /// Updates scale.
  void _updateScale(mapbox.CameraState state) {
    final coordinate = mapPointCoordinatesOrNull(state.center);
    if (_disposed || coordinate == null || !state.zoom.isFinite) return;
    final nextBearing = state.bearing.isFinite ? state.bearing : 0.0;
    if ((state.zoom - zoom).abs() < .005 &&
        (coordinate.latitude - latitude).abs() < .0005 &&
        (nextBearing - bearing).abs() < .1) {
      return;
    }
    zoom = state.zoom;
    latitude = coordinate.latitude;
    bearing = nextBearing;
    notifyListeners();
  }

  /// Computes zoom by.
  Future<void> zoomBy(double amount) async {
    final map = _map;
    final epoch = _mapEpoch;
    if (map == null || _disposed || !amount.isFinite) return;
    try {
      final camera = await map.getCameraState();
      if (!_isCurrent(map, epoch) || !camera.zoom.isFinite) return;
      await map.flyTo(
        mapbox.CameraOptions(
          zoom: (camera.zoom + amount)
              .clamp(kMapMinZoom, kMapMaxZoom)
              .toDouble(),
        ),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {
      // A native map may be replaced while a control is being tapped.
    }
  }

  /// Checks whether current.
  bool _isCurrent(mapbox.MapboxMap map, int epoch, [int? revision]) =>
      !_disposed &&
      identical(map, _map) &&
      epoch == _mapEpoch &&
      (revision == null || revision == _revision);

  /// Refreshes camera.
  Future<void> _refreshCamera() async {
    final map = _map;
    final epoch = _mapEpoch;
    if (_disposed || map == null) return;
    try {
      final state = await map.getCameraState();
      if (_isCurrent(map, epoch)) _updateScale(state);
    } catch (_) {
      // A native map may have been removed while its camera was queried.
    }
  }

  /// A provider failure releases queued choices, including retrying the last
  /// confirmed style. It never declares an unprepared native style ready.
  void styleLoadFailed() {
    if (_disposed || !_awaitingStyleLoad) return;
    _invalidateStyle();
    notifyListeners();
  }

  /// Computes invalidate style.
  void _invalidateStyle() {
    _revision++;
    _preparedRevision = -1;
    _styleReady = false;
    _needsReload = true;
    _awaitingStyleLoad = false;
    if (!_ready.isCompleted) _ready.complete(false);
  }

  /// Loaded/map-loaded duplicates share one setup. Native URI/readiness checks
  /// exclude a late callback from the provider being replaced.
  Future<void> styleLoaded(Future<void> Function() renderAnnotations) {
    if (_disposed) return Future<void>.value();
    final map = _map;
    if (map == null) {
      _earlyStyleRenderer = renderAnnotations;
      return Future<void>.value();
    }
    if (_preparedRevision == _revision && _styleReady) {
      return Future<void>.value();
    }
    final existing = _styleSetup;
    if (existing != null) return existing;
    final epoch = _mapEpoch;
    final revision = _revision;
    final active = _activeSettings;
    final ready = _ready;
    final token = Object();
    _styleSetupToken = token;
    final operation = () async {
      // Install the shared future before even a synchronous renderer can fail.
      await Future<void>.value();
      var attemptedSetup = false;
      var success = false;
      try {
        try {
          final uri = await map.style.getStyleURI();
          if (uri.isNotEmpty && uri != active.styleUrl) return;
          if (!await map.style.isStyleLoaded()) return;
        } catch (_) {
          // Some native versions cannot query style metadata during callbacks.
        }
        if (!_isCurrent(map, epoch, revision)) return;
        attemptedSetup = true;
        // Initial parent fitting may animate. Apply pitch first so that a later
        // pitch-only setCamera cannot cancel its fit before the target arrives.
        await applyMapDimension(
          map,
          active.dimension,
          pitch: _savedPitch ?? (active.is3D ? 50 : 0),
        );
        if (!_isCurrent(map, epoch, revision)) return;
        await renderAnnotations();
        if (!_isCurrent(map, epoch, revision)) return;
        final camera = _savedCamera;
        if (camera != null) {
          await map.setCamera(
            mapbox.CameraOptions(
              center: camera.center,
              zoom: camera.zoom,
              bearing: camera.bearing,
              pitch: active.is3D ? (_savedPitch ?? camera.pitch) : 0,
              padding: camera.padding,
            ),
          );
        }
        if (!_isCurrent(map, epoch, revision)) return;
        _preparedRevision = revision;
        _appliedSettings = active;
        _savedCamera = null;
        _savedPitch = null;
        _styleReady = true;
        _needsReload = false;
        _awaitingStyleLoad = false;
        _hasPreparedStyle = true;
        await _refreshCamera();
        if (!_isCurrent(map, epoch, revision)) return;
        success = true;
        notifyListeners();
      } catch (_) {
        if (_isCurrent(map, epoch, revision)) {
          _invalidateStyle();
          notifyListeners();
        }
      } finally {
        if (attemptedSetup && !ready.isCompleted) ready.complete(success);
        if (identical(_styleSetupToken, token)) {
          _styleSetup = null;
          _styleSetupToken = null;
        }
      }
    }();
    _styleSetup = operation;
    return operation;
  }

  /// Latest pending choices win; an already-loading provider finishes before
  /// the next one starts so annotation cleanup and camera restore cannot race.
  Future<bool> changeView(MapViewSettings next) {
    if (_disposed) return Future<bool>.value(false);
    final choice = next.copyWith();
    final request = ++_request;
    _settings = choice;
    notifyListeners();
    final result = Completer<bool>();
    _changes = _changes.catchError((Object _) {}).then((_) async {
      if (_disposed) {
        result.complete(false);
      } else if (request != _request) {
        result.complete(true); // A newer choice owns the eventual result.
      } else {
        result.complete(await _applyChoice(choice, request));
      }
    });
    return result.future;
  }

  /// Applies choice.
  Future<bool> _applyChoice(MapViewSettings next, int request) async {
    final map = _map;
    final epoch = _mapEpoch;
    var changedNativeView = false;
    try {
      if (map == null) throw StateError('Map is not attached');
      if (!_styleReady && !_needsReload) {
        try {
          await _ready.future.timeout(readinessTimeout);
        } on TimeoutException {
          if (_isCurrent(map, epoch)) _invalidateStyle();
        }
      }
      if (!_isCurrent(map, epoch)) return false;
      if (request != _request) return true;
      final setup = _styleSetup;
      if (setup != null) await setup.timeout(readinessTimeout);
      if (!_isCurrent(map, epoch)) return false;
      final styleChanged =
          _needsReload ||
          next.safeStyleIndex != _appliedSettings.safeStyleIndex;
      final dimensionChanged = next.dimension != _appliedSettings.dimension;
      if (!styleChanged && !dimensionChanged) return true;
      if (_hasPreparedStyle && _savedCamera == null) {
        _savedCamera = await map.getCameraState();
      }
      if (!_isCurrent(map, epoch)) return false;
      _savedPitch = next.is3D
          ? (dimensionChanged ? 50 : _savedCamera?.pitch ?? 50)
          : 0;
      _activeSettings = next;
      _changing = true;
      notifyListeners();
      if (styleChanged) {
        _revision++;
        _preparedRevision = -1;
        _ready = Completer<bool>();
        final ready = _ready;
        _styleReady = false;
        _needsReload = true;
        _awaitingStyleLoad = true;
        changedNativeView = true;
        await onBeforeStyleReload?.call();
        if (!_isCurrent(map, epoch)) return false;
        await map.loadStyleURI(next.styleUrl);
        if (!await ready.future.timeout(readinessTimeout)) {
          throw StateError('Map style did not load');
        }
      } else {
        changedNativeView = true;
        await applyMapDimension(map, next.dimension, pitch: _savedPitch!);
        if (!_isCurrent(map, epoch)) return false;
        _appliedSettings = next;
        _savedCamera = null;
        _savedPitch = null;
        await _refreshCamera();
      }
      return _isCurrent(map, epoch);
    } catch (_) {
      if (!_disposed && (map == null || _isCurrent(map, epoch))) {
        if (changedNativeView) _invalidateStyle();
        _activeSettings = _appliedSettings;
        if (request == _request) _settings = _appliedSettings;
        notifyListeners();
      }
      return false;
    } finally {
      if (!_disposed && epoch == _mapEpoch) {
        _changing = false;
        notifyListeners();
      }
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    _map = null;
    _earlyStyleRenderer = null;
    if (!_ready.isCompleted) _ready.complete(false);
    super.dispose();
  }
}

/// Displays the map view controls.
class MapViewControls extends StatelessWidget {
  /// Creates map view controls.
  const MapViewControls({super.key, required this.controller});
  final MapViewController controller;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => IgnorePointer(
      ignoring: !controller.hasMap,
      child: Opacity(
        opacity: controller.hasMap ? 1 : .5,
        child: MapStyleControls(
          settings: controller.settings,
          onChanged: (settings) async {
            final success = await controller.changeView(settings);
            if (!success && context.mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                  content: Text('Could not change the map view. Try again.'),
                ),
              );
            }
          },
        ),
      ),
    ),
  );
}

/// Displays the map view overlay.
class MapViewOverlay extends StatelessWidget {
  /// Creates map view overlay.
  const MapViewOverlay({
    super.key,
    required this.controller,
    required this.onReset,
    this.onZoomIn,
    this.onZoomOut,
  });
  final MapViewController controller;
  final VoidCallback onReset;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => MapControlOverlay(
      zoomControls: MapZoomControls(
        onZoomIn: onZoomIn ?? () => unawaited(controller.zoomBy(1)),
        onZoomOut: onZoomOut ?? () => unawaited(controller.zoomBy(-1)),
        onReset: onReset,
      ),
      styleControls: MapViewControls(controller: controller),
      scale: MapViewScale(controller: controller),
      bearing: controller.bearing,
    ),
  );
}

/// Displays the map view scale.
class MapViewScale extends StatelessWidget {
  /// Creates map view scale.
  const MapViewScale({super.key, required this.controller});
  final MapViewController controller;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => MapScaleWithStyle(
      zoom: controller.zoom,
      latitude: controller.latitude,
      settings: controller.displaySettings,
      styleName: controller.styleUnavailable
          ? '${controller.displaySettings.styleName} unavailable'
          : null,
    ),
  );
}

/// Retire native managers before replacing a style, so pins are not duplicated.
Future<void> removeMapAnnotationManagers(
  mapbox.MapboxMap? map,
  Iterable<mapbox.BaseAnnotationManager?> managers,
) async {
  if (map == null) return;
  for (final manager in managers) {
    if (manager == null) continue;
    try {
      await map.annotations.removeAnnotationManager(manager);
    } catch (_) {
      // A map disposal or style replacement may already have removed it.
    }
  }
}

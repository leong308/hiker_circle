part of '../active_tracking_map_view_feature.dart';

/// Owns the state and non-visual actions of ActiveTrackingMapView.
class ActiveTrackingMapViewModel extends ChangeNotifier {
  /// Creates active tracking map view state view model.
  ActiveTrackingMapViewModel({
    required this.readActiveHike,
    required this.readCurrentPhoneNumber,
    required this.readTeamHikeSession,
    required this.readWeatherSamples,
    required this.effectCreateAnnotationManagers,
    required this.effectOnStyleLoaded,
    required this.effectPauseNavigationFollow,
    required this.effectQueueMapSettingsUpdate,
    required this.effectRenderRouteNow,
    required this.effectScheduleTeamProjection,
    required this.effectScheduleWeatherProjection,
    required this.effectSyncScaleFromCamera,
    required this.effectUpdateScale,
  });
  final ActiveHikeSession Function() readActiveHike;
  final String Function() readCurrentPhoneNumber;
  final TeamHikeSession? Function() readTeamHikeSession;
  final List<ActiveHikeWeatherSample> Function() readWeatherSamples;
  final Future<bool> Function(mapbox.MapboxMap map, int generation)
  effectCreateAnnotationManagers;
  final Future<void> Function(int generation) effectOnStyleLoaded;
  final void Function() effectPauseNavigationFollow;
  final void Function() effectQueueMapSettingsUpdate;
  final Future<void> Function(
    mapbox.MapboxMap map,
    int mapGeneration,
    int renderGeneration,
  )
  effectRenderRouteNow;
  final void Function() effectScheduleTeamProjection;
  final void Function() effectScheduleWeatherProjection;
  final Future<void> Function() effectSyncScaleFromCamera;
  final void Function(mapbox.CameraChangedEventData data) effectUpdateScale;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  mapbox.MapboxMap? stateMapboxMap;

  Future<bool>? stateAnnotationManagersFuture;

  late final LocalSessionDatabase stateLocalDatabase;

  List<LocalTrailHazardMatch> stateStaticHazards = const [];

  int stateHazardLoadGeneration = 0;

  List<Offset?> stateWeatherScreenPositions = const [];

  Map<String, Offset?> stateTeamScreenPositions = const {};

  var stateWeatherProjectionGeneration = 0;

  var stateTeamProjectionGeneration = 0;

  var stateMapSettings = const MapViewSettings();
  var stateMapMode = ActiveHikeMapMode.normal;
  var _normalDimension = MapDimension.threeD;
  int _cameraViewRevision = 0;

  /// Reuses the route preview's FPV angle without its playback controller.
  double get cameraPitch => stateMapMode == ActiveHikeMapMode.firstPerson
      ? routePreviewCameraTuning(null).pitch
      : stateMapSettings.is3D
      ? 50
      : 0;

  /// Retains the ordinary map's dimension while terrain view stays in 3D.
  void commandSetMapMode(ActiveHikeMapMode mode) {
    if (!mounted || stateMapMode == mode) return;
    _cameraViewRevision++;
    if (mode == ActiveHikeMapMode.firstPerson) {
      _normalDimension = stateMapSettings.dimension;
    }
    _publish(() {
      stateMapMode = mode;
      stateMapSettings = stateMapSettings.copyWith(
        dimension: mode == ActiveHikeMapMode.firstPerson
            ? MapDimension.threeD
            : _normalDimension,
      );
    });
    effectQueueMapSettingsUpdate();
  }

  /// Applies live camera changes immediately in FPV, including zoom and fit.
  Future<void> commandMoveCamera(
    mapbox.CameraOptions camera, {
    int durationMillis = 300,
    bool immediately = false,
  }) async {
    final map = stateMapboxMap;
    final generation = stateMapGeneration;
    final viewRevision = _cameraViewRevision;
    if (map == null || !mounted) return;
    if (immediately || stateMapMode == ActiveHikeMapMode.firstPerson) {
      await map.cancelCameraAnimation();
      if (!commandIsCurrentMap(map, generation) ||
          viewRevision != _cameraViewRevision) {
        return;
      }
      if (stateMapMode == ActiveHikeMapMode.firstPerson) {
        camera.pitch = cameraPitch;
      }
      await map.setCamera(camera);
    } else {
      await map.flyTo(
        camera,
        mapbox.MapAnimationOptions(duration: durationMillis),
      );
    }
  }

  var stateStyleLoaded = false;

  var stateRouteRendered = false;

  var stateIsRendering = false;

  var stateRenderPending = false;

  var stateMapGeneration = 0;

  var stateRenderGeneration = 0;

  var stateHasReferenceEndpoints = false;

  late double stateCurrentZoom;

  List<mapbox.Point> stateRoutePoints = const [];

  late mapbox.Point stateStartPoint;

  late mapbox.Point stateEndPoint;

  /// Loads static hazards.
  Future<void> commandLoadStaticHazards() async {
    final generation = ++stateHazardLoadGeneration;
    try {
      final currentScan = await stateLocalDatabase.loadStaticHazardScanTime(
        readActiveHike().trail.trailId,
      );
      if (!mounted || generation != stateHazardLoadGeneration) return;
      if (currentScan != null) {
        final cached = await stateLocalDatabase.loadStaticHazardsForTrail(
          readActiveHike().trail.trailId,
        );
        if (!mounted || generation != stateHazardLoadGeneration) return;
        commandApplyStaticHazards(cached);
      } else {
        commandApplyStaticHazards(const []);
      }
      final hazards = await StaticHazardDatasetService(
        database: stateLocalDatabase,
      ).ensureForTrail(readActiveHike().trail);
      if (!mounted || generation != stateHazardLoadGeneration) return;
      commandApplyStaticHazards(hazards);
    } catch (_) {
      // The active hike remains fully usable with cached tiles when offline.
    }
  }

  /// Applies static hazards.
  void commandApplyStaticHazards(List<LocalTrailHazardMatch> hazards) {
    if (!mounted) return;
    _publish(() {
      stateStaticHazards = prepareStaticHazardsForMapDisplay(hazards);
      stateRouteRendered = false;
    });
    unawaited(commandRenderRouteIfReady());
  }

  /// Computes navigation bearing.
  double? commandNavigationBearing() {
    final latest = commandLatestPoint;
    final recorded = commandRecordedRoutePoints;
    if (latest != null && recorded.length >= 2) {
      for (var index = recorded.length - 2; index >= 0; index--) {
        if (distanceMeters(recorded[index], latest) >= 5) {
          return commandBearingBetween(recorded[index], latest);
        }
      }
    }

    final planned = stateRoutePoints.length >= 2
        ? stateRoutePoints
        : commandCheckpointPoints;
    if (planned.length < 2) return null;
    if (latest == null) {
      return commandBearingBetween(planned.first, planned[1]);
    }

    var nearestIndex = 0;
    var nearestDistance = double.infinity;
    for (var index = 0; index < planned.length; index++) {
      final distance = distanceMeters(latest, planned[index]);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }
    for (var index = nearestIndex + 1; index < planned.length; index++) {
      if (distanceMeters(latest, planned[index]) >= 15) {
        return commandBearingBetween(latest, planned[index]);
      }
    }
    if (nearestIndex > 0) {
      return commandBearingBetween(
        planned[nearestIndex - 1],
        planned[nearestIndex],
      );
    }
    return commandBearingBetween(planned.first, planned[1]);
  }

  /// Computes bearing between.
  double? commandBearingBetween(mapbox.Point from, mapbox.Point to) {
    final start = mapPointCoordinatesOrNull(from);
    final end = mapPointCoordinatesOrNull(to);
    if (start == null || end == null || distanceMeters(from, to) < 2) {
      return null;
    }
    final startLatitude = start.latitude * math.pi / 180;
    final endLatitude = end.latitude * math.pi / 180;
    final longitudeDelta = (end.longitude - start.longitude) * math.pi / 180;
    final y = math.sin(longitudeDelta) * math.cos(endLatitude);
    final x =
        math.cos(startLatitude) * math.sin(endLatitude) -
        math.sin(startLatitude) *
            math.cos(endLatitude) *
            math.cos(longitudeDelta);
    if (x.abs() < 1e-12 && y.abs() < 1e-12) return null;
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// Computes point for checkpoint.
  mapbox.Point commandPointForCheckpoint(TrailCheckpoint checkpoint) =>
      mapbox.Point(
        coordinates: mapbox.Position(checkpoint.longitude, checkpoint.latitude),
      );

  /// Computes valid trail center point.
  mapbox.Point? commandValidTrailCenterPoint() {
    final latitude = readActiveHike().trail.latitude;
    final longitude = readActiveHike().trail.longitude;
    if (!_isValidCoordinate(latitude, longitude)) {
      return null;
    }
    return mapbox.Point(coordinates: mapbox.Position(longitude, latitude));
  }

  /// Returns command recorded route points.
  List<mapbox.Point> get commandRecordedRoutePoints {
    return readActiveHike().routePoints
        .where((point) => point.hasValidPosition)
        .map(
          (point) => mapbox.Point(
            coordinates: mapbox.Position(point.longitude, point.latitude),
          ),
        )
        .toList();
  }

  /// Returns command checkpoint points.
  List<mapbox.Point> get commandCheckpointPoints {
    final checkpoints =
        readActiveHike().draft.effectiveCheckpoints
            .where((checkpoint) => checkpoint.hasValidCoordinate)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    return checkpoints
        .map(
          (checkpoint) => mapbox.Point(
            coordinates: mapbox.Position(
              checkpoint.longitude,
              checkpoint.latitude,
            ),
          ),
        )
        .toList();
  }

  /// Returns command effective participants.
  List<TeamHikeParticipant> get commandEffectiveParticipants {
    if (readActiveHike().draft.hikeType != HikeType.team) {
      return const [];
    }

    final realParticipants =
        (readTeamHikeSession() ?? readActiveHike().teamHikeSession)
            ?.participants ??
        const <TeamHikeParticipant>[];
    return realParticipants;
  }

  /// Returns command located team participants.
  List<TeamHikeParticipant> get commandLocatedTeamParticipants {
    final now = DateTime.now().toUtc();
    return commandEffectiveParticipants
        .where((participant) => participant.hasFreshLocationAt(now))
        .toList();
  }

  /// Computes color for participant.
  Color commandColorForParticipant(TeamHikeParticipant participant, int index) {
    return _displayColorForParticipant(
      participant,
      index,
      readCurrentPhoneNumber(),
    );
  }

  /// Returns command team mate points.
  List<mapbox.Point> get commandTeamMatePoints {
    return commandLocatedTeamParticipants
        .map(
          (p) => mapbox.Point(
            coordinates: mapbox.Position(
              p.latestLocation!.longitude,
              p.latestLocation!.latitude,
            ),
          ),
        )
        .toList();
  }

  /// Returns command latest point.
  mapbox.Point? get commandLatestPoint {
    final latest = readActiveHike().latestLocation;
    if (latest == null || !latest.hasValidPosition) {
      return null;
    }
    return mapbox.Point(
      coordinates: mapbox.Position(latest.longitude, latest.latitude),
    );
  }

  /// Returns command visible points.
  List<mapbox.Point> get commandVisiblePoints {
    final points = <mapbox.Point>[
      ...commandRecordedRoutePoints,
      ...commandTeamMatePoints,
      if (commandLatestPoint != null) commandLatestPoint!,
      ...commandCheckpointPoints,
    ];
    if (stateRoutePoints.length >= 2) {
      points.addAll(stateRoutePoints);
    }
    return points;
  }

  /// Computes decode polyline.
  List<mapbox.Point> commandDecodePolyline(String encoded) {
    try {
      final points = <mapbox.Point>[];
      var index = 0;
      var latitude = 0;
      var longitude = 0;

      /// Computes delta.
      int? readDelta() {
        var shift = 0;
        var result = 0;
        while (true) {
          if (index >= encoded.length || shift > 30) return null;
          final byte = encoded.codeUnitAt(index++) - 63;
          if (byte < 0 || byte > 0x3f) return null;
          result |= (byte & 0x1f) << shift;
          if (byte < 0x20) {
            return (result & 1) == 1 ? ~(result >> 1) : result >> 1;
          }
          shift += 5;
        }
      }

      while (index < encoded.length) {
        final latitudeDelta = readDelta();
        final longitudeDelta = readDelta();
        if (latitudeDelta == null || longitudeDelta == null) return const [];
        latitude += latitudeDelta;
        longitude += longitudeDelta;
        final decodedLatitude = latitude / 100000;
        final decodedLongitude = longitude / 100000;
        if (!_isValidCoordinate(decodedLatitude, decodedLongitude)) {
          return const [];
        }
        points.add(
          mapbox.Point(
            coordinates: mapbox.Position(decodedLongitude, decodedLatitude),
          ),
        );
      }
      return points;
    } catch (_) {
      return const [];
    }
  }

  /// Computes orient route points.
  List<mapbox.Point> commandOrientRoutePoints(List<mapbox.Point> points) {
    if (points.length < 2 || !stateHasReferenceEndpoints) {
      return points;
    }
    final forwardScore =
        distanceMeters(points.first, stateStartPoint) +
        distanceMeters(points.last, stateEndPoint);
    final reverseScore =
        distanceMeters(points.first, stateEndPoint) +
        distanceMeters(points.last, stateStartPoint);
    if (reverseScore < forwardScore) {
      return points.reversed.toList();
    }
    return points;
  }

  /// Checks whether current map.
  bool commandIsCurrentMap(mapbox.MapboxMap map, int generation) {
    return mounted &&
        generation == stateMapGeneration &&
        identical(map, stateMapboxMap);
  }

  /// Computes on map loaded.
  Future<void> commandOnMapLoaded(int generation) async {
    final map = stateMapboxMap;
    if (map == null ||
        !commandIsCurrentMap(map, generation) ||
        stateStyleLoaded) {
      return;
    }
    await effectOnStyleLoaded(generation);
  }

  /// Ensures annotation managers.
  Future<bool> commandEnsureAnnotationManagers(
    mapbox.MapboxMap map,
    int generation,
  ) {
    if (!stateStyleLoaded || !commandIsCurrentMap(map, generation)) {
      return Future.value(false);
    }
    final existingFuture = stateAnnotationManagersFuture;
    if (existingFuture != null) return existingFuture;
    final future = effectCreateAnnotationManagers(map, generation);
    stateAnnotationManagersFuture = future;
    return future.whenComplete(() {
      if (identical(stateAnnotationManagersFuture, future)) {
        stateAnnotationManagersFuture = null;
      }
    });
  }

  /// Computes render route if ready.
  Future<void> commandRenderRouteIfReady() async {
    if (stateIsRendering) {
      stateRenderPending = true;
      return;
    }
    final map = stateMapboxMap;
    final mapGeneration = stateMapGeneration;
    if (map == null ||
        !stateStyleLoaded ||
        stateRouteRendered ||
        commandVisiblePoints.isEmpty) {
      return;
    }
    if (!await commandEnsureAnnotationManagers(map, mapGeneration)) return;

    stateIsRendering = true;
    final renderGeneration = stateRenderGeneration;
    try {
      await effectRenderRouteNow(map, mapGeneration, renderGeneration);
    } catch (error) {
      if (commandIsCurrentMap(map, mapGeneration) &&
          renderGeneration == stateRenderGeneration) {
        stateRouteRendered = false;
        debugPrint('Unable to draw active hike route: $error');
      }
    } finally {
      stateIsRendering = false;
      if (stateRenderPending && mounted) {
        stateRenderPending = false;
        stateRouteRendered = false;
        unawaited(commandRenderRouteIfReady());
      }
    }
  }

  /// Computes project weather markers.
  Future<void> commandProjectWeatherMarkers() async {
    final map = stateMapboxMap;
    final generation = stateMapGeneration;
    final projectionGeneration = stateWeatherProjectionGeneration;
    final samples = readWeatherSamples();
    final validIndices = <int>[
      for (var index = 0; index < samples.length; index++)
        if (samples[index].coordinate.hasValidPosition) index,
    ];
    if (map == null || !stateStyleLoaded || validIndices.isEmpty) {
      if (mounted && stateWeatherScreenPositions.isNotEmpty) {
        _publish(() {
          stateWeatherScreenPositions = const [];
        });
      }
      return;
    }

    try {
      final pixels = await map.pixelsForCoordinates([
        for (final index in validIndices)
          mapbox.Point(
            coordinates: mapbox.Position(
              samples[index].coordinate.longitude,
              samples[index].coordinate.latitude,
            ),
          ),
      ]);
      if (!commandIsCurrentMap(map, generation) ||
          projectionGeneration != stateWeatherProjectionGeneration) {
        return;
      }
      _publish(() {
        final positions = List<Offset?>.filled(samples.length, null);
        final projectedCount = math.min(validIndices.length, pixels.length);
        for (var index = 0; index < projectedCount; index++) {
          final pixel = pixels[index];
          positions[validIndices[index]] =
              pixel == null || !pixel.x.isFinite || !pixel.y.isFinite
              ? null
              : Offset(pixel.x, pixel.y);
        }
        stateWeatherScreenPositions = positions;
      });
    } catch (error) {
      debugPrint('Unable to project hike weather markers: $error');
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && generation == stateMapGeneration) {
          effectScheduleWeatherProjection();
        }
      });
    }
  }

  /// Computes project team markers.
  Future<void> commandProjectTeamMarkers() async {
    final map = stateMapboxMap;
    final generation = stateMapGeneration;
    final projectionGeneration = stateTeamProjectionGeneration;
    final participants = commandLocatedTeamParticipants;
    if (map == null || !stateStyleLoaded || participants.isEmpty) {
      if (mounted && stateTeamScreenPositions.isNotEmpty) {
        _publish(() {
          stateTeamScreenPositions = const {};
        });
      }
      return;
    }

    try {
      final participantKeys = participants
          .map(commandParticipantProjectionKey)
          .toList();
      final pixels = await map.pixelsForCoordinates([
        for (final participant in participants)
          mapbox.Point(
            coordinates: mapbox.Position(
              participant.latestLocation!.longitude,
              participant.latestLocation!.latitude,
            ),
          ),
      ]);
      if (!commandIsCurrentMap(map, generation) ||
          projectionGeneration != stateTeamProjectionGeneration) {
        return;
      }
      _publish(() {
        final projectedCount = math.min(participantKeys.length, pixels.length);
        stateTeamScreenPositions = {
          for (var index = 0; index < projectedCount; index++)
            participantKeys[index]: pixels[index] == null
                ? null
                : pixels[index]!.x.isFinite && pixels[index]!.y.isFinite
                ? Offset(pixels[index]!.x, pixels[index]!.y)
                : null,
        };
      });
    } catch (error) {
      debugPrint('Unable to project team markers: $error');
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && generation == stateMapGeneration) {
          effectScheduleTeamProjection();
        }
      });
    }
  }

  /// Computes participant projection key.
  String commandParticipantProjectionKey(TeamHikeParticipant participant) {
    final phone = participant.phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isNotEmpty) return 'phone:$phone';
    final handle = participant.buddy.handle.trim().toLowerCase();
    if (handle.isNotEmpty) return 'handle:$handle';
    return 'name:${participant.buddy.name.trim().toLowerCase()}';
  }

  /// Computes fit route.
  Future<void> commandFitRoute() async {
    effectPauseNavigationFollow();
    final map = stateMapboxMap;
    final points = commandVisiblePoints;
    if (map == null || points.isEmpty) {
      return;
    }
    if (points.length == 1) {
      try {
        await commandMoveCamera(
          mapbox.CameraOptions(center: points.first, zoom: 15),
        );
      } catch (_) {
        return;
      }
      await effectSyncScaleFromCamera();
      return;
    }

    try {
      try {
        final b = boundsFor(points);
        if (b.minLon > b.maxLon || b.minLat > b.maxLat) {
          final center = centerFor(points);
          await commandMoveCamera(
            mapbox.CameraOptions(center: center, zoom: stateCurrentZoom),
          );
          await effectSyncScaleFromCamera();
          return;
        }

        final camera = await map.cameraForCoordinateBounds(
          mapbox.CoordinateBounds(
            southwest: mapbox.Point(
              coordinates: mapbox.Position(b.minLon, b.minLat),
            ),
            northeast: mapbox.Point(
              coordinates: mapbox.Position(b.maxLon, b.maxLat),
            ),
            infiniteBounds: false,
          ),
          mapbox.MbxEdgeInsets(top: 60, left: 60, bottom: 60, right: 60),
          null,
          null,
          null,
          null,
        );
        final cameraCenter = camera.center == null
            ? null
            : mapPointCoordinatesOrNull(camera.center!);
        if (camera.zoom != null &&
            camera.zoom!.isFinite &&
            cameraCenter != null) {
          await commandMoveCamera(camera);
        } else {
          throw Exception('Invalid camera from cameraForCoordinateBounds');
        }
      } catch (_) {
        final center = centerFor(points);
        await commandMoveCamera(
          mapbox.CameraOptions(center: center, zoom: stateCurrentZoom),
        );
      }
    } catch (_) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) unawaited(commandFitRoute());
      });
    }
    await effectSyncScaleFromCamera();
  }

  /// Computes change map settings.
  void commandChangeMapSettings(MapViewSettings next) {
    if (stateMapMode == ActiveHikeMapMode.firstPerson) {
      next = next.copyWith(dimension: MapDimension.threeD);
    }
    final previous = stateMapSettings;
    if (previous.styleIndex == next.styleIndex &&
        previous.dimension == next.dimension) {
      return;
    }
    _publish(() => stateMapSettings = next);
    effectQueueMapSettingsUpdate();
  }

  /// Computes zoom by.
  Future<void> commandZoomBy(double amount) async {
    if (stateMapboxMap == null) return;
    effectPauseNavigationFollow();
    try {
      await commandMoveCamera(
        mapbox.CameraOptions(zoom: stateCurrentZoom + amount),
      );
    } catch (_) {}
    await effectSyncScaleFromCamera();
  }

  /// Computes on camera change.
  void commandOnCameraChange(mapbox.CameraChangedEventData data) {
    effectUpdateScale(data);
    effectScheduleWeatherProjection();
    effectScheduleTeamProjection();
  }

  /// Computes weather marker visual offset.
  Offset commandWeatherMarkerVisualOffset(int index) {
    final sample = readWeatherSamples()[index];
    final coincidentCount = readWeatherSamples()
        .take(index)
        .where(
          (previous) => previous.coordinate.distanceTo(sample.coordinate) < 12,
        )
        .length;
    final direction = index.isEven ? -1.0 : 1.0;
    final separation = coincidentCount * 14.0;
    return Offset(direction * (18 + separation), -54);
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

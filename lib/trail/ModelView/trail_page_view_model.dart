part of '../trail_page_feature.dart';

/// Owns the state and non-visual actions of _AddTrailSheet.
class _AddTrailSheetStateViewModel extends ChangeNotifier {
  /// Creates add trail sheet state view model.
  _AddTrailSheetStateViewModel({required this.effectValidateAndSaveTrail});
  final Future<void> Function() effectValidateAndSaveTrail;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  final List<_PendingTrailImage> statePendingImages = [];

  String stateArea = '';

  String stateLocationState = '';

  String stateCountry = '';

  final List<_CheckpointDraft> stateCheckpoints = [];

  String? stateErrorMessage;

  bool stateHasFetchedRoute = false;

  String? stateRouteResultCheckpointsHash;

  bool stateLocationFailed = false;

  bool stateIsResolvingLocation = false;

  int stateLocationGeneration = 0;

  String? stateLocationLookupKey;

  bool stateIsUploadingImages = false;

  bool stateIsSavingTrail = false, stateIsCheckingDuplicate = false;

  HikingRouteResult? stateRouteResult;

  /// Returns command camera supported.
  bool get commandCameraSupported {
    if (kIsWeb) {
      return true;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Removes pending image.
  void commandRemovePendingImage(int index) {
    if (stateIsUploadingImages ||
        index < 0 ||
        index >= statePendingImages.length) {
      return;
    }
    _publish(() {
      statePendingImages.removeAt(index);
    });
  }

  /// Computes checkpoints changed.
  void commandCheckpointsChanged() {
    _publish(() {
      stateRouteResult = null;
      stateHasFetchedRoute = false;
      stateRouteResultCheckpointsHash = null;
    });
    final points = commandCheckpointModels();
    if (points.isNotEmpty) {
      unawaited(
        commandResolveLocation(points.first.latitude, points.first.longitude),
      );
    }
  }

  /// Computes draft trail.
  Trail commandDraftTrail(List<TrailCheckpoint> checkpoints) => Trail(
    trailId: '',
    name: '',
    area: '',
    state: '',
    latitude: checkpoints.first.latitude,
    longitude: checkpoints.first.longitude,
    distanceKm: 0,
    difficulty: '',
    estimatedDurationMinutes: 0,
    elevationGainMeters: 0,
    ratingAverage: 0,
    offlineMapAvailable: false,
    offlineMapDownloaded: false,
    isVerifiedTrail: true,
    routeFilePath: '',
    coverColorValue: 0xFF34A853,
    checkpoints: checkpoints,
    weather: TrailWeather(
      summary: '',
      temperatureRange: '',
      rainProbability: 0,
      cachedAt: DateTime.now().toUtc(),
    ),
    hazards: const [],
  );

  /// Fetches route.
  Future<HikingRouteResult?> commandFetchRoute(
    List<TrailCheckpoint> checkpoints,
  ) async {
    try {
      final trail = commandDraftTrail(checkpoints);

      return await HikingRouteService().findHikingRouteForTrail(trail);
    } catch (_) {
      return null;
    }
  }

  /// Resolve the selected coordinate's region instead of inferring identity from map camera presets.
  Future<void> commandResolveLocation(double latitude, double longitude) async {
    final key =
        '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';
    if (key == stateLocationLookupKey &&
        !stateLocationFailed &&
        (stateIsResolvingLocation ||
            (stateArea.trim().isNotEmpty &&
                stateLocationState.trim().isNotEmpty &&
                stateCountry.trim().isNotEmpty))) {
      return;
    }
    stateLocationLookupKey = key;
    final generation = ++stateLocationGeneration;
    _publish(() {
      stateErrorMessage = null;
      stateLocationFailed = false;
      stateIsResolvingLocation = true;
      stateArea = '';
      stateLocationState = '';
      stateCountry = '';
    });
    try {
      final geocoding = GoogleCityGeocodingService();
      final result = await geocoding.resolveCity(
        latitude: latitude,
        longitude: longitude,
      );
      final region = await WorldwideRegionCatalog.normalize(
        country: result.country,
        state: result.state,
      );
      if (result.city.trim().isEmpty ||
          (region?.state ?? result.state).trim().isEmpty ||
          (region?.country ?? result.country).trim().isEmpty) {
        throw StateError('The starting point location is incomplete.');
      }
      if (mounted && generation == stateLocationGeneration) {
        _publish(() {
          stateIsResolvingLocation = false;
          if (stateArea.isEmpty) {
            stateArea = result.city;
          }
          stateLocationState = region?.state ?? result.state;
          stateCountry = region?.country ?? result.country;
        });
      }
      return;
    } catch (_) {
      if (!mounted || generation != stateLocationGeneration) return;
      try {
        final geoapify = GeoapifyService();
        final result = await geoapify.reverseGeocode(
          latitude: latitude,
          longitude: longitude,
        );
        final region = await WorldwideRegionCatalog.normalize(
          country: result.country,
          state: result.state,
        );
        if (result.area.trim().isEmpty ||
            (region?.state ?? result.state).trim().isEmpty ||
            (region?.country ?? result.country).trim().isEmpty) {
          throw StateError('The starting point location is incomplete.');
        }
        if (mounted && generation == stateLocationGeneration) {
          _publish(() {
            stateIsResolvingLocation = false;
            if (stateArea.isEmpty && result.area.isNotEmpty) {
              stateArea = result.area;
            }
            stateLocationState = region?.state ?? result.state;
            stateCountry = region?.country ?? result.country;
          });
        }
        return;
      } catch (_) {}
    }
    if (mounted && generation == stateLocationGeneration) {
      _publish(() {
        stateIsResolvingLocation = false;
        stateLocationFailed = true;
      });
    }
  }

  /// Saves trail.
  Future<void> commandSaveTrail() async {
    if (stateIsSavingTrail ||
        stateIsUploadingImages ||
        stateIsResolvingLocation) {
      return;
    }
    _publish(() => stateIsSavingTrail = true);
    try {
      await effectValidateAndSaveTrail();
    } finally {
      if (mounted) _publish(() => stateIsSavingTrail = false);
    }
  }

  /// Computes checkpoint models.
  List<TrailCheckpoint> commandCheckpointModels() {
    final checkpoints = <TrailCheckpoint>[];
    for (var index = 0; index < stateCheckpoints.length; index++) {
      final draft = stateCheckpoints[index];
      final name = draft.nameController.text.trim();
      final latitude = double.tryParse(draft.latitudeController.text.trim());
      final longitude = double.tryParse(draft.longitudeController.text.trim());
      if (name.isEmpty ||
          latitude == null ||
          longitude == null ||
          !latitude.isFinite ||
          !longitude.isFinite ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180) {
        continue;
      }
      checkpoints.add(
        TrailCheckpoint(
          name: name,
          latitude: latitude,
          longitude: longitude,
          order: index + 1,
        ),
      );
    }
    return checkpoints;
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final AppSession Function() readSession;

  late final HikerCircleFirebaseRepository Function() readRepository;

  late final String? Function() effectValidatedImageUrl;

  late final void Function(
    String trailId,
    String name,
    String area,
    String state,
    String country,
    double latitude,
    double longitude,
    double distance,
    int duration,
    int elevation,
    int? minElevation,
    int? maxElevation,
    List<String> imageUrls,
    List<TrailCheckpoint> checkpoints,
    String? polyline,
    String? hash,
  )
  effectPresentDoSaveTrailEffect1;

  /// Computes do save trail.
  Future<void> commandDoSaveTrail({
    required String name,
    required String area,
    required String state,
    required String country,
    required double latitude,
    required double longitude,
    required double distance,
    required int duration,
    required int elevation,
    required int? minElevation,
    required int? maxElevation,
    required List<TrailCheckpoint> checkpoints,
  }) async {
    final polyline = stateRouteResult?.encodedPolyline;
    final hash = stateRouteResult != null
        ? HikingRouteService.checkpointsHash(checkpoints)
        : null;
    final trailId = readRepository().newTrailIdForName(name);
    final imageUrls = <String>[];
    final manualImageUrl = effectValidatedImageUrl();
    if (manualImageUrl != null && manualImageUrl.isNotEmpty) {
      imageUrls.add(manualImageUrl);
    }

    if (statePendingImages.isNotEmpty) {
      _publish(() {
        stateIsUploadingImages = true;
        stateErrorMessage = null;
      });
      try {
        final uploadedUrls = await readRepository()
            .uploadTrailCoverImagesByAdmin(
              session: readSession(),
              trailId: trailId,
              images: statePendingImages
                  .map(
                    (image) => AdminTrailImageUpload(
                      bytes: image.bytes,
                      fileName: image.fileName,
                      contentType: image.contentType,
                    ),
                  )
                  .toList(),
            );
        imageUrls.insertAll(0, uploadedUrls);
      } on HikerCircleFirebaseRepositoryException catch (error) {
        if (mounted) {
          _publish(() {
            stateIsUploadingImages = false;
            stateErrorMessage = error.message;
          });
        }
        return;
      } catch (error) {
        if (mounted) {
          _publish(() {
            stateIsUploadingImages = false;
            stateErrorMessage = 'Unable to upload trail images: $error';
          });
        }
        return;
      }
    }
    if (!mounted) {
      return;
    }
    effectPresentDoSaveTrailEffect1(
      trailId,
      name,
      area,
      state,
      country,
      latitude,
      longitude,
      distance,
      duration,
      elevation,
      minElevation,
      maxElevation,
      imageUrls,
      checkpoints,
      polyline,
      hash,
    );
  }
}

/// Owns the state and non-visual actions of _MapBasedCheckpointPicker.
class _MapBasedCheckpointPickerStateViewModel extends ChangeNotifier {
  /// Creates map based checkpoint picker state view model.
  _MapBasedCheckpointPickerStateViewModel({
    required this.readEditableIndex,
    required this.readRouteCoordinates,
    required this.readShowStateFocus,
    required this.readSinglePinMode,
    required this.effectPrepareStyle,
  });
  final int? Function() readEditableIndex;
  final List<mapbox.Position>? Function() readRouteCoordinates;
  final bool Function() readShowStateFocus;
  final bool Function() readSinglePinMode;
  final Future<void> Function() effectPrepareStyle;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  mapbox.MapboxMap? stateMapboxMap;

  mapbox.CircleAnnotationManager? stateCircleManager;

  mapbox.PointAnnotationManager? statePointManager;

  mapbox.PolylineAnnotationManager? statePolylineManager;

  bool stateStyleLoaded = false;

  Future<void>? stateStyleSetup;

  Future<void> statePinRendering = Future.value();

  int statePinRevision = 0;

  MalaysiaMapRegion stateFocusRegion = MalaysiaMapRegion.peninsula;

  int stateFocusRevision = 0;

  late List<mapbox.Point> statePins;

  /// Computes initial center.
  mapbox.Point commandInitialCenter() => statePins.isNotEmpty
      ? statePins.first
      : readShowStateFocus()
      ? mapbox.Point(
          coordinates: mapbox.Position(
            stateFocusRegion.longitude,
            stateFocusRegion.latitude,
          ),
        )
      : mapbox.Point(coordinates: mapbox.Position(101.6869, 3.1390));

  /// Computes focus on region.
  Future<void> commandFocusOnRegion({int duration = 450}) async {
    final map = stateMapboxMap;
    if (map == null) return;
    final region = stateFocusRegion;
    final revision = ++stateFocusRevision;
    try {
      final camera = await map.cameraForCoordinateBounds(
        mapbox.CoordinateBounds(
          southwest: mapbox.Point(
            coordinates: mapbox.Position(region.west, region.south),
          ),
          northeast: mapbox.Point(
            coordinates: mapbox.Position(region.east, region.north),
          ),
          infiniteBounds: false,
        ),
        mapbox.MbxEdgeInsets(top: 32, left: 24, bottom: 110, right: 54),
        0,
        0,
        null,
        null,
      );
      if (!mounted ||
          !identical(map, stateMapboxMap) ||
          revision != stateFocusRevision) {
        return;
      }
      await map.flyTo(camera, mapbox.MapAnimationOptions(duration: duration));
    } catch (_) {
      // Navigation can dispose the native map while it computes the framing.
    }
  }

  /// Prepares map style.
  Future<void> commandPrepareMapStyle() {
    final existing = stateStyleSetup;
    if (existing != null) return existing;
    final future = effectPrepareStyle();
    stateStyleSetup = future;
    return future.whenComplete(() {
      if (identical(stateStyleSetup, future)) stateStyleSetup = null;
    });
  }

  /// Update map route annotations only for the current route inputs and loaded style.
  Future<void> commandSyncRoute() async {
    if (!stateStyleLoaded) return;
    final manager = statePolylineManager;
    if (manager == null) return;
    try {
      await manager.deleteAll();
      if (!mounted || !identical(manager, statePolylineManager)) return;
      final coords = readRouteCoordinates();
      if (coords != null && coords.length >= 2) {
        await manager.create(
          mapbox.PolylineAnnotationOptions(
            geometry: mapbox.LineString(coordinates: coords),
            lineColor: const Color(0xFF4ADE80).toARGB32(),
            lineOpacity: 0.4,
            lineWidth: 4,
            lineJoin: mapbox.LineJoin.ROUND,
          ),
        );
      }
    } catch (_) {
      // Style replacement invalidates its annotation managers.
    }
  }

  /// Synchronizes pins.
  Future<void> commandSyncPins() {
    final revision = ++statePinRevision;
    statePinRendering = statePinRendering.catchError((Object _) {}).then((
      _,
    ) async {
      if (!mounted || revision != statePinRevision) return;
      await commandRenderPins(revision);
    });
    return statePinRendering;
  }

  /// Computes render pins.
  Future<void> commandRenderPins(int revision) async {
    if (!stateStyleLoaded) return;
    final circleManager = stateCircleManager;
    final pointManager = statePointManager;
    if (circleManager == null || pointManager == null) return;

    try {
      await circleManager.deleteAll();
      await pointManager.deleteAll();
      if (!mounted ||
          !identical(circleManager, stateCircleManager) ||
          !identical(pointManager, statePointManager)) {
        return;
      }

      final pins = List<mapbox.Point>.of(statePins);
      for (var i = 0; i < pins.length; i++) {
        if (!mounted || revision != statePinRevision) return;
        final point = pins[i];
        final isEditable =
            readEditableIndex() != null && i == readEditableIndex();
        if (isEditable) {
          await circleManager.create(
            mapbox.CircleAnnotationOptions(
              geometry: point,
              circleRadius: 14,
              circleColor: const Color(0xFFF59E0B).toARGB32(),
              circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
              circleStrokeWidth: 3.5,
            ),
          );
          await circleManager.create(
            mapbox.CircleAnnotationOptions(
              geometry: point,
              circleRadius: 22,
              circleColor: const Color(0xFFF59E0B).toARGB32(),
              circleStrokeColor: const Color(0xFFF59E0B).toARGB32(),
              circleStrokeWidth: 0,
              circleOpacity: 0.3,
            ),
          );
        } else {
          await circleManager.create(
            mapbox.CircleAnnotationOptions(
              geometry: point,
              circleRadius: readSinglePinMode() ? 14 : 10,
              circleColor: const Color(0xFF147DDB).toARGB32(),
              circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
              circleStrokeWidth: 2.5,
            ),
          );
        }
        if (!readSinglePinMode()) {
          await pointManager.create(
            mapbox.PointAnnotationOptions(
              geometry: point,
              textField: '${i + 1}',
              textSize: 11,
              textColor: 0xFFFFFFFF,
              textHaloColor: 0xFF111111,
              textHaloWidth: 0.7,
              textAnchor: mapbox.TextAnchor.CENTER,
            ),
          );
        }
      }
    } catch (_) {
      // Style replacement invalidates its annotation managers.
    }
  }

  /// Computes tapped pin index.
  int? commandTappedPinIndex(mapbox.Point tapped) {
    final tappedCoordinates = mapPointCoordinatesOrNull(tapped);
    if (tappedCoordinates == null) return null;
    for (var i = 0; i < statePins.length; i++) {
      final pinCoordinates = mapPointCoordinatesOrNull(statePins[i]);
      if (pinCoordinates == null) continue;
      final dlat = tappedCoordinates.latitude - pinCoordinates.latitude;
      final dlng = tappedCoordinates.longitude - pinCoordinates.longitude;
      if (dlat.abs() + dlng.abs() < 0.001) return i;
    }
    return null;
  }

  /// Computes zoom by.
  Future<void> commandZoomBy(double amount) async {
    final map = stateMapboxMap;
    if (map == null) return;
    try {
      final state = await map.getCameraState();
      if (!state.zoom.isFinite) return;
      await map.flyTo(
        mapbox.CameraOptions(
          zoom: (state.zoom + amount)
              .clamp(kMapMinZoom, kMapMaxZoom)
              .toDouble(),
        ),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {
      // The native map may have been disposed before the camera update.
    }
  }

  /// Computes fit pins.
  Future<void> commandFitPins() async {
    if (statePins.isEmpty) {
      if (readShowStateFocus()) await commandFocusOnRegion();
      return;
    }
    stateFocusRevision++;
    final map = stateMapboxMap;
    if (map == null) return;
    try {
      if (statePins.length == 1) {
        await map.flyTo(
          mapbox.CameraOptions(center: statePins.first, zoom: 15),
          mapbox.MapAnimationOptions(duration: 300),
        );
      } else {
        await map.flyTo(
          mapbox.CameraOptions(center: centerFor(statePins), zoom: 13),
          mapbox.MapAnimationOptions(duration: 300),
        );
      }
    } catch (_) {
      // The native map may have been disposed before the camera update.
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final void Function() effectPresentUpdateStateBoundaryEffect1;

  /// Updates state boundary.
  Future<void> commandUpdateStateBoundary(Future<void> update) async {
    try {
      await update;
    } catch (_) {
      if (!mounted) return;
      effectPresentUpdateStateBoundaryEffect1();
    }
  }
}

/// Owns the state and non-visual actions of _SinglePinPickerSheet.
class _SinglePinPickerSheetStateViewModel extends ChangeNotifier {
  /// Creates single pin picker sheet state view model.
  _SinglePinPickerSheetStateViewModel();

  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late mapbox.Point stateSelected = mapbox.Point(
    coordinates: mapbox.Position(101.6869, 3.1390),
  );

  mapbox.MapboxMap? stateMapboxMap;

  mapbox.CircleAnnotationManager? stateCircleManager;

  mapbox.PointAnnotationManager? statePointManager;

  bool stateStyleLoaded = false;

  /// Selects coordinate.
  void commandSelectCoordinate(mapbox.Point coordinate) {
    if (!mounted || mapPointCoordinatesOrNull(coordinate) == null) return;
    _publish(() => stateSelected = coordinate);
    unawaited(commandSyncSelectedPin());
    unawaited(commandCenterOn(coordinate));
  }

  /// Computes center on.
  Future<void> commandCenterOn(mapbox.Point coordinate, {double? zoom}) async {
    final map = stateMapboxMap;
    if (map == null) return;
    try {
      await map.flyTo(
        mapbox.CameraOptions(center: coordinate, zoom: zoom),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {
      // The native map may have been disposed while handling a tap.
    }
  }

  /// Computes fit selected pin.
  Future<void> commandFitSelectedPin() =>
      commandCenterOn(stateSelected, zoom: 15);

  /// Prepares map style.
  Future<void> commandPrepareMapStyle() async {
    final map = stateMapboxMap;
    if (map == null || !mounted) return;
    try {
      stateCircleManager ??= await map.annotations
          .createCircleAnnotationManager();
      statePointManager ??= await map.annotations
          .createPointAnnotationManager();
      if (!mounted || !identical(map, stateMapboxMap)) return;
      stateStyleLoaded = true;
      await commandSyncSelectedPin();
    } catch (_) {
      // The style callback may outlive the native map instance.
    }
  }

  /// Synchronizes selected pin.
  Future<void> commandSyncSelectedPin() async {
    if (!stateStyleLoaded) return;
    final circleManager = stateCircleManager;
    final pointManager = statePointManager;
    if (circleManager == null || pointManager == null) return;
    try {
      await circleManager.deleteAll();
      await pointManager.deleteAll();
      if (!mounted ||
          !identical(circleManager, stateCircleManager) ||
          !identical(pointManager, statePointManager)) {
        return;
      }
      await circleManager.create(
        mapbox.CircleAnnotationOptions(
          geometry: stateSelected,
          circleRadius: 10,
          circleColor: const Color(0xFFE11D48).toARGB32(),
          circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
          circleStrokeWidth: 3,
        ),
      );
      await pointManager.create(
        mapbox.PointAnnotationOptions(
          geometry: stateSelected,
          textField: 'Pin',
          textSize: 12,
          textColor: 0xFFFFFFFF,
          textHaloColor: 0xFF111111,
          textHaloWidth: 0.8,
          textOffset: const [0.0, 1.35],
          textAnchor: mapbox.TextAnchor.TOP,
        ),
      );
    } catch (_) {
      // Style replacement invalidates its annotation managers.
    }
  }

  /// Computes zoom by.
  Future<void> commandZoomBy(double amount) async {
    final map = stateMapboxMap;
    if (map == null) return;
    try {
      final state = await map.getCameraState();
      if (!state.zoom.isFinite) return;
      await map.flyTo(
        mapbox.CameraOptions(
          zoom: (state.zoom + amount)
              .clamp(kMapMinZoom, kMapMaxZoom)
              .toDouble(),
        ),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {
      // The native map may have been disposed before the camera update.
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _EditTrailPage.
class _EditTrailPageStateViewModel extends ChangeNotifier {
  /// Creates edit trail page state view model.
  _EditTrailPageStateViewModel({
    required this.readTrail,
    required this.effectDraftTrailForRoute,
  });
  final Trail Function() readTrail;
  final Trail Function(List<TrailCheckpoint> checkpoints)
  effectDraftTrailForRoute;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  HikingRouteResult? stateRefreshedRoute;

  String? stateRefreshedRouteCheckpointsHash;

  /// Computes decode polyline.
  List<mapbox.Point> commandDecodePolyline(String encoded) {
    final points = <mapbox.Point>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;

    /// Computes delta.
    int? readDelta() {
      var shift = 0;
      var result = 0;
      while (true) {
        if (index >= encoded.length) return null;
        final byte = encoded.codeUnitAt(index++) - 63;
        if (byte < 0 || byte > 0x3f || shift > 30) return null;
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
      final point = mapbox.Point(
        coordinates: mapbox.Position(longitude / 100000, latitude / 100000),
      );
      if (mapPointCoordinatesOrNull(point) == null) return const [];
      points.add(point);
    }
    return points;
  }

  /// Computes route inputs changed.
  bool commandRouteInputsChanged(List<TrailCheckpoint> checkpoints) {
    return HikingRouteService.checkpointsHash(checkpoints) !=
        HikingRouteService.checkpointsHash(readTrail().checkpoints);
  }

  /// Refresh route-derived values when the edited checkpoints no longer match the stored route inputs.
  Future<HikingRouteResult?> commandFreshRouteForSave(
    List<TrailCheckpoint> checkpoints,
  ) async {
    final checkpointsHash = HikingRouteService.checkpointsHash(checkpoints);
    if (stateRefreshedRoute != null &&
        stateRefreshedRouteCheckpointsHash == checkpointsHash) {
      return stateRefreshedRoute;
    }
    final route = await HikingRouteService().findHikingRouteForTrail(
      effectDraftTrailForRoute(checkpoints),
    );
    if (mounted) {
      _publish(() {
        stateRefreshedRoute = route;
        stateRefreshedRouteCheckpointsHash = checkpointsHash;
      });
    }
    return route;
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _RoutePreview.
class _RoutePreviewStateViewModel extends ChangeNotifier {
  /// Creates route preview state view model.
  _RoutePreviewStateViewModel({
    required this.readLocalDatabase,
    required this.readOnRouteLoaded,
    required this.readTrail,
  });
  final LocalSessionDatabase? Function() readLocalDatabase;
  final ValueChanged<HikingRouteResult>? Function() readOnRouteLoaded;
  final Trail Function() readTrail;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  HikingRouteResult? stateRoute;

  Timer? stateRetryTimer;

  var stateLoadGeneration = 0;

  var stateAttempt = 0;

  var stateIsLoadingRoute = true;

  String stateLoadingMessage = 'Loading detailed hiking route…';

  /// Computes route stored with trail.
  HikingRouteResult? commandRouteStoredWithTrail(Trail trail) {
    final encoded = trail.routeEncodedPolyline?.trim() ?? '';
    if (encoded.isEmpty ||
        !HikingRouteService.savedRouteMatchesCheckpoints(trail)) {
      return null;
    }
    try {
      if (PolylineCodec.decode(encoded).length < 2) {
        return null;
      }
    } catch (_) {
      return null;
    }
    return HikingRouteResult(
      distanceMeters: (trail.distanceKm * 1000).round(),
      duration: Duration(minutes: trail.estimatedDurationMinutes),
      encodedPolyline: encoded,
      elevationGainMeters: trail.elevationGainMeters.toDouble(),
      minElevationMeters: trail.minElevationMeters?.toDouble(),
      maxElevationMeters: trail.maxElevationMeters?.toDouble(),
      sourceLabel: 'Saved trail route',
    );
  }

  /// Loads hiking route.
  Future<void> commandLoadHikingRoute() async {
    final generation = ++stateLoadGeneration;
    stateRetryTimer?.cancel();
    if (mounted) {
      _publish(() {
        stateIsLoadingRoute = true;
        stateLoadingMessage = stateAttempt == 0
            ? 'Loading detailed hiking route…'
            : 'Connection is slow. Still trying for the route…';
      });
    }

    final service = HikingRouteService(localDatabase: readLocalDatabase());
    final slowConnectionTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && generation == stateLoadGeneration) {
        _publish(() {
          stateLoadingMessage =
              'The network is slow. The route is still loading…';
        });
      }
    });
    try {
      final route = await service.findHikingRouteForTrailWithCache(readTrail());
      if (!mounted || generation != stateLoadGeneration) {
        return;
      }
      if (route.encodedPolyline.isEmpty ||
          PolylineCodec.decode(route.encodedPolyline).length < 2) {
        throw const HikingRouteServiceException(
          'The route response did not contain a usable path.',
        );
      }
      _publish(() {
        stateRoute = route;
        stateIsLoadingRoute = false;
        stateLoadingMessage = '';
        stateAttempt = 0;
      });
      readOnRouteLoaded()?.call(route);
    } catch (_) {
      if (!mounted || generation != stateLoadGeneration) {
        return;
      }
      stateAttempt++;
      _publish(() {
        stateIsLoadingRoute = true;
        stateLoadingMessage =
            'Connection is slow. Showing checkpoints while the route keeps loading…';
      });
      final retrySeconds = math.min(15, 2 + (stateAttempt * 2));
      stateRetryTimer = Timer(Duration(seconds: retrySeconds), () {
        if (mounted && generation == stateLoadGeneration) {
          unawaited(commandLoadHikingRoute());
        }
      });
    } finally {
      slowConnectionTimer.cancel();
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _WeatherInsightsSheet.
class _WeatherInsightsSheetStateViewModel extends ChangeNotifier {
  /// Creates weather insights sheet state view model.
  _WeatherInsightsSheetStateViewModel();

  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Computes time ago.
  String commandTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().toUtc().difference(dateTime.toUtc());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// Computes uv label.
  String commandUvLabel(double uvIndex) {
    if (uvIndex < 3) return '${uvIndex.toStringAsFixed(1)} (Low)';
    if (uvIndex < 6) return '${uvIndex.toStringAsFixed(1)} (Moderate)';
    if (uvIndex < 8) return '${uvIndex.toStringAsFixed(1)} (High)';
    if (uvIndex < 11) return '${uvIndex.toStringAsFixed(1)} (Very High)';
    return '${uvIndex.toStringAsFixed(1)} (Extreme)';
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

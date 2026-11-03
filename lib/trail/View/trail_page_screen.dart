part of '../trail_page_feature.dart';

/// Shows add trail sheet.
Future<Trail?> showAddTrailSheet(
  BuildContext context, {
  required AppSession session,
  required HikerCircleFirebaseRepository repository,
}) {
  return Navigator.of(context).push<Trail>(
    MaterialPageRoute(
      builder: (_) => _AddTrailSheet(session: session, repository: repository),
    ),
  );
}

/// Shows edit trail sheet.
Future<Trail?> showEditTrailSheet(BuildContext context, Trail trail) {
  return Navigator.of(context).push<Trail>(
    MaterialPageRoute(builder: (_) => _EditTrailPage(trail: trail)),
  );
}

/// Normalizes trail difficulty.
String _normalizeTrailDifficulty(String raw) {
  return switch (raw.trim().toLowerCase()) {
    'easy' => 'Easy',
    'moderate' || 'medium' => 'Moderate',
    'hard' => 'Hard',
    _ => '',
  };
}

/// Displays the trail page.
class TrailPage extends StatefulWidget {
  /// Creates trail page.
  const TrailPage({
    super.key,
    required this.session,
    required this.hikerCircleRepository,
    required this.onStartHike,
    this.initialTrails,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository hikerCircleRepository;
  final Future<void> Function(Trail trail) onStartHike;
  final List<Trail>? initialTrails;

  /// Creates the presentation state for this widget.
  @override
  State<TrailPage> createState() => _TrailPageState();
}

/// Manages the trail page presentation and lifecycle.
class _TrailPageState extends State<TrailPage> {
  late List<Trail> _trails;
  String _query = '';
  String _filter = 'Nearby';
  bool _isLoadingTrails = false;
  StreamSubscription<List<Trail>>? _trailsSubscription;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _trails = List.of(widget.initialTrails ?? const []);
    unawaited(_loadLiveTrails());
    _trailsSubscription =
        _TrailPageDataActions.watchTrails(
          widget.hikerCircleRepository,
        )().listen((trails) {
          if (mounted) setState(() => _trails = trails);
        }, onError: (_) {});
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _trailsSubscription?.cancel();
    super.dispose();
  }

  /// Loads live trails.
  Future<void> _loadLiveTrails() async {
    setState(() {
      _isLoadingTrails = true;
    });
    try {
      final liveTrails = await _TrailPageDataActions.loadTrails(
        widget.hikerCircleRepository,
      )();
      if (!mounted) {
        return;
      }
      setState(() {
        _trails = liveTrails;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Unable to refresh trails right now.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTrails = false;
        });
      }
    }
  }

  /// Returns visible trails.
  List<Trail> get _visibleTrails {
    return _trails.where((trail) {
      final matchesQuery =
          _query.isEmpty ||
          trail.name.toLowerCase().contains(_query) ||
          trail.area.toLowerCase().contains(_query) ||
          trail.state.toLowerCase().contains(_query);
      final matchesFilter = switch (_filter) {
        'Beginner' =>
          trail.hasCommunityDifficulty &&
              _normalizeTrailDifficulty(trail.difficulty) == 'Easy',
        'Saved' => trail.isVerifiedTrail,
        'Popular' => trail.ratingAverage >= 4.5,
        _ => true,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  /// Adds trail.
  Future<void> _addTrail() async {
    if (!widget.session.isAdmin) {
      return;
    }

    final trail = await showAddTrailSheet(
      context,
      session: widget.session,
      repository: widget.hikerCircleRepository,
    );
    if (trail == null || !mounted) {
      return;
    }

    setState(() {
      _isLoadingTrails = true;
    });
    try {
      await _TrailPageDataActions.createTrailByAdmin(
        widget.hikerCircleRepository,
      )(session: widget.session, trail: trail);
      await _loadLiveTrails();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${trail.name} added to Firebase trails.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message),
            behavior: SnackBarBehavior.floating,
            backgroundColor: _TrailColors.redFor(context),
          ),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Unable to add this trail right now.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: _TrailColors.redFor(context),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTrails = false;
        });
      }
    }
  }

  /// Computes edit trail from card.
  Future<void> _editTrailFromCard(Trail trail) async {
    if (!widget.session.isAdmin) {
      return;
    }

    final updatedTrail = await showEditTrailSheet(context, trail);
    if (updatedTrail == null || !mounted) {
      return;
    }

    setState(() {
      _isLoadingTrails = true;
    });
    try {
      await _TrailPageDataActions.updateTrailByAdmin(
        widget.hikerCircleRepository,
      )(session: widget.session, trail: updatedTrail);
      await _loadLiveTrails();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Trail updated.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message),
            behavior: SnackBarBehavior.floating,
            backgroundColor: _TrailColors.redFor(context),
          ),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Unable to update this trail right now.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: _TrailColors.redFor(context),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTrails = false;
        });
      }
    }
  }

  /// Deletes trail.
  Future<void> _deleteTrail(Trail trail) async {
    if (!widget.session.isAdmin) {
      return;
    }

    final shouldDelete = await _presentDeleteTrailEffect1(trail);
    if (shouldDelete != true || !mounted) {
      return;
    }

    setState(() {
      _isLoadingTrails = true;
    });
    try {
      await _TrailPageDataActions.deleteTrailByAdmin(
        widget.hikerCircleRepository,
      )(session: widget.session, trail: trail);
      await _loadLiveTrails();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${trail.name} deleted.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message),
            behavior: SnackBarBehavior.floating,
            backgroundColor: _TrailColors.redFor(context),
          ),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Unable to delete this trail right now.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: _TrailColors.redFor(context),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTrails = false;
        });
      }
    }
  }

  /// Opens trail.
  void _openTrail(Trail trail) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TrailDetailPage(
          session: widget.session,
          hikerCircleRepository: widget.hikerCircleRepository,
          trail: trail,
          onStartHike: widget.onStartHike,
        ),
      ),
    );
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final visibleTrails = _visibleTrails;
    return TrailCardViewBuilder(
      builder: (context, cardView, onToggleView) => ColoredBox(
        color: _TrailColors.backgroundFor(context),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 112),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      isAdmin: widget.session.isAdmin,
                      onAddTrail: () => unawaited(_addTrail()),
                      view: cardView,
                      onToggleView: onToggleView,
                    ),
                    if (_isLoadingTrails) ...[
                      const SizedBox(height: 10),
                      const HikerCircleLoadingView(
                        message: 'Updating trail information…',
                        detail:
                            'Loading the latest routes and trail conditions.',
                        compact: true,
                        padding: EdgeInsets.symmetric(vertical: 4),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _DiscoverHero(trails: _trails),
                    const SizedBox(height: 14),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search trail, hill or area...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _query = value.trim().toLowerCase();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _FilterChips(
                      selectedFilter: _filter,
                      onSelected: (filter) {
                        setState(() {
                          _filter = filter;
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    _TrailInsightStrip(
                      visibleCount: visibleTrails.length,
                      verifiedCount: visibleTrails
                          .where((trail) => trail.isVerifiedTrail)
                          .length,
                      hazardCount: visibleTrails.fold<int>(
                        0,
                        (total, trail) => total + trail.hazards.length,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SectionLabel(label: 'Best Matches'),
                    const SizedBox(height: 8),
                    if (visibleTrails.isEmpty)
                      _EmptyState(
                        message: _trails.isEmpty
                            ? 'No Firebase trails are available yet. Add a real trail from the admin tools.'
                            : 'No trails match this filter.',
                      )
                    else
                      TrailCardCollection(
                        view: cardView,
                        itemCount: visibleTrails.length,
                        itemBuilder: (context, index) {
                          final trail = visibleTrails[index];
                          return _TrailCard(
                            key: ValueKey(trail.trailId),
                            trail: trail,
                            grid: cardView == TrailCardView.grid,
                            onOpenTrail: () => _openTrail(trail),
                            onEditTrail: widget.session.isAdmin
                                ? () => _editTrailFromCard(trail)
                                : null,
                            onDeleteTrail: widget.session.isAdmin
                                ? () => _deleteTrail(trail)
                                : null,
                          );
                        },
                      ),
                    const SizedBox(height: 10),
                    const SectionLabel(label: 'Offline Route Packs'),
                    const SizedBox(height: 8),
                    const _EmptyState(
                      message:
                          'Download the Malaysia offline map from App Settings before heading out.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Presents the delete trail effect1 UI.
  Future<bool?> _presentDeleteTrailEffect1(Trail trail) =>
      showCupertinoDialog<bool>(
        context: context,
        builder: (context) {
          return CupertinoAlertDialog(
            title: const Text('Delete trail?'),
            content: Text(
              '${trail.name} will be removed from Firebase trails.',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          );
        },
      );
}

/// Displays the trail detail page.
class TrailDetailPage extends StatefulWidget {
  /// Creates trail detail page.
  const TrailDetailPage({
    super.key,
    required this.session,
    required this.hikerCircleRepository,
    required this.trail,
    required this.onStartHike,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository hikerCircleRepository;
  final Trail trail;
  final Future<void> Function(Trail trail) onStartHike;

  /// Creates the presentation state for this widget.
  @override
  State<TrailDetailPage> createState() => _TrailDetailPageState();
}

/// Manages the trail detail page presentation and lifecycle.
class _TrailDetailPageState extends State<TrailDetailPage> {
  final _checkpointPlayback = ValueNotifier(const RouteCheckpointProgress());
  DateTime? _previewDepartureTime;
  late Trail _trail = widget.trail;
  final _scrollController = ScrollController();
  final _routePreviewKey = GlobalKey();
  int? _highlightedCheckpointIndex;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _trailSubscription;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _trailSubscription = widget.hikerCircleRepository.firestore
        .collection('trails')
        .doc(_trail.trailId)
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          final data = snapshot.data();
          if (data == null) return;
          final publishedCover = Trail.fromPersistence(data);
          final weatherData = data['weather'];
          final rawDifficultyCounts = data['difficultyVoteCounts'];
          final difficultyCounts = rawDifficultyCounts is Map
              ? Map<String, dynamic>.from(rawDifficultyCounts)
              : const <String, dynamic>{};

          /// Computes vote count.
          int voteCount(String key) {
            final value = difficultyCounts[key];
            return value is num ? math.max(0, value.toInt()) : 0;
          }

          final easyVotes = voteCount('easy');
          final moderateVotes = voteCount('moderate');
          final hardVotes = voteCount('hard');
          final hasDifficultyVotes = easyVotes + moderateVotes + hardVotes > 0;
          setState(() {
            _trail = _trail.copyWith(
              coverImageUrls: publishedCover.coverImageUrls,
              coverImageCredits: publishedCover.coverImageCredits,
              coverColorValue: publishedCover.coverColorValue,
              weather: weatherData == null
                  ? _trail.weather
                  : _TrailPageDataActions.weatherFromFirestore(
                      widget.hikerCircleRepository,
                    )(weatherData),
              difficulty: hasDifficultyVotes
                  ? _normalizeTrailDifficulty('${data['difficulty'] ?? ''}')
                  : '',
              ratingAverage: data['ratingAverage'] is num
                  ? (data['ratingAverage'] as num).toDouble()
                  : _trail.ratingAverage,
              ratingCount: data['ratingCount'] is num
                  ? math.max(0, (data['ratingCount'] as num).toInt())
                  : _trail.ratingCount,
              ratingVoteCounts: publishedCover.ratingVoteCounts,
              easyDifficultyVotes: easyVotes,
              moderateDifficultyVotes: moderateVotes,
              hardDifficultyVotes: hardVotes,
            );
          });
        }, onError: (_) {});
    final weather = _trail.weather;
    if (weather.forecastData.isEmpty ||
        weather.isStale ||
        weather.summary.isEmpty ||
        weather.summary == 'Weather unavailable' ||
        weather.temperatureRange == 'Not provided') {
      unawaited(_refreshWeather());
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _trailSubscription?.cancel();
    _checkpointPlayback.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Refreshes weather.
  Future<void> _refreshWeather() async {
    try {
      final updated = await _TrailPageDataActions.refreshTrailWeatherViaCloud(
        widget.hikerCircleRepository,
      )(_trail);
      if (!mounted) return;
      setState(() {
        _trail = updated;
      });
    } catch (_) {
      // Existing weather remains visible when refresh is unavailable.
    }
  }

  /// Shows checkpoint on map.
  void _showCheckpointOnMap(int index) {
    setState(() {
      _highlightedCheckpointIndex = index;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _routePreviewKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.3,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  /// Starts trail hike.
  void _startTrailHike(Trail trail) {
    if (trail.checkpoints.length < 2) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'This trail has no usable route checkpoints. Choose another trail or ask an admin to repair it.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    unawaited(widget.onStartHike(trail));
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final trail = _trail;

    return Scaffold(
      backgroundColor: _TrailColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(
                    onBack: () => Navigator.of(context).pop(),
                    subtitle: trail.name,
                  ),
                  const SizedBox(height: 16),
                  _TrailDetailHero(trail: trail),
                  const SizedBox(height: 14),
                  _MetricGroup(trail: trail),
                  const SizedBox(height: 14),
                  _TrailPlanCard(
                    trail: trail,
                    onStartHike: () => _startTrailHike(trail),
                  ),
                  const SizedBox(height: 22),
                  const SectionLabel(label: 'Route Preview'),
                  const SizedBox(height: 8),
                  if (trail.checkpoints.isEmpty)
                    const _EmptyState(
                      message:
                          'Route preview is unavailable because this trail has no checkpoints.',
                    )
                  else
                    _RoutePreview(
                      key: _routePreviewKey,
                      trail: trail,
                      departureTime: _previewDepartureTime,
                      onAnimationProgress: (value) =>
                          _checkpointPlayback.value = value,
                      highlightedCheckpointIndex: _highlightedCheckpointIndex,
                      onHighlightCleared: () {
                        if (_highlightedCheckpointIndex != null) {
                          setState(() => _highlightedCheckpointIndex = null);
                        }
                      },
                      localDatabase: widget.hikerCircleRepository.localDatabase,
                    ),
                  const SizedBox(height: 22),
                  SectionLabel(label: 'Checkpoint Flow'),
                  const SizedBox(height: 8),
                  if (trail.checkpoints.isEmpty)
                    const _EmptyState(message: 'No checkpoints available.')
                  else
                    CheckpointFlow(
                      checkpoints: trail.checkpoints,
                      playback: _checkpointPlayback,
                      highlightedIndex: _highlightedCheckpointIndex,
                      onShowOnMap: _showCheckpointOnMap,
                    ),
                  const SizedBox(height: 22),
                  if (trail.hasCommunityDifficulty ||
                      trail.ratingCount > 0) ...[
                    const SectionLabel(label: 'Hiker Feedbacks'),
                    const SizedBox(height: 8),
                    HikerFeedbackCarousel(trail: trail),
                    const SizedBox(height: 22),
                  ],
                  const SectionLabel(label: 'Conditions and Safety'),
                  const SizedBox(height: 8),
                  if (trail.weather.forecastData.isEmpty) ...[
                    _WeatherCard(trail: trail),
                    const SizedBox(height: 12),
                  ],
                  TrailWeatherPanel(
                    trail: trail,
                    loadLocationWeather: widget
                        .hikerCircleRepository
                        .watchTrailCheckpointWeather,
                    weather: trail.weather,
                    elevationGainMeters: trail.elevationGainMeters,
                    durationMinutes: trail.estimatedDurationMinutes,
                    onDepartureChanged: (time) =>
                        setState(() => _previewDepartureTime = time),
                  ),
                  const SizedBox(height: 24),
                  TrailCautionsHistory(trailId: trail.trailId),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Defines the add trail step choices.
enum _AddTrailStep { pickCheckpoints, loading, form }

/// Displays the add trail sheet.
class _AddTrailSheet extends StatefulWidget {
  /// Creates add trail sheet.
  const _AddTrailSheet({required this.session, required this.repository});

  final AppSession session;
  final HikerCircleFirebaseRepository repository;

  /// Creates the presentation state for this widget.
  @override
  State<_AddTrailSheet> createState() => _AddTrailSheetState();
}

/// Manages the add trail sheet presentation and lifecycle.
class _AddTrailSheetState extends State<_AddTrailSheet> {
  late final _AddTrailSheetStateViewModel _screenModel;

  /// Returns pending images.
  List<_PendingTrailImage> get _pendingImages =>
      _screenModel.statePendingImages;

  /// Returns area.
  String get _area => _screenModel.stateArea;

  /// Updates area.
  set _area(String value) => _screenModel.stateArea = value;

  /// Returns location state.
  String get _locationState => _screenModel.stateLocationState;

  /// Updates location state.
  set _locationState(String value) => _screenModel.stateLocationState = value;

  /// Returns country.
  String get _country => _screenModel.stateCountry;

  /// Updates country.
  set _country(String value) => _screenModel.stateCountry = value;

  /// Returns checkpoints.
  List<_CheckpointDraft> get _checkpoints => _screenModel.stateCheckpoints;

  /// Returns error message.
  String? get _errorMessage => _screenModel.stateErrorMessage;

  /// Updates error message.
  set _errorMessage(String? value) => _screenModel.stateErrorMessage = value;

  /// Returns has fetched route.
  bool get _hasFetchedRoute => _screenModel.stateHasFetchedRoute;

  /// Updates has fetched route.
  set _hasFetchedRoute(bool value) => _screenModel.stateHasFetchedRoute = value;

  /// Returns route result checkpoints hash.
  String? get _routeResultCheckpointsHash =>
      _screenModel.stateRouteResultCheckpointsHash;

  /// Updates route result checkpoints hash.
  set _routeResultCheckpointsHash(String? value) =>
      _screenModel.stateRouteResultCheckpointsHash = value;

  /// Returns location failed.
  bool get _locationFailed => _screenModel.stateLocationFailed;

  /// Updates location failed.
  set _locationFailed(bool value) => _screenModel.stateLocationFailed = value;

  /// Returns is resolving location.
  bool get _isResolvingLocation => _screenModel.stateIsResolvingLocation;

  /// Updates is resolving location.
  set _isResolvingLocation(bool value) =>
      _screenModel.stateIsResolvingLocation = value;

  /// Returns location generation.
  int get _locationGeneration => _screenModel.stateLocationGeneration;

  /// Updates location generation.
  set _locationGeneration(int value) =>
      _screenModel.stateLocationGeneration = value;

  /// Updates location lookup key.
  set _locationLookupKey(String? value) =>
      _screenModel.stateLocationLookupKey = value;

  /// Returns is uploading images.
  bool get _isUploadingImages => _screenModel.stateIsUploadingImages;

  /// Updates is uploading images.
  set _isUploadingImages(bool value) =>
      _screenModel.stateIsUploadingImages = value;

  /// Returns is saving trail.
  bool get _isSavingTrail => _screenModel.stateIsSavingTrail;

  /// Returns is checking duplicate.
  bool get _isCheckingDuplicate => _screenModel.stateIsCheckingDuplicate;

  /// Updates is checking duplicate.
  set _isCheckingDuplicate(bool value) =>
      _screenModel.stateIsCheckingDuplicate = value;

  /// Returns route result.
  HikingRouteResult? get _routeResult => _screenModel.stateRouteResult;

  /// Updates route result.
  set _routeResult(HikingRouteResult? value) =>
      _screenModel.stateRouteResult = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  static const String _defaultRouteFilePath =
      'offline/maps/admin_added_trail.mbtiles';
  static const int _maxImageBytes = 10 * 1024 * 1024;
  static const int _maxImages = 10;

  var _step = _AddTrailStep.pickCheckpoints;
  final _trailPins = <mapbox.Point>[];
  final _imagePicker = ImagePicker();

  final _nameController = TextEditingController();

  final _distanceController = TextEditingController();
  final _durationController = TextEditingController(text: '120');
  final _elevationController = TextEditingController();

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _AddTrailSheetStateViewModel(
      effectValidateAndSaveTrail: _validateAndSaveTrail,
    )..addListener(_renderScreenModel);
    _screenModel.readSession = () => widget.session;
    _screenModel.readRepository = () => widget.repository;
    _screenModel.effectPresentDoSaveTrailEffect1 = _presentDoSaveTrailEffect1;

    unawaited(_recoverLostImages());
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _nameController.dispose();
    _distanceController.dispose();
    _durationController.dispose();
    _elevationController.dispose();
    for (final checkpoint in _checkpoints) {
      checkpoint.dispose();
    }

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Returns camera supported.
  bool get _cameraSupported => _screenModel.commandCameraSupported;

  /// Computes recover lost images.
  Future<void> _recoverLostImages() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      final response = await _imagePicker.retrieveLostData();
      final files = response.files;
      if (files != null && files.isNotEmpty) {
        await _addPickedImages(files);
      } else if (response.exception != null && mounted) {
        setState(() {
          _errorMessage =
              'Could not restore the selected image: ${response.exception}';
        });
      }
    } catch (_) {
      // Lost-image recovery is best effort.
    }
  }

  /// Computes take photo.
  Future<void> _takePhoto() async {
    if (!_cameraSupported || _isUploadingImages) {
      return;
    }
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2048,
        maxHeight: 2048,
        requestFullMetadata: false,
      );
      if (image != null) {
        await _addPickedImages([image]);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Unable to open the camera: $error';
        });
      }
    }
  }

  /// Computes pick from gallery.
  Future<void> _pickFromGallery() async {
    if (_isUploadingImages) {
      return;
    }
    try {
      final images = await _imagePicker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 2048,
        maxHeight: 2048,
        requestFullMetadata: false,
      );
      if (images.isNotEmpty) {
        await _addPickedImages(images);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Unable to open the image gallery: $error';
        });
      }
    }
  }

  /// Adds picked images.
  Future<void> _addPickedImages(List<XFile> files) async {
    final availableSlots = _maxImages - _pendingImages.length;
    if (availableSlots <= 0) {
      if (mounted) {
        setState(() {
          _errorMessage = 'A trail can have up to $_maxImages images.';
        });
      }
      return;
    }

    final accepted = <_PendingTrailImage>[];
    final rejected = <String>[];
    for (final file in files.take(availableSlots)) {
      try {
        final length = await file.length();
        if (length > _maxImageBytes) {
          rejected.add('${file.name} is larger than 10 MB');
          continue;
        }
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          rejected.add('${file.name} is empty');
          continue;
        }
        if (bytes.length > _maxImageBytes) {
          rejected.add('${file.name} is larger than 10 MB');
          continue;
        }
        accepted.add(
          _PendingTrailImage(
            bytes: bytes,
            fileName: file.name,
            contentType: file.mimeType,
          ),
        );
      } catch (_) {
        rejected.add('${file.name} could not be read');
      }
    }
    if (files.length > availableSlots) {
      rejected.add(
        '${files.length - availableSlots} image(s) exceeded the $_maxImages-image limit',
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingImages.addAll(accepted);
      _errorMessage = rejected.isEmpty ? null : rejected.join('. ');
    });
  }

  /// Delegates remove pending image to the ViewModel.
  void _removePendingImage(int index) =>
      _screenModel.commandRemovePendingImage(index);

  /// Computes on pins confirmed.
  void _onPinsConfirmed(List<mapbox.Point> pins) {
    final validPins = pins
        .where((point) => mapPointCoordinatesOrNull(point) != null)
        .toList(growable: false);
    if (validPins.isEmpty) return;
    _trailPins
      ..clear()
      ..addAll(validPins);

    final coordinates = mapPointCoordinatesOrNull(validPins.first);
    if (coordinates == null) return;
    final lat = coordinates.latitude;
    final lng = coordinates.longitude;

    _checkpoints.clear();
    final draft = _CheckpointDraft(order: 1, name: 'Trailhead');
    draft.latitudeController.text = lat.toStringAsFixed(6);
    draft.longitudeController.text = lng.toStringAsFixed(6);
    _checkpoints.add(draft);

    unawaited(_resolveLocation(lat, lng));
    setState(() {
      _step = _AddTrailStep.form;
      _errorMessage = null;
    });
  }

  /// Adds checkpoints on map.
  Future<void> _addCheckpointsOnMap() async {
    final previousCheckpoints = _checkpointModels();
    final existingPins = previousCheckpoints
        .map(
          (c) => mapbox.Point(
            coordinates: mapbox.Position(c.longitude, c.latitude),
          ),
        )
        .toList();
    final confirmed = await _presentAddCheckpointsOnMapEffect1(existingPins);
    if (confirmed == null || !mounted) return;
    final validConfirmed = confirmed
        .map(mapPointCoordinatesOrNull)
        .whereType<({double longitude, double latitude})>()
        .toList(growable: false);
    if (validConfirmed.isEmpty) return;
    for (final checkpoint in _checkpoints) {
      checkpoint.dispose();
    }
    _checkpoints.clear();
    for (var i = 0; i < validConfirmed.length; i++) {
      final matching = previousCheckpoints.where(
        (point) =>
            (point.latitude - validConfirmed[i].latitude).abs() < 0.000001 &&
            (point.longitude - validConfirmed[i].longitude).abs() < 0.000001,
      );
      final name = matching.isNotEmpty
          ? matching.first.name
          : i == 0
          ? 'Trailhead'
          : i == validConfirmed.length - 1
          ? 'End point'
          : 'Waypoint $i';
      final draft = _CheckpointDraft(order: i + 1, name: name);
      draft.latitudeController.text = validConfirmed[i].latitude
          .toStringAsFixed(6);
      draft.longitudeController.text = validConfirmed[i].longitude
          .toStringAsFixed(6);
      _checkpoints.add(draft);
    }
    _checkpointsChanged();
  }

  /// Delegates checkpoints changed to the ViewModel.
  void _checkpointsChanged() => _screenModel.commandCheckpointsChanged();

  /// Removes checkpoint.
  void _removeCheckpoint(int index) {
    if (_checkpoints.length <= 3) return;
    setState(() {
      _checkpoints.removeAt(index).dispose();
    });
    _checkpointsChanged();
  }

  /// Delegates draft trail to the ViewModel.
  Trail _draftTrail(List<TrailCheckpoint> checkpoints) =>
      _screenModel.commandDraftTrail(checkpoints);

  /// Delegates fetch route to the ViewModel.
  Future<HikingRouteResult?> _fetchRoute(List<TrailCheckpoint> checkpoints) =>
      _screenModel.commandFetchRoute(checkpoints);

  /// Applies route data.
  void _applyRouteData(
    HikingRouteResult route,
    List<TrailCheckpoint>? checkpoints,
  ) {
    _distanceController.text = (route.distanceMeters / 1000).toStringAsFixed(1);
    _durationController.text = route.duration.inMinutes.toString();
    if (route.elevationGainMeters != null) {
      _elevationController.text = route.elevationGainMeters!.round().toString();
    }
    _hasFetchedRoute = true;
    _routeResultCheckpointsHash = HikingRouteService.checkpointsHash(
      checkpoints ?? _checkpointModels(),
    );
  }

  /// Resolve the selected coordinate's region instead of inferring identity from map camera presets.
  Future<void> _resolveLocation(double latitude, double longitude) =>
      _screenModel.commandResolveLocation(latitude, longitude);

  /// Delegates save trail to the ViewModel.
  Future<void> _saveTrail() => _screenModel.commandSaveTrail();

  /// Validates and save trail.
  Future<void> _validateAndSaveTrail() async {
    final name = _nameController.text.trim();
    final area = _area.trim();
    final state = _locationState.trim();
    final country = _country.trim();
    final checkpoints = _checkpointModels();
    final latitude = checkpoints.isEmpty ? null : checkpoints.first.latitude;
    final longitude = checkpoints.isEmpty ? null : checkpoints.first.longitude;

    if (area.isEmpty || state.isEmpty || country.isEmpty) {
      setState(
        () => _errorMessage =
            'Find the location before adding this trail. Retry or choose another starting point.',
      );
      return;
    }
    if (name.isEmpty ||
        latitude == null ||
        longitude == null ||
        checkpoints.length < 3 ||
        checkpoints.length > 12) {
      setState(() {
        _errorMessage =
            'Fill in trail identity and add between 3 and 12 checkpoints.';
      });
      return;
    }
    if (!_hasFetchedRoute ||
        _routeResultCheckpointsHash !=
            HikingRouteService.checkpointsHash(checkpoints)) {
      _routeResult = null;
      _hasFetchedRoute = false;
      setState(() {
        _step = _AddTrailStep.loading;
        _errorMessage = null;
      });
      try {
        final route = await _fetchRoute(checkpoints);
        if (!mounted) return;
        if (route != null) {
          _routeResult = route;
          _applyRouteData(route, checkpoints);
        }
      } catch (_) {
        if (!mounted) return;
      }
    }

    final distance = double.tryParse(_distanceController.text.trim());
    final duration = int.tryParse(_durationController.text.trim());
    final elevation = int.tryParse(_elevationController.text.trim()) ?? 0;

    if (_routeResult?.hasElevationRange != true) {
      if (mounted) {
        setState(() {
          _step = _AddTrailStep.form;
          _errorMessage =
              'Could not calculate the trail elevation range. Check your connection and try again.';
        });
      }
      return;
    }

    if (distance == null ||
        distance <= 0 ||
        duration == null ||
        duration <= 0) {
      if (mounted) {
        setState(() {
          _step = _AddTrailStep.form;
          _errorMessage =
              'Could not compute a route. Ensure your checkpoints are valid and try again.';
        });
      }
      return;
    }

    setState(() {
      _isCheckingDuplicate = true;
      _step = _AddTrailStep.loading;
      _errorMessage = null;
    });
    try {
      final match = await TrailDuplicateChecker(
        widget.repository.localDatabase,
      ).checkPolyline(_routeResult!.encodedPolyline);
      if (!mounted) return;
      if (match != null) {
        await showTrailDuplicateDialog(context, match: match);
        if (mounted) _restartTrailRoute();
        return;
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _step = _AddTrailStep.form;
          _errorMessage =
              'Saved trails could not be checked. Try again before adding this trail.';
        });
      }
      return;
    } finally {
      if (mounted) setState(() => _isCheckingDuplicate = false);
    }

    setState(() => _step = _AddTrailStep.form);
    await _doSaveTrail(
      name: name,
      area: area,
      state: state,
      country: country,
      latitude: latitude,
      longitude: longitude,
      distance: distance,
      duration: duration,
      elevation: elevation,
      minElevation: _routeResult?.minElevationMeters?.round(),
      maxElevation: _routeResult?.maxElevationMeters?.round(),
      checkpoints: checkpoints,
    );
  }

  /// Computes restart trail route.
  void _restartTrailRoute() {
    for (final checkpoint in _checkpoints) {
      checkpoint.dispose();
    }
    setState(() {
      _trailPins.clear();
      _checkpoints.clear();
      _routeResult = null;
      _routeResultCheckpointsHash = null;
      _hasFetchedRoute = false;
      _locationGeneration++;
      _locationLookupKey = null;
      _area = _locationState = _country = '';
      _isResolvingLocation = _locationFailed = false;
      _distanceController.clear();
      _durationController.text = '120';
      _elevationController.clear();
      _errorMessage = null;
      _step = _AddTrailStep.pickCheckpoints;
    });
  }

  /// Delegates do save trail to the ViewModel.
  Future<void> _doSaveTrail({
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
  }) => _screenModel.commandDoSaveTrail(
    name: name,
    area: area,
    state: state,
    country: country,
    latitude: latitude,
    longitude: longitude,
    distance: distance,
    duration: duration,
    elevation: elevation,
    minElevation: minElevation,
    maxElevation: maxElevation,
    checkpoints: checkpoints,
  );

  /// Delegates checkpoint models to the ViewModel.
  List<TrailCheckpoint> _checkpointModels() =>
      _screenModel.commandCheckpointModels();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _TrailColors.backgroundFor(context),
      body: Stack(
        children: [
          switch (_step) {
            _AddTrailStep.pickCheckpoints => _buildCheckpointPicker(),
            _AddTrailStep.loading => _buildLoading(),
            _AddTrailStep.form => _buildForm(),
          },
          if (_isUploadingImages)
            HikerCircleLoadingToastOverlay(
              message: 'Saving trail…',
              detail: 'Uploading images and updating trail data.',
              timeout: const Duration(seconds: 30),
              onTimeout: () {
                if (mounted) {
                  setState(() {
                    _isUploadingImages = false;
                  });
                }
              },
            ),
        ],
      ),
    );
  }

  /// Builds checkpoint picker.
  Widget _buildCheckpointPicker() {
    return _MapBasedCheckpointPicker(
      localDatabase: widget.repository.localDatabase,
      showStateFocus: true,
      onClose: () => Navigator.of(context).pop(),
      singlePinMode: true,
      pins: _trailPins,
      onPinsChanged: (pins) => _trailPins
        ..clear()
        ..addAll(pins),
      onConfirm: _onPinsConfirmed,
    );
  }

  /// Builds loading.
  Widget _buildLoading() {
    return SafeArea(
      child: HikerCircleLoadingView(
        message: _isCheckingDuplicate
            ? 'Checking existing trails…'
            : 'Building your trail route…',
        detail: _isCheckingDuplicate
            ? 'Comparing the full route with saved trails.'
            : 'Finding a reliable path through every checkpoint.',
      ),
    );
  }

  /// Computes route metric row.
  Widget _routeMetricRow(BuildContext context, String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: _TrailColors.secondaryTextFor(context),
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: _TrailColors.textFor(context),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  /// Builds form.
  Widget _buildForm() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          18,
          6,
          18,
          18 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Trail',
                        style: PageHeaderStyle.title(
                          context,
                          _TrailColors.textFor(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Plan the route, add details, and preview your trail.',
                        style: PageHeaderStyle.subtitle(
                          context,
                          _TrailColors.secondaryTextFor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                PageHeaderAction(
                  icon: Icons.close_rounded,
                  tooltip: 'Close',
                  color: _TrailColors.textFor(context),
                  surface: _TrailColors.surfaceFor(context),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const SectionLabel(label: 'Trail details'),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              _TrailFormError(message: _errorMessage!),
            ],
            const SizedBox(height: 14),
            _InsetGroup(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Trail name',
                        prefixIcon: Icon(Icons.terrain_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const _HorizontalSeparator(),
                    const SizedBox(height: 16),
                    TrailLocationSummary(
                      area: _area,
                      state: _locationState,
                      country: _country,
                      isLoading: _isResolvingLocation,
                      hasError: _locationFailed,
                      onRetry: () {
                        final points = _checkpointModels();
                        if (points.isNotEmpty) {
                          unawaited(
                            _resolveLocation(
                              points.first.latitude,
                              points.first.longitude,
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            TrailImagesCard(
              images: [
                for (final image in _pendingImages)
                  TrailImagePreview(bytes: image.bytes, name: image.fileName),
              ],
              onGallery: () => unawaited(_pickFromGallery()),
              onCamera: () => unawaited(_takePhoto()),
              onRemove: _removePendingImage,
              cameraSupported: _cameraSupported,
              isBusy: _isUploadingImages,
              maxImages: _maxImages,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _addCheckpointsOnMap,
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text('Add checkpoints on map'),
            ),
            const SizedBox(height: 14),
            const SectionLabel(label: 'Checkpoints'),
            const SizedBox(height: 8),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _checkpoints.length,
              onReorderItem: (int oldIndex, int newIndex) {
                setState(() {
                  final draft = _checkpoints.removeAt(oldIndex);
                  _checkpoints.insert(newIndex, draft);
                });
                _checkpointsChanged();
              },
              itemBuilder: (context, index) {
                final draft = _checkpoints[index];
                return Padding(
                  key: ValueKey(draft.id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CheckpointDraftFields(
                    draft: draft,
                    index: index,
                    canRemove: _checkpoints.length > 3,
                    onRemove: () => _removeCheckpoint(index),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            const SectionLabel(label: 'Route preview'),
            const SizedBox(height: 8),
            if (_checkpointModels().length >= 3)
              _RoutePreview(
                trail: _draftTrail(_checkpointModels()),
                onRouteLoaded: (route) {
                  if (!mounted) return;
                  setState(() {
                    _routeResult = route;
                    _applyRouteData(route, _checkpointModels());
                  });
                },
              )
            else
              const _InsetGroup(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Add at least 3 checkpoints to preview your trail route.',
                  ),
                ),
              ),
            if (_hasFetchedRoute) ...[
              const SizedBox(height: 10),
              _InsetGroup(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: _TrailColors.green,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Route found',
                            style: TextStyle(
                              color: _TrailColors.green,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (_routeResult != null) ...[
                        _routeMetricRow(
                          context,
                          'Provider',
                          _routeResult!.sourceLabel,
                        ),
                        const SizedBox(height: 4),
                      ],
                      _routeMetricRow(
                        context,
                        'Distance',
                        '${(double.tryParse(_distanceController.text.trim()) ?? 0).toStringAsFixed(1)} km',
                      ),
                      const SizedBox(height: 4),
                      _routeMetricRow(
                        context,
                        'Duration',
                        '${_durationController.text.trim()} min',
                      ),
                      if (_routeResult != null) ...[
                        const SizedBox(height: 4),
                        _routeMetricRow(
                          context,
                          'Elevation range',
                          _routeResult!.elevationRangeLabel,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed:
                  _isSavingTrail || _isUploadingImages || _isResolvingLocation
                  ? null
                  : _saveTrail,
              icon: const Icon(Icons.cloud_upload_rounded),
              label: Text(
                _isUploadingImages ? 'Uploading trail images…' : 'Finish & Add',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Presents the add checkpoints on map effect1 UI.
  Future<List<mapbox.Point>?> _presentAddCheckpointsOnMapEffect1(
    List<mapbox.Point> existingPins,
  ) => Navigator.of(context).push<List<mapbox.Point>>(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: _TrailColors.backgroundFor(context),
        appBar: PageHeaderAppBar(
          title: const Text('Select checkpoints'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: _MapBasedCheckpointPicker(
          singlePinMode: false,
          pins: existingPins,
          onPinsChanged: (_) {},
          onConfirm: (pins) => Navigator.of(context).pop(pins),
        ),
      ),
    ),
  );

  /// Presents the do save trail effect1 UI.
  void _presentDoSaveTrailEffect1(
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
  ) => Navigator.of(context).pop(
    Trail(
      trailId: trailId,
      name: name,
      area: area,
      state: state,
      country: country,
      latitude: latitude,
      longitude: longitude,
      distanceKm: distance,
      difficulty: '',
      estimatedDurationMinutes: duration,
      elevationGainMeters: elevation,
      minElevationMeters: minElevation,
      maxElevationMeters: maxElevation,
      ratingAverage: 0,
      offlineMapAvailable: false,
      offlineMapDownloaded: false,
      isVerifiedTrail: true,
      routeFilePath: _defaultRouteFilePath,
      coverColorValue: 0xFF34A853,
      coverImageUrls: imageUrls,
      checkpoints: checkpoints,
      weather: TrailWeather(
        summary: 'Weather unavailable',
        temperatureRange: 'Not provided',
        rainProbability: 0,
        cachedAt: DateTime.now().toUtc(),
      ),
      hazards: const [],
      routeEncodedPolyline: polyline,
      routeCheckpointsHash: hash,
    ),
  );
}

/// Displays the map based checkpoint picker.
class _MapBasedCheckpointPicker extends StatefulWidget {
  /// Creates map based checkpoint picker.
  const _MapBasedCheckpointPicker({
    required this.pins,
    required this.onPinsChanged,
    required this.onConfirm,
    this.singlePinMode = false,
    this.showStateFocus = false,
    this.onClose,
    this.editableIndex,
    this.routeCoordinates,
    this.localDatabase,
  });

  final List<mapbox.Point> pins;
  final ValueChanged<List<mapbox.Point>> onPinsChanged;
  final ValueChanged<List<mapbox.Point>> onConfirm;
  final bool singlePinMode;
  final bool showStateFocus;
  final VoidCallback? onClose;
  final int? editableIndex;
  final List<mapbox.Position>? routeCoordinates;
  final LocalSessionDatabase? localDatabase;

  /// Creates the presentation state for this widget.
  @override
  State<_MapBasedCheckpointPicker> createState() =>
      _MapBasedCheckpointPickerState();
}

/// Manages the map based checkpoint picker presentation and lifecycle.
class _MapBasedCheckpointPickerState extends State<_MapBasedCheckpointPicker> {
  late final _MapBasedCheckpointPickerStateViewModel _screenModel;

  /// Returns mapbox map.
  mapbox.MapboxMap? get _mapboxMap => _screenModel.stateMapboxMap;

  /// Updates mapbox map.
  set _mapboxMap(mapbox.MapboxMap? value) =>
      _screenModel.stateMapboxMap = value;

  /// Returns circle manager.
  mapbox.CircleAnnotationManager? get _circleManager =>
      _screenModel.stateCircleManager;

  /// Updates circle manager.
  set _circleManager(mapbox.CircleAnnotationManager? value) =>
      _screenModel.stateCircleManager = value;

  /// Returns point manager.
  mapbox.PointAnnotationManager? get _pointManager =>
      _screenModel.statePointManager;

  /// Updates point manager.
  set _pointManager(mapbox.PointAnnotationManager? value) =>
      _screenModel.statePointManager = value;

  /// Returns polyline manager.
  mapbox.PolylineAnnotationManager? get _polylineManager =>
      _screenModel.statePolylineManager;

  /// Updates polyline manager.
  set _polylineManager(mapbox.PolylineAnnotationManager? value) =>
      _screenModel.statePolylineManager = value;

  /// Updates style loaded.
  set _styleLoaded(bool value) => _screenModel.stateStyleLoaded = value;

  /// Updates style setup.
  set _styleSetup(Future<void>? value) => _screenModel.stateStyleSetup = value;

  /// Returns pin revision.
  int get _pinRevision => _screenModel.statePinRevision;

  /// Updates pin revision.
  set _pinRevision(int value) => _screenModel.statePinRevision = value;

  /// Returns focus region.
  MalaysiaMapRegion get _focusRegion => _screenModel.stateFocusRegion;

  /// Updates focus region.
  set _focusRegion(MalaysiaMapRegion value) =>
      _screenModel.stateFocusRegion = value;

  /// Returns focus revision.
  int get _focusRevision => _screenModel.stateFocusRevision;

  /// Updates focus revision.
  set _focusRevision(int value) => _screenModel.stateFocusRevision = value;

  /// Returns pins.
  List<mapbox.Point> get _pins => _screenModel.statePins;

  /// Updates pins.
  set _pins(List<mapbox.Point> value) => _screenModel.statePins = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late final _mapView = MapViewController(
    settings: MapViewSettings(
      dimension: widget.showStateFocus
          ? MapDimension.twoD
          : MapDimension.threeD,
    ),
    onBeforeStyleReload: () async {
      final managers = <mapbox.BaseAnnotationManager?>[
        _circleManager,
        _pointManager,
        _polylineManager,
      ];
      _styleLoaded = false;
      _styleSetup = null;
      _existingTrailPaths.reset();
      _pinRevision++;
      _circleManager = null;
      _pointManager = null;
      _polylineManager = null;
      await removeMapAnnotationManagers(_mapboxMap, managers);
    },
  );

  // Camera-only state. Confirm returns pins; this selection never leaves the picker.

  final _stateBoundary = StateBoundaryOverlay();
  final _existingTrailPaths = ExistingTrailPathOverlay();
  bool _pathsLoading = false, _pathsFailed = false;
  int _pathCount = 0, _unavailablePaths = 0, _pathLoadRevision = 0;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _MapBasedCheckpointPickerStateViewModel(
      readEditableIndex: () => widget.editableIndex,
      readRouteCoordinates: () => widget.routeCoordinates,
      readShowStateFocus: () => widget.showStateFocus,
      readSinglePinMode: () => widget.singlePinMode,
      effectPrepareStyle: _prepareStyle,
    )..addListener(_renderScreenModel);
    _screenModel.effectPresentUpdateStateBoundaryEffect1 =
        _presentUpdateStateBoundaryEffect1;

    _pins = _validPoints(widget.pins);
    if (widget.localDatabase != null) unawaited(_loadExistingTrailPaths());
    if (widget.showStateFocus) {
      unawaited(
        StateBoundaryOverlay.prewarm()
            .then<void>((_) {})
            .catchError((Object _) {}),
      );
    }
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(_MapBasedCheckpointPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextPins = _validPoints(widget.pins);
    if (!listEquals(nextPins, _validPoints(oldWidget.pins))) {
      _pins = nextPins;
      unawaited(_syncPins());
    }
    if (oldWidget.localDatabase != widget.localDatabase) {
      unawaited(_loadExistingTrailPaths());
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _mapView.dispose();
    _focusRevision++;
    _pinRevision++;
    _stateBoundary.dispose();
    _pathLoadRevision++;
    _existingTrailPaths.reset();
    _mapboxMap = null;
    _circleManager = null;
    _pointManager = null;
    _polylineManager = null;

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Computes valid points.
  static List<mapbox.Point> _validPoints(Iterable<mapbox.Point> points) {
    return points
        .where((point) => mapPointCoordinatesOrNull(point) != null)
        .toList();
  }

  /// Loads existing trail paths.
  Future<void> _loadExistingTrailPaths() async {
    final database = widget.localDatabase;
    if (database == null) return;
    final revision = ++_pathLoadRevision;
    setState(() {
      _pathsLoading = true;
      _pathsFailed = false;
    });
    try {
      final catalog = await LocalTrailPaths(database).load();
      if (!mounted || revision != _pathLoadRevision) return;
      await _existingTrailPaths.setPaths(catalog.paths);
      if (!mounted || revision != _pathLoadRevision) return;
      setState(() {
        _pathCount = catalog.paths.length;
        _unavailablePaths = catalog.unavailable;
        _pathsLoading = false;
      });
    } catch (_) {
      if (!mounted || revision != _pathLoadRevision) return;
      setState(() {
        _pathsLoading = false;
        _pathsFailed = true;
      });
    }
  }

  /// Restores existing trail paths.
  Future<void> _restoreExistingTrailPaths(mapbox.MapboxMap map) async {
    try {
      await _existingTrailPaths.onStyleLoaded(map);
    } catch (_) {
      if (mounted && identical(map, _mapboxMap)) {
        setState(() => _pathsFailed = true);
      }
    }
  }

  /// Computes list equals.
  static bool listEquals(List<mapbox.Point>? a, List<mapbox.Point>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final first = mapPointCoordinatesOrNull(a[i]);
      final second = mapPointCoordinatesOrNull(b[i]);
      if (first == null ||
          second == null ||
          first.latitude != second.latitude ||
          first.longitude != second.longitude) {
        return false;
      }
    }
    return true;
  }

  /// Delegates initial center to the ViewModel.
  mapbox.Point _initialCenter() => _screenModel.commandInitialCenter();

  /// Delegates focus on region to the ViewModel.
  Future<void> _focusOnRegion({int duration = 450}) =>
      _screenModel.commandFocusOnRegion(duration: duration);

  /// Selects focus region.
  void _selectFocusRegion(MalaysiaMapRegion? region) {
    if (region == null) return;
    setState(() => _focusRegion = region);
    unawaited(_updateStateBoundary(_stateBoundary.select(region)));
    unawaited(_focusOnRegion());
  }

  /// Delegates update state boundary to the ViewModel.
  Future<void> _updateStateBoundary(Future<void> update) =>
      _screenModel.commandUpdateStateBoundary(update);

  /// Computes on map created.
  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    if (!mounted) return;
    _mapboxMap = mapboxMap;
    _mapView.attach(mapboxMap);
    try {
      await mapboxMap.compass.updateSettings(
        mapbox.CompassSettings(enabled: false),
      );
      await mapboxMap.logo.updateSettings(mapbox.LogoSettings(enabled: false));
      await mapboxMap.gestures.updateSettings(
        mapbox.GesturesSettings(
          scrollEnabled: true,
          pinchToZoomEnabled: true,
          rotateEnabled: true,
          pitchEnabled: true,
        ),
      );
      await mapboxMap.setBounds(
        mapbox.CameraBoundsOptions(minZoom: 3, maxZoom: 21),
      );
      if (widget.showStateFocus && _pins.isEmpty) {
        await _focusOnRegion(duration: 0);
      } else {
        await mapboxMap.flyTo(
          mapbox.CameraOptions(
            center: _initialCenter(),
            zoom: _pins.isNotEmpty ? 15 : 6,
          ),
          mapbox.MapAnimationOptions(duration: 0),
        );
      }
      if (await mapboxMap.style.isStyleLoaded()) await _onStyleLoaded();
    } catch (_) {
      // The native map can be disposed or replaced during initialization.
    }
  }

  /// Computes on style loaded.
  Future<void> _onStyleLoaded() => _mapView.styleLoaded(_prepareMapStyle);

  /// Delegates prepare map style to the ViewModel.
  Future<void> _prepareMapStyle() => _screenModel.commandPrepareMapStyle();

  /// Prepares style.
  Future<void> _prepareStyle() async {
    final map = _mapboxMap;
    if (map == null || !mounted) return;
    try {
      _polylineManager ??= await map.annotations
          .createPolylineAnnotationManager();
      if (!mounted || !identical(map, _mapboxMap)) return;
      _circleManager ??= await map.annotations.createCircleAnnotationManager();
      if (!mounted || !identical(map, _mapboxMap)) return;
      _pointManager ??= await map.annotations.createPointAnnotationManager();
      if (!mounted || !identical(map, _mapboxMap)) return;
      await _pointManager!.setTextAllowOverlap(true);
      _styleLoaded = true;
      await _syncPins();
      if (widget.showStateFocus) {
        unawaited(_updateStateBoundary(_stateBoundary.onStyleLoaded(map)));
      }
      await _syncRoute();
      await _syncPins();
      if (widget.localDatabase != null && identical(map, _mapboxMap)) {
        unawaited(_restoreExistingTrailPaths(map));
      }
    } catch (_) {
      // The style callback may outlive the native map instance.
    }
  }

  /// Update map route annotations only for the current route inputs and loaded style.
  Future<void> _syncRoute() => _screenModel.commandSyncRoute();

  /// Delegates sync pins to the ViewModel.
  Future<void> _syncPins() => _screenModel.commandSyncPins();

  /// Delegates tapped pin index to the ViewModel.
  int? _tappedPinIndex(mapbox.Point tapped) =>
      _screenModel.commandTappedPinIndex(tapped);

  /// Computes on map tap.
  void _onMapTap(mapbox.Point coordinate) {
    if (!mounted || mapPointCoordinatesOrNull(coordinate) == null) return;
    final editable = widget.editableIndex;
    if (editable != null) {
      if (editable < 0 || editable >= _pins.length) return;
      setState(() {
        _pins[editable] = coordinate;
      });
      widget.onPinsChanged(List.of(_pins));
      unawaited(_syncPins());
      return;
    }
    if (widget.singlePinMode) {
      setState(() => _pins = [coordinate]);
      widget.onPinsChanged(List.of(_pins));
      unawaited(_syncPins());
      return;
    }
    final tappedIndex = _tappedPinIndex(coordinate);
    if (tappedIndex != null) {
      setState(() => _pins.removeAt(tappedIndex));
    } else {
      if (_pins.length >= 12) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('A route can contain up to 12 checkpoints.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }
      setState(() {
        _pins.add(coordinate);
      });
    }
    widget.onPinsChanged(List.of(_pins));
    unawaited(_syncPins());
  }

  /// Delegates zoom by to the ViewModel.
  Future<void> _zoomBy(double amount) => _screenModel.commandZoomBy(amount);

  /// Delegates fit pins to the ViewModel.
  Future<void> _fitPins() => _screenModel.commandFitPins();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final editable = widget.editableIndex;
    return SafeArea(
      child: Column(
        children: [
          if (widget.showStateFocus)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 18, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select a Starting Point',
                          style: PageHeaderStyle.title(
                            context,
                            _TrailColors.textFor(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Check existing trails, then tap where the new trail begins.',
                          style: PageHeaderStyle.subtitle(
                            context,
                            _TrailColors.secondaryTextFor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  PageHeaderAction(
                    tooltip: 'Close starting point selection',
                    icon: Icons.close_rounded,
                    onPressed: widget.onClose,
                    color: _TrailColors.textFor(context),
                    surface: _TrailColors.surfaceFor(context),
                  ),
                ],
              ),
            ),
          if (widget.showStateFocus)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: DropdownButtonFormField<MalaysiaMapRegion>(
                key: const ValueKey('add-trail-state-focus'),
                initialValue: _focusRegion,
                isExpanded: true,
                menuMaxHeight: 360,
                decoration: const InputDecoration(
                  labelText: 'Focus map on a state',
                  prefixIcon: Icon(Icons.map_outlined),
                  helperText: 'The selected pin determines the saved location.',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final region in MalaysiaMapRegion.values)
                    DropdownMenuItem(
                      value: region,
                      child: Text(
                        region.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _selectFocusRegion,
              ),
            ),
          if (widget.localDatabase != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 18, 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.route_rounded,
                    size: 19,
                    color: Color(0xFF16834B),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _pathsLoading
                              ? 'Loading saved trail routes…'
                              : _pathsFailed
                              ? 'Saved trail routes couldn’t load'
                              : _pathCount == 0
                              ? 'No route shapes saved on this device'
                              : '$_pathCount existing trail${_pathCount == 1 ? '' : 's'} · green routes',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (!_pathsLoading &&
                            !_pathsFailed &&
                            _unavailablePaths > 0)
                          Text(
                            '$_unavailablePaths trail route${_unavailablePaths == 1 ? ' is' : 's are'} not available locally.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _TrailColors.secondaryTextFor(context),
                                ),
                          ),
                      ],
                    ),
                  ),
                  if (_pathsLoading)
                    const HikerCircleMinorLoadingIndicator(size: 18),
                  if (_pathsFailed)
                    TextButton(
                      onPressed: () => unawaited(_loadExistingTrailPaths()),
                      child: const Text('Retry'),
                    ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                DeferredMap(
                  child: mapbox.MapWidget(
                    key: const ValueKey('checkpoint-picker'),
                    // Initial framing only; subsequent camera moves use flyTo.
                    // ignore: deprecated_member_use
                    cameraOptions: mapbox.CameraOptions(
                      center: _initialCenter(),
                      zoom: _pins.isEmpty ? 5 : 15,
                      pitch: 0,
                      bearing: 0,
                    ),
                    styleUri: mapStyleUrls[0],
                    gestureRecognizers: eagerMapGestureRecognizers,
                    onMapLoadErrorListener: (event) {
                      if (event.type == mapbox.MapLoadErrorType.STYLE) {
                        _mapView.styleLoadFailed();
                      }
                    },
                    onMapCreated: _onMapCreated,
                    onCameraChangeListener: _mapView.cameraChanged,
                    onStyleLoadedListener: (_) => _onStyleLoaded(),
                    onMapLoadedListener: (_) => _onStyleLoaded(),
                    // ignore: deprecated_member_use
                    onTapListener: (context) => _onMapTap(context.point),
                  ),
                ),
                MapViewOverlay(
                  controller: _mapView,
                  onZoomIn: () => unawaited(_zoomBy(1)),
                  onZoomOut: () => unawaited(_zoomBy(-1)),
                  onReset: () => unawaited(_fitPins()),
                ),
                IgnorePointer(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 88),
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            editable != null
                                ? 'Tap the map to set a new location for checkpoint ${editable + 1}'
                                : widget.singlePinMode
                                ? _pins.isEmpty
                                      ? 'Tap the map to select a trail location'
                                      : 'Starting point selected\n${_pins.first.coordinates.lat.toStringAsFixed(6)}, ${_pins.first.coordinates.lng.toStringAsFixed(6)}'
                                : 'Add 3–12 pins · tap a pin to remove',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          _pins.isEmpty ||
                              (!widget.singlePinMode &&
                                  editable == null &&
                                  (_pins.length < 3 || _pins.length > 12))
                          ? null
                          : () => widget.onConfirm(List.of(_pins)),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(
                        editable != null
                            ? 'Save Location'
                            : widget.singlePinMode
                            ? 'Use this location'
                            : 'Confirm ${_pins.length} pin${_pins.length == 1 ? '' : 's'}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Presents the update state boundary effect1 UI.
  void _presentUpdateStateBoundaryEffect1() =>
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'State outline could not load. You can still select a location.',
          ),
        ),
      );
}

/// Displays the single pin picker sheet.
class _SinglePinPickerSheet extends StatefulWidget {
  /// Creates single pin picker sheet.
  const _SinglePinPickerSheet({required this.title});

  final String title;

  /// Creates the presentation state for this widget.
  @override
  State<_SinglePinPickerSheet> createState() => _SinglePinPickerSheetState();
}

/// Manages the single pin picker sheet presentation and lifecycle.
class _SinglePinPickerSheetState extends State<_SinglePinPickerSheet> {
  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _SinglePinPickerSheetStateViewModel()
      ..addListener(_renderScreenModel);
  }

  late final _SinglePinPickerSheetStateViewModel _screenModel;

  /// Returns selected.
  mapbox.Point get _selected => _screenModel.stateSelected;

  /// Returns mapbox map.
  mapbox.MapboxMap? get _mapboxMap => _screenModel.stateMapboxMap;

  /// Updates mapbox map.
  set _mapboxMap(mapbox.MapboxMap? value) =>
      _screenModel.stateMapboxMap = value;

  /// Returns circle manager.
  mapbox.CircleAnnotationManager? get _circleManager =>
      _screenModel.stateCircleManager;

  /// Updates circle manager.
  set _circleManager(mapbox.CircleAnnotationManager? value) =>
      _screenModel.stateCircleManager = value;

  /// Returns point manager.
  mapbox.PointAnnotationManager? get _pointManager =>
      _screenModel.statePointManager;

  /// Updates point manager.
  set _pointManager(mapbox.PointAnnotationManager? value) =>
      _screenModel.statePointManager = value;

  /// Updates style loaded.
  set _styleLoaded(bool value) => _screenModel.stateStyleLoaded = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late final _mapView = MapViewController(
    settings: const MapViewSettings(),
    onBeforeStyleReload: () async {
      final managers = <mapbox.BaseAnnotationManager?>[
        _circleManager,
        _pointManager,
      ];
      _styleLoaded = false;
      _circleManager = null;
      _pointManager = null;
      await removeMapAnnotationManagers(_mapboxMap, managers);
    },
  );

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _mapView.dispose();
    _mapboxMap = null;
    _circleManager = null;
    _pointManager = null;

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates select coordinate to the ViewModel.
  void _selectCoordinate(mapbox.Point coordinate) =>
      _screenModel.commandSelectCoordinate(coordinate);

  /// Delegates fit selected pin to the ViewModel.
  Future<void> _fitSelectedPin() => _screenModel.commandFitSelectedPin();

  /// Computes on style loaded.
  Future<void> _onStyleLoaded() => _mapView.styleLoaded(_prepareMapStyle);

  /// Delegates prepare map style to the ViewModel.
  Future<void> _prepareMapStyle() => _screenModel.commandPrepareMapStyle();

  /// Delegates sync selected pin to the ViewModel.
  Future<void> _syncSelectedPin() => _screenModel.commandSyncSelectedPin();

  /// Computes on map created.
  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    if (!mounted) return;
    _mapboxMap = mapboxMap;
    _mapView.attach(mapboxMap);
    try {
      await mapboxMap.compass.updateSettings(
        mapbox.CompassSettings(enabled: false),
      );
      await mapboxMap.logo.updateSettings(mapbox.LogoSettings(enabled: false));
      await mapboxMap.gestures.updateSettings(
        mapbox.GesturesSettings(
          scrollEnabled: true,
          pinchToZoomEnabled: true,
          rotateEnabled: true,
          pitchEnabled: true,
        ),
      );
      await mapboxMap.setBounds(
        mapbox.CameraBoundsOptions(minZoom: 3, maxZoom: 21),
      );
      await mapboxMap.flyTo(
        mapbox.CameraOptions(center: _selected, zoom: 15),
        mapbox.MapAnimationOptions(duration: 0),
      );
      await _syncSelectedPin();
    } catch (_) {
      // The native map can be disposed or replaced during initialization.
    }
  }

  /// Delegates zoom by to the ViewModel.
  Future<void> _zoomBy(double amount) => _screenModel.commandZoomBy(amount);

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          6,
          18,
          18 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _TrailColors.textFor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap the map to place the pin, then confirm the selected coordinate.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _TrailColors.secondaryTextFor(context),
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 360,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DeferredMap(
                      child: mapbox.MapWidget(
                        key: const ValueKey('single-pin-picker'),
                        styleUri: mapStyleUrls[0],
                        gestureRecognizers: mapGestureRecognizers,
                        onMapLoadErrorListener: (event) {
                          if (event.type == mapbox.MapLoadErrorType.STYLE) {
                            _mapView.styleLoadFailed();
                          }
                        },
                        onMapCreated: _onMapCreated,
                        onCameraChangeListener: _mapView.cameraChanged,
                        onStyleLoadedListener: (_) => _onStyleLoaded(),
                        // ignore: deprecated_member_use
                        onTapListener: (context) =>
                            _selectCoordinate(context.point),
                      ),
                    ),
                    MapViewOverlay(
                      controller: _mapView,
                      onZoomIn: () => unawaited(_zoomBy(1)),
                      onZoomOut: () => unawaited(_zoomBy(-1)),
                      onReset: () => unawaited(_fitSelectedPin()),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Use Location'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Represents checkpoint draft.
class _CheckpointDraft {
  /// Creates checkpoint draft.
  _CheckpointDraft({required int order, required String name})
    : id = _nextId++,
      nameController = TextEditingController(text: name),
      latitudeController = TextEditingController(),
      longitudeController = TextEditingController();

  static int _nextId = 0;
  final int id;
  final TextEditingController nameController;
  final TextEditingController latitudeController;
  final TextEditingController longitudeController;

  /// Releases resources owned by this instance.
  void dispose() {
    nameController.dispose();
    latitudeController.dispose();
    longitudeController.dispose();
  }
}

/// Displays the checkpoint draft fields.
class _CheckpointDraftFields extends StatelessWidget {
  /// Creates checkpoint draft fields.
  const _CheckpointDraftFields({
    required this.draft,
    required this.index,
    required this.canRemove,
    this.onRemove,
    this.onEdit,
  });

  final _CheckpointDraft draft;
  final int index;
  final bool canRemove;
  final VoidCallback? onRemove;
  final VoidCallback? onEdit;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle_rounded, color: Colors.grey),
            ),
            const SizedBox(width: 8),
            Container(
              width: 24,
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: _TrailColors.secondaryTextFor(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: draft.nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
            ),
            if (onEdit != null) ...[
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Edit location on map',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_location_alt_rounded),
              ),
            ],
            if (canRemove && onRemove != null) ...[
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Remove checkpoint',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Displays the trail form error.
class _TrailFormError extends StatelessWidget {
  /// Creates trail form error.
  const _TrailFormError({required this.message});

  final String message;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _TrailColors.redFor(context).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _TrailColors.redFor(context),
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

/// Displays the discover hero.
class _DiscoverHero extends StatelessWidget {
  /// Creates discover hero.
  const _DiscoverHero({required this.trails});

  final List<Trail> trails;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final topTrail = trails.isEmpty ? null : trails.first;

    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Glyph(icon: Icons.explore_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topTrail == null
                        ? 'Build your next hiking plan'
                        : 'Suggested for today: ${topTrail.name}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: _TrailColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Compare difficulty, forecast, and hazard reports before you commit.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _TrailColors.secondaryTextFor(context),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusPill(
                        label: '${trails.length} routes',
                        color: _TrailColors.green,
                      ),
                      const _StatusPill(
                        label: 'Firebase live',
                        color: _TrailColors.orange,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the filter chips.
class _FilterChips extends StatelessWidget {
  /// Creates filter chips.
  const _FilterChips({required this.selectedFilter, required this.onSelected});

  final String selectedFilter;
  final ValueChanged<String> onSelected;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    const filters = ['Nearby', 'Popular', 'Beginner', 'Saved'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in filters) ...[
            ChoiceChip(
              label: Text(filter),
              selected: selectedFilter == filter,
              onSelected: (_) => onSelected(filter),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// Displays the trail swipe action background.
class _TrailSwipeActionBackground extends StatelessWidget {
  /// Creates trail swipe action background.
  const _TrailSwipeActionBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final isLeft = alignment == Alignment.centerLeft;

    return Container(
      color: color,
      alignment: alignment,
      padding: EdgeInsets.only(left: isLeft ? 18 : 0, right: isLeft ? 0 : 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: isLeft
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the trail detail hero.
class _TrailDetailHero extends StatelessWidget {
  /// Creates trail detail hero.
  const _TrailDetailHero({required this.trail});

  final Trail trail;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _TrailCover(
              trail: trail,
              height: 240,
              showGradient: false,
              showLocationLabel: false,
            ),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x22000000),
                      Color(0x00000000),
                      Color(0xCC000000),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _HeroPill(label: trail.difficultyDisplayLabel),
                        _HeroPill(label: trail.ratingLabel),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      trail.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      trail.locationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the edit trail page.
class _EditTrailPage extends StatefulWidget {
  /// Creates edit trail page.
  const _EditTrailPage({required this.trail});

  final Trail trail;

  /// Creates the presentation state for this widget.
  @override
  State<_EditTrailPage> createState() => _EditTrailPageState();
}

/// Manages the edit trail page presentation and lifecycle.
class _EditTrailPageState extends State<_EditTrailPage> {
  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _EditTrailPageStateViewModel(
      readTrail: () => widget.trail,
      effectDraftTrailForRoute: _draftTrailForRoute,
    )..addListener(_renderScreenModel);
  }

  late final _EditTrailPageStateViewModel _screenModel;

  /// Returns refreshed route.
  HikingRouteResult? get _refreshedRoute => _screenModel.stateRefreshedRoute;

  /// Updates refreshed route.
  set _refreshedRoute(HikingRouteResult? value) =>
      _screenModel.stateRefreshedRoute = value;

  /// Returns refreshed route checkpoints hash.
  String? get _refreshedRouteCheckpointsHash =>
      _screenModel.stateRefreshedRouteCheckpointsHash;

  /// Updates refreshed route checkpoints hash.
  set _refreshedRouteCheckpointsHash(String? value) =>
      _screenModel.stateRefreshedRouteCheckpointsHash = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late final _nameController = TextEditingController(text: widget.trail.name);
  late final _areaController = TextEditingController(text: widget.trail.area);
  late final _stateController = TextEditingController(text: widget.trail.state);
  late final _countryController = TextEditingController(
    text: widget.trail.country,
  );
  late final List<_CheckpointDraft> _checkpoints = widget.trail.checkpoints
      .map(
        (c) => _CheckpointDraft(order: c.order, name: c.name)
          ..latitudeController.text = c.latitude.toStringAsFixed(6)
          ..longitudeController.text = c.longitude.toStringAsFixed(6),
      )
      .toList();

  bool _isRefreshing = false;
  String? _routeRefreshError;

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _nameController.dispose();
    _areaController.dispose();
    _stateController.dispose();
    _countryController.dispose();
    for (final c in _checkpoints) {
      c.dispose();
    }

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates decode polyline to the ViewModel.
  List<mapbox.Point> _decodePolyline(String encoded) =>
      _screenModel.commandDecodePolyline(encoded);

  /// Adds checkpoints on map.
  Future<void> _addCheckpointsOnMap() async {
    final models = _buildCheckpointModels();
    final existingPins = models
        .map(
          (c) => mapbox.Point(
            coordinates: mapbox.Position(c.longitude, c.latitude),
          ),
        )
        .toList();
    final confirmed = await _presentAddCheckpointsOnMapEffect1(existingPins);
    if (confirmed == null || !mounted) return;
    final validConfirmed = confirmed
        .map(mapPointCoordinatesOrNull)
        .whereType<({double longitude, double latitude})>()
        .toList(growable: false);
    if (validConfirmed.isEmpty) return;
    for (final c in _checkpoints) {
      c.dispose();
    }
    _checkpoints.clear();
    for (var i = 0; i < validConfirmed.length; i++) {
      final name = i == 0
          ? 'Trailhead'
          : i == validConfirmed.length - 1
          ? 'End point'
          : 'Waypoint $i';
      final draft = _CheckpointDraft(order: i + 1, name: name);
      draft.latitudeController.text = validConfirmed[i].latitude
          .toStringAsFixed(6);
      draft.longitudeController.text = validConfirmed[i].longitude
          .toStringAsFixed(6);
      _checkpoints.add(draft);
    }
    setState(() {
      _refreshedRoute = null;
      _refreshedRouteCheckpointsHash = null;
      _routeRefreshError = null;
    });
    unawaited(_refreshMetrics());
  }

  /// Removes checkpoint.
  void _removeCheckpoint(int index) {
    if (_checkpoints.length <= 3) return;
    setState(() {
      _checkpoints.removeAt(index).dispose();
      _refreshedRoute = null;
      _refreshedRouteCheckpointsHash = null;
      _routeRefreshError = null;
    });
  }

  /// Computes edit checkpoint on map.
  Future<void> _editCheckpointOnMap(int index) async {
    final validEntries = <({int draftIndex, TrailCheckpoint checkpoint})>[];
    for (var draftIndex = 0; draftIndex < _checkpoints.length; draftIndex++) {
      final draft = _checkpoints[draftIndex];
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
      validEntries.add((
        draftIndex: draftIndex,
        checkpoint: TrailCheckpoint(
          name: name,
          latitude: latitude,
          longitude: longitude,
          order: draftIndex + 1,
        ),
      ));
    }
    final editablePinIndex = validEntries.indexWhere(
      (entry) => entry.draftIndex == index,
    );
    if (editablePinIndex < 0) {
      setState(() {
        _routeRefreshError =
            'Enter a valid name, latitude, and longitude before editing this checkpoint on the map.';
      });
      return;
    }

    final existingPins = validEntries
        .map(
          (entry) => mapbox.Point(
            coordinates: mapbox.Position(
              entry.checkpoint.longitude,
              entry.checkpoint.latitude,
            ),
          ),
        )
        .toList();

    List<mapbox.Position>? routeCoords;
    if (_refreshedRoute != null &&
        _refreshedRoute!.encodedPolyline.isNotEmpty) {
      final decoded = _decodePolyline(_refreshedRoute!.encodedPolyline);
      routeCoords = decoded
          .map(mapPointCoordinatesOrNull)
          .whereType<({double longitude, double latitude})>()
          .map((p) => mapbox.Position(p.longitude, p.latitude))
          .toList();
    }

    final confirmed = await _presentEditCheckpointOnMapEffect1(
      existingPins,
      editablePinIndex,
      routeCoords,
    );
    if (confirmed == null ||
        !mounted ||
        editablePinIndex >= confirmed.length ||
        index >= _checkpoints.length) {
      return;
    }
    final updated = confirmed[editablePinIndex];
    final updatedCoordinates = mapPointCoordinatesOrNull(updated);
    if (updatedCoordinates == null) return;
    setState(() {
      _checkpoints[index].latitudeController.text = updatedCoordinates.latitude
          .toStringAsFixed(6);
      _checkpoints[index].longitudeController.text = updatedCoordinates
          .longitude
          .toStringAsFixed(6);
      _refreshedRoute = null;
      _refreshedRouteCheckpointsHash = null;
      _routeRefreshError = null;
    });
    unawaited(_refreshMetrics());
  }

  /// Refreshes metrics.
  Future<void> _refreshMetrics() async {
    final models = _buildCheckpointModels();
    if (models.length < 3 || models.length > 12) return;
    final checkpointsHash = HikingRouteService.checkpointsHash(models);

    setState(() {
      _isRefreshing = true;
      _routeRefreshError = null;
    });

    try {
      final route = await HikingRouteService().findHikingRouteForTrail(
        _draftTrailForRoute(models),
      );
      if (mounted) {
        setState(() {
          _refreshedRoute = route;
          _refreshedRouteCheckpointsHash = checkpointsHash;
          _isRefreshing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _routeRefreshError =
              'Unable to refresh this route. Check the checkpoint locations and try again.';
        });
      }
    }
  }

  /// Computes draft trail for route.
  Trail _draftTrailForRoute(List<TrailCheckpoint> checkpoints) {
    return Trail(
      trailId: widget.trail.trailId,
      name: _nameController.text.trim().isEmpty
          ? widget.trail.name
          : _nameController.text.trim(),
      area: _areaController.text.trim().isEmpty
          ? widget.trail.area
          : _areaController.text.trim(),
      state: _stateController.text.trim().isEmpty
          ? widget.trail.state
          : _stateController.text.trim(),
      country: _countryController.text.trim().isEmpty
          ? widget.trail.country
          : _countryController.text.trim(),
      latitude: checkpoints.first.latitude,
      longitude: checkpoints.first.longitude,
      distanceKm: 0,
      difficulty: widget.trail.difficulty,
      easyDifficultyVotes: widget.trail.easyDifficultyVotes,
      moderateDifficultyVotes: widget.trail.moderateDifficultyVotes,
      hardDifficultyVotes: widget.trail.hardDifficultyVotes,
      estimatedDurationMinutes: 0,
      elevationGainMeters: 0,
      ratingAverage: widget.trail.ratingAverage,
      offlineMapAvailable: widget.trail.offlineMapAvailable,
      offlineMapDownloaded: widget.trail.offlineMapDownloaded,
      isVerifiedTrail: widget.trail.isVerifiedTrail,
      routeFilePath: widget.trail.routeFilePath,
      coverColorValue: widget.trail.coverColorValue,
      coverImageUrls: widget.trail.coverImageUrls,
      coverImageCredits: widget.trail.coverImageCredits,
      checkpoints: checkpoints,
      weather: widget.trail.weather,
      hazards: widget.trail.hazards,
    );
  }

  /// Delegates route inputs changed to the ViewModel.
  bool _routeInputsChanged(List<TrailCheckpoint> checkpoints) =>
      _screenModel.commandRouteInputsChanged(checkpoints);

  /// Refresh route-derived values when the edited checkpoints no longer match the stored route inputs.
  Future<HikingRouteResult?> _freshRouteForSave(
    List<TrailCheckpoint> checkpoints,
  ) => _screenModel.commandFreshRouteForSave(checkpoints);

  /// Builds checkpoint models.
  List<TrailCheckpoint> _buildCheckpointModels() {
    final models = <TrailCheckpoint>[];
    for (var i = 0; i < _checkpoints.length; i++) {
      final d = _checkpoints[i];
      final name = d.nameController.text.trim();
      final lat = double.tryParse(d.latitudeController.text.trim());
      final lng = double.tryParse(d.longitudeController.text.trim());
      if (name.isNotEmpty &&
          lat != null &&
          lng != null &&
          lat.isFinite &&
          lng.isFinite &&
          lat >= -90 &&
          lat <= 90 &&
          lng >= -180 &&
          lng <= 180) {
        models.add(
          TrailCheckpoint(
            name: name,
            latitude: lat,
            longitude: lng,
            order: i + 1,
          ),
        );
      }
    }
    return models;
  }

  /// Saves.
  Future<void> _save() async {
    final models = _buildCheckpointModels();
    if (models.length < 3 || models.length > 12) {
      setState(() {
        _routeRefreshError = 'Add between 3 and 12 checkpoints before saving.';
      });
      return;
    }

    HikingRouteResult? routeForSave =
        _refreshedRouteCheckpointsHash ==
            HikingRouteService.checkpointsHash(models)
        ? _refreshedRoute
        : null;
    if (_routeInputsChanged(models) ||
        (widget.trail.routeEncodedPolyline?.trim().isEmpty ?? true)) {
      setState(() {
        _isRefreshing = true;
        _routeRefreshError = null;
      });
      try {
        routeForSave = await _freshRouteForSave(models);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _isRefreshing = false;
          _routeRefreshError =
              'Unable to refresh this route. Check the checkpoint locations and try again.';
        });
        return;
      }
      if (!mounted) return;
      setState(() => _isRefreshing = false);
    }

    final updatedTrail = widget.trail.copyWith(
      name: _nameController.text.trim().isEmpty
          ? widget.trail.name
          : _nameController.text.trim(),
      area: _areaController.text.trim().isEmpty
          ? widget.trail.area
          : _areaController.text.trim(),
      state: _stateController.text.trim().isEmpty
          ? widget.trail.state
          : _stateController.text.trim(),
      country: _countryController.text.trim().isEmpty
          ? widget.trail.country
          : _countryController.text.trim(),
      checkpoints: models.length >= 3 && models.length <= 12
          ? models
          : widget.trail.checkpoints,
      latitude: models.first.latitude,
      longitude: models.first.longitude,
      distanceKm: routeForSave != null
          ? routeForSave.distanceMeters / 1000
          : widget.trail.distanceKm,
      estimatedDurationMinutes: routeForSave != null
          ? routeForSave.duration.inMinutes
          : widget.trail.estimatedDurationMinutes,
      elevationGainMeters: routeForSave != null
          ? (routeForSave.elevationGainMeters ??
                    widget.trail.elevationGainMeters)
                .round()
          : widget.trail.elevationGainMeters,
      minElevationMeters:
          routeForSave?.minElevationMeters?.round() ??
          widget.trail.minElevationMeters,
      maxElevationMeters:
          routeForSave?.maxElevationMeters?.round() ??
          widget.trail.maxElevationMeters,
      routeEncodedPolyline: routeForSave?.encodedPolyline,
      routeCheckpointsHash: HikingRouteService.checkpointsHash(models),
      dataSource: routeForSave?.sourceLabel,
      routeProvider: routeForSave == null ? null : 'checkpoint-routing',
      routeReferenceNote: routeForSave == null
          ? null
          : 'Current path generated through the manually selected checkpoints in order.',
    );
    _presentSaveEffect1(updatedTrail);
  }

  /// Computes choose worldwide region.
  Future<void> _chooseWorldwideRegion() async {
    final region = await WorldwideRegionPicker.show(
      context,
      initialCountry: _countryController.text,
      initialState: _stateController.text,
    );
    if (!mounted || region == null) return;
    setState(() {
      _countryController.text = region.country;
      _stateController.text = region.state;
    });
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _TrailColors.backgroundFor(context),
      appBar: PageHeaderAppBar(
        title: const Text('Edit Trail'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isRefreshing ? null : () => unawaited(_save()),
            icon: const Icon(Icons.save_rounded),
            label: Text(_isRefreshing ? 'Refreshing route' : 'Save'),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel(label: 'Trail Identity'),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Trail name',
                    prefixIcon: Icon(Icons.terrain_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _areaController,
                        decoration: const InputDecoration(labelText: 'Area'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _stateController,
                        readOnly: true,
                        onTap: _chooseWorldwideRegion,
                        decoration: const InputDecoration(
                          labelText: 'State',
                          suffixIcon: Icon(Icons.expand_more_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _countryController,
                  readOnly: true,
                  onTap: _chooseWorldwideRegion,
                  decoration: const InputDecoration(
                    labelText: 'Country',
                    prefixIcon: Icon(Icons.public_rounded),
                    suffixIcon: Icon(Icons.expand_more_rounded),
                  ),
                ),
                const SizedBox(height: 20),
                _InsetGroup(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Route metrics',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: _TrailColors.secondaryTextFor(
                                        context,
                                      ),
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0,
                                    ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _isRefreshing ? null : _refreshMetrics,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: Text(
                                _isRefreshing ? 'Refreshing' : 'Refresh',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _metricRow(
                          context,
                          Icons.straighten_rounded,
                          'Distance',
                          _refreshedRoute?.distanceLabel ??
                              widget.trail.distanceLabel,
                        ),
                        const SizedBox(height: 6),
                        _metricRow(
                          context,
                          Icons.access_time_rounded,
                          'Duration',
                          _refreshedRoute?.durationLabel ??
                              widget.trail.durationLabel,
                        ),
                        const SizedBox(height: 6),
                        _metricRow(
                          context,
                          Icons.trending_up_rounded,
                          'Elevation range',
                          _refreshedRoute?.elevationRangeLabel ??
                              widget.trail.elevationRangeLabel,
                        ),
                        const SizedBox(height: 6),
                        _metricRow(
                          context,
                          Icons.star_rounded,
                          'Rating',
                          widget.trail.ratingLabel,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Routes use 3-12 checkpoints. The first and last '
                          'stay fixed while intermediate checkpoints are optimized.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _TrailColors.secondaryTextFor(context),
                              ),
                        ),
                        if (_routeRefreshError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _routeRefreshError!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _TrailColors.redFor(context),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => unawaited(_addCheckpointsOnMap()),
                  icon: const Icon(Icons.add_location_alt_rounded),
                  label: const Text('Add checkpoints on map'),
                ),
                const SizedBox(height: 14),
                const SectionLabel(label: 'Checkpoints'),
                const SizedBox(height: 8),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: _checkpoints.length,
                  onReorderItem: (int oldIndex, int newIndex) {
                    setState(() {
                      final draft = _checkpoints.removeAt(oldIndex);
                      _checkpoints.insert(newIndex, draft);
                      _refreshedRoute = null;
                      _refreshedRouteCheckpointsHash = null;
                      _routeRefreshError = null;
                    });
                  },
                  itemBuilder: (context, index) {
                    final draft = _checkpoints[index];
                    return Padding(
                      key: ValueKey(draft.id),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CheckpointDraftFields(
                        draft: draft,
                        index: index,
                        canRemove: _checkpoints.length > 3,
                        onRemove: () => _removeCheckpoint(index),
                        onEdit: () => unawaited(_editCheckpointOnMap(index)),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          if (_isRefreshing)
            HikerCircleLoadingToastOverlay(
              message: 'Refreshing route…',
              detail: 'Updating route metrics from the checkpoints.',
              timeout: const Duration(seconds: 30),
              onTimeout: () {
                if (mounted) setState(() => _isRefreshing = false);
              },
            ),
        ],
      ),
    );
  }

  /// Computes metric row.
  Widget _metricRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _TrailColors.secondaryTextFor(context)),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: _TrailColors.secondaryTextFor(context),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: _TrailColors.textFor(context),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  /// Presents the add checkpoints on map effect1 UI.
  Future<List<mapbox.Point>?> _presentAddCheckpointsOnMapEffect1(
    List<mapbox.Point> existingPins,
  ) => Navigator.of(context).push<List<mapbox.Point>>(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: _TrailColors.backgroundFor(context),
        appBar: PageHeaderAppBar(
          title: const Text('Select checkpoints'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: _MapBasedCheckpointPicker(
          singlePinMode: false,
          pins: existingPins,
          onPinsChanged: (_) {},
          onConfirm: (pins) => Navigator.of(context).pop(pins),
        ),
      ),
    ),
  );

  /// Presents the edit checkpoint on map effect1 UI.
  Future<List<mapbox.Point>?> _presentEditCheckpointOnMapEffect1(
    List<mapbox.Point> existingPins,
    int editablePinIndex,
    List<mapbox.Position>? routeCoords,
  ) => Navigator.of(context).push<List<mapbox.Point>>(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: _TrailColors.backgroundFor(context),
        appBar: PageHeaderAppBar(
          title: const Text('Move checkpoint'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: _MapBasedCheckpointPicker(
          singlePinMode: false,
          pins: existingPins,
          editableIndex: editablePinIndex,
          routeCoordinates: routeCoords,
          onPinsChanged: (_) {},
          onConfirm: (pins) => Navigator.of(context).pop(pins),
        ),
      ),
    ),
  );

  /// Presents the save effect1 UI.
  void _presentSaveEffect1(Trail updatedTrail) =>
      Navigator.of(context).pop(updatedTrail);
}

/// Displays the trail cover.
class _TrailCover extends StatelessWidget {
  /// Creates trail cover.
  const _TrailCover({
    required this.trail,
    required this.height,
    this.width,
    this.showGradient = true,
    this.showLocationLabel = true,
  });

  final Trail trail;
  final double height;
  final double? width;
  final bool showGradient;
  final bool showLocationLabel;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _TrailCoverImages(trail: trail),
            if (showGradient)
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x11000000),
                        Color(0x05000000),
                        Color(0xAA000000),
                      ],
                    ),
                  ),
                ),
              ),
            if (showLocationLabel)
              Positioned(
                left: 10,
                right: 10,
                bottom: 9,
                child: IgnorePointer(
                  child: Text(
                    trail.locationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                      shadows: const [
                        Shadow(
                          color: Color(0xAA000000),
                          offset: Offset(0, 1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Displays the trail cover images.
class _TrailCoverImages extends StatefulWidget {
  /// Creates trail cover images.
  const _TrailCoverImages({required this.trail});

  final Trail trail;

  /// Creates the presentation state for this widget.
  @override
  State<_TrailCoverImages> createState() => _TrailCoverImagesState();
}

/// Manages the trail cover images presentation and lifecycle.
class _TrailCoverImagesState extends State<_TrailCoverImages> {
  int _currentPage = 0;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final trail = widget.trail;
    final urls = trail.coverImageUrls;
    if (urls.isEmpty) {
      return _TrailCoverFallback(trail: trail);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView(
          onPageChanged: (page) => setState(() => _currentPage = page),
          children: urls
              .map(
                (url) => CachedTrailImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  semanticLabel: '${trail.name} trail cover',
                  fallbackBuilder: (context) =>
                      _TrailCoverFallback(trail: trail),
                ),
              )
              .toList(),
        ),
        if (urls.length > 1)
          Positioned(
            top: 10,
            right: 10,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_currentPage + 1}/${urls.length}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Displays the trail cover fallback.
class _TrailCoverFallback extends StatelessWidget {
  /// Creates trail cover fallback.
  const _TrailCoverFallback({required this.trail});

  final Trail trail;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TrailCoverPainter(color: Color(trail.coverColorValue)),
    );
  }
}

/// Displays the metric group.
class _MetricGroup extends StatelessWidget {
  /// Creates metric group.
  const _MetricGroup({required this.trail});

  final Trail trail;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: SizedBox(
        height: 74,
        child: Row(
          children: [
            Expanded(
              child: _MetricCell(label: 'Distance', value: trail.distanceLabel),
            ),
            const _VerticalSeparator(),
            Expanded(
              child: _MetricCell(
                label: 'Elevation',
                value: trail.elevationRangeLabel,
              ),
            ),
            const _VerticalSeparator(),
            Expanded(
              child: _MetricCell(
                label: 'Typical Time',
                value: trail.durationLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the metric cell.
class _MetricCell extends StatelessWidget {
  /// Creates metric cell.
  const _MetricCell({required this.label, required this.value});

  final String label;
  final String value;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: _TrailColors.textFor(context),
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: _TrailColors.secondaryTextFor(context),
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

/// Displays the route preview.
class _RoutePreview extends StatefulWidget {
  /// Creates route preview.
  const _RoutePreview({
    super.key,
    required this.trail,
    this.highlightedCheckpointIndex,
    this.onHighlightCleared,
    this.localDatabase,
    this.departureTime,
    this.onAnimationProgress,
    this.onRouteLoaded,
  });

  final ValueChanged<HikingRouteResult>? onRouteLoaded;
  final ValueChanged<RouteCheckpointProgress>? onAnimationProgress;
  final DateTime? departureTime;
  final Trail trail;
  final int? highlightedCheckpointIndex;
  final VoidCallback? onHighlightCleared;
  final LocalSessionDatabase? localDatabase;

  /// Creates the presentation state for this widget.
  @override
  State<_RoutePreview> createState() => _RoutePreviewState();
}

/// Manages the route preview presentation and lifecycle.
class _RoutePreviewState extends State<_RoutePreview> {
  late final _RoutePreviewStateViewModel _screenModel;

  /// Returns route.
  HikingRouteResult? get _route => _screenModel.stateRoute;

  /// Updates route.
  set _route(HikingRouteResult? value) => _screenModel.stateRoute = value;

  /// Returns retry timer.
  Timer? get _retryTimer => _screenModel.stateRetryTimer;

  /// Returns load generation.
  int get _loadGeneration => _screenModel.stateLoadGeneration;

  /// Updates load generation.
  set _loadGeneration(int value) => _screenModel.stateLoadGeneration = value;

  /// Updates attempt.
  set _attempt(int value) => _screenModel.stateAttempt = value;

  /// Returns is loading route.
  bool get _isLoadingRoute => _screenModel.stateIsLoadingRoute;

  /// Updates is loading route.
  set _isLoadingRoute(bool value) => _screenModel.stateIsLoadingRoute = value;

  /// Returns loading message.
  String get _loadingMessage => _screenModel.stateLoadingMessage;

  /// Updates loading message.
  set _loadingMessage(String value) => _screenModel.stateLoadingMessage = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  RoutePreviewMode _previewMode = RoutePreviewMode.normal;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _RoutePreviewStateViewModel(
      readLocalDatabase: () => widget.localDatabase,
      readOnRouteLoaded: () => widget.onRouteLoaded,
      readTrail: () => widget.trail,
    )..addListener(_renderScreenModel);

    _route = _routeStoredWithTrail(widget.trail);
    _isLoadingRoute = _route == null;
    if (_route == null) {
      unawaited(_loadHikingRoute());
    }
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant _RoutePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trail.trailId != widget.trail.trailId ||
        oldWidget.trail.routeEncodedPolyline !=
            widget.trail.routeEncodedPolyline ||
        HikingRouteService.checkpointsHash(oldWidget.trail.checkpoints) !=
            HikingRouteService.checkpointsHash(widget.trail.checkpoints)) {
      _retryTimer?.cancel();
      _loadGeneration++;
      _attempt = 0;
      _route = _routeStoredWithTrail(widget.trail);
      _isLoadingRoute = _route == null;
      _loadingMessage = 'Loading detailed hiking route…';
      if (_route == null) {
        unawaited(_loadHikingRoute());
      }
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _loadGeneration++;
    _retryTimer?.cancel();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates route stored with trail to the ViewModel.
  HikingRouteResult? _routeStoredWithTrail(Trail trail) =>
      _screenModel.commandRouteStoredWithTrail(trail);

  /// Delegates load hiking route to the ViewModel.
  Future<void> _loadHikingRoute() => _screenModel.commandLoadHikingRoute();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        height: _previewMode == RoutePreviewMode.firstPerson ? 420 : 318,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<RoutePreviewMode>(
                  groupValue: _previewMode,
                  backgroundColor: _TrailColors.greenSoftFor(context),
                  thumbColor: _TrailColors.green,
                  padding: const EdgeInsets.all(3),
                  children: {
                    RoutePreviewMode.normal: _RoutePreviewModeLabel(
                      icon: Icons.map_outlined,
                      label: 'Normal',
                      selected: _previewMode == RoutePreviewMode.normal,
                    ),
                    RoutePreviewMode.firstPerson: _RoutePreviewModeLabel(
                      icon: Icons.navigation_rounded,
                      label: 'FPV',
                      selected: _previewMode == RoutePreviewMode.firstPerson,
                    ),
                  },
                  onValueChanged: (mode) {
                    if (mode == null || mode == _previewMode) return;
                    setState(() => _previewMode = mode);
                  },
                ),
              ),
              const SizedBox(height: 9),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: RoutePreviewMap(
                    key: ValueKey(widget.trail.trailId),
                    trail: widget.trail,
                    route: _route,
                    departureTime: widget.departureTime,
                    onAnimationProgress: widget.onAnimationProgress,
                    previewMode: _previewMode,
                    highlightedCheckpointIndex:
                        widget.highlightedCheckpointIndex,
                    isRouteLoading: _isLoadingRoute,
                    loadingMessage: _loadingMessage,
                    localDatabase: widget.localDatabase,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows weather insights sheet.
void showWeatherInsightsSheet(
  BuildContext context, {
  required Trail trail,
  required HikerCircleFirebaseRepository repository,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: _TrailColors.surfaceFor(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) =>
        _WeatherInsightsSheet(trail: trail, repository: repository),
  );
}

/// Displays the weather insights sheet.
class _WeatherInsightsSheet extends StatefulWidget {
  /// Creates weather insights sheet.
  const _WeatherInsightsSheet({required this.trail, required this.repository});

  final Trail trail;
  final HikerCircleFirebaseRepository repository;

  /// Creates the presentation state for this widget.
  @override
  State<_WeatherInsightsSheet> createState() => _WeatherInsightsSheetState();
}

/// Manages the weather insights sheet presentation and lifecycle.
class _WeatherInsightsSheetState extends State<_WeatherInsightsSheet> {
  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _WeatherInsightsSheetStateViewModel()
      ..addListener(_renderScreenModel);
  }

  late final _WeatherInsightsSheetStateViewModel _screenModel;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late final Trail _trail = widget.trail;

  /// Delegates time ago to the ViewModel.
  String _timeAgo(DateTime dateTime) => _screenModel.commandTimeAgo(dateTime);

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final weather = _trail.weather;
    final hourlyForecasts = weather.hourlyForecast;
    if (weather.forecastData.isNotEmpty || _trail.distanceKm > 3) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: TrailWeatherPanel(
          trail: _trail,
          loadLocationWeather: widget.repository.watchTrailCheckpointWeather,
          weather: weather,
          elevationGainMeters: _trail.elevationGainMeters,
          durationMinutes: _trail.estimatedDurationMinutes,
        ),
      );
    }
    final hasExtraDetails =
        weather.feelsLike != null ||
        weather.windSpeed != null ||
        weather.humidity != null ||
        weather.uvIndex != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hourly Forecast',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _TrailColors.textFor(context),
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Last refreshed ${_timeAgo(weather.cachedAt)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _TrailColors.secondaryTextFor(context),
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasExtraDetails) ...[
                    _ExtraDetailCard(weather: weather, uvLabel: _uvLabel),
                    const SizedBox(height: 16),
                  ],
                  if (hourlyForecasts.isNotEmpty) ...[
                    Text(
                      'HOURLY FORECAST',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _TrailColors.secondaryTextFor(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _InsetGroup(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            for (
                              var i = 0;
                              i < hourlyForecasts.length;
                              i++
                            ) ...[
                              if (i > 0) const _HorizontalSeparator(),
                              _HourlyForecastRow(forecast: hourlyForecasts[i]),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Delegates uv label to the ViewModel.
  String _uvLabel(double uvIndex) => _screenModel.commandUvLabel(uvIndex);

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }
}

/// Displays the glyph.
class _Glyph extends StatelessWidget {
  /// Creates glyph.
  const _Glyph({required this.icon});

  final IconData icon;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _TrailColors.green,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

/// Displays the inset group.
class _InsetGroup extends StatelessWidget {
  /// Creates inset group.
  const _InsetGroup({required this.child});

  final Widget child;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _TrailColors.surfaceFor(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }
}

/// Displays the horizontal separator.
class _HorizontalSeparator extends StatelessWidget {
  /// Creates horizontal separator.
  const _HorizontalSeparator();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.7,
      color: _TrailColors.separatorFor(context),
    );
  }
}

/// Displays the vertical separator.
class _VerticalSeparator extends StatelessWidget {
  /// Creates vertical separator.
  const _VerticalSeparator();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: VerticalDivider(
        width: 1,
        thickness: 0.7,
        color: _TrailColors.separatorFor(context),
      ),
    );
  }
}

/// Represents trail cover painter.
class _TrailCoverPainter extends CustomPainter {
  /// Creates trail cover painter.
  const _TrailCoverPainter({required this.color});

  final Color color;

  /// Computes paint.
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas.drawRect(Offset.zero & size, paint);

    final ridgePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    final foregroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;

    final backRidge = Path()
      ..moveTo(0, size.height * 0.74)
      ..lineTo(size.width * 0.24, size.height * 0.38)
      ..lineTo(size.width * 0.50, size.height * 0.70)
      ..lineTo(size.width * 0.72, size.height * 0.34)
      ..lineTo(size.width, size.height * 0.72)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(backRidge, ridgePaint);

    final frontRidge = Path()
      ..moveTo(0, size.height * 0.84)
      ..lineTo(size.width * 0.34, size.height * 0.56)
      ..lineTo(size.width * 0.58, size.height * 0.78)
      ..lineTo(size.width * 0.82, size.height * 0.52)
      ..lineTo(size.width, size.height * 0.76)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(frontRidge, foregroundPaint);
  }

  /// Computes should repaint.
  @override
  bool shouldRepaint(covariant _TrailCoverPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// Computes plan summary.
String _planSummary(Trail trail) {
  final hazardText = trail.hazards.isEmpty
      ? 'no active hazard reports'
      : '${trail.hazards.length} hazard report${trail.hazards.length == 1 ? '' : 's'}';
  return '${trail.distanceLabel}, ${trail.durationLabel}, $hazardText, ${trail.weather.rainProbability}% rain probability.';
}

/// Represents trail colors.
abstract final class _TrailColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color blue = Color(0xFF2563EB);
  static const Color orange = Color(0xFFF59E0B);
  static const Color red = Color(0xFFE11D48);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);

  /// Checks whether dark.
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Computes background for.
  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  /// Computes surface for.
  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  /// Computes green soft for.
  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : greenSoft;

  /// Computes separator for.
  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  /// Computes text for.
  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  /// Computes secondary text for.
  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  /// Computes red for.
  static Color redFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF6B88) : red;
}

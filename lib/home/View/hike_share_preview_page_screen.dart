part of '../hike_share_preview_page_feature.dart';

/// Displays the hike share preview page.
class HikeSharePreviewPage extends StatefulWidget {
  /// Creates hike share preview page.
  const HikeSharePreviewPage({
    super.key,
    required this.session,
    required this.report,
    required this.activeHike,
    required this.onShareExternally,
    required this.onPostToCommunity,
    this.repository,
  });

  final AppSession session;
  final HikeSummaryReport report;
  final ActiveHikeSession activeHike;
  final HikerCircleFirebaseRepository? repository;
  final Future<void> Function(
    String caption,
    List<CommunityPostImageUpload> images,
  )
  onPostToCommunity;
  final Future<void> Function(String text, {Uint8List? routeImage})
  onShareExternally;

  /// Creates the presentation state for this widget.
  @override
  State<HikeSharePreviewPage> createState() => _HikeSharePreviewPageState();
}

/// Manages the hike share preview page presentation and lifecycle.
class _HikeSharePreviewPageState extends State<HikeSharePreviewPage>
    with WidgetsBindingObserver {
  late final _HikeSharePreviewPageStateViewModel _screenModel;

  /// Returns initial draft.
  CommunityPostDraft get _initialDraft => _screenModel.stateInitialDraft;

  /// Updates initial draft.
  set _initialDraft(CommunityPostDraft value) =>
      _screenModel.stateInitialDraft = value;

  /// Returns current draft.
  CommunityPostDraft get _currentDraft => _screenModel.stateCurrentDraft;

  /// Updates current draft.
  set _currentDraft(CommunityPostDraft value) =>
      _screenModel.stateCurrentDraft = value;

  /// Updates post id.
  set _postId(String value) => _screenModel.statePostId = value;

  /// Updates is editing busy.
  set _isEditingBusy(bool value) => _screenModel.stateIsEditingBusy = value;

  /// Returns is sharing externally.
  bool get _isSharingExternally => _screenModel.stateIsSharingExternally;

  /// Updates is sharing externally.
  set _isSharingExternally(bool value) =>
      _screenModel.stateIsSharingExternally = value;

  /// Returns is closing.
  bool get _isClosing => _screenModel.stateIsClosing;

  /// Updates is closing.
  set _isClosing(bool value) => _screenModel.stateIsClosing = value;

  /// Returns is loading.
  bool get _isLoading => _screenModel.stateIsLoading;

  /// Updates is loading.
  set _isLoading(bool value) => _screenModel.stateIsLoading = value;

  /// Returns published.
  bool get _published => _screenModel.statePublished;

  /// Returns load error.
  String? get _loadError => _screenModel.stateLoadError;

  /// Returns save timer.
  Timer? get _saveTimer => _screenModel.stateSaveTimer;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  final _editorKey = GlobalKey<CommunityPostEditorState>();

  bool _canLeave = false;

  String? _saveError;

  /// Returns is busy.
  bool get _isBusy => _screenModel.commandIsBusy;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _HikeSharePreviewPageStateViewModel(
      readActiveHike: () => widget.activeHike,
      readOnPostToCommunity: () => widget.onPostToCommunity,
      readRepository: () => widget.repository,
      readSession: () => widget.session,
      effectSaveInBackground: _saveInBackground,
    )..addListener(_renderScreenModel);

    WidgetsBinding.instance.addObserver(this);
    _initialDraft = CommunityPostDraft(
      caption: defaultHikeShareCaption(widget.report),
      images: const [],
      includeHike: true,
    );
    _currentDraft = _initialDraft;
    final random = Random.secure();
    _postId =
        'post_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_'
        '${random.nextInt(0x100000000).toRadixString(36)}'
        '${random.nextInt(0x100000000).toRadixString(36)}';
    _isLoading = widget.repository != null;
    if (_isLoading) unawaited(_loadDraft());
  }

  /// Delegates load draft to the ViewModel.
  Future<void> _loadDraft() => _screenModel.commandLoadDraft();

  /// Delegates draft changed to the ViewModel.
  void _draftChanged(CommunityPostDraft draft) =>
      _screenModel.commandDraftChanged(draft);

  /// Serialize end-hike draft writes so a late autosave cannot overwrite a newer caption or photo selection.
  Future<void> _saveDraft() => _screenModel.commandSaveDraft();

  /// Saves in background.
  void _saveInBackground() {
    unawaited(
      _saveDraft()
          .then((_) {
            if (mounted && _saveError != null) {
              setState(() => _saveError = null);
            }
          })
          .catchError((Object _) {
            if (mounted) {
              setState(
                () => _saveError =
                    'Your draft could not be saved. Keep this page open and try again.',
              );
            }
          }),
    );
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_published) {
      _saveTimer?.cancel();
      _saveInBackground();
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Closes.
  Future<void> _close() async {
    if (_isBusy) return;
    if (widget.repository != null && _loadError == null) {
      _saveTimer?.cancel();
      setState(() => _isClosing = true);
      try {
        await _saveDraft();
        if (mounted) _leave(false);
      } catch (_) {
        if (mounted) {
          setState(() {
            _isClosing = false;
            _saveError =
                'Your draft could not be saved. Try again before closing.';
          });
        }
      }
      return;
    }
    if (_editorKey.currentState?.hasChanges ?? false) {
      final discard = await _presentCloseEffect1();
      if (discard != true || !mounted) return;
    }
    _leave(false);
  }

  /// Computes leave.
  void _leave(bool posted) {
    setState(() => _canLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(posted);
    });
  }

  /// Save the stable post identity before publishing; local cleanup cannot turn a confirmed post into failure.
  Future<void> _publish(CommunityPostDraft draft) =>
      _screenModel.commandPublish(draft);

  /// Share the currently edited caption and report while blocking a simultaneous community publish.
  Future<void> _shareExternally() async {
    if (_isBusy) return;
    final caption =
        _editorKey.currentState?.caption ?? _currentDraft.caption.trim();
    if (countWords(caption) > 300 ||
        caption.length > communityPostCaptionLimit) {
      _presentShareExternallyEffect1();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isSharingExternally = true);
    try {
      Uint8List? image;
      try {
        image = await HikeShareCardRenderer.render(
          hike: widget.activeHike,
          report: widget.report,
        );
      } catch (_) {
        // Text remains shareable if the device cannot allocate a route image.
      }
      if (!mounted) return;
      await widget.onShareExternally(
        buildExternalHikeShareText(report: widget.report, caption: caption),
        routeImage: image,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Sharing is unavailable on this device.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _isSharingExternally = false);
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope<bool>(
      canPop: _canLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: colors.surface,
        appBar: PageHeaderAppBar(
          backgroundColor: colors.surface,
          leading: IconButton(
            key: const Key('hike-share-back'),
            tooltip: 'Back',
            onPressed: _isBusy ? null : _close,
            icon: const Icon(CupertinoIcons.chevron_back),
          ),
          title: const Text('Share your hike'),
        ),
        body: SafeArea(
          top: false,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadDraft,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_saveError != null) ...[
                            Semantics(
                              liveRegion: true,
                              child: MaterialBanner(
                                content: Text(_saveError!),
                                actions: [
                                  TextButton(
                                    onPressed: _isBusy
                                        ? null
                                        : _saveInBackground,
                                    child: const Text('Try again'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          CommunityPostEditor(
                            key: _editorKey,
                            authorName: widget.session.username,
                            photoURL: widget.session.photoURL ?? '',
                            photoBytes: widget.session.photoBytes,
                            initialCaption: _initialDraft.caption,
                            initialImages: _initialDraft.images,
                            captionKey: const Key('hike-share-caption'),
                            publishKey: const Key('post-hike-to-community'),
                            publishLabel: 'Post hike',
                            captionWordLimit: 300,
                            enabled: !_isSharingExternally && !_isClosing,
                            allowHikeToggle: false,
                            hikeAttachment: _HikeAttachment(
                              report: widget.report,
                              activeHike: widget.activeHike,
                              enabled: !_isBusy,
                            ),
                            onDraftChanged: _draftChanged,
                            onPublish: _publish,
                            onBusyChanged: (busy) {
                              if (mounted) {
                                setState(() => _isEditingBusy = busy);
                              }
                            },
                            onPublished: () => _leave(true),
                            secondaryAction: TextButton.icon(
                              key: const Key('share-hike-externally'),
                              onPressed: _isBusy ? null : _shareExternally,
                              icon: _isSharingExternally
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      CupertinoIcons.square_arrow_up,
                                      size: 19,
                                    ),
                              label: Text(
                                _isSharingExternally
                                    ? 'Opening share…'
                                    : 'Share outside HikerCircle',
                              ),
                            ),
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

  /// Presents the close effect1 UI.
  Future<bool?> _presentCloseEffect1() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Discard this draft?'),
      content: const Text('Your text and selected photos will be removed.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep editing'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );

  /// Presents the share externally effect1 UI.
  void _presentShareExternallyEffect1() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Keep your caption within 300 words and $communityPostCaptionLimitLabel characters before sharing.',
        ),
      ),
    );
  }
}

/// Displays the hike attachment.
class _HikeAttachment extends StatelessWidget {
  /// Creates hike attachment.
  const _HikeAttachment({
    required this.report,
    required this.activeHike,
    required this.enabled,
  });
  final HikeSummaryReport report;
  final ActiveHikeSession activeHike;
  final bool enabled;

  /// Computes explore route.
  Future<void> _exploreRoute(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (context) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        report.trailName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close route preview',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: _routeMap(context, interactive: true),
                  ),
                ),
                const SizedBox(height: 16),
                _HikeMetrics(report: report),
              ],
            ),
          ),
        ),
      );

  /// Computes route map.
  Widget _routeMap(BuildContext context, {required bool interactive}) =>
      RoutePreviewMap(
        trail: activeHike.trail,
        recordedTrackPoints: recordedHikeMapPoints(activeHike),
        checkInPoints: _checkInPoints(activeHike),
        captureAllGestures: interactive,
        animateRoute: false,
        showLayerToggle: true,
      );

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .7)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 240,
              child: AbsorbPointer(
                absorbing: !enabled,
                child: _routeMap(context, interactive: false),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: TextButton.icon(
                  key: const Key('hike-share-explore-route'),
                  onPressed: enabled ? () => _exploreRoute(context) : null,
                  icon: const Icon(Icons.open_in_full_rounded, size: 16),
                  label: const Text('Explore route'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 19,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          report.trailName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Completed ${_formatShareDate(report.endedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 15),
                  _HikeMetrics(report: report),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the hike metrics.
class _HikeMetrics extends StatelessWidget {
  /// Creates hike metrics.
  const _HikeMetrics({required this.report});
  final HikeSummaryReport report;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 24,
    runSpacing: 14,
    children: [
      _Metric(
        icon: Icons.route_rounded,
        label: 'Distance',
        value: '${report.distanceKm.toStringAsFixed(2)} km',
      ),
      _Metric(
        icon: CupertinoIcons.clock,
        label: 'Time',
        value: _formatDuration(report.duration),
      ),
    ],
  );
}

/// Computes default hike share caption.
String defaultHikeShareCaption(HikeSummaryReport report) =>
    'Completed ${report.trailName}.';

/// Builds external hike share text.
String buildExternalHikeShareText({
  required HikeSummaryReport report,
  required String caption,
}) {
  final text = caption.trim();
  return [
    if (text.isNotEmpty && text != defaultHikeShareCaption(report)) ...[
      text,
      '',
    ],
    'Completed ${report.trailName}',
    _formatShareDate(report.endedAt),
    '',
    'Distance: ${report.distanceKm.toStringAsFixed(2)} km',
    'Duration: ${_formatDuration(report.duration)}',
    'Average speed: ${report.averageSpeedKmh.toStringAsFixed(2)} km/h',
    '',
    'Recorded with HikerCircle',
  ].join('\n');
}

/// Formats duration.
String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (duration.inMinutes == 0) return '${duration.inSeconds}s';
  if (hours == 0) return '${minutes}m';
  return '${hours}h ${minutes}m';
}

/// Formats share date.
String _formatShareDate(DateTime value) {
  final local = value.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

/// Checks in points.
List<mapbox.Point> _checkInPoints(ActiveHikeSession activeHike) => activeHike
    .checkInRecords
    .map((record) => record.coordinate)
    .whereType<HikeCoordinate>()
    .map(
      (coordinate) => mapbox.Point(
        coordinates: mapbox.Position(coordinate.longitude, coordinate.latitude),
      ),
    )
    .toList();

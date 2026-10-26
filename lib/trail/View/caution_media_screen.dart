part of '../caution_media_feature.dart';

/// Displays the caution evidence editor.
class CautionEvidenceEditor extends StatefulWidget {
  /// Creates caution evidence editor.
  const CautionEvidenceEditor({
    super.key,
    this.requiredEvidence = false,
    this.enabled = true,
  });
  final bool requiredEvidence, enabled;

  /// Creates the presentation state for this widget.
  @override
  State<CautionEvidenceEditor> createState() => CautionEvidenceEditorState();
}

/// Hold selected evidence locally until the caller submits the report or evidence update.
class CautionEvidenceEditorState extends State<CautionEvidenceEditor> {
  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = CautionEvidenceEditorStateViewModel(
      readEnabled: () => widget.enabled,
    )..addListener(_renderScreenModel);
  }

  late final CautionEvidenceEditorStateViewModel _screenModel;

  /// Returns files.
  List<PendingCautionMedia> get files => _screenModel.stateFiles;

  /// Returns error.
  String? get error => _screenModel.stateError;

  /// Updates error.
  set error(String? value) => _screenModel.stateError = value;

  /// Returns picking.
  bool get picking => _screenModel.statePicking;

  /// Updates picking.
  set picking(bool value) => _screenModel.statePicking = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  final note = TextEditingController();

  /// Returns has evidence.
  bool get hasEvidence => note.text.trim().isNotEmpty || files.isNotEmpty;

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    note.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates pick to the ViewModel.
  Future<void> pick() => _screenModel.commandPick();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: note,
        enabled: widget.enabled,
        maxLength: 1000,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: widget.requiredEvidence
              ? 'Describe what you saw, or add media'
              : 'Add a note (optional)',
          hintText: 'What should other hikers know?',
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      OutlinedButton.icon(
        onPressed: widget.enabled && !picking ? pick : null,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(picking ? 'Selecting…' : 'Add photos or videos'),
      ),
      Text(
        '${(files.fold<int>(0, (a, b) => a + b.sizeBytes) / 1024 / 1024).toStringAsFixed(1)} / 50 MB · ${widget.requiredEvidence ? 'Note or media required' : 'optional'}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      for (final file in files)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            file.isVideo ? Icons.videocam_rounded : Icons.image_rounded,
          ),
          title: Text(
            file.file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: 'Remove attachment',
            onPressed: widget.enabled
                ? () => setState(() => files.remove(file))
                : null,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}

/// Open report evidence independently from the editable evidence selection.
class CautionMediaViewer extends StatefulWidget {
  /// Creates caution media viewer.
  const CautionMediaViewer({
    super.key,
    required this.media,
    this.initialIndex = 0,
  });
  final List<Map<String, dynamic>> media;
  final int initialIndex;

  /// Creates the presentation state for this widget.
  @override
  State<CautionMediaViewer> createState() => _CautionMediaViewerState();
}

/// Manages the caution media viewer presentation and lifecycle.
class _CautionMediaViewerState extends State<CautionMediaViewer> {
  late final controller = PageController(initialPage: widget.initialIndex);
  late int index = widget.initialIndex;

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: PageHeaderAppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text('${index + 1} / ${widget.media.length}'),
    ),
    body: PageView.builder(
      controller: controller,
      itemCount: widget.media.length,
      onPageChanged: (value) => setState(() => index = value),
      itemBuilder: (context, i) {
        final item = widget.media[i];
        return i != index
            ? const SizedBox.shrink()
            : '${item['contentType']}'.startsWith('video/')
            ? _CautionVideo(url: '${item['url']}')
            : InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    '${item['url']}',
                    errorBuilder: (_, _, _) => const Text(
                      'Unable to load this photo.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              );
      },
    ),
  );
}

/// Displays the caution video.
class _CautionVideo extends StatefulWidget {
  /// Creates caution video.
  const _CautionVideo({required this.url});
  final String url;

  /// Creates the presentation state for this widget.
  @override
  State<_CautionVideo> createState() => _CautionVideoState();
}

/// Manages the caution video presentation and lifecycle.
class _CautionVideoState extends State<_CautionVideo>
    with WidgetsBindingObserver {
  late final VideoPlayerController controller =
      VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
  String? error;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller
        .initialize()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((Object e) {
          if (mounted) setState(() => error = 'Unable to play this video.');
        });
  }

  /// Refreshes presentation dependencies.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false) controller.pause();
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) controller.pause();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => error != null
      ? Center(
          child: Text(error!, style: const TextStyle(color: Colors.white)),
        )
      : !controller.value.isInitialized
      ? const Center(child: CircularProgressIndicator())
      : Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),
              VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                padding: const EdgeInsets.all(18),
              ),
              ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, value, _) => IconButton(
                  tooltip: value.isPlaying ? 'Pause' : 'Play',
                  iconSize: 48,
                  color: Colors.white,
                  onPressed: () =>
                      value.isPlaying ? controller.pause() : controller.play(),
                  icon: Icon(
                    value.isPlaying ? Icons.pause_circle : Icons.play_circle,
                  ),
                ),
              ),
            ],
          ),
        );
}

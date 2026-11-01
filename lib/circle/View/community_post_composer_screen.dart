part of '../community_post_composer_feature.dart';

const communityPostPhotoLimit = 6;

/// The same editor is used for a new story and the end-of-hike share preview.
class CommunityPostEditor extends StatefulWidget {
  /// Creates community post editor.
  const CommunityPostEditor({
    super.key,
    required this.authorName,
    required this.onPublish,
    this.photoURL = '',
    this.photoBytes,
    this.initialCaption = '',
    this.initialImages = const [],
    this.hikeAttachment,
    this.hikeLabel,
    this.includeHikeInitially = true,
    this.allowHikeToggle = true,
    this.publishLabel = 'Post',
    this.secondaryAction,
    this.onPublished,
    this.onBusyChanged,
    this.onChanged,
    this.onDraftChanged,
    this.enabled = true,
    this.captionKey = const ValueKey('community-caption'),
    this.publishKey = const ValueKey('community-publish'),
    this.captionWordLimit,
  });

  final String authorName;
  final String photoURL;
  final Uint8List? photoBytes;
  final String initialCaption;
  final List<CommunityPostImageUpload> initialImages;
  final Widget? hikeAttachment;
  final String? hikeLabel;
  final bool includeHikeInitially;
  final bool allowHikeToggle;
  final String publishLabel;
  final Widget? secondaryAction;
  final Future<void> Function(CommunityPostDraft draft) onPublish;
  final VoidCallback? onPublished;
  final ValueChanged<bool>? onBusyChanged;
  final VoidCallback? onChanged;
  final ValueChanged<CommunityPostDraft>? onDraftChanged;
  final bool enabled;
  final Key captionKey;
  final Key publishKey;
  final int? captionWordLimit;

  /// Creates the presentation state for this widget.
  @override
  State<CommunityPostEditor> createState() => CommunityPostEditorState();
}

/// Manages the community post editor presentation and lifecycle.
class CommunityPostEditorState extends State<CommunityPostEditor> {
  late final CommunityPostEditorStateViewModel _screenModel;

  /// Returns images.
  List<CommunityPostImageUpload> get _images => _screenModel.stateImages;

  /// Returns is posting.
  bool get _isPosting => _screenModel.stateIsPosting;

  /// Updates is posting.
  set _isPosting(bool value) => _screenModel.stateIsPosting = value;

  /// Returns is picking.
  bool get _isPicking => _screenModel.stateIsPicking;

  /// Returns error.
  String? get _error => _screenModel.stateError;

  /// Updates error.
  set _error(String? value) => _screenModel.stateError = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late final TextEditingController _caption;

  late bool _includeHike;

  /// Returns is busy.
  bool get isBusy => _screenModel.commandIsBusy;

  /// Returns has changes.
  bool get hasChanges =>
      _caption.text.trim() != widget.initialCaption.trim() ||
      _images.length != widget.initialImages.length ||
      _images.indexed.any(
        (entry) => !identical(entry.$2, widget.initialImages[entry.$1]),
      ) ||
      (widget.hikeAttachment != null &&
          _includeHike != widget.includeHikeInitially);

  /// Returns caption.
  String get caption => _caption.text.trim();

  /// Returns is caption valid.
  bool get isCaptionValid =>
      caption.length <= communityPostCaptionLimit &&
      (widget.captionWordLimit == null ||
          countWords(caption) <= widget.captionWordLimit!);

  /// Returns draft.
  CommunityPostDraft get draft => CommunityPostDraft(
    caption: _caption.text,
    images: List.unmodifiable(_images),
    includeHike: _includeHike && widget.hikeAttachment != null,
  );

  /// Returns has content.
  bool get _hasContent =>
      caption.isNotEmpty ||
      _images.isNotEmpty ||
      (_includeHike && widget.hikeAttachment != null);

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = CommunityPostEditorStateViewModel(
      readEnabled: () => widget.enabled,
      readOnBusyChanged: () => widget.onBusyChanged,
      effectNotifyChanged: _notifyChanged,
    )..addListener(_renderScreenModel);

    _caption = TextEditingController(text: widget.initialCaption);
    _images.addAll(widget.initialImages);
    _includeHike = widget.includeHikeInitially;
  }

  /// Notifies changed.
  void _notifyChanged() {
    widget.onChanged?.call();
    widget.onDraftChanged?.call(draft);
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _caption.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Use the single-photo picker for the last slot because pickMultiImage requires a limit of at least two.
  Future<void> _pickPhotos() => _screenModel.commandPickPhotos();

  /// Hold the draft during publishing and leave its text and photos intact when the operation fails.
  Future<void> _publish() async {
    if (isBusy || !_hasContent || !isCaptionValid) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isPosting = true;
      _error = null;
    });
    widget.onBusyChanged?.call(true);
    try {
      await widget.onPublish(
        CommunityPostDraft(
          caption: caption,
          images: List.unmodifiable(_images),
          includeHike: _includeHike && widget.hikeAttachment != null,
        ),
      );
      if (mounted) widget.onPublished?.call();
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is HikerCircleFirebaseRepositoryException
            ? error.message
            : 'Your post could not be shared. Your draft is still here. Try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final quiet = colors.onSurfaceVariant;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    ImageProvider<Object>? avatar;
    if (widget.photoBytes != null) {
      avatar = MemoryImage(widget.photoBytes!);
    } else if (widget.photoURL.isNotEmpty) {
      avatar = NetworkImage(widget.photoURL);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ComposerSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: colors.primaryContainer,
                    foregroundImage: avatar,
                    child: Text(
                      widget.authorName.trim().isEmpty
                          ? 'Y'
                          : widget.authorName
                                .trim()
                                .characters
                                .first
                                .toUpperCase(),
                      style: TextStyle(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.authorName.trim().isEmpty
                              ? 'You'
                              : widget.authorName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(CupertinoIcons.globe, size: 13, color: quiet),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                'Visible to the community',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: quiet,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Divider(
                  height: 1,
                  color: colors.outlineVariant.withValues(alpha: .5),
                ),
              ),
              TextField(
                key: widget.captionKey,
                controller: _caption,
                enabled: !isBusy,
                minLines: 5,
                maxLines: 10,
                maxLength: communityPostCaptionLimit,
                textAlignVertical: TextAlignVertical.top,
                inputFormatters: [
                  if (widget.captionWordLimit != null)
                    WordLimitTextInputFormatter(widget.captionWordLimit!),
                ],
                buildCounter:
                    (
                      context, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => Text(
                      widget.captionWordLimit == null
                          ? '$currentLength / $communityPostCaptionLimitLabel characters'
                          : '${countWords(_caption.text)} / ${widget.captionWordLimit} words · $currentLength / $communityPostCaptionLimitLabel characters',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isCaptionValid ? quiet : colors.error,
                      ),
                    ),
                textCapitalization: TextCapitalization.sentences,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                onChanged: (_) {
                  setState(() => _error = null);
                  _notifyChanged();
                },
                decoration: InputDecoration(
                  hintText:
                      'Share a moment, ask a question, or tell your trail story…',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: quiet,
                    height: 1.6,
                  ),
                  semanticCounterText: widget.captionWordLimit == null
                      ? '${_caption.text.characters.length} of $communityPostCaptionLimit characters'
                      : '${countWords(_caption.text)} of ${widget.captionWordLimit} words and ${_caption.text.characters.length} of $communityPostCaptionLimit characters',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _ComposerSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ComposerSectionHeader(
                icon: CupertinoIcons.photo_on_rectangle,
                title: 'Photos',
                trailing: Semantics(
                  label:
                      '${_images.length} of $communityPostPhotoLimit photos selected',
                  child: ExcludeSemantics(
                    child: Text(
                      '${_images.length} / $communityPostPhotoLimit',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: quiet,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (_images.isNotEmpty) ...[
                SizedBox(
                  height: 116,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _images[index].bytes,
                            width: 116,
                            height: 116,
                            fit: BoxFit.cover,
                            semanticLabel: 'Selected photo ${index + 1}',
                            errorBuilder: (_, _, _) => SizedBox.square(
                              dimension: 116,
                              child: ColoredBox(
                                color: colors.surfaceContainerHighest,
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton.filledTonal(
                            tooltip: 'Remove photo ${index + 1}',
                            style: IconButton.styleFrom(
                              backgroundColor: colors.surface.withValues(
                                alpha: .94,
                              ),
                            ),
                            onPressed: isBusy
                                ? null
                                : () {
                                    setState(() => _images.removeAt(index));
                                    _notifyChanged();
                                  },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                  side: BorderSide(
                    color: colors.primary.withValues(alpha: .35),
                  ),
                  minimumSize: const Size.fromHeight(46),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _isPicking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_photo_alternate_outlined, size: 20),
                label: Text(
                  _isPicking
                      ? 'Opening photos…'
                      : _images.length >= communityPostPhotoLimit
                      ? 'Photo limit reached'
                      : _images.isEmpty
                      ? 'Add photos'
                      : 'Add more photos',
                  textAlign: TextAlign.center,
                ),
                onPressed: isBusy || _images.length >= communityPostPhotoLimit
                    ? null
                    : _pickPhotos,
              ),
            ],
          ),
        ),
        if (widget.hikeAttachment != null) ...[
          const SizedBox(height: 14),
          _ComposerSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ComposerSectionHeader(
                  icon: Icons.route_rounded,
                  title: widget.allowHikeToggle
                      ? widget.hikeLabel ?? 'Attach hike'
                      : 'Hike details',
                  trailing: widget.allowHikeToggle
                      ? Switch.adaptive(
                          value: _includeHike,
                          onChanged: isBusy
                              ? null
                              : (value) {
                                  setState(() => _includeHike = value);
                                  _notifyChanged();
                                },
                        )
                      : null,
                ),
                AnimatedSize(
                  duration: reducedMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  alignment: Alignment.topCenter,
                  child: _includeHike
                      ? Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: widget.hikeAttachment!,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: colors.onErrorContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onErrorContainer,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          key: widget.publishKey,
          style: FilledButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            minimumSize: const Size.fromHeight(50),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            textStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: isBusy || !_hasContent || !isCaptionValid
              ? null
              : _publish,
          icon: _isPosting
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.onPrimary,
                  ),
                )
              : const Icon(CupertinoIcons.paperplane_fill, size: 18),
          label: Text(
            _isPosting ? 'Sharing…' : widget.publishLabel,
            textAlign: TextAlign.center,
          ),
        ),
        if (widget.secondaryAction != null) ...[
          const SizedBox(height: 8),
          IgnorePointer(
            ignoring: isBusy,
            child: Opacity(
              opacity: isBusy ? .5 : 1,
              child: widget.secondaryAction!,
            ),
          ),
        ],
      ],
    );
  }
}

/// Present the shared editor and return whether publication completed before the route closed.
Future<bool> showCommunityPostComposer(
  BuildContext context, {
  required String authorName,
  required Future<void> Function(CommunityPostDraft draft) onPublish,
  String photoURL = '',
  Uint8List? photoBytes,
  Widget? hikeAttachment,
  String? hikeLabel,
  bool includeHikeInitially = false,
  String initialCaption = '',
  List<CommunityPostImageUpload> initialImages = const [],
  ValueChanged<CommunityPostDraft>? onDraftChanged,
  Future<void> Function()? onDiscard,
  Future<void> Function(CommunityPostDraft draft)? onSaveDraft,
}) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => _CommunityComposerPage(
          authorName: authorName,
          photoURL: photoURL,
          photoBytes: photoBytes,
          hikeAttachment: hikeAttachment,
          hikeLabel: hikeLabel,
          includeHikeInitially: includeHikeInitially,
          onPublish: onPublish,
          initialCaption: initialCaption,
          initialImages: initialImages,
          onDraftChanged: onDraftChanged,
          onDiscard: onDiscard,
          onSaveDraft: onSaveDraft,
        ),
      ),
    ) ??
    false;

/// Displays the community composer page.
class _CommunityComposerPage extends StatefulWidget {
  /// Creates community composer page.
  const _CommunityComposerPage({
    required this.authorName,
    required this.photoURL,
    required this.photoBytes,
    required this.hikeAttachment,
    required this.hikeLabel,
    required this.includeHikeInitially,
    required this.onPublish,
    required this.initialCaption,
    required this.initialImages,
    required this.onDraftChanged,
    required this.onDiscard,
    required this.onSaveDraft,
  });
  final String authorName;
  final String photoURL;
  final Uint8List? photoBytes;
  final Widget? hikeAttachment;
  final String? hikeLabel;
  final bool includeHikeInitially;
  final Future<void> Function(CommunityPostDraft draft) onPublish;
  final String initialCaption;
  final List<CommunityPostImageUpload> initialImages;
  final ValueChanged<CommunityPostDraft>? onDraftChanged;
  final Future<void> Function()? onDiscard;
  final Future<void> Function(CommunityPostDraft draft)? onSaveDraft;

  /// Creates the presentation state for this widget.
  @override
  State<_CommunityComposerPage> createState() => _CommunityComposerPageState();
}

/// Manages the community composer page presentation and lifecycle.
class _CommunityComposerPageState extends State<_CommunityComposerPage> {
  final _editorKey = GlobalKey<CommunityPostEditorState>();
  bool _busy = false;
  bool _canLeave = false;

  bool _closing = false;

  /// Closes.
  Future<void> _close() async {
    if (_busy || _closing) return;
    setState(() => _closing = true);
    try {
      final editor = _editorKey.currentState;
      if (editor?.hasChanges ?? false) {
        final action = await _presentCloseEffect1();
        if (action == null || action == 'edit' || !mounted) return;
        if (action == 'discard') {
          await widget.onDiscard?.call();
        } else if (editor != null) {
          await widget.onSaveDraft?.call(editor.draft);
        }
        if (!mounted) return;
      }
      setState(() => _canLeave = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _presentCloseEffect2();
      });
    } catch (_) {
      if (mounted) {
        _presentCloseEffect3();
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF0C120F)
        : const Color(0xFFF2F2F7);
    return PopScope<bool>(
      canPop: _canLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: background,
        appBar: PageHeaderAppBar(
          backgroundColor: background,
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _busy || _closing ? null : _close,
            icon: const Icon(CupertinoIcons.chevron_back),
          ),
          title: const Text('Write a story'),
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: CommunityPostEditor(
                  key: _editorKey,
                  enabled: !_closing,
                  authorName: widget.authorName,
                  photoURL: widget.photoURL,
                  photoBytes: widget.photoBytes,
                  initialCaption: widget.initialCaption,
                  initialImages: widget.initialImages,
                  hikeAttachment: widget.hikeAttachment,
                  hikeLabel: widget.hikeLabel,
                  includeHikeInitially: widget.includeHikeInitially,
                  publishLabel: 'Share story',
                  onPublish: widget.onPublish,
                  onDraftChanged: widget.onDraftChanged,
                  onBusyChanged: (busy) {
                    if (mounted) setState(() => _busy = busy);
                  },
                  onPublished: () {
                    setState(() => _canLeave = true);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) Navigator.of(context).pop(true);
                    });
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Presents the close effect1 UI.
  Future<String?> _presentCloseEffect1() => showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Save for later?'),
      content: const Text(
        'Keep your draft and finish your story when you’re ready.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'edit'),
          child: const Text('Keep editing'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'discard'),
          child: const Text('Discard'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, 'save'),
          child: const Text('Save draft'),
        ),
      ],
    ),
  );

  /// Presents the close effect2 UI.
  void _presentCloseEffect2() => Navigator.of(context).pop(false);

  /// Presents the close effect3 UI.
  void _presentCloseEffect3() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Your draft couldn’t be saved. Please try again before leaving.',
      ),
    ),
  );
}

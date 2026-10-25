// CommunityPostEditor shares caption, photo and hike composition across community and end-hike posting.
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../core/widgets/word_limit_formatter.dart';

const communityPostCaptionLimit = 5000;
const communityPostPhotoLimit = 6;

/// Carry caption, selected image bytes and the optional hike attachment as one editor value.
class CommunityPostDraft {
  const CommunityPostDraft({
    required this.caption,
    required this.images,
    required this.includeHike,
  });

  final String caption;
  final List<CommunityPostImageUpload> images;
  final bool includeHike;
}

/// The same editor is used for a new story and the end-of-hike share preview.
class CommunityPostEditor extends StatefulWidget {
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

  @override
  State<CommunityPostEditor> createState() => CommunityPostEditorState();
}

class CommunityPostEditorState extends State<CommunityPostEditor> {
  late final TextEditingController _caption;
  final List<CommunityPostImageUpload> _images = [];
  late bool _includeHike;
  bool _isPosting = false;
  bool _isPicking = false;
  String? _error;

  bool get isBusy => !widget.enabled || _isPosting || _isPicking;
  bool get hasChanges =>
      _caption.text.trim() != widget.initialCaption.trim() ||
      _images.length != widget.initialImages.length ||
      _images.indexed.any(
        (entry) => !identical(entry.$2, widget.initialImages[entry.$1]),
      ) ||
      (widget.hikeAttachment != null &&
          _includeHike != widget.includeHikeInitially);
  String get caption => _caption.text.trim();
  bool get isCaptionValid =>
      caption.length <= communityPostCaptionLimit &&
      (widget.captionWordLimit == null ||
          countWords(caption) <= widget.captionWordLimit!);
  CommunityPostDraft get draft => CommunityPostDraft(
    caption: _caption.text,
    images: List.unmodifiable(_images),
    includeHike: _includeHike && widget.hikeAttachment != null,
  );
  bool get _hasContent =>
      caption.isNotEmpty ||
      _images.isNotEmpty ||
      (_includeHike && widget.hikeAttachment != null);

  @override
  void initState() {
    super.initState();
    _caption = TextEditingController(text: widget.initialCaption);
    _images.addAll(widget.initialImages);
    _includeHike = widget.includeHikeInitially;
  }

  void _notifyChanged() {
    widget.onChanged?.call();
    widget.onDraftChanged?.call(draft);
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  /// Use the single-photo picker for the last slot because pickMultiImage requires a limit of at least two.
  Future<void> _pickPhotos() async {
    if (isBusy || _images.length >= communityPostPhotoLimit) return;
    setState(() {
      _isPicking = true;
      _error = null;
    });
    widget.onBusyChanged?.call(true);
    try {
      final remaining = communityPostPhotoLimit - _images.length;
      final picker = ImagePicker();
      final picked = remaining == 1
          ? [
              await picker.pickImage(
                source: ImageSource.gallery,
                maxWidth: 2048,
                maxHeight: 2048,
                imageQuality: 85,
              ),
            ].nonNulls.toList()
          : await picker.pickMultiImage(
              maxWidth: 2048,
              maxHeight: 2048,
              imageQuality: 85,
              limit: remaining,
            );
      final additions = <CommunityPostImageUpload>[];
      var rejected = false;
      for (final file in picked.take(
        communityPostPhotoLimit - _images.length,
      )) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
          rejected = true;
          continue;
        }
        additions.add(
          CommunityPostImageUpload(
            bytes: bytes,
            fileName: file.name,
            contentType: file.mimeType,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _images.addAll(additions);
        if (rejected) {
          _error =
              'Some photos were too large. Choose photos under 10 MB each.';
        }
      });
      if (additions.isNotEmpty) _notifyChanged();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Unable to open your photos. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

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
        Row(
          children: [
            CircleAvatar(
              radius: 23,
              backgroundColor: colors.primaryContainer,
              foregroundImage: avatar,
              child: Text(
                widget.authorName.trim().isEmpty
                    ? 'Y'
                    : widget.authorName.trim().characters.first.toUpperCase(),
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
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(CupertinoIcons.globe, size: 13, color: quiet),
                      const SizedBox(width: 5),
                      Flexible(
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
        const SizedBox(height: 20),
        TextField(
          key: widget.captionKey,
          controller: _caption,
          enabled: !isBusy,
          minLines: 4,
          maxLines: 10,
          maxLength: communityPostCaptionLimit,
          textAlignVertical: TextAlignVertical.top,
          inputFormatters: [
            if (widget.captionWordLimit != null)
              WordLimitTextInputFormatter(widget.captionWordLimit!),
          ],
          buildCounter: widget.captionWordLimit == null
              ? null
              : (
                  context, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => Text(
                  '${countWords(_caption.text)}/${widget.captionWordLimit} words',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isCaptionValid ? quiet : colors.error,
                  ),
                ),
          textCapitalization: TextCapitalization.sentences,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          onChanged: (_) {
            setState(() => _error = null);
            _notifyChanged();
          },
          decoration: InputDecoration(
            hintText:
                'Share a moment, ask a question, or tell your trail story…',
            hintStyle: TextStyle(color: quiet),
            filled: true,
            fillColor: colors.surfaceContainerLow,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colors.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colors.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.all(16),
            counterStyle: TextStyle(color: quiet, fontSize: 11),
          ),
        ),
        if (_images.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.memory(
                      _images[index].bytes,
                      width: 124,
                      height: 132,
                      fit: BoxFit.cover,
                      semanticLabel: 'Selected photo ${index + 1}',
                      errorBuilder: (_, _, _) => SizedBox(
                        width: 124,
                        height: 132,
                        child: ColoredBox(
                          color: colors.surfaceContainerHighest,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 3,
                    right: 3,
                    child: IconButton.filledTonal(
                      tooltip: 'Remove photo ${index + 1}',
                      style: IconButton.styleFrom(
                        backgroundColor: colors.surface.withValues(alpha: .94),
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
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: _isPicking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(CupertinoIcons.photo_on_rectangle, size: 18),
              label: Text(
                _images.isEmpty
                    ? 'Add photos'
                    : '${_images.length}/$communityPostPhotoLimit photos',
              ),
              onPressed: isBusy || _images.length >= communityPostPhotoLimit
                  ? null
                  : _pickPhotos,
            ),
            if (widget.hikeAttachment != null && widget.allowHikeToggle)
              FilterChip(
                avatar: const Icon(Icons.route_rounded, size: 18),
                label: Text(widget.hikeLabel ?? 'Attach hike'),
                selected: _includeHike,
                onSelected: isBusy
                    ? null
                    : (value) {
                        setState(() => _includeHike = value);
                        _notifyChanged();
                      },
              ),
          ],
        ),
        AnimatedSize(
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          alignment: Alignment.topCenter,
          child: _includeHike && widget.hikeAttachment != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: widget.hikeAttachment!,
                )
              : const SizedBox.shrink(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(16),
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
                      style: TextStyle(
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
        const SizedBox(height: 24),
        FilledButton.icon(
          key: widget.publishKey,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF23834B),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          onPressed: isBusy || !_hasContent || !isCaptionValid
              ? null
              : _publish,
          icon: _isPosting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(CupertinoIcons.arrow_up_circle_fill, size: 20),
          label: Text(_isPosting ? 'Sharing…' : widget.publishLabel),
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

class _CommunityComposerPage extends StatefulWidget {
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
  @override
  State<_CommunityComposerPage> createState() => _CommunityComposerPageState();
}

class _CommunityComposerPageState extends State<_CommunityComposerPage> {
  final _editorKey = GlobalKey<CommunityPostEditorState>();
  bool _busy = false;
  bool _canLeave = false;

  bool _closing = false;
  Future<void> _close() async {
    if (_busy || _closing) return;
    setState(() => _closing = true);
    try {
      final editor = _editorKey.currentState;
      if (editor?.hasChanges ?? false) {
        final action = await showDialog<String>(
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
        if (mounted) Navigator.of(context).pop(false);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your draft couldn’t be saved. Please try again before leaving.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: _canLeave,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close composer',
          onPressed: _busy ? null : _close,
          icon: const Icon(Icons.close_rounded),
        ),
        title: const Text('Create a post'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
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

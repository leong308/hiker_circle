// CautionEvidenceEditor and CautionMediaViewer manage report photos and video evidence previews.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../Data/trail_caution_service.dart';

class CautionEvidenceEditor extends StatefulWidget {
  const CautionEvidenceEditor({
    super.key,
    this.requiredEvidence = false,
    this.enabled = true,
  });
  final bool requiredEvidence, enabled;
  @override
  State<CautionEvidenceEditor> createState() => CautionEvidenceEditorState();
}

/// Hold selected evidence locally until the caller submits the report or evidence update.
class CautionEvidenceEditorState extends State<CautionEvidenceEditor> {
  final note = TextEditingController();
  final files = <PendingCautionMedia>[];
  String? error;
  bool picking = false;
  bool get hasEvidence => note.text.trim().isNotEmpty || files.isNotEmpty;
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    if (picking || !widget.enabled) return;
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final selected = await ImagePicker().pickMultipleMedia(
        imageQuality: 85,
        requestFullMetadata: false,
      );
      final additions = <PendingCautionMedia>[];
      for (final file in selected) {
        final contentType =
            cautionMediaTypes[file.name.split('.').last.toLowerCase()];
        if (contentType == null) {
          throw StateError('Choose a supported photo or an MP4/MOV video.');
        }
        additions.add(
          PendingCautionMedia(
            file: file,
            sizeBytes: await file.length(),
            contentType: contentType,
          ),
        );
      }
      final combined = [...files, ...additions];
      if (combined.length > 6 ||
          combined.fold<int>(0, (a, b) => a + b.sizeBytes) >
              cautionMediaLimit) {
        throw StateError(
          'Choose up to six photos or videos, totaling at most 50 MB.',
        );
      }
      if (mounted) setState(() => files.addAll(additions));
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

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

class CautionMediaStrip extends StatelessWidget {
  const CautionMediaStrip({super.key, required this.media});
  final List<Map<String, dynamic>> media;
  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: media.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = media[index],
              video = '${media[index]['contentType']}'.startsWith('video/');
          return Semantics(
            label: video ? 'View video full screen' : 'View photo full screen',
            button: true,
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      CautionMediaViewer(media: media, initialIndex: index),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 145,
                  child: video
                      ? ColoredBox(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.play_circle_fill_rounded, size: 40),
                              Text('Video'),
                            ],
                          ),
                        )
                      : Image.network(
                          '${item['url']}',
                          fit: BoxFit.cover,
                          cacheWidth: 360,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Open report evidence independently from the editable evidence selection.
class CautionMediaViewer extends StatefulWidget {
  const CautionMediaViewer({
    super.key,
    required this.media,
    this.initialIndex = 0,
  });
  final List<Map<String, dynamic>> media;
  final int initialIndex;
  @override
  State<CautionMediaViewer> createState() => _CautionMediaViewerState();
}

class _CautionMediaViewerState extends State<CautionMediaViewer> {
  late final controller = PageController(initialPage: widget.initialIndex);
  late int index = widget.initialIndex;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

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

class _CautionVideo extends StatefulWidget {
  const _CautionVideo({required this.url});
  final String url;
  @override
  State<_CautionVideo> createState() => _CautionVideoState();
}

class _CautionVideoState extends State<_CautionVideo>
    with WidgetsBindingObserver {
  late final VideoPlayerController controller =
      VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
  String? error;
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false) controller.pause();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) controller.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

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

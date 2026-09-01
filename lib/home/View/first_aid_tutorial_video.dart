import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/widgets/loading_toast.dart';
import '../Data/first_aid_video_cache_service.dart';
import '../Model/first_aid_video.dart';

class FirstAidTutorialVideoCard extends StatefulWidget {
  const FirstAidTutorialVideoCard({
    super.key,
    required this.topicId,
    required this.video,
    required this.color,
  });

  final String topicId;
  final FirstAidVideo video;
  final Color color;

  @override
  State<FirstAidTutorialVideoCard> createState() =>
      _FirstAidTutorialVideoCardState();
}

class _FirstAidTutorialVideoCardState extends State<FirstAidTutorialVideoCard> {
  late Future<File> _cachedVideo;

  @override
  void initState() {
    super.initState();
    _startCache();
  }

  @override
  void didUpdateWidget(covariant FirstAidTutorialVideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topicId != widget.topicId ||
        oldWidget.video.storagePath != widget.video.storagePath ||
        oldWidget.video.version != widget.video.version) {
      _startCache();
    }
  }

  void _startCache() {
    _cachedVideo = FirstAidVideoCacheService.instance.cache(
      topicId: widget.topicId,
      video: widget.video,
    );
  }

  void _retry() {
    setState(_startCache);
  }

  Future<void> _openPlayer(File file) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _FirstAidVideoPlayerPage(file: file, video: widget.video),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark
        ? const Color(0xFFEAF4EE)
        : const Color(0xFF142019);
    final secondary = isDark
        ? const Color(0xFFA8B8AE)
        : const Color(0xFF66716A);
    final surface = isDark ? const Color(0xFF141C17) : Colors.white;

    return FutureBuilder<File>(
      future: _cachedVideo,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final failed = snapshot.hasError;
        final cachedFile = snapshot.data;
        return Semantics(
          button: !loading,
          label: loading
              ? 'Saving first-aid tutorial for offline use'
              : failed
              ? 'Tutorial download failed. Tap to retry.'
              : 'Play cached first-aid tutorial ${widget.video.title}',
          child: Material(
            color: surface,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: loading
                  ? null
                  : failed
                  ? _retry
                  : cachedFile == null
                  ? null
                  : () => _openPlayer(cachedFile),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 172,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          widget.color.withValues(alpha: 0.95),
                          widget.color.withValues(alpha: 0.58),
                        ],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -30,
                          top: -42,
                          child: Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                        ),
                        Center(
                          child: loading
                              ? const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    HikerCircleMinorLoadingIndicator(
                                      size: 64,
                                      semanticsLabel: 'Caching tutorial',
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Saving for offline use',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                )
                              : Icon(
                                  failed
                                      ? Icons.refresh_rounded
                                      : Icons.play_circle_fill_rounded,
                                  color: failed
                                      ? Colors.white
                                      : const Color(0xFFFFF8F5),
                                  size: 64,
                                ),
                        ),
                        Positioned(
                          left: 12,
                          top: 12,
                          child: _VideoStatusBadge(
                            label: loading
                                ? 'DOWNLOADING'
                                : failed
                                ? 'RETRY'
                                : 'SAVED OFFLINE',
                            icon: loading
                                ? Icons.cloud_download_rounded
                                : failed
                                ? Icons.error_outline_rounded
                                : Icons.offline_pin_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: widget.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.health_and_safety_rounded,
                            color: widget.color,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.video.title,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      color: foreground,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                failed
                                    ? 'Could not save the video. Your written guide is still available.'
                                    : '${widget.video.durationLabel} • ${widget.video.license}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: failed
                                          ? Colors.redAccent
                                          : secondary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        if (!loading)
                          Icon(Icons.chevron_right_rounded, color: secondary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VideoStatusBadge extends StatelessWidget {
  const _VideoStatusBadge({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _FirstAidVideoPlayerPage extends StatefulWidget {
  const _FirstAidVideoPlayerPage({required this.file, required this.video});

  final File file;
  final FirstAidVideo video;

  @override
  State<_FirstAidVideoPlayerPage> createState() =>
      _FirstAidVideoPlayerPageState();
}

class _FirstAidVideoPlayerPageState extends State<_FirstAidVideoPlayerPage> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialised;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    _initialised = _controller.initialize().then((_) {
      _controller.setLooping(false);
      if (mounted) setState(() {});
    });
    _controller.addListener(_refreshControls);
  }

  void _refreshControls() {
    if (mounted && _controller.value.isInitialized) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_refreshControls);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openSource() async {
    final uri = Uri.tryParse(widget.video.sourceUrl);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return Scaffold(
      backgroundColor: const Color(0xFF07100B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF07100B),
        foregroundColor: Colors.white,
        title: Text(
          widget.video.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<void>(
          future: _initialised,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'This cached tutorial could not be played.',
                  style: TextStyle(color: Colors.white),
                ),
              );
            }
            if (snapshot.connectionState != ConnectionState.done ||
                !value.isInitialized) {
              return const HikerCircleLoadingView(
                message: 'Preparing first-aid tutorial',
                detail: 'Opening the saved offline video.',
                compact: true,
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: value.aspectRatio <= 0
                        ? 16 / 9
                        : value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        VideoPlayer(_controller),
                        Material(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: const CircleBorder(),
                          child: IconButton(
                            iconSize: 42,
                            color: Colors.white,
                            tooltip: value.isPlaying ? 'Pause' : 'Play',
                            onPressed: () => value.isPlaying
                                ? _controller.pause()
                                : _controller.play(),
                            icon: Icon(
                              value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  colors: const VideoProgressColors(
                    playedColor: Color(0xFF63D58A),
                    bufferedColor: Color(0xFF64756B),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.video.attribution,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.video.license,
                  style: const TextStyle(color: Color(0xFFA8B8AE)),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _openSource,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('View original source and licence'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

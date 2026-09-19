import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../../core/widgets/loading_toast.dart';
import '../../core/widgets/route_preview_map.dart';
import '../Model/hike_session_models.dart';
import '../Model/recorded_hike_map_points.dart';

class HikeSharePreviewPage extends StatefulWidget {
  const HikeSharePreviewPage({
    super.key,
    required this.session,
    required this.report,
    required this.activeHike,
    required this.onShareExternally,
    required this.onPostToCommunity,
    this.initialMapStyleIndex = 0,
  });

  final AppSession session;
  final HikeSummaryReport report;
  final ActiveHikeSession activeHike;
  final Future<void> Function(
    String caption,
    List<CommunityPostImageUpload> images,
  )
  onPostToCommunity;
  final Future<void> Function(String text) onShareExternally;
  final int initialMapStyleIndex;

  @override
  State<HikeSharePreviewPage> createState() => _HikeSharePreviewPageState();
}

class _HikeSharePreviewPageState extends State<HikeSharePreviewPage> {
  late final TextEditingController _captionController;
  bool _isPosting = false;
  bool _isSharingExternally = false;
  final List<_SelectedHikeImage> _images = <_SelectedHikeImage>[];

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(
      text: defaultHikeShareCaption(widget.report),
    );
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _postToCommunity() async {
    final post = widget.onPostToCommunity;
    if (_isPosting || _isSharingExternally) return;

    final caption = _captionController.text.trim();
    if (caption.isEmpty) {
      _showMessage('Add a caption before sharing your hike.');
      return;
    }

    setState(() => _isPosting = true);
    try {
      await post(
        caption,
        _images
            .map(
              (image) => CommunityPostImageUpload(
                bytes: image.bytes,
                fileName: image.fileName,
                contentType: image.contentType,
              ),
            )
            .toList(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is HikerCircleFirebaseRepositoryException
              ? error.message
              : 'Unable to share this hike right now. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _addImages() async {
    if (_images.length >= 6 || _isPosting || _isSharingExternally) return;
    try {
      final picked = await ImagePicker().pickMultiImage(
        imageQuality: 88,
        limit: 6 - _images.length,
      );
      final additions = <_SelectedHikeImage>[];
      for (final file in picked) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) continue;
        additions.add(
          _SelectedHikeImage(
            bytes: bytes,
            fileName: file.name,
            contentType: file.mimeType,
          ),
        );
      }
      if (mounted && additions.isNotEmpty) {
        setState(() => _images.addAll(additions));
      }
    } catch (_) {
      if (mounted) _showMessage('Unable to open the photo library.');
    }
  }

  Future<void> _shareExternally() async {
    if (_isPosting || _isSharingExternally) return;

    setState(() => _isSharingExternally = true);
    try {
      await widget.onShareExternally(
        buildExternalHikeShareText(
          report: widget.report,
          caption: _captionController.text.trim(),
        ),
      );
    } catch (_) {
      if (mounted) _showMessage('Sharing is unavailable on this device.');
    } finally {
      if (mounted) setState(() => _isSharingExternally = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final isBusy = _isPosting || _isSharingExternally;

    return PopScope(
      canPop: !isBusy,
      child: Scaffold(
        backgroundColor: _ShareColors.backgroundFor(context),
        appBar: AppBar(
          backgroundColor: _ShareColors.backgroundFor(context),
          surfaceTintColor: Colors.transparent,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: isBusy ? null : () => Navigator.of(context).pop(),
            child: const Icon(CupertinoIcons.xmark, size: 20),
          ),
          titleSpacing: 4,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Share hike',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: _ShareColors.textFor(context),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              Text(
                'Preview your post before sharing',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _ShareColors.secondaryTextFor(context),
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _AudienceRow(),
                              const SizedBox(height: 12),
                              _PostPreviewCard(
                                session: widget.session,
                                report: report,
                                activeHike: widget.activeHike,
                                initialMapStyleIndex:
                                    widget.initialMapStyleIndex,
                                captionController: _captionController,
                                enabled: !isBusy,
                              ),
                              const SizedBox(height: 12),
                              _HikePhotoPicker(
                                images: _images,
                                enabled: !isBusy,
                                onAdd: _addImages,
                                onRemove: (index) =>
                                    setState(() => _images.removeAt(index)),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Your route and hike totals will be included with this post.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: _ShareColors.secondaryTextFor(
                                        context,
                                      ),
                                      letterSpacing: 0,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _ShareActionBar(
                    isPosting: _isPosting,
                    isSharingExternally: _isSharingExternally,
                    onPost: _postToCommunity,
                    onShareExternally: _shareExternally,
                  ),
                ],
              ),
              if (isBusy)
                HikerCircleLoadingToastOverlay(
                  message: _isPosting
                      ? 'Sharing your hike…'
                      : 'Preparing share…',
                  detail: _isPosting
                      ? 'Uploading your preview and route details.'
                      : 'Opening the selected sharing app.',
                  timeout: const Duration(seconds: 30),
                  onTimeout: () {
                    if (mounted) {
                      _showMessage(
                        'Sharing is taking longer than usual. '
                        'Please wait while the current request finishes.',
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudienceRow extends StatelessWidget {
  const _AudienceRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'SHARING TO',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: _ShareColors.secondaryTextFor(context),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _ShareColors.green.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_2_rounded, color: _ShareColors.green, size: 16),
              const SizedBox(width: 6),
              Text(
                'Public community',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: _ShareColors.green,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PostPreviewCard extends StatelessWidget {
  const _PostPreviewCard({
    required this.session,
    required this.report,
    required this.activeHike,
    required this.initialMapStyleIndex,
    required this.captionController,
    required this.enabled,
  });

  final AppSession session;
  final HikeSummaryReport report;
  final ActiveHikeSession activeHike;
  final int initialMapStyleIndex;
  final TextEditingController captionController;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _ShareColors.surfaceFor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _ShareColors.separatorFor(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.18
                  : 0.06,
            ),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                _ShareAvatar(session: session),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.username.trim().isEmpty
                            ? 'HikerCircle member'
                            : session.username.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: _ShareColors.textFor(context),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      Text(
                        'Completed a hike • ${_formatShareDate(report.endedAt)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _ShareColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.verified_rounded,
                  color: _ShareColors.green,
                  size: 20,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: TextField(
              key: const Key('hike-share-caption'),
              controller: captionController,
              enabled: enabled,
              minLines: 2,
              maxLines: 5,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Say something about your hike...',
                counterStyle: TextStyle(
                  color: _ShareColors.secondaryTextFor(context),
                ),
                filled: true,
                fillColor: _ShareColors.inputFor(context),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 230,
            child: RoutePreviewMap(
              trail: activeHike.trail,
              recordedTrackPoints: recordedHikeMapPoints(activeHike),
              pinnedPoints: _pinPoints(activeHike),
              checkInPoints: _checkInPoints(activeHike),
              captureAllGestures: true,
              animateRoute: true,
              initialStyleIndex: initialMapStyleIndex,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _ShareColors.green.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.terrain_rounded,
                    color: _ShareColors.green,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TRAIL COMPLETED',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _ShareColors.green,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        report.trailName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _ShareColors.textFor(context),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
            child: Row(
              children: [
                Expanded(
                  child: _PreviewMetric(
                    value: '${report.distanceKm.toStringAsFixed(2)} km',
                    label: 'Distance',
                  ),
                ),
                _MetricDivider(color: _ShareColors.separatorFor(context)),
                Expanded(
                  child: _PreviewMetric(
                    value: _formatDuration(report.duration),
                    label: 'Duration',
                  ),
                ),
                _MetricDivider(color: _ShareColors.separatorFor(context)),
                Expanded(
                  child: _PreviewMetric(
                    value: '${report.routePointCount}',
                    label: 'GPS points',
                  ),
                ),
              ],
            ),
          ),
          if (report.manualPins > 0)
            Container(
              color: _ShareColors.inputFor(context),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.push_pin_rounded,
                    color: Color(0xFFE11D48),
                    size: 17,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '${report.manualPins} ${report.manualPins == 1 ? 'location' : 'locations'} pinned along the route',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _ShareColors.secondaryTextFor(context),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ShareAvatar extends StatelessWidget {
  const _ShareAvatar({required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    final photoBytes = session.photoBytes;
    final photoUrl = session.photoURL?.trim() ?? '';
    final username = session.username.trim();
    final initial = username.isEmpty ? 'H' : username.characters.first;

    Widget child;
    if (photoBytes != null && photoBytes.isNotEmpty) {
      child = Image.memory(photoBytes, fit: BoxFit.cover);
    } else if (photoUrl.isNotEmpty) {
      child = Image.network(
        photoUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _AvatarInitial(initial: initial),
      );
    } else {
      child = _AvatarInitial(initial: initial);
    }

    return ClipOval(child: SizedBox.square(dimension: 42, child: child));
  }
}

class _SelectedHikeImage {
  const _SelectedHikeImage({
    required this.bytes,
    required this.fileName,
    this.contentType,
  });

  final Uint8List bytes;
  final String fileName;
  final String? contentType;
}

class _HikePhotoPicker extends StatelessWidget {
  const _HikePhotoPicker({
    required this.images,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_SelectedHikeImage> images;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _ShareColors.surfaceFor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _ShareColors.separatorFor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.photo_library_outlined,
                color: _ShareColors.green,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Hike photos (${images.length}/6)',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: enabled && images.length < 6 ? onAdd : null,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Add'),
              ),
            ],
          ),
          if (images.isEmpty)
            Text(
              'Add photos from this hike to make the post more personal.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _ShareColors.secondaryTextFor(context),
              ),
            )
          else
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.memory(
                        images[index].bytes,
                        width: 92,
                        height: 92,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: InkWell(
                        onTap: enabled ? () => onRemove(index) : null,
                        child: const CircleAvatar(
                          radius: 12,
                          backgroundColor: Color(0xB3000000),
                          child: Icon(
                            Icons.close,
                            size: 15,
                            color: Colors.white,
                          ),
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
}

class _AvatarInitial extends StatelessWidget {
  const _AvatarInitial({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _ShareColors.green,
      child: Center(
        child: Text(
          initial.toUpperCase(),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _PreviewMetric extends StatelessWidget {
  const _PreviewMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: _ShareColors.textFor(context),
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _ShareColors.secondaryTextFor(context),
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: VerticalDivider(width: 1, thickness: 0.7, color: color),
    );
  }
}

class _ShareActionBar extends StatelessWidget {
  const _ShareActionBar({
    required this.isPosting,
    required this.isSharingExternally,
    required this.onPost,
    required this.onShareExternally,
  });

  final bool isPosting;
  final bool isSharingExternally;
  final VoidCallback onPost;
  final VoidCallback onShareExternally;

  @override
  Widget build(BuildContext context) {
    final isBusy = isPosting || isSharingExternally;
    final externalAction = OutlinedButton.icon(
      key: const Key('share-hike-externally'),
      onPressed: isBusy ? null : onShareExternally,
      icon: const Icon(Icons.ios_share_rounded),
      label: const Text('Other apps'),
    );
    final communityAction = FilledButton.icon(
      key: const Key('post-hike-to-community'),
      onPressed: isBusy ? null : onPost,
      style: FilledButton.styleFrom(
        backgroundColor: _ShareColors.green,
        foregroundColor: Colors.white,
      ),
      icon: const Icon(Icons.send_rounded),
      label: const Text('Post to Community'),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _ShareColors.surfaceFor(context),
        border: Border(
          top: BorderSide(color: _ShareColors.separatorFor(context)),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 420) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      communityAction,
                      const SizedBox(height: 8),
                      externalAction,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: externalAction),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: communityAction),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

String defaultHikeShareCaption(HikeSummaryReport report) {
  return 'Completed ${report.trailName} — '
      '${report.distanceKm.toStringAsFixed(2)} km in '
      '${_formatDuration(report.duration)}. '
      '${report.routePointCount} GPS points recorded along the way.';
}

String buildExternalHikeShareText({
  required HikeSummaryReport report,
  required String caption,
}) {
  return [
    if (caption.isNotEmpty) ...[caption, ''],
    report.shareText,
  ].join('\n');
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  return '${hours}h ${minutes}m';
}

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
  return '${months[local.month - 1]} ${local.day}';
}

List<mapbox.Point> _pinPoints(ActiveHikeSession activeHike) {
  return activeHike.manualPinLocations
      .map(
        (pin) => mapbox.Point(
          coordinates: mapbox.Position(
            pin.coordinate.longitude,
            pin.coordinate.latitude,
          ),
        ),
      )
      .toList();
}

List<mapbox.Point> _checkInPoints(ActiveHikeSession activeHike) {
  return activeHike.checkInRecords
      .map((record) => record.coordinate)
      .whereType<HikeCoordinate>()
      .map(
        (coordinate) => mapbox.Point(
          coordinates: mapbox.Position(
            coordinate.longitude,
            coordinate.latitude,
          ),
        ),
      )
      .toList();
}

abstract final class _ShareColors {
  static const green = Color(0xFF34A853);
  static const lightBackground = Color(0xFFF2F2F7);
  static const lightText = Color(0xFF111111);
  static const lightSecondaryText = Color(0xFF6E6E73);
  static const lightSeparator = Color(0xFFD9E1DC);

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      _isDark(context) ? const Color(0xFF0C120F) : lightBackground;

  static Color surfaceFor(BuildContext context) =>
      _isDark(context) ? const Color(0xFF141C17) : Colors.white;

  static Color inputFor(BuildContext context) =>
      _isDark(context) ? const Color(0xFF1B261F) : const Color(0xFFF5F7F5);

  static Color textFor(BuildContext context) =>
      _isDark(context) ? const Color(0xFFEAF4EE) : lightText;

  static Color secondaryTextFor(BuildContext context) =>
      _isDark(context) ? const Color(0xFFA8B8AE) : lightSecondaryText;

  static Color separatorFor(BuildContext context) =>
      _isDark(context) ? const Color(0xFF2B3A31) : lightSeparator;
}

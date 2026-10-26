part of '../../trail_images_card_feature.dart';

/// Displays the trail images card.
class TrailImagesCard extends StatelessWidget {
  /// Creates trail images card.
  const TrailImagesCard({
    super.key,
    required this.images,
    required this.linkController,
    required this.onGallery,
    required this.onCamera,
    required this.onRemove,
    required this.cameraSupported,
    this.isBusy = false,
    this.maxImages = 10,
  });

  final List<TrailImagePreview> images;
  final TextEditingController linkController;
  final VoidCallback onGallery;
  final VoidCallback onCamera;
  final ValueChanged<int> onRemove;
  final bool cameraSupported;
  final bool isBusy;
  final int maxImages;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final canAdd = !isBusy && images.length < maxImages;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.photo_library_outlined,
                    color: colors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: const SectionLabel(
                    label: 'Trail Images',
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  label: '${images.length} of $maxImages photos selected',
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${images.length}/$maxImages',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (images.isEmpty)
              Material(
                color: colors.primaryContainer.withValues(alpha: .28),
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: canAdd ? onGallery : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 24,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 38,
                          color: colors.primary,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Add trail photos',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'First photo is your cover',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _PhotoPreview(
                  image: images.first,
                  label: 'Cover',
                  onRemove: isBusy ? null : () => onRemove(0),
                ),
              ),
              if (images.length > 1 || canAdd) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: images.length - 1 + (canAdd ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final photoIndex = index + 1;
                      return SizedBox(
                        width: 84,
                        child: photoIndex < images.length
                            ? _PhotoPreview(
                                image: images[photoIndex],
                                label: '${photoIndex + 1}',
                                onRemove: isBusy
                                    ? null
                                    : () => onRemove(photoIndex),
                              )
                            : Material(
                                color: colors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(12),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: onGallery,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_rounded,
                                        color: colors.primary,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Add',
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              color: colors.primary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      );
                    },
                  ),
                ),
              ],
            ],
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final stackButtons =
                    constraints.maxWidth < 260 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                final gallery = FilledButton.icon(
                  onPressed: canAdd ? onGallery : null,
                  icon: const Icon(Icons.photo_library_outlined, size: 19),
                  label: const Text('Gallery'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
                final camera = OutlinedButton.icon(
                  onPressed: canAdd && cameraSupported ? onCamera : null,
                  icon: const Icon(Icons.photo_camera_outlined, size: 19),
                  label: const Text('Camera'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
                return stackButtons
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [gallery, const SizedBox(height: 8), camera],
                      )
                    : Row(
                        children: [
                          Expanded(child: gallery),
                          const SizedBox(width: 10),
                          Expanded(child: camera),
                        ],
                      );
              },
            ),
            const SizedBox(height: 16),
            Divider(
              height: 1,
              color: colors.outlineVariant.withValues(alpha: .65),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: linkController,
              enabled: !isBusy,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Image link',
                prefixIcon: const Icon(Icons.link_rounded, size: 21),
                filled: true,
                fillColor: colors.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.primary, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

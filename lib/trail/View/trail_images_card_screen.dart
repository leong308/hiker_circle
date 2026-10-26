part of '../trail_images_card_feature.dart';

/// Displays the photo preview.
class _PhotoPreview extends StatelessWidget {
  /// Creates photo preview.
  const _PhotoPreview({
    required this.image,
    required this.label,
    required this.onRemove,
  });
  final TrailImagePreview image;
  final String label;
  final VoidCallback? onRemove;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(
          image.bytes,
          fit: BoxFit.cover,
          semanticLabel: label == 'Cover'
              ? 'Trail cover: ${image.name}'
              : 'Trail photo $label: ${image.name}',
          errorBuilder: (context, error, stackTrace) => ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: const Icon(Icons.broken_image_outlined),
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x66000000)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0x99000000),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: IconButton(
            tooltip: label == 'Cover'
                ? 'Remove cover image'
                : 'Remove image $label',
            onPressed: onRemove,
            icon: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Color(0x99000000),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 17,
                color: Colors.white,
              ),
            ),
            style: IconButton.styleFrom(minimumSize: const Size.square(44)),
          ),
        ),
      ],
    ),
  );
}

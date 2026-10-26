part of '../../caution_media_feature.dart';

/// Displays the caution media strip.
class CautionMediaStrip extends StatelessWidget {
  /// Creates caution media strip.
  const CautionMediaStrip({super.key, required this.media});
  final List<Map<String, dynamic>> media;

  /// Builds this widget from its current presentation state.
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

part of '../../community_post_management_page_feature.dart';

/// Displays the post photo strip.
class _PostPhotoStrip extends StatelessWidget {
  /// Creates post photo strip.
  const _PostPhotoStrip({required this.urls});
  final List<String> urls;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 156,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: urls.length,
      separatorBuilder: (_, index) => const SizedBox(width: 8),
      itemBuilder: (context, index) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Semantics(
          label: 'Post photo ${index + 1} of ${urls.length}. Tap to enlarge.',
          button: true,
          child: InkWell(
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Close photo',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                    Flexible(
                      child: InteractiveViewer(
                        child: Image.network(
                          urls[index],
                          fit: BoxFit.contain,
                          errorBuilder: (_, error, stack) => const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Photo preview unavailable'),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            child: Image.network(
              urls[index],
              width: 180,
              height: 156,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) => const SizedBox(
                width: 180,
                child: Center(child: Text('Photo preview unavailable')),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

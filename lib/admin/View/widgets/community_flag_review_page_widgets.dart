part of '../../community_flag_review_page_feature.dart';

/// Displays the section label.
class _SectionLabel extends StatelessWidget {
  /// Creates section label.
  const _SectionLabel(this.text);
  final String text;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) =>
      SectionLabel(label: text, padding: EdgeInsets.zero);
}

/// Displays the content card.
class _ContentCard extends StatelessWidget {
  /// Creates content card.
  const _ContentCard({
    required this.title,
    required this.data,
    required this.isComment,
    this.compact = false,
  });
  final String title;
  final Map<String, dynamic> data;
  final bool isComment, compact;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final author = data['author'];
    final name = author is Map
        ? _text(author['name'])
        : _text(data['authorName']);
    final handle = author is Map
        ? _text(author['handle'])
        : _text(data['authorHandle']);
    final body = _text(data[isComment ? 'body' : 'caption']);
    final urls =
        <String>[
              if (data['images'] is List)
                for (final image in data['images'] as List)
                  if (image is Map && image['url'] is String)
                    image['url'] as String,
              if (data['imageUrls'] is List)
                ...(data['imageUrls'] as List).whereType<String>(),
            ]
            .where((url) {
              final uri = Uri.tryParse(url);
              return uri != null &&
                  (uri.scheme == 'https' || uri.scheme == 'http') &&
                  uri.host.isNotEmpty;
            })
            .toSet()
            .toList();
    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(title),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: AdminUi.green(context).withValues(alpha: .1),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: AdminUi.green(context),
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? (handle.isEmpty ? 'Hiker' : handle) : name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (name.isNotEmpty && handle.isNotEmpty)
                      Text(
                        handle,
                        style: TextStyle(color: AdminUi.muted(context)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (!isComment && data['visibility'] is String) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: AdminTag(
                label: switch (data['visibility']) {
                  'public' => 'Public',
                  'hidden' => 'Hidden',
                  'removed' => 'Removed',
                  _ => 'Visibility unavailable',
                },
                icon: data['visibility'] == 'public'
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AdminUi.muted(context),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SelectableText(
            body.isEmpty
                ? (isComment ? 'No comment text available.' : 'No caption')
                : body,
            style: const TextStyle(height: 1.5),
          ),
          if (!isComment && urls.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '${urls.length} ${urls.length == 1 ? 'photo' : 'photos'} · Tap to enlarge',
              style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
            ),
            const SizedBox(height: 8),
            _PhotoStrip(urls: urls, compact: compact),
          ],
        ],
      ),
    );
  }
}

/// Displays the photo strip.
class _PhotoStrip extends StatelessWidget {
  /// Creates photo strip.
  const _PhotoStrip({required this.urls, required this.compact});
  final List<String> urls;
  final bool compact;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => SizedBox(
    height: compact ? 120 : 180,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: urls.length,
      separatorBuilder: (_, index) => const SizedBox(width: 8),
      itemBuilder: (context, index) => Semantics(
        button: true,
        label: 'Photo ${index + 1} of ${urls.length}. Tap to enlarge.',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: ValueKey('flag-photo-$index'),
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
              width: compact ? 150 : 220,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) => SizedBox(
                width: compact ? 150 : 220,
                child: const Center(child: Text('Photo preview unavailable')),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

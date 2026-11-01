import 'package:flutter/material.dart';

import '../../Model/shared_community_post.dart';

/// A linked Circle story preview inside a chat message.
class SharedCommunityPostCard extends StatelessWidget {
  /// Creates an accessible preview with a dedicated open action.
  const SharedCommunityPostCard({
    super.key,
    required this.post,
    required this.onOpen,
  });

  final SharedCommunityPost post;
  final VoidCallback onOpen;

  /// Presents the author, caption and trail in a compact, tappable surface.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const green = Color(0xFF438D62);
    return Material(
      color: dark ? const Color(0xFF16281E) : const Color(0xFFF4F8F3),
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.forum_outlined, size: 18, color: green),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'CIRCLE STORY',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                post.authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (post.caption.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  post.caption,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ],
              if (post.trailName.trim().isNotEmpty &&
                  post.trailName != 'Community') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.terrain_outlined, size: 16, color: green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        post.trailName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'View post',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 17,
                    color: green,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

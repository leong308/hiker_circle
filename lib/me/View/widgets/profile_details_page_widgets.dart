part of '../../profile_details_page_feature.dart';

/// Displays the header.
class _Header extends StatelessWidget {
  /// Creates header.
  const _Header({required this.onBack});

  final VoidCallback onBack;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
    child: PageHeader(title: 'Personal Profile', onBack: onBack),
  );
}

/// Displays the identity card.
class _IdentityCard extends StatelessWidget {
  /// Creates identity card.
  const _IdentityCard({
    required this.profile,
    this.photoBytes,
    this.onChangePhoto,
  });

  final OnboardingProfile profile;
  final Uint8List? photoBytes;
  final VoidCallback? onChangePhoto;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final username = profile.username.trim().isEmpty
        ? 'Trail Friend'
        : profile.username.trim();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _ProfileColors.heroGradientFor(context),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x243F8F5E),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onChangePhoto,
            child: Stack(
              children: [
                Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.36),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(39),
                    child: photoBytes != null && photoBytes!.isNotEmpty
                        ? Image.memory(
                            photoBytes!,
                            width: 78,
                            height: 78,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  CupertinoIcons.person_fill,
                                  color: Colors.white,
                                  size: 40,
                                ),
                          )
                        : profile.photoURL != null
                        ? Image.network(
                            profile.photoURL!,
                            width: 78,
                            height: 78,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  CupertinoIcons.person_fill,
                                  color: Colors.white,
                                  size: 40,
                                ),
                          )
                        : const Icon(
                            CupertinoIcons.person_fill,
                            color: Colors.white,
                            size: 40,
                          ),
                  ),
                ),
                if (onChangePhoto != null)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF3F8F5E),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        CupertinoIcons.camera_fill,
                        size: 13,
                        color: Color(0xFF3F8F5E),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
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

/// Displays the detail row.
class _DetailRow extends StatelessWidget {
  /// Creates detail row.
  const _DetailRow({required this.detail});

  final _ProfileDetail detail;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _ProfileColors.greenSoftFor(context),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(detail.icon, color: _ProfileColors.green, size: 18),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _ProfileColors.secondaryTextFor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail.value,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _ProfileColors.textFor(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (detail.onEdit != null) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: detail.onEdit,
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('Edit'),
            ),
          ],
        ],
      ),
    );
  }
}

part of '../../group_chat_detail_page_feature.dart';

/// Displays the hike info card.
class _HikeInfoCard extends StatelessWidget {
  /// Creates hike info card.
  const _HikeInfoCard({
    required this.hike,
    required this.isDark,
    required this.onTap,
  });

  final UpcomingHike hike;
  final bool isDark;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final dateStr = '${hike.departureTime.day}/${hike.departureTime.month}';
    final timeStr =
        '${hike.departureTime.hour.toString().padLeft(2, '0')}:${hike.departureTime.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: _surfaceFor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _green.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: _green.withValues(alpha: isDark ? 0.08 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _greenSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.hiking_rounded,
                    color: _green,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hike.trailName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: _textFor(context),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 12,
                            color: _secondaryTextFor(context),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$dateStr · $timeStr',
                            style: TextStyle(
                              fontSize: 12,
                              color: _secondaryTextFor(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.people_rounded,
                            size: 12,
                            color: _secondaryTextFor(context),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${hike.participantCount}',
                            style: TextStyle(
                              fontSize: 12,
                              color: _secondaryTextFor(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: _secondaryTextFor(context),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the empty state.
class _EmptyState extends StatelessWidget {
  /// Creates empty state.
  const _EmptyState({required this.isDark});
  final bool isDark;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _greenSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chat_rounded, color: _green, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              color: isDark ? const Color(0xFFEAF4EE) : const Color(0xFF111111),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Say something to start the conversation!',
            style: TextStyle(
              color: isDark ? const Color(0xFFA8B8AE) : const Color(0xFF6E6E73),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the system message pill.
class _SystemMessagePill extends StatelessWidget {
  /// Creates system message pill.
  const _SystemMessagePill({required this.message, required this.isDark});
  final ChatMessage message;
  final bool isDark;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: isDark ? 0.15 : 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_add_rounded, size: 14, color: _green),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${privateChatLabel(message.senderName)} just joined!',
                  style: TextStyle(
                    color: _green,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the attachment file tile.
class _AttachmentFileTile extends StatelessWidget {
  /// Creates attachment file tile.
  const _AttachmentFileTile({
    required this.attachment,
    required this.icon,
    required this.isMe,
    this.label,
  });

  final ChatAttachment attachment;
  final IconData icon;
  final bool isMe;
  final String? label;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: isMe
          ? Colors.white.withValues(alpha: 0.14)
          : Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => unawaited(_openExternalUrl(attachment.url)),
        child: SizedBox(
          width: 230,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(icon, color: isMe ? Colors.white : _green, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isMe ? Colors.white : _textFor(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label ?? _fileSizeLabel(attachment.sizeBytes),
                        style: TextStyle(
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.7)
                              : _secondaryTextFor(context),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 16,
                  color: isMe
                      ? Colors.white.withValues(alpha: 0.8)
                      : _secondaryTextFor(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the file list tile.
class _FileListTile extends StatelessWidget {
  /// Creates file list tile.
  const _FileListTile({
    required this.icon,
    required this.fileName,
    required this.subtitle,
    required this.senderName,
    required this.sentAt,
    required this.onTap,
    required this.isDark,
  });

  final IconData icon;
  final String fileName;
  final String subtitle;
  final String senderName;
  final DateTime sentAt;
  final VoidCallback onTap;
  final bool isDark;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _green, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFFEAF4EE)
                            : const Color(0xFF111111),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _secondaryTextFor(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTime(sentAt),
                style: TextStyle(
                  color: _secondaryTextFor(context),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Formats time.
  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${dt.day}/${dt.month}';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

/// Displays the participant card.
class _ParticipantCard extends StatelessWidget {
  /// Creates participant card.
  const _ParticipantCard({
    required this.phone,
    required this.isYou,
    required this.username,
    this.onReminder,
  });

  final VoidCallback? onReminder;
  final String phone;
  final bool isYou;
  final String username;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayName = isYou && username.isNotEmpty
        ? username
        : maskPhoneNumber(phone);
    final subtitle = isYou && username.isNotEmpty
        ? maskPhoneNumber(phone)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B261F) : const Color(0xFFF5F7F5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _greenSoft,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                style: TextStyle(
                  color: _green,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: _textFor(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: _secondaryTextFor(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (onReminder != null)
            TextButton.icon(
              onPressed: onReminder,
              icon: const Icon(Icons.notifications_active_outlined, size: 16),
              label: const Text('Send reminder now'),
            ),
          if (isYou)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'You',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _green,
                ),
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
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _green),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: _secondaryTextFor(context)),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _textFor(context),
          ),
        ),
      ],
    );
  }
}

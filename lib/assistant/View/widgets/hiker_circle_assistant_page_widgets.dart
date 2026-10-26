part of '../../hiker_circle_assistant_page_feature.dart';

/// Displays the assistant intro card.
class _AssistantIntroCard extends StatelessWidget {
  /// Creates assistant intro card.
  const _AssistantIntroCard({
    required this.surface,
    required this.text,
    required this.secondary,
    required this.separator,
  });

  final Color surface;
  final Color text;
  final Color secondary;
  final Color separator;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: separator),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _HikerCircleAssistantPageState._green.withValues(
                    alpha: 0.14,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: _HikerCircleAssistantPageState._green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'App help, not an open chatbot',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Reviewed app guides · chat synced to your account',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _HikerCircleAssistantPageState._green.withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'GUIDES',
                  style: TextStyle(
                    color: _HikerCircleAssistantPageState._green,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Free-tier questions may be reviewed by Google. Do not enter names, phone numbers, email addresses, verification codes, precise coordinates, or medical details. For an active emergency, call 999 or 112.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: secondary, height: 1.4),
          ),
        ],
      ),
    );
  }
}

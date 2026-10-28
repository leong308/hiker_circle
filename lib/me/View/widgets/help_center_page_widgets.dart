part of '../../help_center_page_feature.dart';

/// Displays the help overview row.
class _HelpOverviewRow extends StatelessWidget {
  /// Creates help overview row.
  const _HelpOverviewRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String count;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? const Color(0xFFEAF4EE) : const Color(0xFF111111);
    final secondary = dark ? const Color(0xFFA8B8AE) : const Color(0xFF6E6E73);
    return Material(
      color: _surface(context),
      borderRadius: BorderRadius.circular(17),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surface(context),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: _green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TextStyle(color: secondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    count,
                    style: const TextStyle(
                      color: _green,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: _green,
                    size: 18,
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

/// Displays the help topic card.
class _HelpTopicCard extends StatelessWidget {
  /// Creates help topic card.
  const _HelpTopicCard({
    required this.index,
    required this.article,
    required this.meta,
    required this.expanded,
    required this.reviewed,
    required this.selected,
  });

  final int index;
  final HelpArticle article;
  final _HelpStepMeta meta;
  final bool expanded;
  final bool reviewed;
  final bool selected;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? const Color(0xFFEAF4EE) : const Color(0xFF111111);
    final border = dark ? const Color(0xFF2B3A31) : const Color(0xFFD9E1DC);
    return Material(
      key: ValueKey('plan-step-card-$index'),
      color: _surface(context),
      borderRadius: BorderRadius.circular(19),
      clipBehavior: Clip.antiAlias,
      child: AnimatedContainer(
        duration: _helpAnimation(context, 220),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          border: Border.all(
            color: selected ? _green.withValues(alpha: 0.7) : border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            InkWell(
              key: ValueKey('plan-step-toggle-$index'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(15, 14, 12, 14),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: reviewed
                            ? _green
                            : _green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: reviewed
                          ? const Icon(Icons.check_rounded, color: Colors.white)
                          : Icon(meta.icon, color: _green),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${meta.stage.toUpperCase()} · STEP ${index + 1}',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: _green,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.45,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            meta.eyebrow,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: text.withValues(alpha: 0.66)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            article.title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: text,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Divider(color: border, height: 1),
                    const SizedBox(height: 14),
                    Text(
                      article.text,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: text,
                        height: 1.52,
                      ),
                    ),
                    if (article.location != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _green.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.near_me_outlined,
                              color: _green,
                              size: 18,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                article.location!,
                                style: TextStyle(
                                  color: text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (article.actions.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'What to do',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      for (
                        var action = 0;
                        action < article.actions.length;
                        action++
                      )
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _green.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${action + 1}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _green,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  article.actions[action],
                                  style: TextStyle(color: text, height: 1.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    if (article.tip != null) ...[
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: text.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              article.tip!,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: text.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: _helpAnimation(context, 240),
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the help card.
class _HelpCard extends StatelessWidget {
  /// Creates help card.
  const _HelpCard({required this.child});
  final Widget child;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Material(
    color: _surface(context),
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

part of '../community_moderation_rules_feature.dart';

/// Keeps the popup focused on keywords and patterns from the shared catalog.
class _ModerationRulesSheet extends StatelessWidget {
  /// Opens with keyword matching selected and all category drawers collapsed.
  const _ModerationRulesSheet();

  /// Keeps the title, close control and tabs visible above scrollable categories.
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Moderation rules',
                    style: PageHeaderStyle.title(
                      context,
                      Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                PageHeaderAction(
                  tooltip: 'Close moderation rules',
                  icon: Icons.close_rounded,
                  onPressed: () => Navigator.pop(context),
                  color: AdminUi.green(context),
                  surface: AdminUi.surface(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TabBar(
              labelColor: AdminUi.green(context),
              unselectedLabelColor: AdminUi.muted(context),
              indicatorColor: AdminUi.green(context),
              dividerColor: AdminUi.border(context),
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              tabs: const [
                Tab(text: 'Keywords'),
                Tab(text: 'Patterns'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _MatchingCategoryList(showPatterns: false),
                _MatchingCategoryList(showPatterns: true),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Presents only category names and their matching terms, without explanatory copy.
class _MatchingCategoryList extends StatelessWidget {
  /// Reuses one layout for keyword phrases and authored pattern names.
  const _MatchingCategoryList({required this.showPatterns});
  final bool showPatterns;

  /// Groups the catalog's terms in independently scrollable category drawers.
  @override
  Widget build(BuildContext context) {
    final sections = CommunityModerationPolicy.categories
        .map(
          (category) => (
            category: category,
            terms: showPatterns
                ? CommunityModerationPolicy.patterns
                      .where((pattern) => pattern['category'] == category.label)
                      .map((pattern) => pattern['label']!)
                      .toList(growable: false)
                : category.keywords,
          ),
        )
        .where((section) => section.terms.isNotEmpty)
        .toList(growable: false);
    final group = showPatterns ? 'patterns' : 'keywords';
    return ListView.separated(
      key: PageStorageKey('moderation-$group-list'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final section = sections[index];
        return AdminPanel(
          padding: EdgeInsets.zero,
          child: ExpansionTile(
            key: PageStorageKey('moderation-$group-${section.category.id}'),
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              section.category.label,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final term in section.terms)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AdminUi.green(context).withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          term,
                          style: TextStyle(color: AdminUi.green(context)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

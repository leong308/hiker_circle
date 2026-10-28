part of '../../me_page_feature.dart';

/// Displays the header.
class _Header extends StatelessWidget {
  /// Creates header.
  const _Header({
    required this.profile,
    required this.onShowQr,
    required this.onOpenScanner,
    required this.onOpenSettings,
  });

  final MeProfile profile;
  final VoidCallback onShowQr;
  final VoidCallback onOpenScanner;
  final VoidCallback onOpenSettings;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile',
                  style: PageHeaderStyle.title(
                    context,
                    _MeColors.textFor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Welcome back, ${profile.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PageHeaderStyle.subtitle(
                    context,
                    _MeColors.secondaryTextFor(context),
                  ),
                ),
              ],
            ),
          ),
          _HeaderAction(
            tooltip: 'QR code',
            icon: Icons.qr_code_rounded,
            onPressed: onShowQr,
          ),
          const SizedBox(width: 8),
          _HeaderAction(
            tooltip: 'Scan QR',
            icon: Icons.qr_code_scanner_rounded,
            onPressed: onOpenScanner,
          ),
          const SizedBox(width: 8),
          _HeaderAction(
            tooltip: 'Settings',
            icon: CupertinoIcons.gear_alt_fill,
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

/// Displays the detail header.
class _DetailHeader extends StatelessWidget {
  /// Creates detail header.
  const _DetailHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) =>
      PageHeader(title: title, subtitle: subtitle, onBack: onBack);
}

/// Displays the profile history card.
class _ProfileHistoryCard extends StatelessWidget {
  /// Creates profile history card.
  const _ProfileHistoryCard({required this.item});

  final _ProfileHistoryItem item;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(icon: item.icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _MeColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _MeColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _MiniPill(label: item.meta),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the achievements summary card.
class _AchievementsSummaryCard extends StatelessWidget {
  /// Creates achievements summary card.
  const _AchievementsSummaryCard({
    required this.achievementsFuture,
    required this.onTap,
  });

  final Future<List<Map<String, dynamic>>> achievementsFuture;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: achievementsFuture,
      builder: (context, snapshot) {
        final isLoading =
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;
        final items = _achievementItemsFromRows(snapshot.data ?? const []);
        final unlocked = items.where((item) => item.isUnlocked).length;
        final total = items.isEmpty ? 0 : items.length;
        final progress = total == 0 ? 0.0 : unlocked / total;
        final points = items
            .where((item) => item.isUnlocked)
            .fold<int>(0, (total, item) => total + item.pointsAwarded);
        final level = HikerLevel.fromPoints(points);
        final locked = items.where((item) => !item.isUnlocked).toList();
        final subtitle = isLoading
            ? 'Your hiking milestones'
            : locked.isEmpty && total > 0
            ? 'All current badges unlocked'
            : locked.isEmpty
            ? 'Track your hike milestones'
            : 'Next: ${locked.first.title}';

        return _InsetGroup(
          child: _TapSurface(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 64,
                    child: FittedBox(
                      child: _AchievementLevelMedallion(
                        level: level.number,
                        onTap: () => _showHikerLevelRoadmap(context, points),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Achievements',
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: _MeColors.textFor(context),
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          total == 0
                              ? subtitle
                              : '$unlocked of $total unlocked - $subtitle',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _MeColors.secondaryTextFor(context),
                                letterSpacing: 0,
                              ),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 7,
                            backgroundColor: _MeColors.greenSoftFor(context),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              _MeColors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    color: _MeColors.chevronFor(context),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Displays the achievement header button.
class _AchievementHeaderButton extends StatelessWidget {
  /// Creates achievement header button.
  const _AchievementHeaderButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => PageHeaderAction(
    tooltip: tooltip,
    icon: icon,
    onPressed: onPressed,
    color: _MeColors.green,
    surface: _MeColors.surfaceFor(context),
  );
}

/// Displays the achievement tab label.
class _AchievementTabLabel extends StatelessWidget {
  /// Creates achievement tab label.
  const _AchievementTabLabel({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? Colors.white
                  : _MeColors.secondaryTextFor(context),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? Colors.white : _MeColors.textFor(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the achievement period button.
class _AchievementPeriodButton extends StatelessWidget {
  /// Creates achievement period button.
  const _AchievementPeriodButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: selected ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? _MeColors.green.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _MeColors.green.withValues(alpha: 0.38)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected
                  ? (_MeColors.isDark(context)
                        ? const Color(0xFF8CE7A8)
                        : const Color(0xFF16743A))
                  : _MeColors.secondaryTextFor(context),
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the achievement leaderboard card.
class _AchievementLeaderboardCard extends StatelessWidget {
  /// Creates achievement leaderboard card.
  const _AchievementLeaderboardCard({
    required this.period,
    required this.entries,
    required this.isLoading,
    required this.onPeriodChanged,
    required this.onTitleTap,
    required this.onExitPreview,
    required this.isPreview,
  });

  final String period;
  final List<Map<String, dynamic>> entries;
  final bool isLoading;
  final ValueChanged<String> onPeriodChanged;
  final VoidCallback onTitleTap;
  final VoidCallback onExitPreview;
  final bool isPreview;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _AchievementGlassSurface(
      blur: true,
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _AchievementSectionGlyph(icon: Icons.leaderboard_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: onTitleTap,
                      child: Text(
                        'Hiker leaderboard',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _MeColors.textFor(context),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    Text(
                      'Points earned during the selected period',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _MeColors.secondaryTextFor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isPreview)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Preview · 50 sample hikers'),
              subtitle: const Text('Temporary data for this visit only'),
              trailing: TextButton(
                onPressed: onExitPreview,
                child: const Text('Exit'),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _MeColors.backgroundFor(context).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                _AchievementPeriodButton(
                  label: 'This month',
                  selected: period == 'month',
                  onTap: () => onPeriodChanged('month'),
                ),
                _AchievementPeriodButton(
                  label: 'This year',
                  selected: period == 'year',
                  onTap: () => onPeriodChanged('year'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (isLoading)
            const Center(child: HikerCircleMinorLoadingIndicator(size: 72))
          else if (entries.isEmpty)
            Text(
              'No achievement points have been earned in this period yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _MeColors.secondaryTextFor(context)),
            )
          else ...[
            _AchievementPodium(entries: entries.take(3).toList()),
            const SizedBox(height: 20),
            Text('Top 10', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            for (final entry in entries.take(10)) ...[
              _AchievementLeaderboardRow(
                rank: entry['rank'],
                displayName: entry['displayName']?.toString() ?? 'Hiker',
                points: entry['points'],
                isCurrentUser: entry['isCurrentUser'] == true,
                margin: const EdgeInsets.only(bottom: 7),
              ),
            ],
            for (final entry in entries.where(
              (entry) =>
                  entry['isCurrentUser'] == true &&
                  (int.tryParse('${entry['rank']}') ?? 0) > 10,
            )) ...[
              const Divider(height: 28),
              Text(
                'Your ranking',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              _AchievementLeaderboardRow(
                rank: entry['rank'],
                displayName: entry['displayName']?.toString() ?? 'You',
                points: entry['points'],
                isCurrentUser: true,
                margin: EdgeInsets.zero,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Displays the achievement leaderboard row.
class _AchievementLeaderboardRow extends StatelessWidget {
  /// Creates achievement leaderboard row.
  const _AchievementLeaderboardRow({
    required this.rank,
    required this.displayName,
    required this.points,
    required this.isCurrentUser,
    required this.margin,
  });

  final Object? rank;
  final String displayName;
  final Object? points;
  final bool isCurrentUser;
  final EdgeInsets margin;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final rankNumber = int.tryParse('$rank');
    final medalColor = switch (rankNumber) {
      1 => const Color(0xFFFFC857),
      2 => const Color(0xFFB9C2CE),
      3 => const Color(0xFFC98955),
      _ => _MeColors.secondaryTextFor(context),
    };
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? _MeColors.green.withValues(alpha: 0.14)
            : Colors.white.withValues(
                alpha: _MeColors.isDark(context) ? 0.035 : 0.48,
              ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isCurrentUser
              ? _MeColors.green.withValues(alpha: 0.32)
              : Colors.white.withValues(
                  alpha: _MeColors.isDark(context) ? 0.07 : 0.7,
                ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: medalColor.withValues(alpha: 0.16),
            ),
            child: Text(
              '${rankNumber ?? '-'}',
              style: TextStyle(
                color: medalColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _MeColors.textFor(context),
                fontWeight: isCurrentUser ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          if (isCurrentUser) ...[
            const _AchievementTag(label: 'You', compact: true),
            const SizedBox(width: 8),
          ],
          Text(
            '${points ?? 0} pts',
            style: const TextStyle(
              color: _MeColors.green,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the achievement progress panel.
class _AchievementProgressPanel extends StatelessWidget {
  /// Creates achievement progress panel.
  const _AchievementProgressPanel({required this.items});

  final List<_AchievementProfileItem> items;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final earned = items.where((item) => item.isUnlocked).toList();
    final locked = items.length - earned.length;
    final points = earned.fold<int>(
      0,
      (total, item) => total + item.pointsAwarded,
    );
    final level = HikerLevel.fromPoints(points);
    final nextLevelName = level.nextLevelPoints == null
        ? 'Peak rank reached'
        : HikerLevel.tiers[level.number].name;
    final remaining = level.pointsToNextLevel(points);
    return _AchievementGlassSurface(
      blur: true,
      radius: 30,
      padding: EdgeInsets.zero,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xEE0B3323), Color(0xE61A6A40), Color(0xDC37A95C)],
        stops: [0, 0.55, 1],
      ),
      borderColor: Colors.white24,
      shadowColor: const Color(0xFF249A51).withValues(alpha: 0.3),
      child: Stack(
        children: [
          const Positioned(
            right: -35,
            top: -45,
            child: _AchievementHeroOrb(size: 170),
          ),
          Positioned(
            left: -50,
            bottom: -80,
            child: _AchievementHeroOrb(
              size: 190,
              color: const Color(0xFFFFD166).withValues(alpha: 0.12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'YOUR TRAIL JOURNEY',
                  style: TextStyle(
                    color: Color(0xFFC8F3D6),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.9,
                  ),
                ),
                const SizedBox(height: 13),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final badge = _AchievementLevelMedallion(
                      level: level.number,
                      onTap: () => _showHikerLevelRoadmap(context, points),
                    );
                    final details = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          level.name,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          level.nextLevelPoints == null
                              ? 'You have reached the highest trail rank'
                              : '$remaining points until $nextLevelName',
                          style: const TextStyle(
                            color: Color(0xFFD9F4E2),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Tap badge to view all levels',
                                style: TextStyle(
                                  color: Color(0xFFB8EDC9),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(width: 3),
                            Icon(
                              CupertinoIcons.chevron_forward,
                              color: Color(0xFFB8EDC9),
                              size: 10,
                            ),
                          ],
                        ),
                      ],
                    );
                    if (constraints.maxWidth < 300 &&
                        MediaQuery.textScalerOf(context).scale(14) > 18) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [badge, const SizedBox(height: 14), details],
                      );
                    }
                    return Row(
                      children: [
                        badge,
                        const SizedBox(width: 16),
                        Expanded(child: details),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 22),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      level.nextLevelPoints == null
                          ? 'Peak achieved'
                          : 'Progress to $nextLevelName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      level.nextLevelPoints == null
                          ? '$points pts'
                          : '$points / ${level.nextLevelPoints}',
                      style: const TextStyle(
                        color: Color(0xFFFFE297),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 10,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06170E).withValues(alpha: 0.38),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: level.progressFor(points),
                      backgroundColor: Colors.transparent,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFFFD166),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _AchievementMetric(
                        icon: Icons.workspace_premium_rounded,
                        label: 'Earned',
                        value: '${earned.length}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AchievementMetric(
                        icon: Icons.lock_outline_rounded,
                        label: 'Locked',
                        value: '$locked',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AchievementMetric(
                        icon: Icons.auto_awesome_rounded,
                        label: 'Points',
                        value: '$points',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the hiker level roadmap row.
class _HikerLevelRoadmapRow extends StatelessWidget {
  /// Creates hiker level roadmap row.
  const _HikerLevelRoadmapRow({
    required this.level,
    required this.currentLevel,
    required this.points,
    required this.selected,
    required this.onTap,
  });
  final HikerLevel level;
  final HikerLevel currentLevel;
  final int points;
  final bool selected;
  final VoidCallback onTap;

  static const _icons = [
    CupertinoIcons.leaf_arrow_circlepath,
    CupertinoIcons.compass,
    Icons.hiking_rounded,
    Icons.landscape_rounded,
    CupertinoIcons.map,
    CupertinoIcons.shield,
    CupertinoIcons.rosette,
  ];
  static const _descriptions = [
    'Every journey starts here. Discover the badges you can earn on your first hikes.',
    'Build your hiking rhythm and turn your early adventures into lasting progress.',
    'Keep exploring trails and completing achievement goals as your experience grows.',
    'Celebrate the milestones collected along your journey toward new summits.',
    'Bring together the points earned through exploration, consistency, and community.',
    'Acknowledge a sustained commitment to hiking and the milestones along the way.',
    'The highest hiker rank celebrates your accumulated achievement points.',
  ];

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final reached = points >= level.minimumPoints;
    final isCurrent = level.number == currentLevel.number;
    final range = level.nextLevelPoints == null
        ? '${_formatRankPoints(level.minimumPoints)}+ points'
        : '${_formatRankPoints(level.minimumPoints)}–${_formatRankPoints(level.nextLevelPoints! - 1)} points';
    final foreground = _MeColors.textFor(context);
    final secondary = _MeColors.secondaryTextFor(context);
    return AnimatedContainer(
      key: ValueKey('hiker-level-card-${level.number}'),
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected
            ? _MeColors.green.withValues(alpha: 0.07)
            : _MeColors.backgroundFor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? _MeColors.green.withValues(alpha: 0.5)
              : _MeColors.separatorFor(context),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Semantics(
              selected: selected,
              button: true,
              child: InkWell(
                key: ValueKey('trail-level-${level.number}'),
                borderRadius: BorderRadius.circular(20),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: _MeColors.green.withValues(
                            alpha: reached ? 0.14 : 0.06,
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          _icons[level.number - 1],
                          color: reached ? _MeColors.green : secondary,
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Level ${level.number} · ${level.name}',
                              style: TextStyle(
                                color: foreground,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              range,
                              style: TextStyle(color: secondary, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isCurrent
                                  ? 'Current level'
                                  : reached
                                  ? 'Completed'
                                  : 'Locked',
                              style: TextStyle(
                                color: reached ? _MeColors.green : secondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        reached
                            ? Icons.check_circle_outline_rounded
                            : Icons.lock_outline_rounded,
                        size: 15,
                        color: secondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Divider(
                            color: _MeColors.separatorFor(context),
                            height: 16,
                          ),
                          Text(
                            _descriptions[level.number - 1],
                            style: TextStyle(color: secondary, height: 1.5),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Unlocks at ${_formatRankPoints(level.minimumPoints)} points',
                            style: TextStyle(
                              color: foreground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            reached
                                ? 'You have reached this milestone.'
                                : '${_formatRankPoints(level.minimumPoints - points)} more points to unlock',
                            style: TextStyle(color: secondary),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: level.minimumPoints == 0
                                  ? 1
                                  : (points / level.minimumPoints).clamp(
                                      0.0,
                                      1.0,
                                    ),
                              minHeight: 5,
                              color: _MeColors.green,
                              backgroundColor: _MeColors.green.withValues(
                                alpha: 0.12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Earn points by completing the goals listed on achievement badges.',
                            style: TextStyle(
                              color: secondary,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the achievement metric.
class _AchievementMetric extends StatelessWidget {
  /// Creates achievement metric.
  const _AchievementMetric({
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFFB8EDC9), size: 17),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFFC8F3D6),
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the achievement badge card.
class _AchievementBadgeCard extends StatelessWidget {
  /// Creates achievement badge card.
  const _AchievementBadgeCard({required this.item, required this.onTap});

  final _AchievementProfileItem item;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final accent = item.accentColor;
    final displayAccent = item.isUnlocked
        ? accent
        : Color.lerp(accent, _MeColors.secondaryTextFor(context), 0.48)!;
    final remaining = (item.targetCount - item.progressCount).clamp(
      0,
      item.targetCount,
    );

    return _AchievementGlassSurface(
      radius: 25,
      padding: EdgeInsets.zero,
      accent: displayAccent,
      child: _TapSurface(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _AchievementTag(
                        label: item.category.toUpperCase(),
                        accent: displayAccent,
                        compact: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    item.isUnlocked
                        ? CupertinoIcons.checkmark_seal_fill
                        : CupertinoIcons.lock_fill,
                    color: displayAccent,
                    size: 17,
                  ),
                ],
              ),
              const Spacer(),
              Center(
                child: _AchievementBadge(
                  icon: _achievementIconFor(item.iconName),
                  color: displayAccent,
                  unlocked: item.isUnlocked,
                  size: 76,
                ),
              ),
              const Spacer(),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: _MeColors.textFor(context),
                  fontWeight: FontWeight.w900,
                  height: 1.13,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 9),
              if (item.isCumulative && !item.isUnlocked) ...[
                Container(
                  height: 7,
                  padding: const EdgeInsets.all(1.2),
                  decoration: BoxDecoration(
                    color: displayAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: item.progress,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(displayAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$remaining left',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _MeColors.secondaryTextFor(context),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    Text(
                      '${item.progressCount}/${item.targetCount}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: displayAccent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ] else
                Text(
                  item.isUnlocked
                      ? (item.awardedAt == null
                            ? 'Earned · ${item.pointsAwarded} pts'
                            : '${_formatAchievementDate(item.awardedAt!)} · ${item.pointsAwarded} pts')
                      : 'One hike · ${item.rewardPoints} pts',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: displayAccent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the achievement badge.
class _AchievementBadge extends StatelessWidget {
  /// Creates achievement badge.
  const _AchievementBadge({
    required this.icon,
    required this.color,
    required this.unlocked,
    this.size = 62,
    this.showShadow = true,
  });

  final IconData icon;
  final Color color;
  final bool unlocked;
  final double size;
  final bool showShadow;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: unlocked ? 0.95 : 0.5),
            color.withValues(alpha: 0.15),
          ],
        ),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: color.withValues(alpha: unlocked ? 0.28 : 0.1),
                  blurRadius: 17,
                  offset: const Offset(0, 7),
                ),
              ]
            : const [],
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _MeColors.surfaceFor(context).withValues(alpha: 0.88),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, color: color, size: size * 0.43),
            if (!unlocked)
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _MeColors.surfaceFor(context),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.35)),
                  ),
                  child: Icon(Icons.lock_rounded, color: color, size: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Displays the achievement detail section.
class _AchievementDetailSection extends StatelessWidget {
  /// Creates achievement detail section.
  const _AchievementDetailSection({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color accent;
  final String? footer;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded:
          title == 'Your goal' || title == 'Why this achievement exists',
      maintainState: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
      shape: Border(bottom: BorderSide(color: _MeColors.separatorFor(context))),
      collapsedShape: Border(
        bottom: BorderSide(color: _MeColors.separatorFor(context)),
      ),
      leading: Icon(icon, color: accent, size: 22),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            body,
            style: TextStyle(
              color: _MeColors.secondaryTextFor(context),
              height: 1.5,
            ),
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              footer!,
              style: TextStyle(color: accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }
}

/// Displays the achievement notice card.
class _AchievementNoticeCard extends StatelessWidget {
  /// Creates achievement notice card.
  const _AchievementNoticeCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _AchievementGlassSurface(
      radius: 20,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AchievementSectionGlyph(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _MeColors.textFor(context),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _MeColors.secondaryTextFor(context),
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

/// Displays the achievement loading card.
class _AchievementLoadingCard extends StatelessWidget {
  /// Creates achievement loading card.
  const _AchievementLoadingCard();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return const _AchievementGlassSurface(
      radius: 22,
      padding: EdgeInsets.zero,
      child: HikerCircleLoadingView(
        message: 'Loading achievements…',
        detail: 'Checking your progress, levels and unlocked badges.',
        padding: EdgeInsets.all(18),
      ),
    );
  }
}

/// Displays the choice setting card.
class _ChoiceSettingCard extends StatelessWidget {
  /// Creates choice setting card.
  const _ChoiceSettingCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final IconData icon;
  final String title;
  final String value;
  final List<String> options;
  final ValueChanged<String> onSelected;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Glyph(icon: icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _MeColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                _MiniPill(label: value),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in options)
                  ChoiceChip(
                    label: Text(option),
                    selected: value == option,
                    onSelected: (_) => onSelected(option),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the time zone setting card.
class _TimeZoneSettingCard extends StatelessWidget {
  /// Creates time zone setting card.
  const _TimeZoneSettingCard({
    required this.value,
    required this.timeZoneId,
    required this.status,
    required this.isBusy,
    required this.onTap,
  });

  final String value;
  final String timeZoneId;
  final String status;
  final bool isBusy;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isBusy ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Glyph(icon: Icons.schedule_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SOS message timezone',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _MeColors.textFor(context),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _MeColors.green,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                      Text(
                        timeZoneId,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _MeColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        status,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _MeColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (isBusy)
                  const SizedBox.square(
                    dimension: 20,
                    child: HikerCircleMinorLoadingIndicator(strokeWidth: 2.2),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: _MeColors.chevronFor(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the switch setting card.
class _SwitchSettingCard extends StatelessWidget {
  /// Creates switch setting card.
  const _SwitchSettingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _MeColors.textFor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _MeColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _AnimatedBooleanToggle(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Displays the settings section.
class _SettingsSection extends StatelessWidget {
  /// Creates settings section.
  const _SettingsSection({
    required this.section,
    required this.onItemTap,
    required this.countForTitle,
  });

  final MeSection section;
  final ValueChanged<MeActionItem> onItemTap;
  final String? Function(String title) countForTitle;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          label: section.title,
          padding: const EdgeInsets.only(left: 14, bottom: 7),
        ),
        _InsetGroup(
          child: Column(
            children: [
              for (var index = 0; index < section.items.length; index++) ...[
                _SettingsCell(
                  item: section.items[index],
                  onTap: () => onItemTap(section.items[index]),
                  countLabel: countForTitle(section.items[index].title),
                ),
                if (index != section.items.length - 1)
                  const Padding(
                    padding: EdgeInsets.only(left: 58),
                    child: _HorizontalSeparator(),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Displays the mini pill.
class _MiniPill extends StatelessWidget {
  /// Creates mini pill.
  const _MiniPill({required this.label});

  final String label;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _MeColors.greenSoftFor(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _MeColors.green,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

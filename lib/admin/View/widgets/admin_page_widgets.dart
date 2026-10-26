part of '../../admin_page_feature.dart';

/// Displays the admin header.
class _AdminHeader extends StatelessWidget {
  /// Creates admin header.
  const _AdminHeader({
    required this.title,
    required this.subtitle,
    required this.isLoading,
    required this.onRefresh,
    this.onBack,
    this.backTooltip = 'Back to admin dashboard',
  });
  final String title, subtitle;
  final bool isLoading;
  final VoidCallback onRefresh;
  final VoidCallback? onBack;
  final String backTooltip;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
    child: Row(
      children: [
        if (onBack != null) ...[
          PageHeaderAction(
            tooltip: backTooltip,
            icon: Icons.arrow_back_rounded,
            onPressed: onBack,
            color: _AdminColors.greenFor(context),
            surface: _AdminColors.surfaceFor(context),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: PageHeaderStyle.title(
                  context,
                  _AdminColors.textFor(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: PageHeaderStyle.subtitle(
                  context,
                  _AdminColors.secondaryTextFor(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        PageHeaderAction(
          tooltip: 'Refresh admin data',
          icon: Icons.refresh_rounded,
          onPressed: isLoading ? null : onRefresh,
          color: _AdminColors.greenFor(context),
          surface: _AdminColors.surfaceFor(context),
        ),
      ],
    ),
  );
}

/// Displays the admin dashboard card.
class _AdminDashboardCard extends StatelessWidget {
  /// Creates admin dashboard card.
  const _AdminDashboardCard({
    required this.title,
    required this.subtitle,
    required this.metric,
    required this.detail,
    required this.icon,
    required this.onTap,
  });
  final String title, subtitle, metric, detail;
  final IconData icon;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => AdminPanel(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AdminUi.blue(context).withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AdminUi.blue(context), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AdminUi.muted(context),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: AdminUi.muted(context),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AdminTag(label: metric, color: AdminUi.blue(context)),
            Text(
              detail,
              style: TextStyle(color: AdminUi.muted(context), fontSize: 11),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Displays the hazard reports section.
class _HazardReportsSection extends StatelessWidget {
  /// Creates hazard reports section.
  const _HazardReportsSection({
    required this.hazardReports,
    required this.isSaving,
    required this.onApprove,
    required this.onReject,
  });

  final List<Map<String, dynamic>> hazardReports;
  final bool isSaving;
  final ValueChanged<Map<String, dynamic>> onApprove;
  final ValueChanged<Map<String, dynamic>> onReject;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(label: 'Hazard Reports'),
        const SizedBox(height: 8),
        Column(
          children: [
            if (hazardReports.isEmpty)
              const _EmptyState(message: 'No hazard reports to review.')
            else
              for (var index = 0; index < hazardReports.length; index++) ...[
                AdminPanel(
                  padding: EdgeInsets.zero,
                  child: _HazardAdminRow(
                    report: hazardReports[index],
                    isSaving: isSaving,
                    onApprove: () => onApprove(hazardReports[index]),
                    onReject: () => onReject(hazardReports[index]),
                  ),
                ),
                if (index != hazardReports.length - 1)
                  const SizedBox(height: 12),
              ],
          ],
        ),
      ],
    );
  }
}

/// Displays the achievement management section.
class _AchievementManagementSection extends StatelessWidget {
  /// Creates achievement management section.
  const _AchievementManagementSection({
    required this.achievements,
    required this.isSaving,
    required this.onAdd,
    required this.onEdit,
    required this.onToggleActive,
  });

  final List<Map<String, dynamic>> achievements;
  final bool isSaving;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onToggleActive;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final active = achievements
        .where((item) => item['isActive'] != false)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionTitle(label: 'Achievement Rules')),
            FilledButton.icon(
              onPressed: isSaving ? null : onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add rule'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _AdminNotice(
          isError: false,
          message:
              '$active active of ${achievements.length}. Rewards are granted once; accumulation rules track progress until their target is reached.',
        ),
        const SizedBox(height: 10),
        Column(
          children: [
            if (achievements.isEmpty)
              const _EmptyState(message: 'No achievement rules configured.')
            else
              for (var index = 0; index < achievements.length; index++) ...[
                AdminPanel(
                  padding: EdgeInsets.zero,
                  child: _AchievementAdminRow(
                    achievement: achievements[index],
                    isSaving: isSaving,
                    onEdit: () => onEdit(achievements[index]),
                    onToggleActive: () => onToggleActive(achievements[index]),
                  ),
                ),
                if (index != achievements.length - 1)
                  const SizedBox(height: 12),
              ],
          ],
        ),
      ],
    );
  }
}

/// Displays the achievement admin row.
class _AchievementAdminRow extends StatelessWidget {
  /// Creates achievement admin row.
  const _AchievementAdminRow({
    required this.achievement,
    required this.isSaving,
    required this.onEdit,
    required this.onToggleActive,
  });

  final Map<String, dynamic> achievement;
  final bool isSaving;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final isActive = achievement['isActive'] != false;
    final isCumulative = _stringFrom(achievement['rewardType']) == 'cumulative';
    final target = isCumulative
        ? 'Target ${_intFrom(achievement['targetCount'])}'
        : 'One-time';
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isActive
                  ? _AdminColors.greenSoftFor(context)
                  : _AdminColors.separatorFor(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.emoji_events_rounded,
              color: isActive
                  ? _AdminColors.green
                  : _AdminColors.secondaryTextFor(context),
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
                        _stringFrom(achievement['title']),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _AdminColors.textFor(context),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    _AdminStatusPill(
                      label: isActive ? 'Active' : 'Archived',
                      color: isActive
                          ? _AdminColors.green
                          : _AdminColors.secondaryTextFor(context),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _stringFrom(achievement['condition']),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _AdminColors.secondaryTextFor(context),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _AdminStatusPill(
                      label: '${_intFrom(achievement['rewardPoints'])} pts',
                      color: _AdminColors.green,
                    ),
                    _AdminStatusPill(label: target, color: Colors.blueAccent),
                    _AdminStatusPill(
                      label: _stringFrom(achievement['metricKey']),
                      color: _AdminColors.orangeFor(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              IconButton(
                tooltip: 'Edit achievement',
                onPressed: isSaving ? null : onEdit,
                icon: const Icon(Icons.edit_rounded),
              ),
              IconButton(
                tooltip: isActive
                    ? 'Archive achievement'
                    : 'Activate achievement',
                onPressed: isSaving ? null : onToggleActive,
                icon: Icon(
                  isActive ? Icons.archive_rounded : Icons.unarchive_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Displays the hazard admin row.
class _HazardAdminRow extends StatelessWidget {
  /// Creates hazard admin row.
  const _HazardAdminRow({
    required this.report,
    required this.isSaving,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> report;
  final bool isSaving;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final status = _stringFrom(report['status']).isEmpty
        ? 'unverified'
        : _stringFrom(report['status']);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CircleIcon(icon: Icons.report_problem_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: _AdminTextBlock(
                  title: _stringFrom(report['hazardType']).isEmpty
                      ? 'Hazard report'
                      : _stringFrom(report['hazardType']),
                  subtitle:
                      '${_stringFrom(report['trailName'])} - ${_stringFrom(report['severity']).toUpperCase()} - $status',
                  body: _stringFrom(report['description']),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: isSaving ? null : onApprove,
                icon: const Icon(Icons.verified_rounded),
                label: const Text('Approve'),
              ),
              OutlinedButton.icon(
                onPressed: isSaving ? null : onReject,
                icon: const Icon(Icons.block_rounded),
                label: const Text('Reject'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Displays the empty state.
class _EmptyState extends StatelessWidget {
  /// Creates empty state.
  const _EmptyState({required this.message});
  final String message;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) =>
      AdminEmptyState(title: 'Nothing to show', message: message);
}

/// Displays the admin status pill.
class _AdminStatusPill extends StatelessWidget {
  /// Creates admin status pill.
  const _AdminStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final effectiveColor = color == _AdminColors.green
        ? _AdminColors.greenFor(context)
        : color;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: effectiveColor.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: effectiveColor,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

/// Displays the collection card.
class _CollectionCard extends StatefulWidget {
  /// Creates collection card.
  const _CollectionCard({required this.collection});

  final _FirestoreCollection collection;

  /// Creates the presentation state for this widget.
  @override
  State<_CollectionCard> createState() => _CollectionCardState();
}

/// Manages the collection card presentation and lifecycle.
class _CollectionCardState extends State<_CollectionCard> {
  bool _expanded = false;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final collection = widget.collection;
    final color = collection.error != null
        ? _AdminColors.redFor(context)
        : collection.documents.isEmpty
        ? _AdminColors.secondaryTextFor(context)
        : _AdminColors.green;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: collection.documents.isEmpty
            ? null
            : () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    collection.error != null
                        ? Icons.error_outline_rounded
                        : collection.documents.isEmpty
                        ? Icons.inbox_rounded
                        : Icons.folder_rounded,
                    size: 20,
                    color: color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      collection.name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _AdminColors.textFor(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  _AdminStatusPill(
                    label: collection.error != null
                        ? 'Error'
                        : '${collection.documents.length}',
                    color: color,
                  ),
                ],
              ),
              if (collection.error != null) ...[
                const SizedBox(height: 6),
                Text(
                  collection.error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _AdminColors.redFor(context),
                    letterSpacing: 0,
                  ),
                ),
              ],
              if (_expanded && collection.documents.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (
                  var docIndex = 0;
                  docIndex < collection.documents.length;
                  docIndex++
                ) ...[
                  _DocCard(
                    index: docIndex,
                    data: collection.documents[docIndex],
                  ),
                  if (docIndex != collection.documents.length - 1)
                    const SizedBox(height: 6),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the doc card.
class _DocCard extends StatelessWidget {
  /// Creates doc card.
  const _DocCard({required this.index, required this.data});

  final int index;
  final Map<String, dynamic> data;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final id = data['id']?.toString() ?? 'unknown';

    return Container(
      decoration: BoxDecoration(
        color: _AdminColors.greenSoftFor(context),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '[$index] $id',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: _AdminColors.green,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          for (final entry in data.entries)
            if (entry.key != 'id')
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: _KeyValueRow(key_: entry.key, value: entry.value),
              ),
        ],
      ),
    );
  }
}

/// Displays the key value row.
class _KeyValueRow extends StatelessWidget {
  /// Creates key value row.
  const _KeyValueRow({required String key_, required Object? value})
    : _key = key_,
      _value = value;

  final String _key;
  final Object? _value;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (_value is List) {
      final list = _value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _key,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _AdminColors.secondaryTextFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          if (list.isEmpty)
            Text(
              '[]',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _AdminColors.textFor(context),
                letterSpacing: 0,
              ),
            )
          else
            Container(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < list.length; i++)
                    _listItemWidget(context, list[i], i),
                ],
              ),
            ),
        ],
      );
    }

    if (_value is Map) {
      final map = Map<Object?, Object?>.from(_value);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _key,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _AdminColors.secondaryTextFor(context),
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          if (map.isEmpty)
            Text(
              '{}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _AdminColors.textFor(context),
                letterSpacing: 0,
              ),
            )
          else
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _AdminColors.greenSoftFor(
                  context,
                ).withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                children: [
                  for (final entry in map.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: _KeyValueRow(
                        key_: entry.key.toString(),
                        value: entry.value,
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    }

    final displayValue = _formatValue(_value);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            _key,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _AdminColors.secondaryTextFor(context),
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            displayValue,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _AdminColors.textFor(context),
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }

  /// Computes list item widget.
  Widget _listItemWidget(BuildContext context, Object? item, int index) {
    if (item is Map) {
      if (item.isEmpty) return const Text('{}');
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Container(
          decoration: BoxDecoration(
            color: _AdminColors.greenSoftFor(context).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '[$index]',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _AdminColors.green,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 3),
              for (final entry in item.entries)
                _KeyValueRow(key_: entry.key, value: entry.value),
            ],
          ),
        ),
      );
    }

    if (item is List) {
      final inner = item;
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          '[$index] ${_formatValue(inner)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _AdminColors.textFor(context),
            letterSpacing: 0,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        '[$index] ${_formatValue(item)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: _AdminColors.textFor(context),
          letterSpacing: 0,
        ),
      ),
    );
  }

  /// Formats value.
  String _formatValue(Object? value) {
    if (value == null) return 'null';
    if (value is double) return value.toStringAsFixed(6);
    if (value is List) {
      if (value.isEmpty) return '[]';
      return '[${value.length} items]';
    }
    if (value is Map) {
      if (value.isEmpty) return '{}';
      return '{${value.length} keys}';
    }
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }
    return value.toString();
  }
}

/// Displays the runtime state card.
class _RuntimeStateCard extends StatefulWidget {
  /// Creates runtime state card.
  const _RuntimeStateCard({required this.name, required this.data});

  final String name;
  final Map<String, Object?> data;

  /// Creates the presentation state for this widget.
  @override
  State<_RuntimeStateCard> createState() => _RuntimeStateCardState();
}

/// Manages the runtime state card presentation and lifecycle.
class _RuntimeStateCardState extends State<_RuntimeStateCard> {
  bool _expanded = false;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.memory_rounded,
                    size: 20,
                    color: _AdminColors.orangeFor(context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _AdminColors.textFor(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  _AdminStatusPill(
                    label: '${widget.data.length}',
                    color: _AdminColors.orangeFor(context),
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 10),
                _DocCard(index: 0, data: widget.data),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the local table card.
class _LocalTableCard extends StatefulWidget {
  /// Creates local table card.
  const _LocalTableCard({required this.name, required this.rows});

  final String name;
  final List<Map<String, dynamic>> rows;

  /// Creates the presentation state for this widget.
  @override
  State<_LocalTableCard> createState() => _LocalTableCardState();
}

/// Manages the local table card presentation and lifecycle.
class _LocalTableCardState extends State<_LocalTableCard> {
  bool _expanded = false;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final color = widget.rows.isEmpty
        ? _AdminColors.secondaryTextFor(context)
        : _AdminColors.green;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.rows.isEmpty
            ? null
            : () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    widget.rows.isEmpty
                        ? Icons.table_chart_outlined
                        : Icons.table_chart_rounded,
                    size: 20,
                    color: color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _AdminColors.textFor(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  _AdminStatusPill(
                    label: '${widget.rows.length}',
                    color: color,
                  ),
                ],
              ),
              if (_expanded && widget.rows.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (
                  var rowIndex = 0;
                  rowIndex < widget.rows.length;
                  rowIndex++
                ) ...[
                  _DocCard(index: rowIndex, data: widget.rows[rowIndex]),
                  if (rowIndex != widget.rows.length - 1)
                    const SizedBox(height: 6),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

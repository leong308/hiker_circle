import 'package:flutter/material.dart';
import '../../core/widgets/section_label.dart';
import '../../core/widgets/page_header_style.dart';
import '../../core/widgets/settings_card.dart';
import '../Model/achievement_catalog.dart';
import '../ModelView/achievement_editor_view_model.dart';

/// Opens both add and edit with the same protected, keyboard-aware sheet layout.
Future<Map<String, dynamic>?> showAchievementEditorSheet(
  BuildContext context, {
  Map<String, dynamic>? initial,
}) => showModalBottomSheet<Map<String, dynamic>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => AchievementEditorSheet(initial: initial),
);

/// Lets administrators author the exact public achievement details beside a verifiable tracking rule.
class AchievementEditorSheet extends StatefulWidget {
  /// Opens a new or existing achievement for moderation.
  const AchievementEditorSheet({super.key, this.initial});
  final Map<String, dynamic>? initial;

  /// Creates the form presentation state.
  @override
  State<AchievementEditorSheet> createState() => _AchievementEditorSheetState();
}

/// Owns only the form lifecycle and presentation; rule decisions belong to the ViewModel.
class _AchievementEditorSheetState extends State<AchievementEditorSheet> {
  final _form = GlobalKey<FormState>();
  late final AchievementEditorViewModel model;

  /// Initializes the editor from the shared offline catalog.
  @override
  void initState() {
    super.initState();
    model = AchievementEditorViewModel(initial: widget.initial)
      ..addListener(_render);
  }

  /// Rebuilds relevant defaults and selections.
  void _render() {
    if (mounted) setState(() {});
  }

  /// Releases the form's model.
  @override
  void dispose() {
    model.removeListener(_render);
    model.dispose();
    super.dispose();
  }

  /// Bounds the sheet to the safe viewport above the keyboard and keeps its header visible.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final keyboardHeight = MediaQuery.viewInsetsOf(
        context,
      ).bottom.clamp(0.0, constraints.maxHeight);
      final availableHeight = constraints.maxHeight - keyboardHeight;
      return Padding(
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: SizedBox(
          height: availableHeight * .92,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.initial == null
                                ? 'Add achievement'
                                : 'Edit achievement',
                            style: PageHeaderStyle.title(
                              context,
                              Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        PageHeaderAction(
                          tooltip: 'Close',
                          icon: Icons.close_rounded,
                          onPressed: () => Navigator.pop(context),
                          color: Theme.of(context).colorScheme.primary,
                          surface: Theme.of(context).colorScheme.surface,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _section('Achievement', [
                              _text('title', 'Title', maxLines: 1),
                              DropdownButtonFormField<String>(
                                key: ValueKey('category-${model.categoryId}'),
                                initialValue: model.categoryId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Category',
                                ),
                                items: AchievementCatalog.categories
                                    .map(
                                      (row) => DropdownMenuItem(
                                        value: row['id'] as String,
                                        child: Text(
                                          row['label'] as String,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    model.selectCategory(value);
                                  }
                                },
                              ),
                            ]),
                            const SizedBox(height: 24),
                            _section('Tracking rule', [
                              DropdownButtonFormField<String>(
                                key: ValueKey('metric-${model.metricKey}'),
                                initialValue: model.metricKey,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Tracked activity',
                                ),
                                items: model.activities
                                    .map(
                                      (row) => DropdownMenuItem(
                                        value: row['key'] as String,
                                        child: Text(
                                          row['label'] as String,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null) model.selectMetric(value);
                                },
                              ),
                              if (model.activity['allowsOneTime'] == true)
                                DropdownButtonFormField<String>(
                                  key: ValueKey('mode-${model.rewardType}'),
                                  initialValue: model.rewardType,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Unlock when',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'one_time',
                                      child: Text(
                                        'One qualifying activity',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'cumulative',
                                      child: Text(
                                        'A target is reached',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      model.selectRewardType(value);
                                    }
                                  },
                                ),
                              if (model.rewardType == 'cumulative')
                                _number(
                                  'targetCount',
                                  'Target (${model.activity['unit']})',
                                  model.validateTarget,
                                  decimal: (model.activity['scale'] as num) > 1,
                                ),
                              _text('condition', 'Your goal'),
                            ]),
                            const SizedBox(height: 24),
                            _section('Achievement details', [
                              _text(
                                'whyItMatters',
                                'Why this achievement exists',
                              ),
                              _text('whatCounts', 'What counts'),
                              _text(
                                'rewardRecognition',
                                'Reward and recognition',
                              ),
                              _number(
                                'rewardPoints',
                                'Reward points',
                                model.validatePoints,
                              ),
                            ]),
                            const SizedBox(height: 24),
                            _section('Availability', [
                              _number('sortOrder', 'Display order', null),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                secondary: Icon(
                                  model.isActive
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                title: const Text('Active'),
                                value: model.isActive,
                                onChanged: (value) =>
                                    setState(() => model.isActive = value),
                              ),
                            ]),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: () {
                                if (_form.currentState?.validate() == true) {
                                  Navigator.pop(context, model.save());
                                }
                              },
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                              icon: const Icon(Icons.save_rounded),
                              label: const Text('Save achievement'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  /// Reuses the app's settings surface and section label for calm, evenly spaced field groups.
  Widget _section(String title, List<Widget> fields) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionLabel(label: title),
      const SizedBox(height: 10),
      SettingsCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < fields.length; index++) ...[
                if (index > 0) const SizedBox(height: 14),
                fields[index],
              ],
            ],
          ),
        ),
      ),
    ],
  );

  /// Renders a public description; suggested content can always be customized.
  Widget _text(String field, String label, {int maxLines = 3}) => TextFormField(
    key: ValueKey('$field-${model.contentRevision}'),
    initialValue: model.values[field],
    maxLines: maxLines,
    minLines: 1,
    decoration: InputDecoration(
      labelText: label,
      alignLabelWithHint: maxLines > 1,
    ),
    onChanged: (value) => model.update(field, value),
    validator: (value) => model.validateText(field, value),
  );

  /// Renders the metric's numeric target or a presentation setting.
  Widget _number(
    String field,
    String label,
    String? Function(String?)? validator, {
    bool decimal = false,
  }) => TextFormField(
    key: field == 'targetCount'
        ? ValueKey('$field-${model.metricKey}')
        : ValueKey(field),
    initialValue: model.values[field],
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    decoration: InputDecoration(labelText: label),
    onChanged: (value) => model.update(field, value),
    validator: validator,
  );
}

import 'package:flutter/material.dart';
import '../../core/widgets/section_label.dart';
import '../Model/achievement_catalog.dart';
import '../ModelView/achievement_editor_view_model.dart';

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

  /// Renders authored content with consistent section labels and a visible automatic rule.
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Material(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.initial == null
                          ? 'Add achievement'
                          : 'Edit achievement',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const SectionLabel(label: 'Achievement'),
              const SizedBox(height: 10),
              _text('title', 'Title', maxLines: 1),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('category-${model.categoryId}'),
                initialValue: model.categoryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: AchievementCatalog.categories
                    .map(
                      (row) => DropdownMenuItem(
                        value: row['id'] as String,
                        child: Text(row['label'] as String),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) model.selectCategory(value);
                },
              ),
              const SizedBox(height: 20),
              const SectionLabel(label: 'Tracking rule'),
              const SizedBox(height: 10),
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
                        child: Text(row['label'] as String),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) model.selectMetric(value);
                },
              ),
              const SizedBox(height: 10),
              Text(
                model.activity['whatCounts'] as String,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (model.activity['allowsOneTime'] == true) ...[
                DropdownButtonFormField<String>(
                  key: ValueKey('mode-${model.rewardType}'),
                  initialValue: model.rewardType,
                  decoration: const InputDecoration(labelText: 'Unlock when'),
                  items: const [
                    DropdownMenuItem(
                      value: 'one_time',
                      child: Text('One qualifying activity'),
                    ),
                    DropdownMenuItem(
                      value: 'cumulative',
                      child: Text('A target is reached'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) model.selectRewardType(value);
                  },
                ),
                const SizedBox(height: 12),
              ],
              if (model.rewardType == 'cumulative') ...[
                _number(
                  'targetCount',
                  'Target (${model.activity['unit']})',
                  model.validateTarget,
                  decimal: (model.activity['scale'] as num) > 1,
                ),
                const SizedBox(height: 12),
              ],
              _text(
                'condition',
                'Your goal',
                hint: 'The requirement shown on the badge and its details.',
              ),
              const SizedBox(height: 20),
              const SectionLabel(label: 'Hiker-facing details'),
              const SizedBox(height: 10),
              const Text(
                'These descriptions appear on the achievement page. Editing them does not change the tracked activity or target.',
              ),
              const SizedBox(height: 12),
              _text('whyItMatters', 'Why this achievement exists'),
              const SizedBox(height: 12),
              _text('whatCounts', 'What counts'),
              const SizedBox(height: 12),
              _text('rewardRecognition', 'Reward and recognition'),
              const SizedBox(height: 12),
              _number('rewardPoints', 'Reward points', model.validatePoints),
              const SizedBox(height: 8),
              const Text(
                'The badge and its points are awarded once. Points contribute to the hiker’s Trail Journey level.',
              ),
              const SizedBox(height: 20),
              const SectionLabel(label: 'Availability'),
              const SizedBox(height: 10),
              _number('sortOrder', 'Display order', null),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text(
                  'Archived rules keep existing awards and stop future progress.',
                ),
                value: model.isActive,
                onChanged: (value) => setState(() => model.isActive = value),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  if (_form.currentState?.validate() == true) {
                    Navigator.pop(context, model.save());
                  }
                },
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save achievement'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  /// Renders a public description; suggested content can always be customized.
  Widget _text(String field, String label, {String? hint, int maxLines = 3}) =>
      TextFormField(
        key: ValueKey('$field-${model.contentRevision}'),
        initialValue: model.values[field],
        maxLines: maxLines,
        minLines: 1,
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
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

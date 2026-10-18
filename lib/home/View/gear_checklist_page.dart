// GearChecklistPage edits the current hike's packed gear selection.
import 'package:flutter/material.dart';
import '../../core/widgets/page_header_style.dart';
import '../Model/hike_session_models.dart';
import '../Model/trail_gear_plan.dart';
import 'trail_gear_checklist.dart';

class GearChecklistPage extends StatefulWidget {
  const GearChecklistPage({super.key, this.plannedHike});
  final PlannedHike? plannedHike;
  static int get checklistItemCount => GearChecklistCatalog.itemCount;
  static Set<String> sanitizeCompletedItems(Iterable<String> items) =>
      GearChecklistCatalog.sanitize(items);
  @override
  State<GearChecklistPage> createState() => _GearChecklistPageState();
}

class _GearChecklistPageState extends State<GearChecklistPage> {
  late Set<String> _items = {
    ...widget.plannedHike?.completedChecklistItems ?? <String>{},
  };
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLow,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  PageHeaderAction(
                    tooltip: 'Back',
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => Navigator.pop(context),
                    color: scheme.primary,
                    surface: scheme.surface,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Gear checklist',
                      style: PageHeaderStyle.title(context, scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  if (widget.plannedHike != null) ...[
                    Text(
                      widget.plannedHike!.trail.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    TrailGearChecklist(
                      plan: widget.plannedHike!
                          .copyWith(completedChecklistItems: _items)
                          .withGearProgress(),
                      onChanged: (items) => setState(() => _items = items),
                    ),
                  ] else ...[
                    const Text(
                      'Everyday essentials · schedule a hike for a trail-specific pack.',
                    ),
                    for (final item in TrailGearPlan.base)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GearPackingTile(
                          item: item,
                          packed: _items.contains(item),
                          compact: true,
                          onTap: () => setState(
                            () => _items.contains(item)
                                ? _items.remove(item)
                                : _items.add(item),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Save checklist'),
                  onPressed: () => Navigator.pop(
                    context,
                    widget.plannedHike == null
                        ? null
                        : Set<String>.unmodifiable(_items),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../Model/hike_session_models.dart';

class GearChecklistPage extends StatefulWidget {
  const GearChecklistPage({super.key, this.plannedHike});

  final PlannedHike? plannedHike;

  @override
  State<GearChecklistPage> createState() => _GearChecklistPageState();
}

class _GearChecklistPageState extends State<GearChecklistPage> {
  late final Set<String> _completedItems = <String>{
    'Charged phone',
    if (widget.plannedHike?.offlineMapDownloaded == true)
      'Offline map downloaded',
    'Torch',
    'Drinking water',
    'Raincoat',
  };

  static const Map<String, List<String>> _sections = {
    'Safety Essentials': [
      'Charged phone',
      'Power bank',
      'Offline map downloaded',
      'Torch',
      'First-aid kit',
      'Emergency whistle',
      'Multi-tool',
    ],
    'Navigation & Communication': [
      'GPS device or app',
      'Physical map',
      'Compass',
      'Fully charged phone',
      'Emergency contacts saved',
    ],
    'Water and Food': [
      'Drinking water',
      'Water filter or tablets',
      'Energy snack',
      'Extra food for delays',
    ],
    'Weather & Clothing': [
      'Raincoat',
      'Extra clothing layer',
      'Sun protection (hat, sunscreen)',
      'Warm hat and gloves',
    ],
    'Emergency & Recovery': [
      'Headlamp with spare batteries',
      'Fire starter or matches',
      'Emergency blanket',
      'Whistle',
      'Signal mirror',
    ],
  };

  int get _totalItems {
    return _sections.values.fold<int>(
      0,
      (total, items) => total + items.length,
    );
  }

  void _toggle(String item, bool? isSelected) {
    setState(() {
      if (isSelected == true) {
        _completedItems.add(item);
      } else {
        _completedItems.remove(item);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ChecklistColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(onBack: () => Navigator.of(context).pop()),
                  const SizedBox(height: 16),
                  if (widget.plannedHike != null)
                    _TripSummary(plannedHike: widget.plannedHike!),
                  if (widget.plannedHike != null)
                    const SizedBox(height: 18),
                  for (final entry in _sections.entries) ...[
                    _ChecklistSection(
                      title: entry.key,
                      items: entry.value,
                      completedItems: _completedItems,
                      onChanged: _toggle,
                    ),
                    const SizedBox(height: 18),
                  ],
                  _ProgressCard(
                    completed: _completedItems.length,
                    total: _totalItems,
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save checklist'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Tooltip(
          message: 'Back',
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(36),
            onPressed: onBack,
            child: const _CircleIcon(icon: CupertinoIcons.chevron_back),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Gear Checklist',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: _ChecklistColors.text,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _TripSummary extends StatelessWidget {
  const _TripSummary({required this.plannedHike});

  final PlannedHike plannedHike;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const _Glyph(icon: Icons.hiking_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plannedHike.trail.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _ChecklistColors.text,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Departure: Tomorrow, 6:30 AM',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _ChecklistColors.secondaryText,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistSection extends StatelessWidget {
  const _ChecklistSection({
    required this.title,
    required this.items,
    required this.completedItems,
    required this.onChanged,
  });

  final String title;
  final List<String> items;
  final Set<String> completedItems;
  final void Function(String item, bool? isSelected) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 14, bottom: 7),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _ChecklistColors.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ),
        _InsetGroup(
          child: Column(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                Material(
                  color: Colors.transparent,
                  child: CheckboxListTile(
                    value: completedItems.contains(items[index]),
                    onChanged: (value) => onChanged(items[index], value),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: _ChecklistColors.green,
                    title: Text(
                      items[index],
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _ChecklistColors.text,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
                if (index != items.length - 1)
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

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.completed, required this.total});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;

    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Progress: $completed / $total Completed',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _ChecklistColors.text,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              borderRadius: BorderRadius.circular(4),
              color: _ChecklistColors.green,
              backgroundColor: _ChecklistColors.greenSoft,
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: _ChecklistColors.green, size: 20),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _ChecklistColors.green,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }
}

class _HorizontalSeparator extends StatelessWidget {
  const _HorizontalSeparator();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 0.7,
      color: _ChecklistColors.separator,
    );
  }
}

abstract final class _ChecklistColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
}

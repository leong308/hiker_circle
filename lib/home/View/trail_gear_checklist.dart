import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../Model/hike_session_models.dart';

class TrailGearChecklist extends StatefulWidget {
  const TrailGearChecklist({
    super.key,
    required this.plan,
    required this.onChanged,
    this.busy = false,
    this.analyzing = false,
    this.onRetryAnalysis,
    this.safetyReadiness,
  });
  final PlannedHike plan;
  final ValueChanged<Set<String>>? onChanged;
  final bool busy, analyzing;
  final VoidCallback? onRetryAnalysis;
  final Widget? safetyReadiness;
  @override
  State<TrailGearChecklist> createState() => _TrailGearChecklistState();
}

class _TrailGearChecklistState extends State<TrailGearChecklist> {
  String _selected = 'Essentials';
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final plan = widget.plan, gear = plan.gearPlan;
    final done = gear.completed(plan.completedChecklistItems);
    final missing = plan.missingRequiredGear;
    final names = [
      ...gear.sections.keys,
      if (widget.safetyReadiness != null) 'Safety readiness',
    ];
    if (!names.contains(_selected)) _selected = names.first;
    final safety = _selected == 'Safety readiness';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: .45),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.backpack_outlined, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your trail pack',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '$done/${gear.items.length}',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: done / gear.items.length),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 250),
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                missing.isEmpty
                    ? 'Required items ready · ${gear.items.length - done} recommended items left'
                    : '${missing.length} required item${missing.length == 1 ? '' : 's'} left before starting',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.analyzing)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.route_rounded, color: scheme.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.analyzing
                    ? 'Checking map features within 50 m of your route…'
                    : plan.gearAssessment?.usable != true
                    ? 'Route conditions unavailable. Known schedule and weather requirements still apply.'
                    : !plan.gearAssessment!.isFresh
                    ? 'Using saved route findings; check current conditions.'
                    : 'Selected using your route, schedule and forecast. Map data © OpenStreetMap contributors.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (!widget.analyzing && widget.onRetryAnalysis != null)
              IconButton(
                tooltip: 'Refresh route analysis',
                onPressed: widget.busy ? null : widget.onRetryAnalysis,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
          ],
        ),
        const SizedBox(height: 14),
        DefaultTabController(
          key: ValueKey(names.join('|')),
          length: names.length,
          initialIndex: names.indexOf(_selected),
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 14),
            onTap: (index) => setState(() => _selected = names[index]),
            tabs: [
              for (final name in names)
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name),
                      if (name != 'Safety readiness' &&
                          gear.sections[name]!.any(missing.contains)) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (safety)
          widget.safetyReadiness!
        else ...[
          Text(
            gear.reasons[_selected]!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >= 280 &&
                      MediaQuery.textScalerOf(context).scale(1) < 1.3
                  ? 2
                  : 1;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final item in gear.sections[_selected]!)
                    SizedBox(
                      width:
                          (constraints.maxWidth - (columns - 1) * 10) / columns,
                      child: GearPackingTile(
                        key: ValueKey('gear-item-$item'),
                        item: item,
                        packed: plan.completedChecklistItems.contains(item),
                        compact: columns == 1,
                        requiredReason: gear.requiredReasons[item],
                        onTap: widget.busy || widget.onChanged == null
                            ? null
                            : () {
                                final items = {...plan.completedChecklistItems};
                                items.contains(item)
                                    ? items.remove(item)
                                    : items.add(item);
                                widget.onChanged!(items);
                              },
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class GearPackingTile extends StatelessWidget {
  const GearPackingTile({
    super.key,
    required this.item,
    required this.packed,
    required this.onTap,
    this.compact = false,
    this.requiredReason,
  });
  final String item;
  final String? requiredReason;
  final bool packed, compact;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);
    final status = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: duration,
          child: Icon(
            packed
                ? Icons.check_circle_rounded
                : Icons.add_circle_outline_rounded,
            key: ValueKey(packed),
            size: 18,
            color: scheme.primary,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          packed ? 'Packed' : 'Pack',
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    final icon = Icon(_gearIcon(item), size: 25, color: scheme.primary);
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (requiredReason != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Tooltip(
              message: requiredReason!,
              child: Text(
                'REQUIRED',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .6,
                ),
              ),
            ),
          ),
        Text(
          item,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      toggled: packed,
      enabled: onTap != null,
      onTap: onTap,
      label:
          '$item, ${requiredReason == null ? 'recommended' : 'required'}, ${packed ? 'packed' : 'not packed'}',
      hint: packed ? 'Tap to remove from your pack' : 'Tap to mark packed',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: packed
              ? scheme.primaryContainer.withValues(alpha: .6)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: packed
                ? scheme.primary.withValues(alpha: .5)
                : scheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: compact
                  ? Row(
                      children: [
                        icon,
                        const SizedBox(width: 12),
                        Expanded(child: label),
                        const SizedBox(width: 8),
                        status,
                      ],
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 114),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              icon,
                              const Spacer(),
                              if (packed)
                                Icon(
                                  Icons.done_rounded,
                                  size: 16,
                                  color: scheme.primary,
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          label,
                          const SizedBox(height: 10),
                          status,
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _gearIcon(String item) {
  final key = item.toLowerCase();
  if (key.contains('water') || key.contains('filter')) {
    return Icons.water_drop_outlined;
  }
  if (key.contains('food') || key.contains('snack') || key.contains('meals')) {
    return Icons.restaurant_outlined;
  }
  if (key.contains('aid') || key.contains('blister')) {
    return Icons.medical_services_outlined;
  }
  if (key.contains('lamp') || key.contains('batter')) {
    return Icons.flashlight_on_outlined;
  }
  if (key.contains('gps') || key.contains('map') || key.contains('compass')) {
    return Icons.explore_outlined;
  }
  if (key.contains('contact') || key.contains('satellite')) {
    return Icons.contact_phone_outlined;
  }
  if (key.contains('sun') || key.contains('hat')) {
    return Icons.wb_sunny_outlined;
  }
  if (key.contains('rain') || key.contains('dry bag')) {
    return Icons.umbrella_outlined;
  }
  if (key.contains('tent') || key.contains('shelter')) {
    return Icons.holiday_village_outlined;
  }
  if (key.contains('bag') ||
      key.contains('blanket') ||
      key.contains('clothing')) {
    return Icons.layers_outlined;
  }
  if (key.contains('footwear') ||
      key.contains('socks') ||
      key.contains('poles')) {
    return Icons.hiking_rounded;
  }
  if (key.contains('power')) return Icons.battery_charging_full_rounded;
  if (key.contains('whistle')) return Icons.campaign_outlined;
  if (key.contains('permit')) return Icons.badge_outlined;
  if (key.contains('stove')) return Icons.local_fire_department_outlined;
  if (key.contains('waste')) return Icons.recycling_rounded;
  return Icons.backpack_outlined;
}

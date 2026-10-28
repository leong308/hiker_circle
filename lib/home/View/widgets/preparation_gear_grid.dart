import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Direct packing choices; the stored item names remain the checklist keys.
class PreparationGearGrid extends StatelessWidget {
  /// Creates preparation gear grid.
  const PreparationGearGrid({
    super.key,
    required this.items,
    required this.selectedItems,
    required this.onToggle,
    this.reasons = const {},
  });

  final Iterable<String> items;
  final Set<String> selectedItems;
  final ValueChanged<String>? onToggle;
  final Map<String, String> reasons;

  /// Computes label for.
  static String labelFor(String item) =>
      const {
        'Drinking water': 'Water',
        'Energy snack': 'Snacks',
        'Sun protection (hat, sunscreen)': 'Hat + sunscreen',
        'Dry bag / waterproof phone pouch': 'Waterproof pouch',
        'Secure water-crossing footwear': 'Crossing footwear',
        'Grippy hiking footwear': 'Hiking footwear',
        'Tent or suitable shelter': 'Tent / shelter',
        'Sleeping bag and sleeping mat': 'Sleeping bag + mat',
        'Meals for each day + reserve': 'Meals + reserves',
        'Satellite communicator if no signal': 'Satellite communicator',
        'Stove and fuel where permitted': 'Stove + fuel',
      }[item] ??
      item;

  /// Computes icon for.
  static IconData iconFor(String item) {
    final name = item.toLowerCase();
    if (name.contains('water') && !name.contains('footwear')) {
      return Icons.water_drop_outlined;
    }
    if (name.contains('snack') ||
        name.contains('food') ||
        name.contains('meal')) {
      return Icons.restaurant_outlined;
    }
    if (name.contains('aid') || name.contains('blister')) {
      return Icons.medical_services_outlined;
    }
    if (name.contains('sun')) return Icons.wb_sunny_outlined;
    if (name.contains('rain')) return Icons.umbrella_outlined;
    if (name.contains('lamp') || name.contains('torch')) {
      return Icons.flashlight_on_outlined;
    }
    if (name.contains('bank')) return Icons.battery_charging_full_rounded;
    if (name.contains('clothing') || name.contains('socks')) {
      return Icons.checkroom_outlined;
    }
    if (name.contains('blanket') || name.contains('sleeping')) {
      return Icons.layers_outlined;
    }
    if (name.contains('tent') || name.contains('shelter')) {
      return Icons.festival_outlined;
    }
    if (name.contains('poles') || name.contains('footwear')) {
      return Icons.hiking_rounded;
    }
    if (name.contains('permit')) return Icons.confirmation_number_outlined;
    return Icons.backpack_outlined;
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final values = items.toList();
    final textScaler = MediaQuery.textScalerOf(context);
    final style = theme.textTheme.labelMedium!.copyWith(
      fontSize: 12,
      height: 1.2,
      fontWeight: FontWeight.w600,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = textScaler.scale(1);
        final columns = constraints.maxWidth < 250 || scale >= 2.5
            ? 1
            : constraints.maxWidth < 330 || scale >= 1.5
            ? 2
            : constraints.maxWidth >= 380 && scale < 1.2
            ? 4
            : 3;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        var textHeight = 0.0;
        for (final item in values) {
          final painter = TextPainter(
            text: TextSpan(text: labelFor(item), style: style),
            textScaler: textScaler,
            textDirection: Directionality.of(context),
          )..layout(maxWidth: width - 20);
          textHeight = math.max(textHeight, painter.height);
          painter.dispose();
        }

        /// Computes tile for.
        Widget tileFor(String item) {
          final selected = selectedItems.contains(item);
          final radius = BorderRadius.circular(12);
          return Tooltip(
            message: reasons[item] == null ? item : '$item · ${reasons[item]}',
            child: Semantics(
              label: item,
              checked: selected,
              enabled: onToggle != null,
              child: Material(
                color: selected
                    ? scheme.primaryContainer.withValues(alpha: .55)
                    : scheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: radius,
                  side: BorderSide(
                    color: selected
                        ? scheme.primary.withValues(alpha: .5)
                        : scheme.outlineVariant.withValues(alpha: .6),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('preparation-gear-$item'),
                  onTap: onToggle == null ? null : () => onToggle!(item),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                iconFor(item),
                                size: 20,
                                color: selected
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                              const Spacer(),
                              Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                size: 16,
                                color: selected
                                    ? scheme.primary
                                    : scheme.outline,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            labelFor(item),
                            style: style.copyWith(
                              color: selected
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in values)
              SizedBox(
                width: width,
                height: math.max(76, textHeight + 48),
                child: tileFor(item),
              ),
          ],
        );
      },
    );
  }
}

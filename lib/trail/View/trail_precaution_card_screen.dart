part of '../trail_precaution_card_feature.dart';

/// Computes precaution accent color.
Color precautionAccentColor(BuildContext context, int priority) {
  final theme = Theme.of(context);
  if (priority >= 3) return theme.colorScheme.error;
  if (priority == 2) {
    return theme.brightness == Brightness.dark
        ? const Color(0xFFF0BF6A)
        : const Color(0xFF95620E);
  }
  return theme.colorScheme.primary;
}

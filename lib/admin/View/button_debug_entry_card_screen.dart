part of '../button_debug_entry_card_feature.dart';

/// Computes operation label.
String _operationLabel(String operation) {
  final label = operation.replaceAll('_', ' ').trim();
  return label.isEmpty
      ? 'Event'
      : '${label[0].toUpperCase()}${label.substring(1)}';
}

part of '../profile_details_page_feature.dart';

/// Represents profile detail.
class _ProfileDetail {
  /// Creates profile detail.
  const _ProfileDetail({
    required this.icon,
    required this.label,
    required this.value,
    this.onEdit,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onEdit;
}

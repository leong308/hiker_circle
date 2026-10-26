part of '../hike_history_page_feature.dart';

/// Represents row data.
class _RowData {
  /// Creates row data.
  const _RowData(this.label, this.value);
  final String label;
  final String value;
}

/// Represents metric.
class _Metric {
  /// Creates metric.
  const _Metric(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;
}

import 'package:cloud_firestore/cloud_firestore.dart';

const feedbackCategories = ['Problem', 'Suggestion', 'Other'];
const feedbackStatuses = ['New', 'In review', 'Resolved'];
const feedbackImageLimit = 5 * 1024 * 1024;
const feedbackReportLimit = 100;

/// Identifies the icon used for each existing feedback category.
enum FeedbackReportKind { problem, suggestion, other }

/// Keeps feedback display parsing separate from inbox and detail widgets.
class FeedbackReport {
  /// Retains the original record without allowing presentation code to edit it.
  FeedbackReport({required this.id, required Map<String, dynamic> data})
    : data = Map<String, dynamic>.unmodifiable(data);

  final String id;
  final Map<String, dynamic> data;

  /// Reads valid text without crashing on an incomplete historical record.
  String _text(String key) =>
      data[key] is String ? (data[key] as String).trim() : '';

  /// Shows the submitted category, falling back only when it is missing.
  String get category =>
      _text('category').isEmpty ? 'Other' : _text('category');

  /// Selects a visual category without changing the saved category value.
  FeedbackReportKind get kind => switch (category) {
    'Problem' => FeedbackReportKind.problem,
    'Suggestion' => FeedbackReportKind.suggestion,
    _ => FeedbackReportKind.other,
  };

  /// Retains the submitted message and provides a clear missing-data state.
  String get message =>
      _text('message').isEmpty ? 'No message available.' : _text('message');

  /// Never invents a review state for incomplete records.
  String get status =>
      _text('status').isEmpty ? 'Status unavailable' : _text('status');

  /// Indicates whether the protected screenshot attachment can be requested.
  String get screenshotPath => _text('screenshotPath');

  /// Supports current server timestamps and older serialized timestamps.
  DateTime? get submittedAt {
    final value = data['createdAt'] ?? data['createdAtLocal'];
    if (value is Timestamp) return value.toDate().toLocal();
    if (value is DateTime) return value.toLocal();
    return value is String ? DateTime.tryParse(value)?.toLocal() : null;
  }

  /// Uses familiar platform names in the report details.
  String get platformLabel => switch (_text('platform').toLowerCase()) {
    'ios' => 'iOS',
    'android' => 'Android',
    'web' => 'Web',
    'macos' => 'macOS',
    'windows' => 'Windows',
    'linux' => 'Linux',
    '' => 'Unavailable',
    _ => _text('platform'),
  };

  /// Explains only the existing three review states.
  static String statusDescription(String status) => switch (status) {
    'New' => 'This report is waiting to be reviewed.',
    'In review' => 'This report is being reviewed.',
    'Resolved' => 'This report has been marked as resolved.',
    _ => 'The review status is unavailable.',
  };
}

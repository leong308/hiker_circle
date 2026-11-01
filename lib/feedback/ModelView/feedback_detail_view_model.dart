import 'dart:async';

import 'package:flutter/foundation.dart';

import '../Model/feedback_report.dart';
import '../feedback_repository.dart';

/// Owns attachment loading and confirmed administrator status changes.
class FeedbackDetailViewModel extends ChangeNotifier {
  /// Uses the inbox's selected repository for both read and write actions.
  FeedbackDetailViewModel({
    required this.report,
    required this.admin,
    required FeedbackRepository repository,
  }) : _repository = repository,
       _status = report.status {
    _loadScreenshot();
  }

  final FeedbackReport report;
  final bool admin;
  final FeedbackRepository _repository;
  String _status;
  bool _busy = false;
  bool _disposed = false;
  String? _error;
  Future<Uint8List?>? _screenshot;

  /// Shows a new status only after its existing backend write succeeds.
  String get status => _status;

  /// Blocks repeated changes while the current update is in flight.
  bool get busy => _busy;

  /// Keeps failed updates visible and retryable on the detail page.
  String? get error => _error;

  /// Supplies the protected attachment without refetching it on rebuild.
  Future<Uint8List?>? get screenshot => _screenshot;

  /// Reuses the original screenshot path and five-megabyte repository limit.
  void _loadScreenshot() {
    _screenshot = report.screenshotPath.isEmpty
        ? null
        : Future<Uint8List?>.sync(
            () => _repository.screenshot(report.screenshotPath),
          ).timeout(const Duration(seconds: 30));
  }

  /// Retries only the screenshot, preserving the report and review status.
  void retryScreenshot() {
    if (_disposed) return;
    _loadScreenshot();
    notifyListeners();
  }

  /// Preserves administrator-only updates and the existing allowed statuses.
  Future<void> changeStatus(String value) async {
    if (_disposed ||
        !admin ||
        _busy ||
        value == _status ||
        !feedbackStatuses.contains(value)) {
      return;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _repository
          .setStatus(report.id, value)
          .timeout(const Duration(seconds: 30));
      if (!_disposed) _status = value;
    } catch (_) {
      if (!_disposed) {
        _error = 'Could not confirm the status update. Please retry.';
      }
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  /// Stops late asynchronous completions from updating a closed page.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

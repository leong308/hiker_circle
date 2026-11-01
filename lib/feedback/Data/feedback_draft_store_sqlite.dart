import 'dart:math';
import 'dart:typed_data';

import '../../app/Data/local_session_database.dart';
import '../Model/feedback_report.dart' show feedbackImageLimit;
import '../Model/feedback_saved_draft.dart';

/// Saves editable feedback in encrypted mobile SQLite.
class FeedbackDraftStore {
  FeedbackDraftStore(this.database);

  final LocalSessionDatabase database;
  static final _random = Random.secure();

  String _owner(String owner) {
    final value = owner.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(owner, 'owner', 'Missing owner');
    }
    return value;
  }

  Future<FeedbackSavedDraft?> load(String owner) =>
      database.loadFeedbackDraft(_owner(owner));

  Future<FeedbackSavedDraft> open({
    required String owner,
    String category = 'Problem',
    String message = '',
    Uint8List? screenshot,
  }) {
    _validateScreenshot(screenshot);
    return database.openFeedbackDraft(
      FeedbackSavedDraft(
        id: List.generate(
          10,
          (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
        uid: _owner(owner),
        category: category,
        message: message,
        screenshot: screenshot,
      ),
    );
  }

  void _validateScreenshot(Uint8List? screenshot) {
    if (screenshot != null && screenshot.length > feedbackImageLimit) {
      throw ArgumentError.value(
        screenshot.length,
        'screenshot',
        'The feedback screenshot must be at most 5 MB.',
      );
    }
  }

  /// A stale screen cannot overwrite a newer save or a cleared draft.
  Future<FeedbackSavedDraft?> save(FeedbackSavedDraft draft) {
    _validateScreenshot(draft.screenshot);
    return database.saveFeedbackDraft(draft);
  }

  Future<bool> discard(FeedbackSavedDraft expected) =>
      database.discardFeedbackDraft(expected);

  /// An acknowledgement clears only the exact payload that was submitted.
  Future<bool> acknowledge({
    required String owner,
    required String id,
    required String category,
    required String message,
    Uint8List? screenshot,
  }) => database.acknowledgeFeedbackDraft(
    owner: _owner(owner),
    id: id,
    category: category,
    message: message,
    screenshot: screenshot,
  );
}

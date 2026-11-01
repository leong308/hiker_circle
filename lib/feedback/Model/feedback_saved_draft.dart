import 'package:flutter/foundation.dart';

/// One account's durable, unsent form, independent of downloaded report caches.
@immutable
class FeedbackSavedDraft {
  FeedbackSavedDraft({
    required this.id,
    required this.uid,
    required this.category,
    required this.message,
    Uint8List? screenshot,
    this.submissionAttempted = false,
    this.revision = 0,
  }) : screenshot = screenshot == null
           ? null
           : Uint8List.fromList(screenshot).asUnmodifiableView();

  const FeedbackSavedDraft._({
    required this.id,
    required this.uid,
    required this.category,
    required this.message,
    required this.screenshot,
    required this.submissionAttempted,
    required this.revision,
  });

  final String id;
  final String uid;
  final String category;
  final String message;
  final Uint8List? screenshot;
  final bool submissionAttempted;
  final int revision;

  bool get hasContent => message.isNotEmpty || screenshot != null;

  FeedbackSavedDraft copyWith({
    String? category,
    String? message,
    Uint8List? screenshot,
    bool removeScreenshot = false,
    bool? submissionAttempted,
  }) => FeedbackSavedDraft._(
    id: id,
    uid: uid,
    category: category ?? this.category,
    message: message ?? this.message,
    screenshot: removeScreenshot
        ? null
        : screenshot == null
        ? this.screenshot
        : Uint8List.fromList(screenshot).asUnmodifiableView(),
    submissionAttempted: submissionAttempted ?? this.submissionAttempted,
    revision: revision,
  );
}
